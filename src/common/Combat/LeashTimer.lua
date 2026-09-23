local _, ns = ...

-- =============================================================================
-- TurboFace Enemy Leash Timer
--
-- GUID-authoritative leash countdowns for hostile NPCs engaged with the player.
-- Threat/nameplate/target events provide identity + level while
-- the shared CLEU dispatcher provides authoritative interaction timestamps.
--
-- Design goals:
--   * no private COMBAT_LOG_EVENT_UNFILTERED frame (uses ns.CLEU)
--   * no FRAME_UPDATE / permanent polling (Cadence only for live rows or
--     a short combat-entry admission window)
--   * no dependency on TurboFace Nameplates or Unit Frames
--   * nameplate removal does not destroy a valid GUID timer
--   * CC temporarily suppresses the timer instead of pretending the leash is
--     progressing normally through loss-of-control effects
-- =============================================================================

local LT = {}
ns.LeashTimer = LT

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClassification = UnitClassification
local UnitCanAttack = UnitCanAttack
local UnitIsPlayer = UnitIsPlayer
local UnitIsDead = UnitIsDead
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsUnit = UnitIsUnit
local UnitDetailedThreatSituation = ns.API.ReadUnitDetailedThreatSituation
local UnitThreatSituation = ns.API.ReadUnitThreatSituation
local GetRaidTargetIndex = GetRaidTargetIndex
local GetUnitSpeed = GetUnitSpeed
local math_max = math.max
local string_format = string.format
local table_sort = table.sort
local wipe = wipe
local bit_band = bit and bit.band

local DB = ns.DB
local API = ns.API

local FALLBACK_POINT = { "CENTER", UIParent, "CENTER", 320, 40 }
local DISPLAY_WIDTH = 280
local CADENCE_INTERVAL = 0.10
local ACQUIRE_INTERVAL = 0.10
local ACQUIRE_WINDOW = 1.50
local TRANSITION_MATCH_WINDOW = 0.35
local DISENGAGE_GRACE = 0.40

local COLOR_NORMAL = "|cFFFBF2EF"
local COLOR_WARNING = "|cFFEAB676"
local COLOR_DANGER = "|cFFD85C2B"
local COLOR_EMPTY = "|cff7f7f7f"

local TRACKED_CLEU = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SWING_MISSED = true,
    RANGE_MISSED = true,
    SPELL_MISSED = true,
    SPELL_CAST_SUCCESS = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REMOVED = true,
    UNIT_DIED = true,
    UNIT_DESTROYED = true,
}

-- Classic loss-of-control effects that pause the leash countdown. TurboFace
-- only needs one canonical spell ID per localized effect name: BuildLeashPauseNames()
-- converts these identities into names, so every rank sharing that name is
-- covered without maintaining rank-by-rank tables. The set is intentionally
-- organized by the *kind of control* that invalidates normal chase timing.
local LEASH_PAUSE_SPELL_IDS = {
    -- Incapacitate / disorient / fear / banish / sleep
    1090, 13327, 2637, 3355, 19386, 19503, 1513, 118, 20066, 2878,
    9484, 8122, 6770, 1776, 2094, 6358, 710, 5782, 5484, 6789, 5246,

    -- Roots and movement-lock effects
    339, 16979, 19185, 19229, 19306, 122, 12494, 23694,

    -- Stuns / hard loss of control
    5211, 19410, 24394, 25999, 853, 20170, 1833, 408, 5530,
    7922, 20253, 12809, 12798,

    -- Engineering explosive control effects
    19784, 19769, 12543, 12562, 12421, 4069, 4068, 4067, 4066, 4065,
}

local leashPauseNames
local states = {}          -- [guid] = timer state currently displayed
local ccCounts = {}        -- [guid] = number of tracked CC auras currently active
local pendingCLEU = {}     -- [guid] = { time=, name= } until a unit token is observed
local guidToUnit = {}      -- visible nameplate GUID -> current recyclable unit token
local unitToGUID = {}      -- current nameplate token -> GUID
local combatByGUID = {}    -- last observed UnitAffectingCombat for visible GUIDs
local combatChangedAt = {} -- timestamp of real combat-flag transitions
local sortBuffer = {}      -- reused every display update
local textBuffer = {}      -- reused every display update
local acquireToken = {}    -- short-lived combat-entry/nameplate admission retry

