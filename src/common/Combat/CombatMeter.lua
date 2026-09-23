local _, ns = ...

-- =============================================================================
-- TurboFace Combat Meter
--
-- Lightweight local combat accounting for leveling and 5-player content.
-- This is deliberately NOT a raid analytics package: no addon comms, no event
-- history, no encounter database, no death logs. The shared ns.CLEU dispatcher
-- feeds a tiny accumulator; the UI redraws at a throttled cadence.
--
-- Current = one locally observed combat segment.
-- Overall = sum of finalized/current combat time since login or manual reset.
-- Pets are attributed to their owner when the pet unit token is known.
-- =============================================================================

local CM = {}
ns.CombatMeter = CM

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_sort = table.sort
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local wipe = wipe

local STALE_COMBAT_TIMEOUT = 10
local VISIBLE_ROWS = 5
local PLAYER_RATE_PLACEHOLDER = "-"

-- Row layout ------------------------------------------------------------------
-- Rows are inset ROW_INSET on each side of the display frame, and the name text
-- starts NAME_COLUMN_PAD inside the row. The name column was previously anchored
-- from the row's left padding to CENTER+18; the styling pass scales that span by
-- NAME_COLUMN_SCALE. Deriving the width rather than hardcoding it keeps the
-- reduction proportional across the whole 160-380 "Meter Width" slider range.
local ROW_INSET = 6
local NAME_COLUMN_PAD = 4
local NAME_COLUMN_SCALE = 0.60

-- The damage / DPS / percent values are three right-justified sub-columns rather
-- than one preformatted string, so the gaps below are real layout spacing and the
-- values line up vertically from row to row. NUMBER_GAP separates the three
-- values; NAME_NUMBER_GAP keeps the block clear of the name column. Widths are
-- shared out of whatever space the name column leaves, so nothing collides at the
-- narrow end of the "Meter Width" slider.
local NAME_NUMBER_GAP = 6
local NUMBER_GAP = 6
local NUMBER_SHARE_DAMAGE = 0.38
local NUMBER_SHARE_DPS = 0.32
local NUMBER_SHARE_PCT = 0.30

-- Header row: four toggle buttons (Damage/Healing, Current/Overall) plus Reset.
-- Five fixed-width buttons would overflow at the narrow end of the Meter Width
-- slider, so the row is shared out proportionally instead. The shares sum to 1
-- across the space left after the two edge margins and four inter-button gaps.
local HEADER_MARGIN = 3
local HEADER_GAP = 1
local HEADER_SHARE_TOGGLE = 0.21
local HEADER_SHARE_RESET = 0.16

local function HeaderButtonWidths(meterWidth)
    local avail = meterWidth - HEADER_MARGIN * 2 - HEADER_GAP * 4
    if avail < 60 then avail = 60 end
    return math_max(1, avail * HEADER_SHARE_TOGGLE), math_max(1, avail * HEADER_SHARE_RESET)
end

local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true,
    DAMAGE_SHIELD = true,
}

-- Absorb shields are deliberately not counted as healing. SPELL_ABSORBED needs a
-- separate shield-attribution model to avoid double counting against the heal
-- that would otherwise have landed, and that is analytics work this module has
-- always pushed to Details rather than absorb here.
local HEAL_EVENTS = {
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
}

local TRACKED_EVENTS = {}
for subevent in pairs(DAMAGE_EVENTS) do TRACKED_EVENTS[subevent] = true end
for subevent in pairs(HEAL_EVENTS) do TRACKED_EVENTS[subevent] = true end

local METRIC_DAMAGE = "damage"
local METRIC_HEALING = "healing"

local rosterByGUID = {}
local trackedUnits = {}
local current = nil
local overall = nil
local display, eventFrame
local rows = {}

-- Combat Meter owns these row/header regions exclusively. Cache the last state
-- we pushed so the recurring display refresh does not call expensive frame
-- mutators when the desired UI state is already identical.
local function SetOwnedText(region, text)
    text = text or ""
    if region and region._tfCMText ~= text then
        region:SetText(text)
        region._tfCMText = text
    end
end

local function SetOwnedShown(frame, shown)
    if not frame then return end
    shown = shown == true
    if frame._tfCMShown == shown then return end
    frame._tfCMShown = shown
    if shown then frame:Show() else frame:Hide() end
end

local function SetOwnedWidth(region, width)
    if region and region._tfCMWidth ~= width then
        region:SetWidth(width)
        region._tfCMWidth = width
    end
end

local function SetOwnedVertexColor(texture, r, g, b, a)
    if not texture then return end
    if texture._tfCMR == r and texture._tfCMG == g
        and texture._tfCMB == b and texture._tfCMA == a then
        return
    end
    texture._tfCMR, texture._tfCMG, texture._tfCMB, texture._tfCMA = r, g, b, a
    texture:SetVertexColor(r, g, b, a)
end
local sortedActors, sortedSpells = {}, {}
local runtimeActive = false
local SyncRuntimeCadence
local playerCombatStartHint = nil
local playerCombatEndHint = nil
local selectedActorGUID = nil
local lastUIUpdate = 0
local appliedWidth
local scrollOffset = 0
local scrollCount = 0

local DB = ns.DB   -- shared root accessor (Config.lua)

local function WindowEnabled()
    local on = DB().combatMeterEnabled == true
    return ns.MoverDependentEnabled(on)
end

local function BadgeDataNeeded()
    local badge = ns.DPSBadge
    return badge and badge.NeedsCombatData and badge:NeedsCombatData() or false
end

local function RuntimeEnabled()
    return WindowEnabled() or BadgeDataNeeded()
end

local function NewSegment()
    return {
        active = false,
        startTime = nil,
        endTime = nil,
        lastEventTime = nil,
        outOfCombatTime = nil,
        damage = 0,
        healing = 0,
        actors = {},
    }
end

local function NewOverall()
    return {
        damage = 0,
        healing = 0,
        combatTime = 0,
        actors = {},
    }
end

local function EnsureData()
    if not current then current = NewSegment() end
    if not overall then overall = NewOverall() end
end

