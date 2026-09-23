local _, ns = ...

-- =============================================================================
-- TurboFace ClassFeatures.lua
-- Classic Era class-specific helpers. Current feature set:
--   Warrior: Overpower indicator on the nameplate of an enemy that dodged you.
--   Hunter:  Counterattack indicator on the nameplate of an enemy you parried.
--
-- Both are reactive abilities that open a short window against one specific
-- enemy, so they share all of the indicator machinery below and differ only in
-- the CLEU trigger, the spell IDs, and which settings prefix they read. That
-- difference is data in CLASS_CONFIG rather than a second copy of the file.
-- =============================================================================

local _, PLAYER_CLASS = UnitClass("player")

-- Trigger directions:
--   selfIsSource = true  -> "they dodged MY attack", indicator on destGUID
--   selfIsSource = false -> "I parried THEIR attack", indicator on sourceGUID
-- Warrior watches an outgoing miss; Hunter watches an incoming one. Getting
-- this backwards would silently show the icon on the wrong nameplate.
local CLASS_CONFIG = {
    WARRIOR = {
        prefix       = "warriorOverpower",
        iconSpellID  = 7384,
        selfIsSource = true,
        missType     = "DODGE",
        spellIDs     = { [7384] = true, [7887] = true, [11584] = true, [11585] = true },
        -- Casting Revenge also consumes the reactive window, so it clears too.
        clearIDs     = { [6572] = true, [6574] = true, [7379] = true,
                         [11600] = true, [11601] = true, [25288] = true },
    },
    HUNTER = {
        prefix       = "hunterCounterattack",
        iconSpellID  = 19306,
        selfIsSource = false,
        missType     = "PARRY",
        -- 19306 is the Survival talent rank; 20909/20910 are trained at 42/54
        -- (confirmed in Trainer/data/Hunter.lua). An untalented hunter knows
        -- none of them, so the spellbook check below hides the feature.
        spellIDs     = { [19306] = true, [20909] = true, [20910] = true },
        clearIDs     = {},
    },
}

local CFG = CLASS_CONFIG[PLAYER_CLASS]
if not CFG then return end

-- Settings are per-class but identically shaped. Nameplates.lua resolves the
-- right saved-variable prefix for the player's class and publishes the result
-- under one generic ns.c_reactive* set, so the reads below stay static names
-- that checks.py's namespace audit can still see.

local CF = ns.ClassFeatures or {}
ns.ClassFeatures = CF

local function ReactiveIndicatorAllowed()
    if type(ns.CombatProviderSupportsReactiveNameplateIndicator) == "function" then
        return ns.CombatProviderSupportsReactiveNameplateIndicator() == true
    end
    return true
end

local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellTexture = ns.API.GetSpellTexture
local IsSpellKnown = ns.API.IsSpellKnown
local IsPlayerSpell = ns.API.IsPlayerSpell
local GetNumSpellTabs = ns.API.GetNumSpellTabs
local GetSpellTabInfo = ns.API.GetSpellTabInfo
local GetSpellBookItemName = ns.API.GetSpellBookItemName
local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"
local CreateFrame = CreateFrame
local pairs = pairs
local tonumber = tonumber
local math_max = math.max
local math_ceil = math.ceil

local PLAYER_GUID
local knowsOverpower

local OVERPOWER_SPELL_IDS = CFG.spellIDs
local REVENGE_SPELL_IDS = CFG.clearIDs

local overpowerNames = {}
local revengeNames = {}
local active = {} -- [destGUID] = { expires=, timer=, unit=, nameplate= }

local function CacheSpellNames()
    for spellID in pairs(OVERPOWER_SPELL_IDS) do
        local name = GetSpellInfo(spellID)
        if name then overpowerNames[name] = true end
    end
    for spellID in pairs(REVENGE_SPELL_IDS) do
        local name = GetSpellInfo(spellID)
        if name then revengeNames[name] = true end
    end
end

local function GetOverpowerTexture()
    return GetSpellTexture(7384) or GetSpellTexture(7887) or "Interface\\Icons\\Ability_MeleeDamage"
end

local function ResetKnownCache()
    knowsOverpower = nil
end


local function IsOverpowerInSpellBook()
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemName then return false end

    local overpowerName = GetSpellInfo(CFG.iconSpellID)
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = offset or 0
        numSpells = numSpells or 0
        for i = offset + 1, offset + numSpells do
            local name = GetSpellBookItemName(i, BOOKTYPE_SPELL)
            if name == overpowerName then
                return true
            end
        end
    end

    return false
