local _, ns = ...

-- Player regeneration/tick subsystem. Power/PowerCost.lua remains the action-button
-- power-cost owner and forwards the player events this module needs. Keeping the
-- clocks, markers, +X popups, and 5SR state here gives regen one clear owner.
local RT = {}
ns.RegenTicks = RT

local _G = _G
local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local InCombatLockdown = InCombatLockdown
local GetSpellPowerCost = ns.API.GetSpellPowerCost
local PowerBarColor = PowerBarColor
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local math_min = math.min
local math_max = math.max
local tonumber = tonumber
local type = type
local After = ns.After
local canaccessvalue = canaccessvalue

local POWER_MANA   = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local POWER_RAGE   = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1
local POWER_FOCUS  = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2
local POWER_ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

-- Keep clock authority conservative, but allow a slightly wider presentation-only
-- window for +X text. Classic can deliver UNIT_POWER/UNIT_HEALTH a few frames late;
-- that jitter must not make a real regen amount disappear, and it also must not be
-- allowed to drag the learned 2-second heartbeat.
local PHASE_VALIDATE_WINDOW = 0.35
local TICK_AMOUNT_DISPLAY_WINDOW = 0.55

local cachedDB
local manaFrame, druidManaFrame, fiveSRFrame, druidFiveSRFrame, energyFrame, rageFrame, healthFrame
local manaLast = -1
local manaTickLastObserved = 0
local manaPhaseKnown = false
local manaOutOfPhaseCandidate = 0
local fiveSRStart = 0
local fiveSREnd = 0
local pendingManaSpendUntil = 0
local pendingManaSpendCastTime = 0
local recentManaDecreaseTime = 0
local manaCurrentPowerType = POWER_MANA
local energyLastTick = 0
local energyPhaseKnown = false
local energyLast = -1
local rageLast = -1
local rageMax = 0
local rageOutOfCombatStart = 0
local rageFirstDecayExpectedAt = 0
local rageDecayLastObserved = 0
local rageDecayClockAnchor = 0
local rageDecayPhaseKnown = false
-- Modern/Forever fallback: current Rage can be secret. Track only whether Rage
-- changed during combat and the timing of post-combat RAGE events; never infer
-- or compare the hidden amount. This keeps the decay phase marker available
-- without attempting to recover a restricted value.
local rageSecretFallbackActive = false
local rageSecretMarkerUntil = 0
local rageObservedDuringCombat = false
local healthTickLastObserved = 0
local healthPhaseKnown = false
local healthOutOfPhaseCandidate = 0
-- Modern/Forever fallback: UnitHealth may be opaque to addon Lua. In that case
-- preserve only the observable 2-second regeneration phase from UNIT_HEALTH
-- event timing. The marker remains predictive without comparing secret HP values.
local healthSecretMarkerUntil = 0
-- Secret-health mode must establish a fresh post-combat heartbeat before the
-- marker is shown. A phase learned before/during the pull may still be useful
-- for validation, but it must never make the HP marker appear the instant
-- PLAYER_REGEN_ENABLED fires.
local healthAwaitingPostCombatPhase = false
local healthLast = -1
local powerAmtLast = -1
-- Resource maxima change only on explicit UNIT_MAX* / world-entry transitions.
-- Keep them with the existing current-value snapshots so the 33 Hz marker
-- driver does not repeatedly query immutable-between-events Blizzard state.
local manaMax = 0
local energyMax = 0
local healthMax = 0
local UpdateTickDriver
local GetSharedRegenTickAnchor

-- Rage uses the inverse shape of Mana's five-second rule: a grace-period sweep
-- begins when combat ends, then the marker changes to the repeating server
-- decay heartbeat as soon as the first real loss is observed. Unlike 5SR, the
-- first Rage loss is phase-bound rather than a fixed delay from combat exit.
-- Retaining its observed phase between pulls keeps the pre-decay sweep aimed at
-- the next real server boundary instead of reusing one pull's variable delay.
local RAGE_DECAY_PERIOD = 2
local RAGE_NATURAL_LOSS_MAX = 5

local function DB(db)
    if db then cachedDB = db end
    return cachedDB or (TurboFaceDB and TurboFaceDB.power) or (ns.defaults and ns.defaults.power) or {}
end

local function AccessibleNumber(value)
    if value == nil then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end

local function ReadPlayerPower(powerType)
    return AccessibleNumber(UnitPower("player", powerType))
end

local function ReadPlayerPowerMax(powerType)
    return AccessibleNumber(UnitPowerMax("player", powerType))
end

local function ReadPlayerHealth()
    return AccessibleNumber(UnitHealth("player"))
end

local function ReadPlayerHealthMax()
    return AccessibleNumber(UnitHealthMax("player"))
end

local function TicksEnabled(db)
    db = db or DB()
    if ns.ModuleEnabled and not ns.ModuleEnabled("playerTicks") then return false end
    return db.enabled ~= false
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue or 0
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function ColorWithAlpha(color, dr, dg, db, da)
    if type(color) ~= "table" then return dr, dg, db, da end
    return color.r or color[1] or dr, color.g or color[2] or dg, color.b or color[3] or db, color.a or color[4] or da
end

local function GetPlayerPowerType()
    local ptype = POWER_MANA
    if UnitPowerType then
        local n = UnitPowerType("player")
        if n ~= nil then ptype = n end
    end
    return ptype
end

local function GetModernPlayerFrameBar(kind)
    -- Mainline/Forever no longer publishes PlayerFrameHealthBar / PlayerFrameManaBar
    -- as the canonical bar globals. Prefer Blizzard's accessors when available,
    -- then fall back to the modern PlayerFrame hierarchy. Keep the legacy globals
    -- last so Era behavior remains unchanged.
    if kind == "health" then
        if type(_G.PlayerFrame_GetHealthBar) == "function" then
            local ok, bar = pcall(_G.PlayerFrame_GetHealthBar)
            if ok and bar then return bar end
        end
        local pf = _G.PlayerFrame
        local content = pf and pf.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        local container = main and main.HealthBarsContainer
        if container and container.HealthBar then return container.HealthBar end
        return _G.PlayerFrameHealthBar
    end

    if type(_G.PlayerFrame_GetManaBar) == "function" then
        local ok, bar = pcall(_G.PlayerFrame_GetManaBar)
        if ok and bar then return bar end
    end
    local pf = _G.PlayerFrame
    local content = pf and pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local area = main and main.ManaBarArea
    if area and area.ManaBar then return area.ManaBar end
    return _G.PlayerFrameManaBar
end

local function GetPlayerBar(kind)
    return GetModernPlayerFrameBar(kind)
end

local function GetDruidManaBar()
    local module = ns.DruidPowerBar
    if not (module and module.GetBar) then return nil end
    local druidBar = module:GetBar()
    if not druidBar or not druidBar.IsShown or not druidBar:IsShown() then return nil end
    return druidBar