local display, displayText, eventFrame
local initialized = false
local runtimeActive = false
local playerInCombat = false
local lastRowCount = -1
local playerGUID
local acquisitionDeadline = 0
local playerCombatStartedAt = 0

local function FeatureEnabled()
    -- Runtime activation is controlled by the feature option and Movers gate.
    local on = DB().leashTimerEnabled == true
    return ns.MoverDependentEnabled(on)
end

local function MoverHidden()
    local movers = DB().movers
    local elements = type(movers) == "table" and movers.elements
    local edb = type(elements) == "table" and elements.LeashTimer
    return type(edb) == "table" and edb.hidden == true
end

local function RuntimeEnabled()
    return FeatureEnabled() and not MoverHidden()
end

local function PlayerIsInCombat()
    if UnitAffectingCombat then return UnitAffectingCombat("player") == true end
    return InCombatLockdown and InCombatLockdown() == true
end

local function LevelToDuration(level)
    level = tonumber(level) or 0
    if level == -1 or level >= 50 then return 15 end
    if level >= 45 then return 14 end
    if level >= 40 then return 13 end
    if level >= 30 then return 12 end
    return 11
end

local function BuildLeashPauseNames()
    if leashPauseNames then return end
    leashPauseNames = {}
    local getInfo = API and API.GetSpellInfo
    if not getInfo then return end
    for i = 1, #LEASH_PAUSE_SPELL_IDS do
        local name = getInfo(LEASH_PAUSE_SPELL_IDS[i])
        if name then leashPauseNames[name] = true end
    end
end

local function IsLeashPausingEffect(spellName)
    if not spellName then return false end
    BuildLeashPauseNames()
    return leashPauseNames and leashPauseNames[spellName] == true
end

local TYPE_BITS = (COMBATLOG_OBJECT_TYPE_NPC or 0) + (COMBATLOG_OBJECT_TYPE_PET or 0)
local REACTION_BITS = (COMBATLOG_OBJECT_REACTION_HOSTILE or 0) + (COMBATLOG_OBJECT_REACTION_NEUTRAL or 0)
local CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC or 0

local function IsHostileNPCFlags(flags)
    if not flags or not bit_band then return false end
    if TYPE_BITS ~= 0 and bit_band(flags, TYPE_BITS) == 0 then return false end
    if CONTROL_NPC ~= 0 and bit_band(flags, CONTROL_NPC) == 0 then return false end
    if REACTION_BITS ~= 0 and bit_band(flags, REACTION_BITS) == 0 then return false end
    return true
end

local function IsHostileNPCUnit(unit)
    return unit and UnitExists(unit)
        and not UnitIsPlayer(unit)
        and UnitCanAttack("player", unit)
        and not UnitIsDead(unit)
end

local function PlayerHasThreat(unit)
    if not unit or not UnitExists(unit) then return false end

    -- Classic can put the player on an NPC's threat table at status 0 while
    -- proximity/social aggro is still settling.  isTanking is therefore too
    -- strict for leash acquisition: status ~= nil is the important signal.
    if UnitThreatSituation then
        local status = UnitThreatSituation("player", unit)
        if status ~= nil then return true end
    end

    -- Fallback for clients where only the detailed API is usable.
    if UnitDetailedThreatSituation then
        local tanking, status = UnitDetailedThreatSituation("player", unit)
        return tanking == true or status ~= nil
    end
    return false
end

local function MobTargetsPlayer(unit)
    if not UnitIsUnit or not unit or not UnitExists(unit) then return false end

    -- Body/proximity pulls can put both actors in combat before Blizzard has
    -- populated a useful threat-table result.  The mob's live victim token is
    -- a stronger relationship signal in that window and is already used by
    -- TurboFace's native nameplate threat system for the same reason.
    local victim = unit .. "target"
    return UnitExists(victim) and UnitIsUnit(victim, "player") == true
end

local function PlayerEngagedWith(unit)
    return PlayerHasThreat(unit) or MobTargetsPlayer(unit)
end

local function ExplicitlyDisengaged(unit)
    if not unit or not UnitExists(unit) then return true end
    if UnitAffectingCombat and not UnitAffectingCombat(unit) then return true end
    if PlayerHasThreat(unit) then return false end

    -- A concrete victim other than the player plus no player threat is strong
    -- evidence that this is no longer our leash relationship.  Missing victim
    -- data is treated as unknown, not as permission to destroy a live timer.
    if UnitIsUnit then
        local victim = unit .. "target"
        if UnitExists(victim) and not UnitIsUnit(victim, "player") then return true end
    end
    return false