end

local function KnowsOverpower()
    if knowsOverpower ~= nil then return knowsOverpower end

    for spellID in pairs(OVERPOWER_SPELL_IDS) do
        if ns.API.IsKnownSpellID(spellID) then
            knowsOverpower = true
            return true
        end
    end

    knowsOverpower = IsOverpowerInSpellBook()
    return knowsOverpower
end

local function IsEnabled()
    return ns.c_reactiveIndicator ~= false
end

local function CanShowOverpower()
    return IsEnabled() and KnowsOverpower()
end

local function GetNameplateForUnit(unit)
    if not unit then return nil end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then return plate end
    end
    return ns.unitToNameplate and ns.unitToNameplate[unit]
end

local function FindUnitForGUID(guid)
    if not guid then return nil, nil end

    if ns.unitToNameplateGUID then
        for unit, cachedGUID in pairs(ns.unitToNameplateGUID) do
            if cachedGUID == guid and UnitExists(unit) then
                return unit, GetNameplateForUnit(unit)
            end
        end
    end

    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit, GetNameplateForUnit(unit)
        end
    end
end

local function SetCooldown(cooldown, start, duration)
    if not cooldown then return end
    if cooldown.SetCooldown then
        cooldown:SetCooldown(start, duration)
    elseif CooldownFrame_Set then
        CooldownFrame_Set(cooldown, start, duration, 1)
    end
end

local function UpdateIndicatorTimer(frame)
    if not frame then return end

    local showTimer = ns.c_reactiveShowTimer ~= false
    local showSwipe = ns.c_reactiveSwipe ~= false
    local remaining = (frame.expires or 0) - GetTime()

    if frame.text then
        if showTimer and remaining > 0 then
            frame.text:SetText(math_ceil(remaining))
            frame.text:Show()
        else
            frame.text:SetText("")
            frame.text:Hide()
        end
    end

    if frame.cooldown then
        if showSwipe and frame.start and frame.duration and frame.duration > 0 and remaining > 0 then
            frame.cooldown:Show()
        else
            frame.cooldown:Hide()
        end
    end
end

local function IndicatorOnUpdate(self)
    UpdateIndicatorTimer(self)
end

local function EnsureIndicator(nameplate)
    if not nameplate then return nil end
    local frame = nameplate.TFOverpowerIndicator
    if frame then return frame end

    frame = CreateFrame("Frame", nil, nameplate)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel((nameplate:GetFrameLevel() or 0) + 30)
    frame:EnableMouse(false)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexture(GetOverpowerTexture())
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = icon

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:EnableMouse(false)
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    cooldown:Hide()
    frame.cooldown = cooldown

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.85)
    frame.bg = bg

    local border = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    frame.border = border

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetText("")
    text:SetTextColor(1, 0.95, 0.2, 1)
    ns:StyleFeatureFont(text, 13, "classFont", "classTextStyle")
    frame.text = text

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local a1 = pulse:CreateAnimation("Alpha")
    a1:SetFromAlpha(1)
    a1:SetToAlpha(0.55)
    a1:SetDuration(0.35)
    a1:SetOrder(1)
    local a2 = pulse:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.55)
    a2:SetToAlpha(1)
    a2:SetDuration(0.35)
    a2:SetOrder(2)
    frame.pulse = pulse
    frame:SetScript("OnShow", function(self) ns.Cadence:Add(self, 0.05, IndicatorOnUpdate) end)
    frame:SetScript("OnHide", function(self) ns.Cadence:Remove(self) end)

    frame:Hide()
    nameplate.TFOverpowerIndicator = frame
    return frame
end

local function PositionIndicator(nameplate, unit)
    local frame = EnsureIndicator(nameplate)
    if not frame then return end

    local size = math_max(10, tonumber(ns.c_reactiveSize) or 20)
    local margin = tonumber(ns.c_reactiveMargin) or 4
    local xoff = tonumber(ns.c_reactiveOffsetX) or 0
    local yoff = tonumber(ns.c_reactiveOffsetY) or 0
    local pos = ns.c_reactivePosition or "LEFT"

    frame:SetSize(size, size)
    frame:SetFrameLevel((nameplate:GetFrameLevel() or 0) + 30)
    if frame.text then ns:StyleFeatureFont(frame.text, math_max(8, size * 0.55), "classFont", "classTextStyle") end

    local anchor = (nameplate.myPlate and (nameplate.myPlate.hp or nameplate.myPlate)) or nameplate
    frame:ClearAllPoints()

    if pos == "LEFT" then
        frame:SetPoint("RIGHT", anchor, "LEFT", -margin + xoff, yoff)
    elseif pos == "TOP" then
        frame:SetPoint("BOTTOM", anchor, "TOP", xoff, margin + yoff)
    elseif pos == "BOTTOM" then
        frame:SetPoint("TOP", anchor, "BOTTOM", xoff, -margin + yoff)
    else
        frame:SetPoint("LEFT", anchor, "RIGHT", margin + xoff, yoff)
    end