end

local function EnsureMarker(parent, name)
    local frame = _G[name]
    if frame then return frame end
    frame = CreateFrame("Frame", name, parent or UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 20)
    frame:EnableMouse(false)
    frame.bg = frame:CreateTexture(nil, "OVERLAY")
    frame.bg:SetDrawLayer("OVERLAY", 6)
    frame.bar = frame:CreateTexture(nil, "OVERLAY")
    frame.bar:SetDrawLayer("OVERLAY", 7)
    frame.bar:SetWidth(1)
    frame:Hide()
    return frame
end

local function ApplyMarkerColors(frame, db, colorKey, borderKey)
    if not frame then return end
    db = db or cachedDB or DB()
    local r, g, b, a = ColorWithAlpha(db[colorKey], 1, 1, 1, 1)
    local br, bg, bb, ba = ColorWithAlpha(db[borderKey], 0, 0, 0, 0.85)
    frame.bar:SetColorTexture(r, g, b, a)
    frame.bg:SetColorTexture(br, bg, bb, ba)
end

local function ReadFrameNumber(frame, methodName)
    if not frame then return nil end
    local method = frame[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, frame)
    if not ok then return nil end
    return AccessibleNumber(value)
end

local function MarkerGeometry(parent)
    local w = ReadFrameNumber(parent, "GetWidth")
    local h = ReadFrameNumber(parent, "GetHeight")

    -- Forever/Mainline can make geometry read from protected PlayerFrame status
    -- bars secret even though TurboFace itself supplied their visual dimensions.
    -- Never compare or perform arithmetic on an opaque geometry value.  When the
    -- protected bar is one of the resolved Blizzard player bars, use the fixed
    -- TurboFace artwork geometry instead.  Era and addon-owned bars continue to
    -- use their readable live size.
    if not w or not h then
        local healthBar = GetPlayerBar("health")
        local powerBar = GetPlayerBar("power")
        if parent == healthBar or parent == powerBar then
            local layout = ns.UF and ns.UF.GetPlayerArtLayout and ns.UF:GetPlayerArtLayout()
            if parent == healthBar then
                w = w or (layout and layout.healthW) or 116
                h = h or (layout and layout.healthH) or 15
            else
                w = w or (layout and layout.powerW) or 116
                h = h or (layout and layout.powerH) or 15
            end
        end
    end

    return w, h
end

local function AnchorMarker(frame, parent, progress, showBg, db, colorKey, borderKey)
    if not frame or not parent then return end
    db = db or cachedDB or DB()
    progress = Clamp(progress, 0, 1)
    local w, h = MarkerGeometry(parent)
    if not w or not h or w <= 0 or h <= 0 then frame:Hide(); return end

    local bw = Clamp(db.tickBorderWidth, 1, 8)
    local tw = Clamp(db.tickWidth, 1, 6)
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", parent, "LEFT", 0, 0)
    frame:SetSize(math_max(1, w * progress), h)
    frame.bg:ClearAllPoints()
    frame.bar:ClearAllPoints()
    frame.bg:SetHeight(h)
    frame.bar:SetHeight(math_max(1, h - 2))
    frame.bg:SetWidth(showBg and bw or tw)
    frame.bar:SetWidth(tw)
    frame.bg:SetPoint("RIGHT", frame, "RIGHT", showBg and 1 or 0, 0)
    frame.bar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.bg:SetShown(showBg == true)
    frame.bar:Show()
    ApplyMarkerColors(frame, db, colorKey, borderKey)
    frame:Show()
end

local function HideMarker(frame)
    if frame then frame:Hide() end
end

-- ---------------------------------------------------------------------------
-- Regen "+X" tick-amount popups (companion to the tick markers).
-- A small resource-colored number that pops at the tick-marker position on the
-- bar and fades in place. Holders are keyed in a Lua table (not stored as a
-- field on the Blizzard bar) so we never taint PlayerFrame*Bar.
-- ---------------------------------------------------------------------------
local TICK_BRIGHTEN = 150 / 255
local function Bright(c) return math_min(1, (c or 0) + TICK_BRIGHTEN) end

local HEALTH_AMOUNT_COLOR = { 0.10, 0.90, 0.10 }
local tickPops = {}

local function ResourceColor(pt)
    local r, g, b = 1, 1, 1
    local c
    if pt == POWER_MANA then c = PowerBarColor and PowerBarColor.MANA
    elseif pt == POWER_ENERGY then c = PowerBarColor and PowerBarColor.ENERGY
    elseif pt == POWER_RAGE then c = PowerBarColor and PowerBarColor.RAGE
    elseif pt == POWER_FOCUS then c = PowerBarColor and PowerBarColor.FOCUS end
    if c then
        r, g, b = c.r, c.g, c.b
    elseif pt == POWER_MANA then r, g, b = 0.20, 0.40, 1.00
    elseif pt == POWER_ENERGY then r, g, b = 1.00, 0.85, 0.10
    elseif pt == POWER_RAGE then r, g, b = 0.90, 0.20, 0.20
    end
    return Bright(r), Bright(g), Bright(b)
end

local function StyleTickPop(h, db)
    if not (h and h.text) then return end
    db = db or cachedDB or DB()
    local size = Clamp(db.tickAmountSize or 14, 8, 40)
    if ns.StyleFont then
        local path = ns:GetFontPath(db.tickFont)
        ns:StyleFont(h.text, path, size, nil, db.tickTextStyle)
    end
    -- Defensive fallback only.  Do not reintroduce a hardcoded OUTLINE here:
    -- tickFont/tickTextStyle are the sole presentation owners for +X popups.
    if not h.text:GetFont() then
        h.text:SetFont(ns.DEFAULT_FONT_PATH or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    end
end

local function EnsureTickPop(bar)
    local h = tickPops[bar]
    if h then return h end
    h = CreateFrame("Frame", nil, bar)
    h:SetFrameStrata("HIGH")
    h:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 25)
    h:SetSize(1, 1)
    h:EnableMouse(false)
    h:Hide()
    local fs = h:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", h, "CENTER", 0, 0)
    h.text = fs
    StyleTickPop(h, cachedDB or DB())
    local ag = h:CreateAnimationGroup()
    local hold = ag:CreateAnimation("Alpha")
    hold:SetOrder(1); hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.20)
    local fade = ag:CreateAnimation("Alpha")
    fade:SetOrder(2); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.35)
    ag:SetScript("OnFinished", function() h:Hide() end)
    h.anim = ag
    tickPops[bar] = h
    return h
end