end

local function ResolveUnit(guid)
    if not guid then return nil end
    local unit = guidToUnit[guid]
    if unit and UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    if UnitExists("target") and UnitGUID("target") == guid then return "target" end
    if UnitExists("focus") and UnitGUID("focus") == guid then return "focus" end
    return nil
end

local function ClearNameplateToken(unit)
    local guid = unitToGUID[unit]
    if not guid then return end
    unitToGUID[unit] = nil
    if guidToUnit[guid] == unit then guidToUnit[guid] = nil end
    combatByGUID[guid] = nil
    combatChangedAt[guid] = nil
    local state = states[guid]
    if state and state.unit == unit then
        -- NAME_PLATE_UNIT_REMOVED can race the final UNIT_FLAGS/threat update
        -- that told us this GUID disengaged. Keep that debounced observation
        -- on the GUID state even though the recyclable token is gone.
        state.unit = nil
    end
end

local function RememberNameplate(unit)
    if not unit or not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end

    local oldGuid = unitToGUID[unit]
    if oldGuid and oldGuid ~= guid and guidToUnit[oldGuid] == unit then
        guidToUnit[oldGuid] = nil
        combatByGUID[oldGuid] = nil
        combatChangedAt[oldGuid] = nil
        local oldState = states[oldGuid]
        if oldState and oldState.unit == unit then oldState.unit = nil end
    end

    unitToGUID[unit] = guid
    guidToUnit[guid] = unit
    return guid
end

local function ObserveUnitCombat(unit)
    if not unit or not UnitExists(unit) or not UnitAffectingCombat then return false, false end
    local guid = UnitGUID(unit)
    if not guid then return false, false end

    local current = UnitAffectingCombat(unit) == true
    local previous = combatByGUID[guid]
    if previous == nil then
        -- First sight is only a baseline. An NPC that merely appears already in
        -- combat is not evidence that it entered combat with *this* player;
        -- treating first sight as a transition admitted unrelated nearby fights.
        combatByGUID[guid] = current
        combatChangedAt[guid] = 0
        return current, false
    end
    if previous ~= current then
        combatByGUID[guid] = current
        combatChangedAt[guid] = GetTime()
        return current, true
    end
    return current, false
end

local function RecentPlayerCombatTransition(unit)
    if playerCombatStartedAt <= 0 or not unit or not UnitExists(unit) then return false end
    local guid = UnitGUID(unit)
    if not guid or combatByGUID[guid] ~= true then return false end
    local changedAt = combatChangedAt[guid] or 0
    if changedAt <= 0 then return false end
    return math.abs(changedAt - playerCombatStartedAt) <= TRANSITION_MATCH_WINDOW
end

local function EstimatedAdmissionTime(unit)
    if unit and UnitExists(unit) then
        local guid = UnitGUID(unit)
        local changedAt = guid and (combatChangedAt[guid] or 0) or 0
        if changedAt > 0 and GetTime() - changedAt <= ACQUIRE_WINDOW then
            return changedAt
        end
    end
    return GetTime()
end

local function ActiveStateCount()
    local n = 0
    for _ in pairs(states) do n = n + 1 end
    return n
end

local function SortByExpiration(a, b)
    if a.expiration == b.expiration then
        return (a.name or "") < (b.name or "")
    end
    return a.expiration < b.expiration
end

local function ApplyFont()
    if not displayText then return end
    local size = tonumber(DB().leashTimerFontSize) or 12
    if size < 8 then size = 8 elseif size > 20 then size = 20 end
    if ns.StyleFeatureFont then ns:StyleFeatureFont(displayText, size, "leashTimerFont", "leashTimerTextStyle") end
    displayText:SetJustifyH("LEFT")
    displayText:SetJustifyV("TOP")
end

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "TurboFaceLeashTimer", UIParent)
    display:SetSize(DISPLAY_WIDTH, 20)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)

    displayText = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    displayText:SetPoint("TOPLEFT", display, "TOPLEFT", 2, -2)
    displayText:SetPoint("TOPRIGHT", display, "TOPRIGHT", -2, -2)
    ApplyFont()
    display:Hide()
    return display
end

local SyncCadence
local UpdateDisplay
local SyncRuntime