local function AddTrackedUnit(unit)
    if not unit or not UnitExists(unit) then return end
    trackedUnits[#trackedUnits + 1] = unit

    local guid = UnitGUID(unit)
    if not guid then return end
    local name = UnitName(unit) or "Unknown"
    local _, class = UnitClass(unit)
    rosterByGUID[guid] = {
        ownerGUID = guid,
        name = name,
        class = class,
        unit = unit,
        isPet = false,
    }
end

local function AddPetUnit(unit, ownerUnit)
    if not unit or not UnitExists(unit) then return end
    local petGUID = UnitGUID(unit)
    local ownerGUID = ownerUnit and UnitGUID(ownerUnit)
    if not petGUID or not ownerGUID then return end

    local owner = rosterByGUID[ownerGUID]
    if not owner then
        AddTrackedUnit(ownerUnit)
        owner = rosterByGUID[ownerGUID]
    end
    if not owner then return end

    rosterByGUID[petGUID] = {
        ownerGUID = ownerGUID,
        name = UnitName(unit) or "Pet",
        ownerName = owner.name,
        class = owner.class,
        unit = unit,
        ownerUnit = ownerUnit,
        isPet = true,
    }
end

function CM:RebuildRoster()
    wipe(rosterByGUID)
    wipe(trackedUnits)

    AddTrackedUnit("player")
    AddPetUnit("pet", "player")

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. i
            AddTrackedUnit(unit)
            AddPetUnit("raidpet" .. i, unit)
        end
    else
        local count
        if GetNumSubgroupMembers then
            count = GetNumSubgroupMembers() or 0
        else
            count = math_max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1)
        end
        if count > 4 then count = 4 end
        for i = 1, count do
            local unit = "party" .. i
            AddTrackedUnit(unit)
            AddPetUnit("partypet" .. i, unit)
        end
    end
end

local function EnsureActor(container, guid, info, fallbackName)
    local actor = container.actors[guid]
    if actor then return actor end
    actor = {
        guid = guid,
        name = (info and (info.isPet and info.ownerName or info.name)) or fallbackName or "Unknown",
        class = info and info.class or nil,
        damage = 0,
        healing = 0,
        spells = {},
    }
    container.actors[guid] = actor
    return actor
end

-- One spell row carries both metrics. A key that only ever heals simply leaves
-- `damage` at zero, and the breakdown filters rows that are zero for the metric
-- being viewed, so the rare ability that does both stays a single row.
local function AddSpell(actor, key, name, metric, amount, critical)
    local spell = actor.spells[key]
    if not spell then
        spell = { key = key, name = name, damage = 0, healing = 0,
                  hits = 0, crits = 0, max = 0 }
        actor.spells[key] = spell
    end
    spell[metric] = spell[metric] + amount
    spell.hits = spell.hits + 1
    if critical then spell.crits = spell.crits + 1 end
    if amount > spell.max then spell.max = amount end
end

local function AddToContainer(container, ownerGUID, info, sourceName, spellKey, spellName, metric, amount, critical)
    local actor = EnsureActor(container, ownerGUID, info, sourceName)
    actor[metric] = actor[metric] + amount
    container[metric] = container[metric] + amount
    AddSpell(actor, spellKey, spellName, metric, amount, critical)
end

local function ParseDamage(e)
    local subevent = e[2]
    if subevent == "SWING_DAMAGE" then
        return tonumber(e[12]) or 0, tonumber(e[13]) or 0, e[18] == true, nil, "Melee"
    end
    if subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE"
        or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_BUILDING_DAMAGE"
        or subevent == "DAMAGE_SHIELD" then
        return tonumber(e[15]) or 0, tonumber(e[16]) or 0, e[21] == true,
            tonumber(e[12]), e[13] or "Spell"
    end
    return 0, 0, false, nil, nil
end

-- Effective healing only: overhealing is subtracted rather than padding totals,
-- matching how ParseDamage/OnCombatLog subtract overkill.
local function ParseHeal(e)
    local subevent = e[2]
    if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        return tonumber(e[15]) or 0, tonumber(e[16]) or 0, e[18] == true,
            tonumber(e[12]), e[13] or "Spell"
    end
    return 0, 0, false, nil, nil
end

local function StartCurrent(now)
    current = NewSegment()
    current.active = true
    local hint = playerCombatStartHint
    if hint and now - hint >= 0 and now - hint <= 3 then
        current.startTime = hint
    else
        current.startTime = now
    end
    current.lastEventTime = now
    current.endTime = nil
    playerCombatEndHint = nil
    selectedActorGUID = nil
end

local function CurrentDuration(now)
    if not current or not current.startTime then return 0 end
    local finish
    if current.active then
        -- As soon as the tracked group is observed out of combat, freeze the
        -- displayed duration there while the merge grace remains open. A new
        -- damage event clears this candidate and resumes the same segment.
        finish = current.outOfCombatTime or (now or GetTime())
    else
        finish = current.endTime or current.lastEventTime or current.startTime
    end
    local duration = finish - current.startTime
    if duration < 0.1 then duration = 0.1 end
    return duration
end

local function OverallDuration(now)
    local duration = overall and overall.combatTime or 0
    if current and current.active then duration = duration + CurrentDuration(now) end
    if duration < 0.1 and overall and overall.damage > 0 then duration = 0.1 end
    return duration
end

local function AnyTrackedUnitInCombat()
    if not UnitAffectingCombat then return false end
    for i = 1, #trackedUnits do
        local unit = trackedUnits[i]
        if UnitExists(unit) and UnitAffectingCombat(unit) then return true end
    end
    return false
end

local function FinalizeCurrent(now)
    if not current or not current.active then return end
    local finish = current.lastEventTime or now
    if current.outOfCombatTime and current.outOfCombatTime >= (current.startTime or 0) then
        finish = math_max(finish, current.outOfCombatTime)
    elseif playerCombatEndHint and playerCombatEndHint >= (current.startTime or 0) then
        finish = math_max(finish, playerCombatEndHint)
    end
    current.endTime = finish
    current.active = false
    local duration = CurrentDuration(now)
    overall.combatTime = (overall.combatTime or 0) + duration
    playerCombatEndHint = nil
end