end

local function ApplyIndicatorVisual(frame, state)
    if not frame or not state then return end

    frame.start = state.start or (state.expires and state.duration and (state.expires - state.duration)) or GetTime()
    frame.duration = state.duration or tonumber(ns.c_reactiveDuration) or 5
    frame.expires = state.expires or (frame.start + frame.duration)

    if frame.cooldown then
        if ns.c_reactiveSwipe ~= false then
            SetCooldown(frame.cooldown, frame.start, frame.duration)
            frame.cooldown:Show()
        else
            frame.cooldown:Hide()
        end
    end

    UpdateIndicatorTimer(frame)
end

local function HideIndicatorForNameplate(nameplate)
    local frame = nameplate and nameplate.TFOverpowerIndicator
    if not frame then return end
    if frame.pulse then frame.pulse:Stop() end
    if frame.cooldown then frame.cooldown:Hide() end
    if frame.text then frame.text:SetText(""); frame.text:Hide() end
    frame:Hide()
end

local function HideGUID(guid)
    local state = guid and active[guid]
    if not state then return end
    if state.timer and state.timer.Cancel then state.timer:Cancel() end
    if state.nameplate then HideIndicatorForNameplate(state.nameplate) end
    active[guid] = nil
end

local function HideAll()
    for guid in pairs(active) do
        HideGUID(guid)
    end
end

local function ShowGUID(guid)
    if not guid or not CanShowOverpower() then return end
    local unit, nameplate = FindUnitForGUID(guid)
    if not unit or not nameplate then return end

    local duration = tonumber(ns.c_reactiveDuration) or 5
    if duration <= 0 then duration = 5 end

    local state = active[guid]
    if state and state.timer and state.timer.Cancel then state.timer:Cancel() end
    state = state or {}
    local now = GetTime()
    state.unit = unit
    state.nameplate = nameplate
    state.start = now
    state.duration = duration
    state.expires = now + duration
    active[guid] = state

    PositionIndicator(nameplate, unit)
    local frame = EnsureIndicator(nameplate)
    if frame then
        frame.icon:SetTexture(GetOverpowerTexture())
        ApplyIndicatorVisual(frame, state)
        frame:SetAlpha(1)
        frame:Show()
        if frame.pulse then frame.pulse:Play() end
    end

    if C_Timer and C_Timer.NewTimer then
        state.timer = C_Timer.NewTimer(duration, function()
            HideGUID(guid)
        end)
    else
        state.timer = nil
    end
end

local function RefreshVisible()
    -- MODULE MASTER GATES: this feature is both class-specific and a Nameplates
    -- presentation consumer. If either owner is off, leave Blizzard plates alone.
    if ns.ModuleEnabled and (not ns.ModuleEnabled("class") or not ns.ModuleEnabled("nameplates")) then
        HideAll()
        return
    end
    if not CanShowOverpower() then
        HideAll()
        return
    end

    local now = GetTime()
    for guid, state in pairs(active) do
        if state.expires and state.expires <= now then
            HideGUID(guid)
        else
            local unit, nameplate = FindUnitForGUID(guid)
            if unit and nameplate then
                state.unit = unit
                state.nameplate = nameplate
                PositionIndicator(nameplate, unit)
                local frame = EnsureIndicator(nameplate)
                if frame then
                    ApplyIndicatorVisual(frame, state)
                    frame:Show()
                    if frame.pulse and not frame.pulse:IsPlaying() then frame.pulse:Play() end
                end
            elseif state.nameplate then
                HideIndicatorForNameplate(state.nameplate)
            end
        end
    end
end

local function IsOverpowerOrRevenge(spellID, spellName)
    if spellID and (OVERPOWER_SPELL_IDS[spellID] or REVENGE_SPELL_IDS[spellID]) then return true end
    if spellName and (overpowerNames[spellName] or revengeNames[spellName]) then return true end
    return false
end