local function RemoveState(guid)
    if not guid or not states[guid] then return false end
    states[guid] = nil
    return true
end

local function ClearCombatState()
    wipe(states)
    wipe(ccCounts)
    wipe(pendingCLEU)
    lastRowCount = -1
    if ns.Cadence then
        ns.Cadence:Remove(LT)
        ns.Cadence:Remove(acquireToken)
    end
    acquisitionDeadline = 0
    if display then
        displayText:SetText("")
        display:Hide()
    end
end

local function CaptureMetadata(state, unit)
    if not state or not unit or not UnitExists(unit) then return end
    state.unit = unit
    state.name = UnitName(unit) or state.name or "Unknown"
    state.level = UnitLevel(unit)
    state.classification = UnitClassification and UnitClassification(unit) or state.classification
    state.raidMarker = GetRaidTargetIndex and GetRaidTargetIndex(unit) or nil
    state.duration = LevelToDuration(state.level)
end

local function StartState(guid, unit, timestamp, estimate, fallbackName)
    if not guid or ccCounts[guid] then return end
    timestamp = tonumber(timestamp) or GetTime()

    if unit and not IsHostileNPCUnit(unit) then return end

    local state = states[guid]
    if not state then
        state = { guid = guid }
        states[guid] = state
    end

    if unit then CaptureMetadata(state, unit) end
    if not state.name then state.name = fallbackName or "Unknown" end
    if not state.duration then state.duration = LevelToDuration(state.level) end

    -- Once a nominal leash countdown reaches zero, preserve that baseline and
    -- enter observation/overtime mode. Late reset-like CLEU/threat signals must
    -- not recycle the row back to a fresh 11-15 second countdown; doing so hides
    -- exactly how long the mob exceeded the estimate. A real interaction can
    -- still upgrade an estimated state to confirmed for disengagement cleanup.
    if state.expiration and timestamp >= state.expiration then
        if estimate ~= true then state.estimate = false end
        state.overrun = true
        state.disengageSince = nil
        state.outOfCombatSince = nil
        pendingCLEU[guid] = nil
        SyncCadence()
        UpdateDisplay(true)
        return
    end

    state.estimate = estimate == true
    state.expiration = timestamp + state.duration
    state.overrun = nil
    -- Admission is sticky. Classic threat/victim/combat flags can oscillate for
    -- a few frames during a pure body pull, especially before either side lands
    -- a hit. Never let one incomplete sample revoke a valid countdown.
    state.disengageSince = nil
    state.outOfCombatSince = nil
    pendingCLEU[guid] = nil

    SyncCadence()
    UpdateDisplay(true)
end

local function StartOrPendFromCLEU(guid, timestamp, fallbackName)
    if not guid or ccCounts[guid] then return end
    local unit = ResolveUnit(guid)
    if unit then
        if IsHostileNPCUnit(unit) then
            -- A direct player CLEU interaction is itself authoritative evidence
            -- of engagement; do not make Blizzard's threat API a second gate.
            StartState(guid, unit, timestamp, false, fallbackName)
        else
            pendingCLEU[guid] = nil
            if RemoveState(guid) then
                SyncCadence()
                UpdateDisplay(true)
            end
        end
        return
    end

    local existing = states[guid]
    if existing and existing.duration then
        -- The plate may have left view, but the GUID state is still authoritative
        -- and already knows its level-derived duration. Before nominal expiry a
        -- direct player action legitimately resets that countdown. After zero,
        -- however, latch overtime mode so late signals cannot hide the measured
        -- overrun by jumping back to a fresh duration.
        existing.estimate = false
        if timestamp >= existing.expiration then
            existing.overrun = true
        else
            existing.expiration = timestamp + existing.duration
            existing.overrun = nil
        end
        if fallbackName then existing.name = fallbackName end
        pendingCLEU[guid] = nil
        SyncCadence()
        UpdateDisplay(true)
        return
    end

    -- A CLEU observation is still useful even when the plate has not become a
    -- unit token yet.  Do not guess the duration from the player's level: hold
    -- the timestamp and enrich it as soon as target/focus/nameplate metadata is
    -- available, exactly preserving the real interaction time.
    local p = pendingCLEU[guid]
    if not p then
        p = {}
        pendingCLEU[guid] = p
    end
    p.time = timestamp
    p.name = fallbackName or p.name
end