local function MaybeFinalize(now)
    if not current or not current.active or not current.lastEventTime then return end
    local grace = tonumber(DB().combatMeterMergeWindow) or 1.5
    if grace < 0.25 then grace = 0.25 end
    local quiet = now - current.lastEventTime
    local inCombat = AnyTrackedUnitInCombat()

    if inCombat then
        current.outOfCombatTime = nil
        -- A stale/broken combat flag must not hold Current open forever. This
        -- fallback is intentionally generous for leveling/dungeon mechanics.
        if quiet < STALE_COMBAT_TIMEOUT then return end
    else
        if not current.outOfCombatTime then current.outOfCombatTime = now end
        if quiet < grace then return end
    end

    FinalizeCurrent(now)
end

-- Breakdown identity for one damage source. This runs on EVERY tracked damage
-- event, and the naive form allocated four strings per event (two tostring
-- calls plus two concatenations) which then fed two AddToContainer calls.
--
-- Spell IDs repeat constantly inside a fight, so the pair is memoised on a
-- two-level table keyed by pet-ness then spell ID. Steady-state cost after the
-- first hit with a given spell is two table lookups and zero allocation.
-- Bounded by the number of distinct spells seen, and cleared with the rest of
-- the meter state on reset.
local spellIdentityCache = { [false] = {}, [true] = {} }

local function SpellIdentity(info, spellID, spellName)
    local isPet = (info and info.isPet) and true or false
    local bucket = spellIdentityCache[isPet]
    local key = spellID or "swing"

    local cached = bucket[key]
    if cached then return cached[1], cached[2] end

    local prefix = isPet and "pet:" or "self:"
    local idKey, displayName
    if spellID then
        idKey = prefix .. tostring(spellID)
        displayName = (isPet and "Pet: " or "") .. tostring(spellName or spellID)
    else
        idKey = prefix .. "swing"
        displayName = isPet and "Pet: Melee" or "Melee"
    end

    -- Only memoise a settled answer. With a cold client cache spellName can be
    -- nil, in which case displayName falls back to the numeric ID; caching that
    -- would freeze the placeholder in the breakdown for the whole session.
    if spellName or not spellID then
        bucket[key] = { idKey, displayName }
    end
    return idKey, displayName
end

local function OnCombatLog(e)
    local subevent = e[2]
    local isHeal = HEAL_EVENTS[subevent]
    if not isHeal and not DAMAGE_EVENTS[subevent] then return end

    local sourceGUID = e[4]
    local info = sourceGUID and rosterByGUID[sourceGUID]
    if not info then return end

    local amount, excess, critical, spellID, spellName
    if isHeal then
        amount, excess, critical, spellID, spellName = ParseHeal(e)
    else
        -- Self-damage is excluded, but self-healing is real output and counts.
        local destGUID = e[8]
        if destGUID and destGUID == sourceGUID then return end
        amount, excess, critical, spellID, spellName = ParseDamage(e)
    end

    if amount <= 0 then return end
    if excess and excess > 0 then amount = amount - excess end
    if amount <= 0 then return end

    EnsureData()
    local now = GetTime()
    if not current.active then
        -- Damage opens a segment on its own. Healing may not: topping the group
        -- up after a pull would otherwise spawn a phantom fight whose duration
        -- then drags every rate down. A heal only opens a segment when a tracked
        -- unit is actually in combat, which is what a healer who never damages
        -- needs.
        if isHeal and not AnyTrackedUnitInCombat() then return end
        StartCurrent(now)
    end
    current.lastEventTime = now
    current.outOfCombatTime = nil
    playerCombatEndHint = nil

    local ownerGUID = info.ownerGUID or sourceGUID
    local ownerInfo = rosterByGUID[ownerGUID] or info
    local spellKey, displayName = SpellIdentity(info, spellID, spellName)
    local sourceName = ownerInfo and ownerInfo.name or e[5]
    local metric = isHeal and METRIC_HEALING or METRIC_DAMAGE

    AddToContainer(current, ownerGUID, ownerInfo, sourceName, spellKey, displayName, metric, amount, critical)
    AddToContainer(overall, ownerGUID, ownerInfo, sourceName, spellKey, displayName, metric, amount, critical)
end

local function FormatNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if value >= 1000 then return string.format("%.1fk", value / 1000) end
    return tostring(math_floor(value + 0.5))
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return 0.25, 0.75, 1
end

local function StyleText(fs, size)
    if not fs then return end
    if ns.StyleFeatureFont then
        ns:StyleFeatureFont(fs, size, "combatMeterFont", "combatMeterTextStyle")
    else
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    end
end

local function GetBarTexture()
    if ns.GetTexture then
        local ok, texture = pcall(ns.GetTexture, DB().texture or "Blizzard")
        if ok and texture then return texture end
    end
    return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

local function MakeTextButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 18)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    StyleText(fs, 10)
    fs:SetText(text)
    b.text = fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(1, 1, 1, 0.08)
    return b
end

-- Current metric, sanitised. Every read goes through this so an unexpected saved
-- value can never leak into a table index.
local function ViewMetric()
    return DB().combatMeterMetric == METRIC_HEALING and METRIC_HEALING or METRIC_DAMAGE
end

-- Amount an actor/spell/container contributed under the selected metric.
local function MetricAmount(entry, metric)
    if not entry then return 0 end
    return entry[metric] or 0
end

local function ResetScroll()
    scrollOffset = 0
end

local function SetMode(mode)
    if mode ~= "overall" then mode = "current" end
    DB().combatMeterView = mode
    selectedActorGUID = nil
    ResetScroll()
    lastUIUpdate = 0
    -- Surfaces that mirror the meter's number follow this selection. The badge's
    -- own ticker only runs in combat and the view is usually changed out of it,
    -- so push the change rather than waiting to be polled.
    if ns.DPSBadge and ns.DPSBadge.Update then ns.DPSBadge:Update() end
end

local function ApplyMetric(metric)
    if metric ~= METRIC_HEALING then metric = METRIC_DAMAGE end
    DB().combatMeterMetric = metric
    -- The selected actor may have no rows under the new metric, and a breakdown
    -- of nothing is worse than dropping back to the rankings.
    selectedActorGUID = nil
    ResetScroll()
    lastUIUpdate = 0
    if ns.DPSBadge and ns.DPSBadge.Update then ns.DPSBadge:Update() end