-- Show "+amount" statically, centered on the bar (over its HP/power text), with
-- a configurable text size and X/Y offset. Fades in place.
local function SpawnTickAmount(bar, amount, r, g, b)
    if not bar or not amount or amount <= 0 then return end
    local db = cachedDB or DB()
    local size = Clamp(db.tickAmountSize or 14, 8, 40)
    local ox = tonumber(db.tickAmountOffsetX) or 0
    local oy = tonumber(db.tickAmountOffsetY) or 0
    local h = EnsureTickPop(bar)
    if h.anim then h.anim:Stop() end
    StyleTickPop(h, db)
    h.text:SetText("+" .. amount)
    h.text:SetTextColor(r or 1, g or 1, b or 1, 1)
    h:ClearAllPoints()
    h:SetPoint("CENTER", bar, "CENTER", ox, oy)
    h:SetAlpha(1)
    h:Show()
    if h.anim then h.anim:Play() end
end

-- Power bar (mana in caster form / energy / rage): centered "+X" over the bar.
local function ShowPowerTickAmount(pt, amount)
    local db = cachedDB or DB()
    if not TicksEnabled(db) or db.powerTickAmount == false then return end
    local mb = GetPlayerBar("power")
    if not mb then return end
    local r, g, b = ResourceColor(pt)
    SpawnTickAmount(mb, amount, r, g, b)
end

-- Health bar: centered "+X" over the bar (out of combat only, matching the marker).
local function ShowHealthTickAmount(amount)
    local db = cachedDB or DB()
    if not TicksEnabled(db) or db.healthTickAmount == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local hb = GetPlayerBar("health")
    if not hb then return end
    SpawnTickAmount(hb, amount, Bright(HEALTH_AMOUNT_COLOR[1]), Bright(HEALTH_AMOUNT_COLOR[2]), Bright(HEALTH_AMOUNT_COLOR[3]))
end

-- Exposed so DruidPowerBar can pop mana amounts on its own bar while shifted.
function RT:ShowTickAmount(bar, amount, r, g, b)
    SpawnTickAmount(bar, amount, r, g, b)
end

-- Exposed: the brightened resource color every "+X" tick-amount popup uses.
-- DruidPowerBar consumes this so its mana popups share the exact same
-- brighten logic instead of maintaining a private copy.
function RT:GetTickAmountColor(pt)
    return ResourceColor(pt)
end

-- Diagnostic snapshot consumed by /tf debug regen. Keeping the state private
-- everywhere else prevents UI consumers from becoming a second timing owner.
function RT:GetDebugState()
    local now = GetTime()
    local sharedAnchor, sharedSource = GetSharedRegenTickAnchor()
    local manaElapsed = manaPhaseKnown and manaTickLastObserved > 0 and ((now - manaTickLastObserved) % 2) or nil
    local energyElapsed = energyPhaseKnown and energyLastTick > 0 and ((now - energyLastTick) % 2) or nil
    local rageElapsed = rageDecayPhaseKnown and rageDecayLastObserved > 0
        and ((now - rageDecayLastObserved) % RAGE_DECAY_PERIOD) or nil
    local sharedElapsed = sharedAnchor > 0 and ((now - sharedAnchor) % 2) or nil
    return {
        manaPhaseKnown = manaPhaseKnown,
        manaTickLastObserved = manaTickLastObserved,
        manaNextIn = manaElapsed and (2 - manaElapsed) or nil,
        fiveSRRemaining = math_max(0, fiveSREnd - now),
        fiveSRStart = fiveSRStart,
        pendingManaSpend = pendingManaSpendUntil >= now,
        energyPhaseKnown = energyPhaseKnown,
        energyTickLastObserved = energyLastTick,
        energyNextIn = energyElapsed and (2 - energyElapsed) or nil,
        rageOutOfCombatStart = rageOutOfCombatStart,
        rageFirstDecayExpectedAt = rageFirstDecayExpectedAt,
        rageDecayPhaseKnown = rageDecayPhaseKnown,
        rageDecayLastObserved = rageDecayLastObserved,
        rageGraceRemaining = rageOutOfCombatStart > 0 and not rageDecayPhaseKnown
            and math_max(0, rageFirstDecayExpectedAt - now) or 0,
        rageNextIn = rageElapsed and (RAGE_DECAY_PERIOD - rageElapsed) or nil,
        healthPhaseKnown = healthPhaseKnown,
        healthTickLastObserved = healthTickLastObserved,
        sharedAnchor = sharedAnchor,
        sharedSource = sharedSource,
        sharedNextIn = sharedElapsed and (2 - sharedElapsed) or nil,
        healthAnchor = sharedAnchor,
        healthNextIn = sharedElapsed and (2 - sharedElapsed) or nil,
    }
end

local function SpellHasManaCost(spellID)
    if not spellID or not GetSpellPowerCost then return false end
    local costs = GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return false end
    for i = 1, #costs do
        local c = costs[i]
        if c and c.type == POWER_MANA and c.cost and c.cost > 0 then return true end
    end
    return false
end

local function IsFiveSRActive(now)
    now = now or GetTime()
    return fiveSREnd > now
end

local function StartFiveSecondRule(startTime)
    startTime = tonumber(startTime) or GetTime()
    fiveSRStart = startTime
    fiveSREnd = startTime + 5
end

local function PhaseDistance(now, anchor, period)
    if not anchor or anchor <= 0 then return math.huge end
    period = period or 2
    local phase = (now - anchor) % period
    return math_min(phase, period - phase)
end

-- Regen timing intentionally does NOT subscribe to CLEU. A permanent CLEU
-- consumer for the player tick markers made an otherwise tiny visual feature
-- participate in every combat-log burst. Instead, once a server phase is known
-- we only accept gains near that 2-second phase. A one-off potion/proc therefore
-- cannot move the clock; two consecutive out-of-phase gains ~2s apart can
-- recover the clock if the old phase genuinely became stale.
local function ConfirmNaturalManaGain(eventTime, amount)
    -- If Energy/Health already established the shared Classic regen heartbeat,
    -- a first Mana gain must agree with that phase before Mana is allowed to
    -- become authoritative. This prevents a potion/proc from stealing the clock
    -- merely because Mana had not produced a natural tick yet.
    local sharedAnchor, sharedSource = GetSharedRegenTickAnchor()
    local referenceAnchor = manaPhaseKnown and manaTickLastObserved
        or ((sharedSource and sharedSource ~= "mana") and sharedAnchor or 0)
    local phaseDistance = referenceAnchor > 0 and PhaseDistance(eventTime, referenceAnchor, 2) or math.huge
    local matchedShared = referenceAnchor > 0 and phaseDistance <= PHASE_VALIDATE_WINDOW
    local displayMatched = referenceAnchor > 0 and phaseDistance <= TICK_AMOUNT_DISPLAY_WINDOW
    local accept = referenceAnchor <= 0 or matchedShared

    if not accept then
        if manaOutOfPhaseCandidate > 0 then
            local delta = eventTime - manaOutOfPhaseCandidate
            if delta >= 1.65 and delta <= 2.35 then
                -- Two consecutive out-of-phase gains form a credible new Mana
                -- heartbeat, so allow recovery if the previous shared phase was stale.
                accept = true
                matchedShared = false
            end
        end
        manaOutOfPhaseCandidate = eventTime
    else
        manaOutOfPhaseCandidate = 0
    end

    if not accept then
        -- Presentation is intentionally more tolerant than phase authority. A
        -- slightly-late UNIT_POWER_UPDATE can still report the observed +Mana
        -- amount without being trusted to move/relearn the shared heartbeat.
        if displayMatched and GetPlayerPowerType() == POWER_MANA then
            ShowPowerTickAmount(POWER_MANA, amount)
        end
        return
    end
    manaTickLastObserved = matchedShared and referenceAnchor or eventTime
    manaPhaseKnown = true
    if GetPlayerPowerType() == POWER_MANA then
        ShowPowerTickAmount(POWER_MANA, amount)
    end
    UpdateTickDriver(cachedDB or DB())