local function RefreshEngagementForUnit(unit, estimateIfNew)
    if not IsHostileNPCUnit(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    if ccCounts[guid] then
        RemoveState(guid)
        return
    end

    if not PlayerEngagedWith(unit) then
        local state = states[guid]
        if state then
            -- Estimated body-pull states are sticky only while their nominal
            -- countdown is still positive. Once the estimate crosses zero, the
            -- row is in overtime observation mode and may accept a stable real
            -- disengagement signal so it can disappear when the mob actually
            -- resets instead of surviving until the player's whole combat ends.
            CaptureMetadata(state, unit)
            local now = GetTime()
            if state.estimate and state.expiration > now then
                state.disengageSince = nil
                state.outOfCombatSince = nil
            elseif ExplicitlyDisengaged(unit) then
                state.disengageSince = state.disengageSince or now
            else
                state.disengageSince = nil
            end
        end
        return
    end

    local state = states[guid]
    if state then
        state.disengageSince = nil
        state.outOfCombatSince = nil
        CaptureMetadata(state, unit)
        return
    end

    local pending = pendingCLEU[guid]
    if pending then
        StartState(guid, unit, pending.time, false, pending.name)
    elseif estimateIfNew then
        StartState(guid, unit, EstimatedAdmissionTime(unit), true, UnitName(unit))
    end
end

local function TryAdmitTransitionFallback()
    if not playerInCombat or ActiveStateCount() > 0 then return false end

    local candidateGUID, candidateUnit
    local count = 0
    for guid, unit in pairs(guidToUnit) do
        if unit and UnitExists(unit) and UnitGUID(unit) == guid
            and not states[guid] and not ccCounts[guid]
            and IsHostileNPCUnit(unit)
            and not PlayerEngagedWith(unit)
            and RecentPlayerCombatTransition(unit) then
            count = count + 1
            if count > 1 then
                -- A synchronized combat flag is deliberately only a rescue
                -- signal, not proof of ownership. Multiple plausible NPCs means
                -- the observation is ambiguous, so wait for threat/victim/CLEU.
                return false
            end
            candidateGUID, candidateUnit = guid, unit
        end
    end

    if count == 1 then
        StartState(candidateGUID, candidateUnit, EstimatedAdmissionTime(candidateUnit), true, UnitName(candidateUnit))
        return true
    end
    return false
end

local function RefreshAllVisibleEngagement(estimateIfNew)
    for guid, unit in pairs(guidToUnit) do
        if unit and UnitExists(unit) and UnitGUID(unit) == guid then
            RefreshEngagementForUnit(unit, estimateIfNew)
        end
    end
    if UnitExists("target") then RefreshEngagementForUnit("target", estimateIfNew) end
    if UnitExists("focus") then RefreshEngagementForUnit("focus", estimateIfNew) end
    if estimateIfNew then TryAdmitTransitionFallback() end
end

local function SeedVisibleNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then return end
    for i = 1, #plates do
        local unit = plates[i] and plates[i].unitToken
        if unit then
            RememberNameplate(unit)
            ObserveUnitCombat(unit)
        end
    end
end

local function StopAcquisitionWindow()
    acquisitionDeadline = 0
    if ns.Cadence then ns.Cadence:Remove(acquireToken) end
end

local function AcquisitionTick()
    if not runtimeActive or not playerInCombat then
        StopAcquisitionWindow()
        return
    end

    local now = GetTime()
    if acquisitionDeadline <= 0 or now >= acquisitionDeadline then
        StopAcquisitionWindow()
        return
    end

    -- PLAYER_REGEN_DISABLED / NAME_PLATE_UNIT_ADDED can precede the NPC target
    -- and threat data by a frame or two.  Re-sample only during this short
    -- admission window; this is not a permanent combat poll.
    SeedVisibleNameplates()
    RefreshAllVisibleEngagement(true)
end

local function BeginAcquisitionWindow(seconds)
    if not runtimeActive or not playerInCombat or not ns.Cadence then return end
    local deadline = GetTime() + (tonumber(seconds) or ACQUIRE_WINDOW)
    if deadline > acquisitionDeadline then acquisitionDeadline = deadline end
    ns.Cadence:Add(acquireToken, ACQUIRE_INTERVAL, AcquisitionTick, true)
end

local function ExpireStates(now)
    local changed = false
    for guid, state in pairs(states) do
        local unit = state.unit
        if unit and (not UnitExists(unit) or UnitGUID(unit) ~= guid) then
            state.unit = nil
            unit = nil
        end

        -- A removed nameplate may still be available through target/focus.
        -- Reattach that concrete token before deciding the GUID is no longer
        -- observable.
        if not unit then
            unit = ResolveUnit(guid)
            if unit then
                CaptureMetadata(state, unit)
            end
        end

        -- Nominal expiration is no longer state destruction. It is the boundary
        -- between the estimated countdown and observable overtime. This makes
        -- real-world leash variance visible instead of silently recycling the
        -- estimate or dropping the row at 0.0.
        local overdue = state.expiration <= now
        if overdue then state.overrun = true end

        local remove = false
        if unit then
            if UnitIsDead(unit) then
                remove = true
            elseif state.estimate and not overdue then
                -- Before the nominal leash boundary, estimated body-pull states
                -- remain sticky because Classic threat/victim/combat flags can
                -- oscillate while the pull is settling.
                state.disengageSince = nil
                state.outOfCombatSince = nil
            else
                -- Confirmed timers may end early, and estimated timers become
                -- eligible for real-reset cleanup once they have crossed zero.
                -- Require stable disengagement so one transient API sample does
                -- not tear down an overtime row.
                if UnitAffectingCombat and not UnitAffectingCombat(unit) then
                    state.outOfCombatSince = state.outOfCombatSince or now
                else
                    state.outOfCombatSince = nil
                end

                local disengageSince = state.outOfCombatSince or state.disengageSince
                if disengageSince and now - disengageSince >= DISENGAGE_GRACE then
                    if PlayerEngagedWith(unit) then
                        state.disengageSince = nil
                        state.outOfCombatSince = nil
                    elseif (UnitAffectingCombat and not UnitAffectingCombat(unit))
                        or ExplicitlyDisengaged(unit) then
                        remove = true
                    else
                        state.disengageSince = nil
                        state.outOfCombatSince = nil
                    end
                end
            end
        else
            local disengageSince = state.outOfCombatSince or state.disengageSince
            if disengageSince and now - disengageSince >= DISENGAGE_GRACE then
                -- Finish a concrete disengagement debounce even if the plate
                -- disappeared between the first observation and this tick.
                remove = true
            elseif overdue then
                -- Overtime is meaningful only while the GUID still has an
                -- observation surface. Once every token is gone, Classic gives
                -- us no later per-GUID reset event; retaining the row would make
                -- it survive until the player's unrelated combat ends.
                remove = true
            end
        end

        if remove then
            states[guid] = nil
            changed = true
        end
    end
    return changed
end

UpdateDisplay = function(force)
    if not display then return end
    if not RuntimeEnabled() or not playerInCombat then
        display:Hide()
        return
    end

    wipe(sortBuffer)
    for _, state in pairs(states) do
        sortBuffer[#sortBuffer + 1] = state
    end
    table_sort(sortBuffer, SortByExpiration)

    wipe(textBuffer)
    local now = GetTime()
    for i = 1, #sortBuffer do
        local state = sortBuffer[i]
        local delta = state.expiration - now
        local marker = state.raidMarker and string_format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t ", state.raidMarker) or ""
        if delta <= 0 then
            -- Once the estimate is exceeded, show measured overtime rather than
            -- clamping at zero or restarting the nominal leash countdown.
            textBuffer[i] = string_format("%s%s: %s+%.1fs|r", marker, state.name or "Unknown", COLOR_DANGER, -delta)
        else
            local color = delta < 3 and COLOR_DANGER or (delta < 7 and COLOR_WARNING or COLOR_NORMAL)
            textBuffer[i] = string_format("%s%s: %s%.1fs|r", marker, state.name or "Unknown", color, delta)
        end
    end

    local rowCount = #textBuffer
    if rowCount == 0 then
        textBuffer[1] = COLOR_EMPTY .. "No tracked enemies|r"
        rowCount = 1
    end

    displayText:SetText(table.concat(textBuffer, "\n"))
    local fontSize = tonumber(DB().leashTimerFontSize) or 12
    local h = math_max(20, rowCount * (fontSize + 2) + 4)
    display:SetHeight(h)
    display:Show()

    if force or rowCount ~= lastRowCount then
        lastRowCount = rowCount
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("LeashTimer") end
    end
end

local function RuntimeTick()
    local changed = ExpireStates(GetTime())
    if changed then SyncCadence() end
    UpdateDisplay(changed)
end

SyncCadence = function()
    if not runtimeActive or not playerInCombat or ActiveStateCount() == 0 then
        ns.Cadence:Remove(LT)
        return
    end
    ns.Cadence:Add(LT, CADENCE_INTERVAL, RuntimeTick)
end

local function HandleCC(subevent, guid, spellName)
    if not guid or not IsLeashPausingEffect(spellName) then return false end
    if subevent == "SPELL_AURA_APPLIED" then
        ccCounts[guid] = (ccCounts[guid] or 0) + 1
        RemoveState(guid)
        pendingCLEU[guid] = nil
        SyncCadence()
        UpdateDisplay(true)
        return true
    elseif subevent == "SPELL_AURA_REMOVED" then
        local count = (ccCounts[guid] or 0) - 1
        if count > 0 then
            ccCounts[guid] = count
        else
            ccCounts[guid] = nil
            local unit = ResolveUnit(guid)
            if unit and IsHostileNPCUnit(unit) and PlayerEngagedWith(unit) then
                StartState(guid, unit, GetTime(), true, UnitName(unit))
            end
        end
        return true
    end
    return false
end

local function OnCombatLog(e)
    if not runtimeActive or not playerInCombat then return end

    local subevent = e[2]
    local sourceGUID, sourceFlags = e[4], e[6]
    local destGUID, destName, destFlags = e[8], e[9], e[10]
    local now = GetTime()

    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        if destGUID then
            ccCounts[destGUID] = nil
            pendingCLEU[destGUID] = nil
            if RemoveState(destGUID) then
                SyncCadence()
                UpdateDisplay(true)
            end
        end
        return
    end

    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REMOVED" then
        if IsHostileNPCFlags(destFlags) and HandleCC(subevent, destGUID, e[13]) then return end
        return
    end

    if sourceGUID == playerGUID and IsHostileNPCFlags(destFlags) then
        local missType
        if subevent == "SWING_MISSED" then
            missType = e[12]
        elseif subevent == "RANGE_MISSED" or subevent == "SPELL_MISSED" then
            missType = e[15]
        end

        -- EVADE is the combat log's explicit per-GUID reset result. It must
        -- destroy only this mob's state even while another mob keeps the player
        -- in combat.
        if missType == "EVADE" then
            pendingCLEU[destGUID] = nil
            if RemoveState(destGUID) then
                SyncCadence()
                UpdateDisplay(true)
            end
            return
        end

        local reset = false
        if subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE"
            or subevent == "SPELL_DAMAGE" or subevent == "SPELL_CAST_SUCCESS" then
            reset = true
        elseif subevent == "SWING_MISSED" then
            reset = missType == "IMMUNE"
        elseif subevent == "RANGE_MISSED" or subevent == "SPELL_MISSED" then
            reset = missType == "IMMUNE"
        end
        if reset then StartOrPendFromCLEU(destGUID, now, destName) end
        return
    end

    -- The newer reference uses an incoming stationary melee swing as a valid
    -- stand-leash reset while the mob is engaged with the player.  Keep this narrow:
    -- outgoing interactions remain the primary signal, and spells/periodics do
    -- not accidentally extend the leash.
    if destGUID == playerGUID and (subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED")
        and IsHostileNPCFlags(sourceFlags) and not ccCounts[sourceGUID] then
        local unit = ResolveUnit(sourceGUID)
        if unit and IsHostileNPCUnit(unit) then
            local mobSpeed = GetUnitSpeed and GetUnitSpeed(unit) or 0
            local playerSpeed = GetUnitSpeed and GetUnitSpeed("player") or 0
            if mobSpeed == 0 and playerSpeed == 0 then
                -- Being struck by this GUID is already authoritative engagement.
                StartState(sourceGUID, unit, now, false, UnitName(unit))
            end
        end
    end
end

local function OnEvent(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        playerInCombat = PlayerIsInCombat()
        wipe(guidToUnit)
        wipe(unitToGUID)
        wipe(combatByGUID)
        wipe(combatChangedAt)
        playerCombatStartedAt = 0
        SeedVisibleNameplates()
        if playerInCombat then RefreshAllVisibleEngagement(true) end
        UpdateDisplay(true)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        playerGUID = UnitGUID("player")
        playerInCombat = true
        playerCombatStartedAt = GetTime()
        SeedVisibleNameplates()
        RefreshAllVisibleEngagement(true)
        BeginAcquisitionWindow(ACQUIRE_WINDOW)
        SyncCadence()
        UpdateDisplay(true)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        playerInCombat = false
        playerCombatStartedAt = 0
        ClearCombatState()
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local guid = RememberNameplate(unit)
        ObserveUnitCombat(unit)
        if playerInCombat and guid then
            RefreshEngagementForUnit(unit, true)
            TryAdmitTransitionFallback()
            -- The unit token can appear just before its target/threat fields.
            BeginAcquisitionWindow(0.75)
        end
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        ClearNameplateToken(unit)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if playerInCombat and UnitExists("target") then RefreshEngagementForUnit("target", true) end
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        if playerInCombat and UnitExists("focus") then RefreshEngagementForUnit("focus", true) end
        return
    end

    if event == "UNIT_TARGET" or event == "UNIT_FLAGS" then
        if not unit then return end
        if unit:find("nameplate", 1, true) == 1 then
            RememberNameplate(unit)
            if event == "UNIT_FLAGS" then ObserveUnitCombat(unit) end
            if playerInCombat then
                RefreshEngagementForUnit(unit, true)
                TryAdmitTransitionFallback()
            end
        elseif playerInCombat and (unit == "target" or unit == "focus") then
            RefreshEngagementForUnit(unit, true)
        end
        return
    end

    if event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if not playerInCombat then return end
        if unit and unit:find("nameplate", 1, true) == 1 then
            RefreshEngagementForUnit(unit, true)
        else
            -- Blizzard may report the actor (often "player") rather than the
            -- affected NPC.  Sweep only the small set of nameplates we already
            -- know about; never scan 40 synthetic unit tokens.
            RefreshAllVisibleEngagement(true)
        end
        SyncCadence()
        UpdateDisplay(true)
    end
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("UNIT_TARGET")
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
end

local function ActivateRuntime()
    if runtimeActive then
        SyncCadence()
        UpdateDisplay(true)
        return
    end
    runtimeActive = true
    playerGUID = UnitGUID("player")
    playerInCombat = PlayerIsInCombat()
    SetEvents(true)
    if ns.CLEU then ns.CLEU:Register(OnCombatLog, TRACKED_CLEU) end
    SeedVisibleNameplates()
    if playerInCombat then
        RefreshAllVisibleEngagement(true)
        BeginAcquisitionWindow(ACQUIRE_WINDOW)
    end
    SyncCadence()
    UpdateDisplay(true)
end

local function DeactivateRuntime()
    if not runtimeActive then
        if display then display:Hide() end
        return
    end
    runtimeActive = false
    if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
    SetEvents(false)
    wipe(guidToUnit)
    wipe(unitToGUID)
    wipe(combatByGUID)
    wipe(combatChangedAt)
    playerCombatStartedAt = 0
    ClearCombatState()
end

SyncRuntime = function()
    if RuntimeEnabled() then ActivateRuntime() else DeactivateRuntime() end
end

function LT:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("LeashTimer", display, {
        label = "Leash Timer",
        overlayWidth = DISPLAY_WIDTH,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = FALLBACK_POINT,
        isAvailable = function() return DB().leashTimerEnabled == true end,
        onApply = function()
            -- Hidden is a Movers-owned visual preference.  With no headless
            -- consumer there is no reason to keep CLEU/cadence work alive while
            -- the widget itself is hidden.
            SyncRuntime()
        end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("LeashTimer") end
end

function LT:Init()
    if initialized then
        self:Refresh()
        return
    end
    if not FeatureEnabled() then return end

    initialized = true
    EnsureDisplay()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    self:RegisterMover()
    SyncRuntime()
end

function LT:Refresh()
    if not initialized then
        if FeatureEnabled() then self:Init() end
        return
    end

    ApplyFont()
    if FeatureEnabled() then self:RegisterMover() end
    SyncRuntime()
    UpdateDisplay(true)
end

function LT:GetFrame()
    return display
end

ns.RegisterCPUProfileTarget("Combat/LeashTimer:CLEU", OnCombatLog)
ns.RegisterCPUProfileTarget("Combat/LeashTimer:Events", OnEvent)
ns.RegisterCPUProfileTarget("Combat/LeashTimer:RuntimeTick", RuntimeTick)