end

local function MeterWidth()
    local width = tonumber(DB().combatMeterWidth) or 260
    if width < 160 then width = 160 elseif width > 380 then width = 380 end
    return width
end

local function NameColumnWidth(meterWidth)
    local rowWidth = meterWidth - ROW_INSET * 2
    -- Former geometry: LEFT+NAME_COLUMN_PAD .. CENTER+18, i.e. rowWidth/2 + 14.
    local previous = rowWidth * 0.5 + 14
    return math_max(1, previous * NAME_COLUMN_SCALE)
end

local function NumberColumnWidths(meterWidth)
    local rowWidth = meterWidth - ROW_INSET * 2
    local used = NAME_COLUMN_PAD + NameColumnWidth(meterWidth) + NAME_NUMBER_GAP
    local avail = rowWidth - used - NAME_COLUMN_PAD - NUMBER_GAP * 2
    if avail < 30 then avail = 30 end
    return math_max(1, avail * NUMBER_SHARE_DAMAGE),
           math_max(1, avail * NUMBER_SHARE_DPS),
           math_max(1, avail * NUMBER_SHARE_PCT)
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_INSET, -26 - (index - 1) * 18)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ROW_INSET, -26 - (index - 1) * 18)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.18)

    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetTexture(GetBarTexture())
    row.bar = bar

    local left = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    left:SetPoint("LEFT", NAME_COLUMN_PAD, 0)
    left:SetWidth(NameColumnWidth(MeterWidth()))
    left:SetJustifyH("LEFT")
    left:SetWordWrap(false)
    StyleText(left, 10)
    row.left = left

    local dmgW, dpsW, pctW = NumberColumnWidths(MeterWidth())

    local pct = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pct:SetPoint("RIGHT", -NAME_COLUMN_PAD, 0)
    pct:SetWidth(pctW)
    pct:SetJustifyH("RIGHT")
    pct:SetWordWrap(false)
    StyleText(pct, 10)
    row.rightPct = pct

    local dps = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dps:SetPoint("RIGHT", pct, "LEFT", -NUMBER_GAP, 0)
    dps:SetWidth(dpsW)
    dps:SetJustifyH("RIGHT")
    dps:SetWordWrap(false)
    StyleText(dps, 10)
    row.rightDPS = dps

    local damage = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    damage:SetPoint("RIGHT", dps, "LEFT", -NUMBER_GAP, 0)
    damage:SetWidth(dmgW)
    damage:SetJustifyH("RIGHT")
    damage:SetWordWrap(false)
    StyleText(damage, 10)
    row.rightDamage = damage

    row.numbers = { damage, dps, pct }

    row:SetScript("OnClick", function(self)
        if self.actorGUID then
            selectedActorGUID = self.actorGUID
            ResetScroll()
            lastUIUpdate = 0
        end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) CM:Scroll(delta) end)
    SetOwnedShown(row, false)
    return row
end

local function UpdateDimensions()
    if not display then return end
    local width = MeterWidth()
    if appliedWidth == width then return end
    appliedWidth = width
    local height = 26 + VISIBLE_ROWS * 18 + 20
    display:SetSize(width, height)

    local toggleW, resetW = HeaderButtonWidths(width)
    local compact = width < 210
    display.damageBtn.text:SetText(compact and "Dmg" or "Damage")
    display.healingBtn.text:SetText(compact and "Heal" or "Healing")
    display.currentBtn.text:SetText(compact and "Cur" or "Current")
    display.overallBtn.text:SetText(compact and "All" or "Overall")
    display.resetBtn.text:SetText(width < 180 and "Rst" or "Reset")
    display.damageBtn:SetWidth(toggleW)
    display.healingBtn:SetWidth(toggleW)
    display.currentBtn:SetWidth(toggleW)
    display.overallBtn:SetWidth(toggleW)
    display.resetBtn:SetWidth(resetW)
    display.backBtn:SetWidth(resetW)

    local nameWidth = NameColumnWidth(width)
    local dmgW, dpsW, pctW = NumberColumnWidths(width)
    for i = 1, #rows do
        local row = rows[i]
        row.left:SetWidth(nameWidth)
        row.rightDamage:SetWidth(dmgW)
        row.rightDPS:SetWidth(dpsW)
        row.rightPct:SetWidth(pctW)
    end
    if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("CombatMeter") end
end

local function EnsureRows(count)
    for i = #rows + 1, count do rows[i] = CreateRow(display, i) end
end