end

local function ObserveSecretHealthEvent(eventTime)
    -- UNIT_HEALTH itself remains an ordinary event even when UnitHealth() returns
    -- an opaque secret number. Learn only timing here; never infer an amount or
    -- compare the hidden HP value. Requiring a credible ~2s cadence prevents a
    -- one-off potion, fall-damage event, or other isolated health change from
    -- becoming the regeneration clock.
    if InCombatLockdown and InCombatLockdown() then return end

    -- On the first secret-health event after combat, only arm a candidate.
    -- Forever can emit an immediate UNIT_HEALTH around the combat transition;
    -- showing from the old phase here makes the marker start too early. The
    -- next ~2s event proves the fresh out-of-combat regeneration cadence.
    if healthAwaitingPostCombatPhase then
        healthAwaitingPostCombatPhase = false
        healthOutOfPhaseCandidate = eventTime
        healthSecretMarkerUntil = 0
        UpdateTickDriver(cachedDB or DB())
        return
    end

    local referenceAnchor = healthPhaseKnown and healthTickLastObserved or 0
    local accept = false
    if referenceAnchor > 0 then
        accept = PhaseDistance(eventTime, referenceAnchor, 2) <= PHASE_VALIDATE_WINDOW
    end

    if not accept and healthOutOfPhaseCandidate > 0 then
        local delta = eventTime - healthOutOfPhaseCandidate
        if delta >= 1.65 and delta <= 2.35 then
            accept = true
        end
    end

    if not accept then
        healthOutOfPhaseCandidate = eventTime
        return
    end

    healthOutOfPhaseCandidate = 0
    healthTickLastObserved = eventTime
    healthPhaseKnown = true
    -- Keep the marker alive through the next expected heartbeat. If no further
    -- UNIT_HEALTH arrives (normally because HP capped), it parks automatically.
    healthSecretMarkerUntil = eventTime + 2.75
    UpdateTickDriver(cachedDB or DB())
end

local function ConfirmNaturalHealthGain(eventTime, amount)
    -- Health regeneration is an out-of-combat signal. Ignoring combat gains here
    -- prevents HoTs and other periodic healing from ever becoming a regen-clock
    -- authority simply because they happen to tick every ~2 seconds.
    if InCombatLockdown and InCombatLockdown() then return end

    -- Any actively-observed resource heartbeat is authoritative for Health. The
    -- important exception is a capped Mana source: once Mana is full there are
    -- no more UNIT_POWER gains to refresh its timestamp, so an otherwise-valid
    -- Health heartbeat must be allowed to keep the shared 2-second clock fresh.
    local sharedAnchor, sharedSource = GetSharedRegenTickAnchor()
    local mana = ReadPlayerPower(POWER_MANA)
    local maxMana = ReadPlayerPowerMax(POWER_MANA)
    local manaCapped = sharedSource == "mana" and mana ~= nil and maxMana ~= nil and maxMana > 0 and mana >= maxMana

    if sharedAnchor > 0 and sharedSource ~= "health" and not manaCapped then
        local phaseDistance = PhaseDistance(eventTime, sharedAnchor, 2)
        if phaseDistance <= PHASE_VALIDATE_WINDOW then
            healthTickLastObserved = eventTime
            healthPhaseKnown = true
            healthOutOfPhaseCandidate = 0
            ShowHealthTickAmount(amount)
        elseif phaseDistance <= TICK_AMOUNT_DISPLAY_WINDOW then
            -- Preserve the resource-owned phase, but do not throw away a real
            -- observed +HP amount solely because UNIT_HEALTH arrived late.
            ShowHealthTickAmount(amount)
        end
        return
    end

    -- Once Mana caps, prefer Health's own most recent validated observation as
    -- the continuity reference. That observation was recorded while Mana was
    -- still active, so HP text does not miss a tick merely because the last
    -- Mana event stopped refreshing at the cap.
    local referenceAnchor = manaCapped and healthPhaseKnown and healthTickLastObserved
        or (sharedAnchor > 0 and sharedAnchor)
        or (healthPhaseKnown and healthTickLastObserved or 0)
    local phaseDistance = referenceAnchor > 0 and PhaseDistance(eventTime, referenceAnchor, 2) or math.huge
    local displayMatched = referenceAnchor > 0 and phaseDistance <= TICK_AMOUNT_DISPLAY_WINDOW
    local accept = referenceAnchor <= 0 or phaseDistance <= PHASE_VALIDATE_WINDOW
    if not accept then
        if healthOutOfPhaseCandidate > 0 then
            local delta = eventTime - healthOutOfPhaseCandidate
            if delta >= 1.65 and delta <= 2.35 then accept = true end
        end
        healthOutOfPhaseCandidate = eventTime
    else
        healthOutOfPhaseCandidate = 0
    end

    if not accept then
        -- Same display/authority split as Mana: near-phase delivery jitter may
        -- show the observed amount, but only strict validation (or two periodic
        -- out-of-phase gains) may relearn the heartbeat.
        if displayMatched then ShowHealthTickAmount(amount) end
        return
    end
    healthOutOfPhaseCandidate = 0
    healthTickLastObserved = eventTime
    healthPhaseKnown = true

    -- Mana remains the preferred shared source, but while it is capped its old
    -- event timestamp would otherwise become stale. Refresh that preferred
    -- anchor from the validated Health heartbeat so HP +X text and all visual
    -- markers stay phase-locked until Mana can produce natural ticks again.
    if manaCapped then
        manaTickLastObserved = eventTime
    end

    ShowHealthTickAmount(amount)
    UpdateTickDriver(cachedDB or DB())
end