local function ExtractCastSpell(...)
    local spellID, spellName
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "number" then
            if OVERPOWER_SPELL_IDS[v] or REVENGE_SPELL_IDS[v] then
                spellID = v
                spellName = GetSpellInfo(v) or spellName
                break
            end
            spellID = v
        elseif type(v) == "string" and (overpowerNames[v] or revengeNames[v]) then
            spellName = v
        end
    end
    if spellID and not spellName then spellName = GetSpellInfo(spellID) end
    return spellID, spellName
end

local function OnCombatLog(info)
    if not CanShowOverpower() then return end
    PLAYER_GUID = PLAYER_GUID or UnitGUID("player")
    if not PLAYER_GUID then return end

    local subevent = info[2]
    if subevent ~= "SWING_MISSED" and subevent ~= "SPELL_MISSED" then return end

    local sourceGUID, destGUID = info[4], info[8]

    -- Warrior watches an outgoing miss (they dodged me) and marks the target;
    -- Hunter watches an incoming one (I parried them) and marks the attacker.
    local watched = CFG.selfIsSource and sourceGUID or destGUID
    if watched ~= PLAYER_GUID then return end

    local missType = (subevent == "SWING_MISSED") and info[12] or info[15]
    if missType ~= CFG.missType then return end

    ShowGUID(CFG.selfIsSource and destGUID or sourceGUID)
end

-- The event frame is lazy. A Warrior/Hunter profile with this reactive
-- indicator disabled should not allocate an inert frame at file load.
local frame
local runtimeActive = false

local function ClassFeatureOnEvent(_, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        PLAYER_GUID = UnitGUID("player")
        ResetKnownCache()
        CacheSpellNames()
        RefreshVisible()
    elseif event == "SPELLS_CHANGED" or event == ns.API.LEARNED_SPELL_EVENT then
        ResetKnownCache()
        CacheSpellNames()
        RefreshVisible()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = arg1
        local guid = unit and UnitGUID(unit)
        if guid and active[guid] then
            RefreshVisible()
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = arg1
        local guid = unit and ((ns.unitToNameplateGUID and ns.unitToNameplateGUID[unit]) or UnitGUID(unit))
        local nameplate = unit and ((ns.unitToNameplate and ns.unitToNameplate[unit]) or GetNameplateForUnit(unit))
        if not guid and unit then
            for activeGUID, state in pairs(active) do
                if state.unit == unit then
                    guid = activeGUID
                    break
                end
            end
        end
        if guid and active[guid] and active[guid].nameplate then
            HideIndicatorForNameplate(active[guid].nameplate)
            active[guid].unit = nil
            active[guid].nameplate = nil
        elseif nameplate then
            HideIndicatorForNameplate(nameplate)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = arg1
        if unit ~= "player" then return end
        local spellID, spellName = ExtractCastSpell(...)
        if IsOverpowerOrRevenge(spellID, spellName) then
            HideAll()
        end
    end
end

local function RuntimeAllowed()
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    return IsEnabled()
end

local function ActivateRuntime()
    if runtimeActive or not RuntimeAllowed() then return false end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", ClassFeatureOnEvent)
    end
    runtimeActive = true
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent(ns.API.LEARNED_SPELL_EVENT)
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    if ns.CLEU then ns.CLEU:Register(OnCombatLog, { SWING_MISSED = true, SPELL_MISSED = true }) end
    return true
end

local function DeactivateRuntime()
    if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
    runtimeActive = false
    HideAll()
end

function CF:Init()
    if not ReactiveIndicatorAllowed() then
        DeactivateRuntime()
        return
    end
    if not RuntimeAllowed() then
        DeactivateRuntime()
        return
    end
    ActivateRuntime()

    -- We are initialized from Core while PLAYER_LOGIN is already dispatching,
    -- so perform the old login setup directly instead of registering for an
    -- event that has already fired for this frame.
    PLAYER_GUID = UnitGUID("player")
    ResetKnownCache()
    CacheSpellNames()
    RefreshVisible()
end

function CF:Refresh()
    ResetKnownCache()
    if not ReactiveIndicatorAllowed() then
        DeactivateRuntime()
        return
    end
    if not RuntimeAllowed() then
        DeactivateRuntime()
        return
    end
    ActivateRuntime()
    CacheSpellNames()
    RefreshVisible()
end

ns.RegisterCPUProfileTarget("Combat/ClassFeatures:CLEU", OnCombatLog)
ns.RegisterCPUProfileTarget("Combat/ClassFeatures:Events", ClassFeatureOnEvent)
ns.RegisterCPUProfileTarget("Combat/ClassFeatures:IndicatorTick", IndicatorOnUpdate)