local function EnsureDisplay()
    if display then return display end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    display = CreateFrame("Frame", "TurboFaceCombatMeter", UIParent, template)
    display:SetSize(260, 136)
    display:SetPoint("CENTER", UIParent, "CENTER", 330, 30)
    display:SetFrameStrata("MEDIUM")
    display:SetClampedToScreen(true)
    display:EnableMouse(true)
    display:EnableMouseWheel(true)
    display:SetScript("OnMouseWheel", function(_, delta) CM:Scroll(delta) end)
    if ns.ApplyBarBackdrop then ns:ApplyBarBackdrop(display) end

    local title = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 7, -6)
    StyleText(title, 11)
    title:SetText("Damage")
    title:SetTextColor(1, 1, 1)
    display.title = title

    -- Header is a 2x2 selector: metric on the left, view on the right, Reset
    -- pinned to the corner. Buttons chain inward from both edges so the row can
    -- be re-sized from one place in UpdateDimensions.
    local damageBtn = MakeTextButton(display, "Damage", 48)
    damageBtn:SetPoint("TOPLEFT", display, "TOPLEFT", HEADER_MARGIN, -2)
    damageBtn:SetScript("OnClick", function() ApplyMetric(METRIC_DAMAGE) end)
    display.damageBtn = damageBtn

    local healingBtn = MakeTextButton(display, "Healing", 48)
    healingBtn:SetPoint("LEFT", damageBtn, "RIGHT", HEADER_GAP, 0)
    healingBtn:SetScript("OnClick", function() ApplyMetric(METRIC_HEALING) end)
    display.healingBtn = healingBtn

    local resetBtn = MakeTextButton(display, "Reset", 36)
    resetBtn:SetPoint("TOPRIGHT", display, "TOPRIGHT", -HEADER_MARGIN, -2)
    resetBtn:SetScript("OnClick", function() CM:Reset() end)
    display.resetBtn = resetBtn

    local overallBtn = MakeTextButton(display, "Overall", 48)
    overallBtn:SetPoint("RIGHT", resetBtn, "LEFT", -HEADER_GAP, 0)
    overallBtn:SetScript("OnClick", function() SetMode("overall") end)
    display.overallBtn = overallBtn

    local currentBtn = MakeTextButton(display, "Current", 48)
    currentBtn:SetPoint("RIGHT", overallBtn, "LEFT", -HEADER_GAP, 0)
    currentBtn:SetScript("OnClick", function() SetMode("current") end)
    display.currentBtn = currentBtn

    local backBtn = MakeTextButton(display, "Back", 36)
    backBtn:SetPoint("TOPRIGHT", display, "TOPRIGHT", -HEADER_MARGIN, -2)
    backBtn:SetScript("OnClick", function() selectedActorGUID = nil; ResetScroll(); lastUIUpdate = 0 end)
    backBtn:Hide()
    display.backBtn = backBtn

    local footer = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    footer:SetPoint("BOTTOMLEFT", 7, 5)
    footer:SetPoint("BOTTOMRIGHT", -7, 5)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)
    footer:SetTextColor(0.65, 0.65, 0.65)
    StyleText(footer, 9)
    display.footer = footer

    EnsureRows(VISIBLE_ROWS)
    UpdateDimensions()
    return display
end

local function ApplyVisuals()
    if not display then return end
    if ns.ApplyBarBackdrop then ns:ApplyBarBackdrop(display) end
    local texture = GetBarTexture()
    StyleText(display.title, 11)
    StyleText(display.footer, 9)
    StyleText(display.damageBtn and display.damageBtn.text, 10)
    StyleText(display.healingBtn and display.healingBtn.text, 10)
    StyleText(display.currentBtn and display.currentBtn.text, 10)
    StyleText(display.overallBtn and display.overallBtn.text, 10)
    StyleText(display.resetBtn and display.resetBtn.text, 10)
    StyleText(display.backBtn and display.backBtn.text, 10)
    for i = 1, #rows do
        local row = rows[i]
        if row then
            StyleText(row.left, 10)
            if row.numbers then
                for n = 1, #row.numbers do StyleText(row.numbers[n], 10) end
            end
            if row.bar then row.bar:SetTexture(texture) end
        end
    end
end

-- Sorting is synchronous, so one file-owned metric selector lets both hot
-- sort paths reuse a static comparator instead of allocating a closure on every
-- visible meter refresh.
local activeSortMetric
local function CompareMetricEntries(a, b)
    local av, bv = MetricAmount(a, activeSortMetric), MetricAmount(b, activeSortMetric)
    if av == bv then return tostring(a.name) < tostring(b.name) end
    return av > bv
end