GetSharedRegenTickAnchor = function()
    -- Classic's player regeneration resources ride the same 2-second heartbeat.
    -- Keep ONE visual phase so UNIT_POWER/UNIT_HEALTH delivery jitter cannot make
    -- Energy, shifted Druid Mana, and HP markers walk ahead/behind each other.
    -- Mana remains the preferred authority when learned; Energy is the strong
    -- fallback (its +20 heartbeat is easy to identify); Health owns phase only
    -- when neither resource clock is available.
    if manaPhaseKnown and manaTickLastObserved > 0 then
        return manaTickLastObserved, "mana"
    elseif energyPhaseKnown and energyLastTick > 0 then
        return energyLastTick, "energy"
    elseif healthPhaseKnown and healthTickLastObserved > 0 then
        return healthTickLastObserved, "health"
    end
    return 0, nil
end

local function UpdateManaTick(elapsed, db)
    db = db or cachedDB or DB()
    if not TicksEnabled(db) then
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
        return
    end

    local ptype = GetPlayerPowerType()
    local mainBar = ptype == POWER_MANA and GetPlayerBar("power") or nil
    local shiftedBar = ptype ~= POWER_MANA and GetDruidManaBar() or nil
    local targetBar = mainBar or shiftedBar
    if not targetBar then
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
        return
    end

    local mana = ReadPlayerPower(POWER_MANA)
    local maxMana = ReadPlayerPowerMax(POWER_MANA)
    if mana == nil or maxMana == nil or maxMana <= 0 or mana >= maxMana then
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
        return
    end

    local now = GetTime()

    -- Persistent shared 2-second regen heartbeat: never overwritten by a Mana
    -- spend or by the 5SR countdown. Mana is preferred when learned, while
    -- Energy/Health can seed the same phase when Mana has not ticked yet.
    local sharedAnchor = GetSharedRegenTickAnchor()
    if db.manaTick ~= false and sharedAnchor > 0 then
        local tickProgress = ((now - sharedAnchor) % 2) / 2
        if targetBar == shiftedBar then
            HideMarker(manaFrame)
            if not druidManaFrame then
                druidManaFrame = EnsureMarker(shiftedBar, "TurboFaceDruidManaTickMarker")
            end
            AnchorMarker(druidManaFrame, shiftedBar, tickProgress, db.manaTickBackground, db, "tickColor", "tickBorderColor")
        else
            HideMarker(druidManaFrame)
            if not manaFrame then manaFrame = EnsureMarker(mainBar, "TurboFaceManaTickMarker") end
            AnchorMarker(manaFrame, mainBar, tickProgress, db.manaTickBackground, db, "tickColor", "tickBorderColor")
        end
    else
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
    end

    -- Independent five-second-rule countdown. The marker starts on the right
    -- and moves left while the mana heartbeat continues underneath it.
    if db.fiveSecondRule ~= false and IsFiveSRActive(now) then
        local fiveProgress = (fiveSREnd - now) / 5
        if targetBar == shiftedBar then
            HideMarker(fiveSRFrame)
            if not druidFiveSRFrame then
                druidFiveSRFrame = EnsureMarker(shiftedBar, "TurboFaceDruidFiveSecondRuleMarker")
            end
            AnchorMarker(druidFiveSRFrame, shiftedBar, fiveProgress, db.fiveSecondRuleBackground, db, "fiveSecondRuleColor", "fiveSecondRuleBorderColor")
        else
            HideMarker(druidFiveSRFrame)
            if not fiveSRFrame then fiveSRFrame = EnsureMarker(mainBar, "TurboFaceFiveSecondRuleMarker") end
            AnchorMarker(fiveSRFrame, mainBar, fiveProgress, db.fiveSecondRuleBackground, db, "fiveSecondRuleColor", "fiveSecondRuleBorderColor")
        end
    else
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
    end
end

local function UpdateEnergyTick(elapsed, db)
    db = db or cachedDB or DB()
    if not TicksEnabled(db) or db.energyTick == false then HideMarker(energyFrame); return end
    local mb = GetPlayerBar("power")
    if not mb then HideMarker(energyFrame); return end
    if GetPlayerPowerType() ~= POWER_ENERGY then HideMarker(energyFrame); return end
    local energy = ReadPlayerPower(POWER_ENERGY)
    local maxEnergy = ReadPlayerPowerMax(POWER_ENERGY)
    if energy == nil or maxEnergy == nil then HideMarker(energyFrame); return end
    -- There is no upcoming regeneration tick to visualize while energy is full.
    -- Hide immediately at the cap rather than leaving the marker parked at the
    -- end of the power bar until energy is spent again.
    if maxEnergy <= 0 or energy >= maxEnergy then HideMarker(energyFrame); return end

    local now = GetTime()
    -- Resource markers are deliberately combat-independent. Keep the visual
    -- heartbeat cycling whenever Energy is below maximum, including between
    -- pulls. A recognized server tick re-synchronizes this baseline, but a
    -- delayed/missing power event must never leave the marker parked at 100%.
    if energyLastTick <= 0 then energyLastTick = now end
    local sharedAnchor = GetSharedRegenTickAnchor()
    local anchor = sharedAnchor > 0 and sharedAnchor or energyLastTick
    local progress = ((now - anchor) % 2) / 2
    if progress < 0 then progress = 0 end

    if not energyFrame then energyFrame = EnsureMarker(mb, "TurboFaceEnergyTickMarker") end
    AnchorMarker(energyFrame, mb, progress, db.energyTickBackground, db, "energyTickColor", "energyTickBorderColor")
end

local function UpdateRageTick(elapsed, db)
    db = db or cachedDB or DB()
    if not TicksEnabled(db) or db.rageDecay == false then HideMarker(rageFrame); return end
    local mb = GetPlayerBar("power")
    if not mb or GetPlayerPowerType() ~= POWER_RAGE then HideMarker(rageFrame); return end
    if InCombatLockdown and InCombatLockdown() then HideMarker(rageFrame); return end

    local rage = ReadPlayerPower(POWER_RAGE)
    local maxRage = ReadPlayerPowerMax(POWER_RAGE)
    local now = GetTime()
    if rage ~= nil then
        if maxRage == nil or maxRage <= 0 or rage <= 0 or rageOutOfCombatStart <= 0 then
            HideMarker(rageFrame)
            return
        end
    elseif not rageSecretFallbackActive or rageOutOfCombatStart <= 0 or rageSecretMarkerUntil <= now then
        HideMarker(rageFrame)
        return
    end

    local progress
    if rageDecayPhaseKnown and rageDecayLastObserved > 0 then
        progress = 1 - (((now - rageDecayLastObserved) % RAGE_DECAY_PERIOD) / RAGE_DECAY_PERIOD)
    else
        -- Hold at the right edge if event delivery arrives slightly after the
        -- predicted server boundary; the observed loss owns the phase change.
        local duration = rageFirstDecayExpectedAt - rageOutOfCombatStart
        progress = duration > 0 and (1 - math_min(1, (now - rageOutOfCombatStart) / duration)) or 0
    end

    if not rageFrame then rageFrame = EnsureMarker(mb, "TurboFaceRageDecayMarker") end
    AnchorMarker(rageFrame, mb, progress, db.rageDecayBackground, db,
        "rageDecayColor", "rageDecayBorderColor")
end

local function ShouldShowHealthMarker()
    if InCombatLockdown and InCombatLockdown() then return false end
    local hp = ReadPlayerHealth()
    local maxHP = ReadPlayerHealthMax()
    if hp == nil or maxHP == nil then
        return healthPhaseKnown and healthSecretMarkerUntil > GetTime()
    end
    return maxHP > 0 and hp > 0 and hp < maxHP
end

local function UpdateHealthTick(elapsed, db)
    db = db or cachedDB or DB()
    if not TicksEnabled(db) or db.healthRegen == false then HideMarker(healthFrame); return end
    local hb = GetPlayerBar("health")
    if not hb or not ShouldShowHealthMarker() then HideMarker(healthFrame); return end

    local now = GetTime()
    local anchor = GetSharedRegenTickAnchor()
    if anchor <= 0 then HideMarker(healthFrame); return end
    local progress = ((now - anchor) % 2) / 2

    if not healthFrame then healthFrame = EnsureMarker(hb, "TurboFaceHealthRegenMarker") end
    AnchorMarker(healthFrame, hb, progress, db.healthRegenBackground, db,
        "healthRegenColor", "healthRegenBorderColor")
end

local TICK_INTERVAL = 1 / 33  -- ~33 Hz while active; the driver remains fully parked while idle

local function MarkersEnabled(db)
    db = db or cachedDB or DB()
    return TicksEnabled(db) and (db.manaTick ~= false or db.fiveSecondRule ~= false
        or db.energyTick ~= false or db.rageDecay ~= false or db.healthRegen ~= false)
end

local function GetMarkerEligibility(db)
    db = db or cachedDB or DB()
    if not MarkersEnabled(db) then return false, false, false, false end

    local ptype = manaCurrentPowerType
    local powerBar = GetPlayerBar("power")
    local healthBar = GetPlayerBar("health")
    local sharedAnchor = GetSharedRegenTickAnchor()

    -- Mana and Energy regeneration continue outside combat, so neither
    -- resource marker may depend on combat state. Current/max resource values
    -- are event-owned snapshots refreshed below; the animation driver only
    -- consumes them between events.
    local manaEligible = false
    if db.manaTick ~= false or db.fiveSecondRule ~= false then
        local manaBar = ptype == POWER_MANA and powerBar or GetDruidManaBar()
        if manaBar then
            local heartbeatVisible = db.manaTick ~= false and sharedAnchor > 0
            local fiveSRVisible = db.fiveSecondRule ~= false and IsFiveSRActive()
            manaEligible = manaMax > 0 and manaLast >= 0 and manaLast < manaMax and (heartbeatVisible or fiveSRVisible)
        end
    end

    local energyEligible = false
    if db.energyTick ~= false and powerBar and ptype == POWER_ENERGY then
        energyEligible = energyMax > 0 and energyLast >= 0 and energyLast < energyMax
    end

    local rageEligible = false
    if db.rageDecay ~= false and powerBar and ptype == POWER_RAGE
        and not (InCombatLockdown and InCombatLockdown()) then
        if rageLast >= 0 then
            rageEligible = rageMax > 0 and rageLast > 0 and rageOutOfCombatStart > 0
        else
            rageEligible = rageSecretFallbackActive and rageOutOfCombatStart > 0
                and rageSecretMarkerUntil > GetTime()
        end
    end

    local healthEligible = false
    if db.healthRegen ~= false and healthBar and not (InCombatLockdown and InCombatLockdown()) then
        if healthLast >= 0 and healthMax > 0 then
            healthEligible = healthLast > 0 and healthLast < healthMax and sharedAnchor > 0
        else
            -- Secret-health fallback: visibility is event-timed rather than HP-valued.
            healthEligible = healthPhaseKnown and healthSecretMarkerUntil > GetTime() and sharedAnchor > 0
        end
    end

    return manaEligible, energyEligible, rageEligible, healthEligible
end

local function HideAllMarkers()
    HideMarker(manaFrame)
    HideMarker(druidManaFrame)
    HideMarker(fiveSRFrame)
    HideMarker(druidFiveSRFrame)
    HideMarker(energyFrame)
    HideMarker(rageFrame)
    HideMarker(healthFrame)
end

local regenTickRegistered = false
local function RegenTickPulse(_, elapsed)
    local tdb = cachedDB or DB()
    local manaEligible, energyEligible, rageEligible, healthEligible = GetMarkerEligibility(tdb)
    if not (manaEligible or energyEligible or rageEligible or healthEligible) then
        ns.Cadence:Remove(RT)
        HideAllMarkers()
        return
    end

    if manaEligible then
        UpdateManaTick(elapsed, tdb)
    else
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
    end
    if energyEligible then UpdateEnergyTick(elapsed, tdb) else HideMarker(energyFrame) end
    if rageEligible then UpdateRageTick(elapsed, tdb) else HideMarker(rageFrame) end
    if healthEligible then UpdateHealthTick(elapsed, tdb) else HideMarker(healthFrame) end
end

local function EnsureTickDriver()
    if regenTickRegistered then return end
    regenTickRegistered = true
    ns.RegisterCPUProfileTarget("Power/RegenTicks:Tick", RegenTickPulse)
end

UpdateTickDriver = function(db)
    db = db or cachedDB or DB()
    local manaEligible, energyEligible, rageEligible, healthEligible = GetMarkerEligibility(db)

    if not (manaEligible or energyEligible or rageEligible or healthEligible) then
        if ns.Cadence then ns.Cadence:Remove(RT) end
        HideAllMarkers()
        return
    end

    EnsureTickDriver()
    if not manaEligible then
        HideMarker(manaFrame)
        HideMarker(druidManaFrame)
        HideMarker(fiveSRFrame)
        HideMarker(druidFiveSRFrame)
    end
    if not energyEligible then HideMarker(energyFrame) end
    if not rageEligible then HideMarker(rageFrame) end
    if not healthEligible then HideMarker(healthFrame) end
    if ns.Cadence then ns.Cadence:Add(RT, TICK_INTERVAL, RegenTickPulse, true) end
end