local function SortActors(container, metric)
    wipe(sortedActors)
    if not container then return sortedActors end
    for _, actor in pairs(container.actors or {}) do
        -- An actor with no output under this metric is not a zero-DPS entry, it
        -- is simply not participating in what is being measured. Listing them
        -- would push real contributors off a party-sized meter.
        if MetricAmount(actor, metric) > 0 then
            sortedActors[#sortedActors + 1] = actor
        end
    end
    activeSortMetric = metric
    table_sort(sortedActors, CompareMetricEntries)
    activeSortMetric = nil
    return sortedActors
end

local function SortSpells(actor, metric)
    wipe(sortedSpells)
    if not actor then return sortedSpells end
    for _, spell in pairs(actor.spells or {}) do
        if MetricAmount(spell, metric) > 0 then
            sortedSpells[#sortedSpells + 1] = spell
        end
    end
    activeSortMetric = metric
    table_sort(sortedSpells, CompareMetricEntries)
    activeSortMetric = nil
    return sortedSpells
end

local function SourceForView(now)
    local mode = DB().combatMeterView == "overall" and "overall" or "current"
    local metric = ViewMetric()
    if mode == "overall" then return overall, OverallDuration(now), mode, metric end
    return current, CurrentDuration(now), mode, metric
end

local function ClearRows(from)
    for i = from or 1, #rows do
        rows[i].actorGUID = nil
        SetOwnedShown(rows[i], false)
    end
end

local SELECTED_R, SELECTED_G, SELECTED_B = 0, 0.85, 1
local UNSELECTED = 0.7

local function SetToggleSelected(button, selected)
    if not button or not button.text then return end
    selected = selected == true
    if button._tfCMSelected == selected then return end
    button._tfCMSelected = selected
    if selected then
        button.text:SetTextColor(SELECTED_R, SELECTED_G, SELECTED_B)
    else
        button.text:SetTextColor(UNSELECTED, UNSELECTED, UNSELECTED)
    end
end

-- Ranking view shows the 2x2 selector (Damage/Healing on the left, Current/
-- Overall on the right) plus Reset. Breakdown replaces the lot with Back and
-- borrows the title line for the actor name, which is why the metric buttons
-- and the title are mutually exclusive rather than stacked.
local function UpdateButtons(mode, metric, breakdown)
    if not display then return end
    if breakdown then
        SetOwnedShown(display.damageBtn, false)
        SetOwnedShown(display.healingBtn, false)
        SetOwnedShown(display.currentBtn, false)
        SetOwnedShown(display.overallBtn, false)
        SetOwnedShown(display.resetBtn, false)
        SetOwnedShown(display.title, true)
        SetOwnedShown(display.backBtn, true)
        return
    end

    SetOwnedShown(display.damageBtn, true)
    SetOwnedShown(display.healingBtn, true)
    SetOwnedShown(display.currentBtn, true)
    SetOwnedShown(display.overallBtn, true)
    SetOwnedShown(display.resetBtn, true)
    SetOwnedShown(display.title, false)
    SetOwnedShown(display.backBtn, false)

    SetToggleSelected(display.damageBtn, metric ~= METRIC_HEALING)
    SetToggleSelected(display.healingBtn, metric == METRIC_HEALING)
    SetToggleSelected(display.currentBtn, mode == "current")
    SetToggleSelected(display.overallBtn, mode == "overall")
end

local function UpdateBreakdown(container, duration, mode, metric, actor)
    local spells = SortSpells(actor, metric)
    scrollCount = #spells
    local maxOffset = math_max(0, scrollCount - VISIBLE_ROWS)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end
    local top = spells[1] and MetricAmount(spells[1], metric) or 1
    local r, g, b = ClassColor(actor.class)
    local actorTotal = MetricAmount(actor, metric)
    local healing = metric == METRIC_HEALING
    local barAlpha = tonumber(DB().combatMeterBarAlpha) or 0.42

    SetOwnedText(display.title, (actor.name or "Unknown") .. " — " .. (mode == "overall" and "Overall" or "Current"))
    UpdateButtons(mode, metric, true)

    for i = 1, VISIBLE_ROWS do
        local sourceIndex = scrollOffset + i
        local row, spell = rows[i], spells[sourceIndex]
        if spell then
            local value = MetricAmount(spell, metric)
            row.actorGUID = nil
            SetOwnedText(row.left, spell.name or "Unknown")
            local pct = actorTotal > 0 and (value / actorTotal * 100) or 0
            SetOwnedText(row.rightDamage, FormatNumber(value))
            SetOwnedText(row.rightDPS, "")
            SetOwnedText(row.rightPct, string.format("%.0f%%", pct))
            SetOwnedVertexColor(row.bar, r, g, b, barAlpha)
            SetOwnedWidth(row.bar, math_max(1, row:GetWidth() * (value / top)))
            SetOwnedShown(row, true)
        else
            SetOwnedShown(row, false)
        end
    end
    ClearRows(VISIBLE_ROWS + 1)
    local rate = duration > 0 and actorTotal / duration or 0
    local scrollText = ""
    if scrollCount > VISIBLE_ROWS then
        scrollText = string.format(" • %d-%d/%d • wheel",
            scrollOffset + 1, math_min(scrollOffset + VISIBLE_ROWS, scrollCount), scrollCount)
    end
    SetOwnedText(display.footer, string.format("%s %s • %.1f %s%s",
        FormatNumber(actorTotal), healing and "heal" or "dmg",
        rate, healing and "HPS" or "DPS", scrollText))
end

local function UpdateRankings(container, duration, mode, metric)
    local actors = SortActors(container, metric)
    scrollCount = #actors
    local maxOffset = math_max(0, scrollCount - VISIBLE_ROWS)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end
    local top = actors[1] and MetricAmount(actors[1], metric) or 1
    local total = MetricAmount(container, metric)
    local healing = metric == METRIC_HEALING
    local barAlpha = tonumber(DB().combatMeterBarAlpha) or 0.42

    UpdateButtons(mode, metric, false)

    for i = 1, VISIBLE_ROWS do
        local sourceIndex = scrollOffset + i
        local row, actor = rows[i], actors[sourceIndex]
        if actor then
            local value = MetricAmount(actor, metric)
            row.actorGUID = actor.guid
            local r, g, b = ClassColor(actor.class)
            local rate = duration > 0 and value / duration or 0
            local pct = total > 0 and value / total * 100 or 0
            SetOwnedText(row.left, string.format("%d. %s", sourceIndex, actor.name or "Unknown"))
            SetOwnedText(row.rightDamage, FormatNumber(value))
            SetOwnedText(row.rightDPS, string.format("%.0f", rate))
            SetOwnedText(row.rightPct, string.format("%.0f%%", pct))
            SetOwnedVertexColor(row.bar, r, g, b, barAlpha)
            SetOwnedWidth(row.bar, math_max(1, row:GetWidth() * (value / top)))
            SetOwnedShown(row, true)
        else
            row.actorGUID = nil
            SetOwnedShown(row, false)
        end
    end
    ClearRows(VISIBLE_ROWS + 1)

    if total <= 0 then
        if mode == "overall" then
            SetOwnedText(display.footer, healing and "No session healing yet." or "No session damage yet.")
        else
            SetOwnedText(display.footer, healing and "No healing this fight yet." or "No current fight yet.")
        end
    else
        local active = (mode == "current" and current and current.active) and " • active" or ""
        local scrollText = ""
        if scrollCount > VISIBLE_ROWS then
            scrollText = string.format(" • %d-%d/%d • wheel",
                scrollOffset + 1, math_min(scrollOffset + VISIBLE_ROWS, scrollCount), scrollCount)
        end
        SetOwnedText(display.footer, string.format("%.1fs%s%s", duration, active, scrollText))
    end
end

function CM:Scroll(delta)
    delta = tonumber(delta) or 0
    if delta == 0 or scrollCount <= VISIBLE_ROWS then return end
    local maxOffset = math_max(0, scrollCount - VISIBLE_ROWS)
    local nextOffset = scrollOffset + (delta < 0 and 1 or -1)
    if nextOffset < 0 then nextOffset = 0 elseif nextOffset > maxOffset then nextOffset = maxOffset end
    if nextOffset == scrollOffset then return end
    scrollOffset = nextOffset
    lastUIUpdate = 0
    self:UpdateDisplay(true)
end

function CM:UpdateDisplay(force)
    if not display then return end
    if not WindowEnabled() then display:Hide(); return end
    if self:IsDisplayHidden() then return end

    local now = GetTime()
    local refresh = tonumber(DB().combatMeterRefresh) or 0.25
    if not force and now - lastUIUpdate < refresh then return end
    lastUIUpdate = now

    UpdateDimensions()
    local container, duration, mode, metric = SourceForView(now)
    local actor = selectedActorGUID and container and container.actors and container.actors[selectedActorGUID] or nil
    if selectedActorGUID and not actor then selectedActorGUID = nil; ResetScroll() end

    if actor then UpdateBreakdown(container, duration, mode, metric, actor)
    else UpdateRankings(container, duration, mode, metric) end

    if not display:IsShown() then display:Show() end
end

-- Which view the meter is currently showing. Exposed so surfaces that mirror the
-- meter can label themselves without duplicating the setting's default handling.
function CM:GetView()
    return DB().combatMeterView == "overall" and "overall" or "current"
end

-- Which metric the meter is currently showing: "damage" or "healing".
function CM:GetMetric()
    return ViewMetric()
end

-- Select a metric directly. Routed through the same file-local the header
-- buttons use, so the redraw and the badge push are identical either way.
function CM:SetMetric(metric)
    ApplyMetric(metric)
    return ViewMetric()
end

-- Select a view directly, sharing the view buttons' code path.
function CM:SetView(mode)
    SetMode(mode)
    return self:GetView()
end

-- Read-only accessor for other TurboFace surfaces that want the player's own DPS/HPS.
-- The independent PlayerFrame badge is the primary headless consumer. CombatMeter remains the
-- sole owner of damage accounting; callers get numbers or nil and never touch the
-- segment tables.
--
-- Follows the meter's own Current/Overall selection, so the meter's view buttons
-- drive every mirror of this number rather than each surface picking its own.
--
-- Returns nil when the runtime is not collecting, when the selected view has no
-- container, or when the player has not dealt damage in it. The fourth return is
-- seconds since the last tracked damage, which lets a caller decide when a frozen
-- value has gone stale; the fifth is the view the numbers came from.
function CM:GetPlayerRate()
    if not runtimeActive then return nil end
    local now = GetTime()
    local container, duration, mode, metric = SourceForView(now)
    if not container or duration <= 0 then return nil end

    local guid = UnitGUID("player")
    local actor = guid and container.actors and container.actors[guid]
    local total = MetricAmount(actor, metric)
    if not actor or total <= 0 then return nil end

    -- Overall is a session total measured against summed combat time, so quiet
    -- time does not make it wrong -- it stays valid until reload or reset. Only
    -- the Current segment can go stale, so only Current reports idle time.
    local idle = 0
    if mode ~= "overall" and current then
        idle = now - (current.lastEventTime or now)
        if idle < 0 then idle = 0 end
    end

    return total / duration, total, duration, idle, mode, metric
end

function CM:IsSupported()
    return true
end

-- Provider-neutral badge renderer.  The Classic provider owns readable local
-- numbers, so it can preserve the historical compact k-format.  Forever's
-- Blizzard provider implements the same method but forwards its opaque value
-- directly into a secret-capable FontString sink.
function CM:RenderPlayerRate(fontString, staleAfter)
    if not fontString then return false end
    local rate, _, _, idle = self:GetPlayerRate()
    if rate and (idle or 0) <= (tonumber(staleAfter) or 30) then
        fontString:SetText(rate >= 1000 and string.format("%.1fk", rate / 1000)
            or string.format("%d", rate + 0.5))
        return true
    end
    fontString:SetText(PLAYER_RATE_PLACEHOLDER)
    return false
end

function CM:GetBadgeTooltipHint()
    if self:CanToggleDisplay() then
        return self:IsDisplayHidden() and "Left-click to show the damage meter."
            or "Left-click to hide the damage meter."
    end
    return "Combat Meter window is disabled; badge accounting remains active."
end

-- Visibility is deliberately delegated to the Movers element flag rather than a
-- private show/hide of `display`. Movers already persists a per-element hidden
-- state, already drives the panel's Hide button, and already makes hidden
-- elements click-through -- so routing through it keeps one source of truth and
-- means the badge and the Movers panel can never disagree. A local display:Hide()
-- would also just be undone by the next window refresh.
function CM:IsDisplayHidden()
    local movers = ns.Movers
    if not movers or not movers.IsElementHidden then return false end
    return movers:IsElementHidden("CombatMeter") == true
end

function CM:CanToggleDisplay()
    return WindowEnabled()
end

-- Returns the new hidden state, or nil when the toggle could not be applied.
function CM:ToggleDisplay()
    if not WindowEnabled() then return nil end
    local movers = ns.Movers
    if not movers or not movers.SetElementHidden or not movers.IsElementHidden then return nil end
    local hidden = not self:IsDisplayHidden()
    movers:SetElementHidden("CombatMeter", hidden)
    return hidden
end

local function InvalidateOwnedWriteState()
    if not display then return end
    local shownObjects = {
        display.damageBtn, display.healingBtn, display.currentBtn,
        display.overallBtn, display.resetBtn, display.backBtn, display.title,
    }
    for i = 1, #shownObjects do
        if shownObjects[i] then shownObjects[i]._tfCMShown = nil end
    end
    local toggleButtons = { display.damageBtn, display.healingBtn, display.currentBtn, display.overallBtn }
    for i = 1, #toggleButtons do
        if toggleButtons[i] then toggleButtons[i]._tfCMSelected = nil end
    end
    if display.title then display.title._tfCMText = nil end
    if display.footer then display.footer._tfCMText = nil end
    for i = 1, #rows do
        local row = rows[i]
        if row then
            row._tfCMShown = nil
            if row.left then row.left._tfCMText = nil end
            if row.rightDamage then row.rightDamage._tfCMText = nil end
            if row.rightDPS then row.rightDPS._tfCMText = nil end
            if row.rightPct then row.rightPct._tfCMText = nil end
            if row.bar then
                row.bar._tfCMWidth = nil
                row.bar._tfCMR, row.bar._tfCMG, row.bar._tfCMB, row.bar._tfCMA = nil, nil, nil, nil
            end
        end
    end
end

function CM:GetChildren()
    local out = {}
    if not display then return out end
    out[#out + 1] = display.damageBtn
    out[#out + 1] = display.healingBtn
    out[#out + 1] = display.currentBtn
    out[#out + 1] = display.overallBtn
    out[#out + 1] = display.resetBtn
    out[#out + 1] = display.backBtn
    for i = 1, #rows do out[#out + 1] = rows[i] end
    return out
end

function CM:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("CombatMeter", display, {
        label = "Combat Meter",
        overlayWidth = display:GetWidth(),
        overlayHeight = display:GetHeight(),
        fallbackPoint = { "CENTER", UIParent, "CENTER", 330, 30 },
        defaultPoint = { "CENTER", UIParent, "CENTER", 330, 30 },
        getChildren = function() return CM:GetChildren() end,
        isAvailable = function() return WindowEnabled() end,
        onApply = function()
            SyncRuntimeCadence()
            if not CM:IsDisplayHidden() then InvalidateOwnedWriteState() end
            CM:UpdateDisplay(true)
        end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("CombatMeter") end
end

function CM:Reset()
    current = NewSegment()
    overall = NewOverall()
    wipe(spellIdentityCache[false])
    wipe(spellIdentityCache[true])
    selectedActorGUID = nil
    ResetScroll()
    playerCombatStartHint = UnitAffectingCombat and UnitAffectingCombat("player") and GetTime() or nil
    playerCombatEndHint = nil
    lastUIUpdate = 0
    self:UpdateDisplay(true)
    -- Same push as the view/metric setters: out of combat nothing polls the
    -- badge, so without this it would keep showing the totals just wiped.
    if ns.DPSBadge and ns.DPSBadge.Update then ns.DPSBadge:Update() end
end

function CM:GetDebugState()
    EnsureData()
    local now = GetTime()
    return {
        enabled = WindowEnabled(),
        windowEnabled = WindowEnabled(),
        windowHidden = self:IsDisplayHidden(),
        badgeConsumer = BadgeDataNeeded(),
        runtimeNeeded = RuntimeEnabled(),
        runtime = runtimeActive,
        currentActive = current.active,
        metric = ViewMetric(),
        currentDamage = current.damage,
        currentHealing = current.healing,
        currentDuration = CurrentDuration(now),
        currentActors = current.actors,
        overallDamage = overall.damage,
        overallHealing = overall.healing,
        overallDuration = OverallDuration(now),
        overallActors = overall.actors,
        roster = rosterByGUID,
    }
end

function CM:HandleSlash(args)
    args = (args or ""):lower()
    if args == "reset" then
        self:Reset()
        if ns.Chat then ns:Chat("Meter", "Current and Overall totals reset.") end
    elseif args == "damage" then
        ApplyMetric(METRIC_DAMAGE)
        self:UpdateDisplay(true)
    elseif args == "healing" or args == "heal" then
        ApplyMetric(METRIC_HEALING)
        self:UpdateDisplay(true)
    elseif args == "overall" then
        SetMode("overall")
        self:UpdateDisplay(true)
    elseif args == "current" then
        SetMode("current")
        self:UpdateDisplay(true)
    elseif args == "show" then
        if self:IsDisplayHidden() then self:ToggleDisplay() end
    elseif args == "hide" then
        if not self:IsDisplayHidden() then self:ToggleDisplay() end
    else
        self:ToggleDisplay()
    end
end

local function OnEvent(_, event)
    if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
        CM:RebuildRoster()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        playerCombatStartHint = GetTime()
        playerCombatEndHint = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        playerCombatEndHint = GetTime()
        playerCombatStartHint = nil
    end
end

local function RuntimeTick()
    local now = GetTime()
    MaybeFinalize(now)
    if WindowEnabled() and not CM:IsDisplayHidden() then CM:UpdateDisplay(false) end
end

SyncRuntimeCadence = function()
    if not runtimeActive then return end
    local visible = WindowEnabled() and not CM:IsDisplayHidden()
    -- Hidden and badge-only windows still finalize fights, but do not redraw.
    ns.Cadence:Add(CM, visible and 0.10 or 0.25, RuntimeTick)
end

local function ActivateRuntime()
    if not runtimeActive then
        runtimeActive = true
        EnsureData()
        CM:RebuildRoster()

        if ns.CLEU then ns.CLEU:Register(OnCombatLog, TRACKED_EVENTS) end

        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("UNIT_PET")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    SyncRuntimeCadence()
end

local function DeactivateRuntime()
    if not runtimeActive then return end
    -- Once collection stops, the current segment cannot remain "active": any
    -- damage that happens while disabled is intentionally unknown. Freeze the
    -- observed portion so re-enabling starts a clean Current fight.
    if current and current.active then FinalizeCurrent(GetTime()) end
    runtimeActive = false
    if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
    eventFrame:UnregisterAllEvents()
    ns.Cadence:Remove(CM)
end

function CM:Init()
    if ns.Providers and not ns.Providers:IsActive("combatMeter", self) then return end
    EnsureData()
    eventFrame = eventFrame or CreateFrame("Frame")
    -- Kill-traced: PLAYER_REGEN_ENABLED here starts encounter finalization and
    -- the merge-window bookkeeping, which is post-combat work by definition.
    eventFrame:SetScript("OnEvent", function(frame, event, ...)
        ns.KillTrace("Combat/CombatMeter:", event, OnEvent, frame, event, ...)
    end)

    ns.RegisterCPUProfileTarget("Combat/CombatMeter:RuntimeTick", RuntimeTick)

    self:Refresh()
end

function CM:Refresh()
    -- A stale direct refresh must never wake a non-selected provider.  Provider
    -- choice belongs to Core/Providers.lua, not to client checks in this file.
    if ns.Providers and not ns.Providers:IsActive("combatMeter", self) then
        if runtimeActive then DeactivateRuntime() end
        if display then display:Hide() end
        return
    end

    -- Runtime activation is controlled by the normal Combat Meter options.
    local window = WindowEnabled()
    local runtime = RuntimeEnabled()

    if window then
        EnsureDisplay()
        appliedWidth = nil
        UpdateDimensions()
        ApplyVisuals()
        self:RegisterMover()
    elseif display then
        display:Hide()
    end

    if runtime then ActivateRuntime() else DeactivateRuntime() end

    if window then self:UpdateDisplay(true) end
    if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("CombatMeter") end
    if ns.DPSBadge and ns.DPSBadge.Update then ns.DPSBadge:Update() end
end

ns.RegisterCPUProfileTarget("Combat/CombatMeter:CLEU", OnCombatLog)
ns.RegisterCPUProfileTarget("Combat/CombatMeter:Events", OnEvent)

if ns.Providers then
    ns.Providers:Register("combatMeter", "turboface-local", CM, 10)
end