function RT:OnEvent(event, arg1, arg2, arg3, db)
    db = DB(db)
    if not TicksEnabled(db) then
        UpdateTickDriver(db)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        healthLast = ReadPlayerHealth() or -1
        if healthLast < 0 then
            healthAwaitingPostCombatPhase = true
            healthOutOfPhaseCandidate = 0
            healthSecretMarkerUntil = 0
        else
            healthAwaitingPostCombatPhase = false
        end

        local now = GetTime()
        local readableRage = ReadPlayerPower(POWER_RAGE)
        rageLast = readableRage or -1
        rageMax = ReadPlayerPowerMax(POWER_RAGE) or 0
        local ragePowerActive = GetPlayerPowerType() == POWER_RAGE
        local shouldStartReadable = ragePowerActive and readableRage ~= nil and readableRage > 0
        local shouldStartSecret = ragePowerActive and readableRage == nil and rageObservedDuringCombat
        if shouldStartReadable or shouldStartSecret then
            rageOutOfCombatStart = now
            local anchor = rageDecayClockAnchor
            if anchor <= 0 then anchor = GetSharedRegenTickAnchor() end
            local untilNext = RAGE_DECAY_PERIOD
            if anchor > 0 then
                untilNext = RAGE_DECAY_PERIOD - ((now - anchor) % RAGE_DECAY_PERIOD)
                if untilNext < 0.05 then untilNext = RAGE_DECAY_PERIOD end
            end
            rageFirstDecayExpectedAt = now + untilNext
            rageDecayLastObserved = 0
            rageDecayPhaseKnown = false
            rageSecretFallbackActive = shouldStartSecret
            rageSecretMarkerUntil = shouldStartSecret and (now + RAGE_DECAY_PERIOD + 0.75) or 0
        else
            rageOutOfCombatStart = 0
            rageFirstDecayExpectedAt = 0
            rageDecayLastObserved = 0
            rageDecayPhaseKnown = false
            rageSecretFallbackActive = false
            rageSecretMarkerUntil = 0
        end
        rageObservedDuringCombat = false
        UpdateTickDriver(db)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        local spellID = arg3 or arg2
        if SpellHasManaCost(spellID) then
            local now = GetTime()
            local currentMana = ReadPlayerPower(POWER_MANA)
            if currentMana == nil then
                -- Modern secret-value rules can hide player power from tainted addon Lua.
                -- A successful mana-cost spell still establishes the 5SR start without
                -- requiring a forbidden numeric comparison.
                StartFiveSecondRule(now)
                pendingManaSpendUntil = 0
                pendingManaSpendCastTime = 0
            elseif recentManaDecreaseTime > 0 and now - recentManaDecreaseTime <= 0.40 then
                StartFiveSecondRule(recentManaDecreaseTime)
                pendingManaSpendUntil = 0
                pendingManaSpendCastTime = 0
            elseif manaLast >= 0 and currentMana < manaLast then
                recentManaDecreaseTime = now
                manaLast = currentMana
                StartFiveSecondRule(now)
                pendingManaSpendUntil = 0
                pendingManaSpendCastTime = 0
            else
                pendingManaSpendCastTime = now
                pendingManaSpendUntil = now + 0.40
                After(0.12, function()
                    if pendingManaSpendCastTime ~= now or pendingManaSpendUntil < GetTime() then return end
                    local observed = ReadPlayerPower(POWER_MANA)
                    if observed ~= nil and manaLast >= 0 and observed < manaLast then
                        local spendTime = GetTime()
                        recentManaDecreaseTime = spendTime
                        manaLast = observed
                        StartFiveSecondRule(spendTime)
                        pendingManaSpendUntil = 0
                        pendingManaSpendCastTime = 0
                        UpdateTickDriver(DB())
                    end
                end)
            end
        end
        UpdateTickDriver(db)
    elseif event == "UNIT_DISPLAYPOWER" and arg1 == "player" then
        local previousPowerType = manaCurrentPowerType
        manaCurrentPowerType = GetPlayerPowerType()
        powerAmtLast = ReadPlayerPower(manaCurrentPowerType) or -1
        rageLast = ReadPlayerPower(POWER_RAGE) or -1
        rageMax = ReadPlayerPowerMax(POWER_RAGE) or 0
        if manaCurrentPowerType == POWER_ENERGY and previousPowerType ~= POWER_ENERGY then
            energyLast = ReadPlayerPower(POWER_ENERGY) or -1
            energyLastTick = GetTime()
            energyPhaseKnown = false
        elseif previousPowerType == POWER_ENERGY and manaCurrentPowerType ~= POWER_ENERGY then
            energyPhaseKnown = false
        end
        UpdateTickDriver(db)
    elseif (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") and arg1 == "player" then
        local now = GetTime()
        local currentMana = ReadPlayerPower(POWER_MANA)
        if currentMana ~= nil and manaLast >= 0 then
            if currentMana > manaLast then
                ConfirmNaturalManaGain(now, currentMana - manaLast)
            elseif currentMana < manaLast then
                recentManaDecreaseTime = now
                if pendingManaSpendUntil >= now then
                    StartFiveSecondRule(now)
                    pendingManaSpendUntil = 0
                    pendingManaSpendCastTime = 0
                end
            end
        end
        manaLast = currentMana or -1

        if arg2 == "RAGE" or GetPlayerPowerType() == POWER_RAGE then
            local inCombat = InCombatLockdown and InCombatLockdown()
            local currentRage = ReadPlayerPower(POWER_RAGE)
            if inCombat then
                -- The event itself is non-secret and tells us Rage changed, even
                -- when the amount is opaque. Remember activity so combat exit can
                -- start a short phase-only decay marker.
                rageObservedDuringCombat = true
            elseif currentRage ~= nil and rageLast >= 0 and currentRage < rageLast and rageOutOfCombatStart > 0 then
                local loss = rageLast - currentRage
                if loss <= RAGE_NATURAL_LOSS_MAX then
                    rageDecayLastObserved = now
                    rageDecayClockAnchor = now
                    rageDecayPhaseKnown = true
                end
            elseif currentRage == nil and rageSecretFallbackActive and rageOutOfCombatStart > 0 then
                -- In secret mode, each post-combat RAGE update is enough to phase
                -- lock the decay clock. Extend visibility only while those decay
                -- events keep arriving; after the last one (normally zero Rage)
                -- the marker parks automatically.
                rageDecayLastObserved = now
                rageDecayClockAnchor = now
                rageDecayPhaseKnown = true
                rageSecretMarkerUntil = now + RAGE_DECAY_PERIOD + 0.75
            end
            rageLast = currentRage or -1
            if currentRage ~= nil and currentRage <= 0 then
                rageOutOfCombatStart = 0
                rageFirstDecayExpectedAt = 0
                rageDecayLastObserved = 0
                rageDecayPhaseKnown = false
                rageSecretFallbackActive = false
                rageSecretMarkerUntil = 0
            end
        end

        if arg2 == "ENERGY" or GetPlayerPowerType() == POWER_ENERGY then
            local current = ReadPlayerPower(POWER_ENERGY)
            if current ~= nil and energyLast >= 0 and current > energyLast then
                local gain = current - energyLast
                local maxEnergy = energyMax
                local sinceLast = now - (energyLastTick or 0)
                local cappedRemainder = maxEnergy > 0 and current >= maxEnergy and gain > 0 and gain < 20
                local normalTick = gain == 20 or cappedRemainder
                local acceleratedTick = gain == 40
                local sharedAnchor, sharedSource = GetSharedRegenTickAnchor()
                local phaseWindow = sinceLast >= 1.40 and sinceLast <= 2.60
                local sharedWindow = sharedAnchor > 0 and PhaseDistance(now, sharedAnchor, 2) <= 0.35
                local accept = false
                if normalTick then
                    if energyPhaseKnown then
                        accept = phaseWindow
                    elseif sharedSource == "mana" then
                        accept = sharedWindow
                    else
                        accept = true
                    end
                elseif acceleratedTick then
                    accept = energyPhaseKnown and phaseWindow or (sharedAnchor > 0 and sharedWindow)
                end
                if accept then
                    energyLastTick = (sharedAnchor > 0 and sharedWindow) and sharedAnchor or now
                    energyPhaseKnown = true
                end
            elseif current ~= nil and energyLast >= 0 and current < energyLast and not energyPhaseKnown then
                energyLastTick = GetTime()
            end
            energyLast = current or -1
        end

        local pt = manaCurrentPowerType
        local curp
        if pt == POWER_MANA then
            curp = currentMana
        elseif pt == POWER_ENERGY then
            curp = energyLast >= 0 and energyLast or ReadPlayerPower(POWER_ENERGY)
        else
            curp = ReadPlayerPower(pt)
        end
        if pt ~= POWER_MANA and curp ~= nil and powerAmtLast >= 0 and curp > powerAmtLast then
            ShowPowerTickAmount(pt, curp - powerAmtLast)
        end
        powerAmtLast = curp or -1
        UpdateTickDriver(db)
    elseif event == "UNIT_MAXPOWER" and arg1 == "player" then
        manaMax = ReadPlayerPowerMax(POWER_MANA) or 0
        energyMax = ReadPlayerPowerMax(POWER_ENERGY) or 0
        rageMax = ReadPlayerPowerMax(POWER_RAGE) or 0
        UpdateTickDriver(db)
    elseif event == "UNIT_MAXHEALTH" and arg1 == "player" then
        healthMax = ReadPlayerHealthMax() or 0
        UpdateTickDriver(db)
    elseif (event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT") and arg1 == "player" then
        local hp = ReadPlayerHealth()
        local now = GetTime()
        if hp ~= nil and healthLast >= 0 and hp > healthLast then
            ConfirmNaturalHealthGain(now, hp - healthLast)
        end
        if hp == nil then
            healthLast = -1
            ObserveSecretHealthEvent(now)
        else
            healthSecretMarkerUntil = 0
            healthLast = hp
        end
        UpdateTickDriver(db)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- UnitHealth may become secret as combat begins on the modern API. Do not
        -- retain a secret value in addon state; reacquire after combat if permitted.
        healthLast = -1
        healthSecretMarkerUntil = 0
        healthAwaitingPostCombatPhase = false
        rageOutOfCombatStart = 0
        rageFirstDecayExpectedAt = 0
        rageDecayLastObserved = 0
        rageDecayPhaseKnown = false
        rageSecretFallbackActive = false
        rageSecretMarkerUntil = 0
        rageObservedDuringCombat = false
        UpdateTickDriver(db)
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_BONUS_ACTIONBAR" then
        manaCurrentPowerType = GetPlayerPowerType()
        powerAmtLast = ReadPlayerPower(manaCurrentPowerType) or -1
        UpdateTickDriver(db)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:Reset(db)
    end
end

function RT:Reset(db)
    db = DB(db)
    manaCurrentPowerType = GetPlayerPowerType()
    manaLast = ReadPlayerPower(POWER_MANA) or -1
    manaMax = ReadPlayerPowerMax(POWER_MANA) or 0
    energyMax = ReadPlayerPowerMax(POWER_ENERGY) or 0
    rageMax = ReadPlayerPowerMax(POWER_RAGE) or 0
    healthMax = ReadPlayerHealthMax() or 0
    manaTickLastObserved = 0
    manaPhaseKnown = false
    manaOutOfPhaseCandidate = 0
    fiveSRStart = 0
    fiveSREnd = 0
    pendingManaSpendUntil = 0
    pendingManaSpendCastTime = 0
    recentManaDecreaseTime = 0
    energyLast = ReadPlayerPower(POWER_ENERGY) or -1
    energyLastTick = GetTime()
    energyPhaseKnown = false
    rageLast = ReadPlayerPower(POWER_RAGE) or -1
    rageOutOfCombatStart = 0
    rageFirstDecayExpectedAt = 0
    rageDecayLastObserved = 0
    rageDecayClockAnchor = 0
    rageDecayPhaseKnown = false
    rageSecretFallbackActive = false
    rageSecretMarkerUntil = 0
    rageObservedDuringCombat = false
    healthLast = ReadPlayerHealth() or -1
    healthTickLastObserved = 0
    healthPhaseKnown = false
    healthOutOfPhaseCandidate = 0
    healthSecretMarkerUntil = 0
    healthAwaitingPostCombatPhase = false
    powerAmtLast = ReadPlayerPower(manaCurrentPowerType) or -1
    UpdateTickDriver(db)
end

function RT:Refresh(db)
    db = DB(db)
    -- Typography options are live. Restyle every popup already created for a
    -- player bar immediately, even while hidden, so changing Font/Text Style/
    -- Size never leaves an old pooled FontString carrying legacy presentation.
    for _, h in pairs(tickPops) do
        StyleTickPop(h, db)
    end
    -- Refresh is also the re-enable boundary after the shared event frame may
    -- have been parked, so take one authoritative snapshot before restarting
    -- the cadence driver. Normal runtime changes are maintained by UNIT_* events.
    manaCurrentPowerType = GetPlayerPowerType()
    manaLast = ReadPlayerPower(POWER_MANA) or -1
    energyLast = ReadPlayerPower(POWER_ENERGY) or -1
    rageLast = ReadPlayerPower(POWER_RAGE) or -1
    healthLast = ReadPlayerHealth() or -1
    manaMax = ReadPlayerPowerMax(POWER_MANA) or 0
    energyMax = ReadPlayerPowerMax(POWER_ENERGY) or 0
    rageMax = ReadPlayerPowerMax(POWER_RAGE) or 0
    healthMax = ReadPlayerHealthMax() or 0
    powerAmtLast = ReadPlayerPower(manaCurrentPowerType) or -1
    UpdateTickDriver(db)
end

ns.RegisterCPUProfileTarget("Power/RegenTicks:Events", RT.OnEvent)
