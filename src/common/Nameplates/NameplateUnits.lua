local _, ns = ...

-- Nameplates/NameplateUnits.lua -- target/combo tracking, quest indicators, native full-plate update, event pipeline.
-- Split from Nameplates.lua (G3 refactor). Shared nameplate internals live in
-- ns.NP, created by Nameplates.lua (loads first in the TOC).

local NP = ns.NP

-- Hot-path aliases (upvalues are cheaper than global lookups)
local UnitExists = ns.API.ReadUnitExists
local UnitGUID = ns.API.ReadUnitGUID
local UnitIsUnit = ns.API.ReadUnitIsUnit
local UnitIsFriend = ns.API.ReadUnitIsFriend
local CreateFrame = CreateFrame
local PixelUtil = PixelUtil
local C_NamePlate = C_NamePlate
local C_NamePlate_GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local C_Timer_After = C_Timer.After
local pairs = pairs
local THROTTLE = NP.THROTTLE
local dirtyHealth = NP.dirtyHealth
local dirtyAbsorb = NP.dirtyAbsorb
local dirtyThreat = NP.dirtyThreat
local dirtyPower = {}
local EnsureFullPlate = NP.EnsureFullPlate
local GetPlateByGUID = NP.GetPlateByGUID
local UpdateAbsorb = NP.UpdateAbsorb
local UpdateHealth = NP.UpdateHealth
local GetQuestLogTitle = ns.API.GetQuestLogTitle
local GetQuestLogIndexByID = ns.API.GetQuestLogIndexByID

-- Update target/combo points. Blizzard owns native selected/base scaling; the
-- TurboFace augmentation host simply inherits the root nameplate transform.
local function UpdateTarget()
    local previousTargetPlate = ns.currentTargetPlate
    if ns.currentTargetPlate then
        -- Verify plate still belongs to our tracked target (not recycled)
        local prevUnit = ns.currentTargetPlate.unit
        local plateGUID = prevUnit and UnitGUID(prevUnit)
        local stillValid = plateGUID and plateGUID == ns.currentTargetGUID
        if not stillValid then previousTargetPlate = nil end
    end
    ns.currentTargetPlate = nil
    ns.currentTargetGUID = nil

    -- Find new target's nameplate
    if UnitExists("target") then
        ns.currentTargetGUID = UnitGUID("target")
        local nameplate = C_NamePlate_GetNamePlateForUnit("target")
        if nameplate and nameplate.myPlate and not nameplate.myPlate._tfNativeFriendlyIdentityOnly then
            -- Target combo dots are drawn by ns.UpdateTargetComboPoints.
            ns.currentTargetPlate = nameplate.myPlate
        end
    end

    if ns.RefreshNameplateComboDriver then ns.RefreshNameplateComboDriver() end
    if ns.BubbleNameplates then
        ns.BubbleNameplates:OnTargetChanged(previousTargetPlate, ns.currentTargetPlate)
    end
end

-- Validate target plate identity using GUID.
-- Detects when the WoW client recycles a nameplate frame to a different unit
-- and repairs TurboFace's cached target reference. Called from Core.lua on
-- NAME_PLATE_UNIT_REMOVED.
local function ValidateTargetPlate()
    -- No target GUID means no target
    if not ns.currentTargetGUID then
        ns.currentTargetPlate = nil
        return
    end

    -- Check if cached plate still matches GUID
    if ns.currentTargetPlate then
        local unit = ns.currentTargetPlate.unit
        local plateGUID = unit and UnitGUID(unit)
        if plateGUID == ns.currentTargetGUID then
            return -- Still valid, no action needed
        end
        -- Mismatch detected. Pooled-frame cleanup already hid any TurboFace
        -- target adjuncts; drop only the stale target reference here.
        ns.currentTargetPlate = nil
    end

    -- Find correct plate by GUID
    ns.currentTargetPlate = GetPlateByGUID(ns.currentTargetGUID)
    if ns.RefreshNameplateComboDriver then ns.RefreshNameplateComboDriver() end
end

-- Exposed for Core.lua's plate-removal path.
ns.ValidateTargetPlate = ValidateTargetPlate

-- Ensure quest icon exists (creates on-demand for any plate type)
local function EnsureQuestIcon(myPlate)
    if myPlate.questIcon then return end

    local questIcon = myPlate:CreateTexture(nil, "OVERLAY")
    PixelUtil.SetSize(questIcon, 16, 16, 1, 1)
    PixelUtil.SetPoint(questIcon, "LEFT", myPlate.hp, "RIGHT", 2, 0, 1, 1)
    questIcon:Hide()
    myPlate.questIcon = questIcon
end

-- Quest system state (consolidated to reduce local variable count)
local Quest = {
    GetLogIndexByID = GetQuestLogIndexByID,
    GetLogTitle = GetQuestLogTitle,
    isNilOrEmpty = string.isNilOrEmpty or function(s) return s == nil or s == "" end,
    retryState = {},  -- Key = unit string, Value = { token, attempt }
    MAX_RETRIES = 4,
    RETRY_DELAYS = { 0.15, 0.3, 0.6, 1.2 },  -- Exponential backoff
    IsObjectiveStatus = function(status)
        return status == "collect" or status == "objective"
    end,
}

-- Update quest objective icon for a unit (full plates)
-- Uses C_QuestLog.GetUnitQuestInfo and QuestUtil to get appropriate icon
-- Logic matches FrameXML/CompactUnitFrame.lua:UpdateQuestIcon()
local function UpdateQuestIcon(unit)
    local myPlate = ns.unitToPlate[unit]
    if not myPlate then return end

    -- Fast path: quest icons completely disabled
    if not ns.c_questIconsEnabled then
        if myPlate.questIcon then myPlate.questIcon:Hide() end
        return
    end


    -- Check if API exists (recheck each call in case C_QuestLog loads late)
    if not (C_QuestLog and C_QuestLog.GetUnitQuestInfo) then
        if myPlate.questIcon then myPlate.questIcon:Hide() end
        return
    end

    -- Get quest info for this unit
    -- C_QuestLog.GetUnitQuestInfo returns: questStatus, questID, talkToMe
    local questStatus, questID, talkToMe = C_QuestLog.GetUnitQuestInfo(unit)

    -- No quest data for this unit
    if Quest.isNilOrEmpty(talkToMe) and not questStatus then
        -- Retry mechanism with exponential backoff
        if UnitExists(unit) then
            local state = Quest.retryState[unit]
            local attempt = state and state.attempt or 0

            if attempt < Quest.MAX_RETRIES then
                local token = {}
                local delay = Quest.RETRY_DELAYS[attempt + 1] or 1.2
                Quest.retryState[unit] = { token = token, attempt = attempt + 1 }

                C_Timer_After(delay, function()
                    local current = Quest.retryState[unit]
                    if not current or current.token ~= token then return end
                    if UnitExists(unit) then
                        UpdateQuestIcon(unit)
                    else
                        Quest.retryState[unit] = nil
                    end
                end)
            end
        end
        if myPlate.questIcon then myPlate.questIcon:Hide() end
        return
    end

    -- Success - clear retry state for this unit
    Quest.retryState[unit] = nil

    -- Validate quest is in log and not complete.
    if questID and questID > 0 then
        local questLogIndex = Quest.GetLogIndexByID(questID)
        if questLogIndex == 0 then
            if myPlate.questIcon then myPlate.questIcon:Hide() end
            return
        else
            local isComplete = select(7, Quest.GetLogTitle(questLogIndex))
            if isComplete then
                if myPlate.questIcon then myPlate.questIcon:Hide() end
                return
            end
        end
    end

    local atlas, desaturate

    -- Check for quest NPC (pickup/turnin) first
    if not Quest.isNilOrEmpty(talkToMe) then
        if not ns.c_showQuestNPCs then
            if myPlate.questIcon then myPlate.questIcon:Hide() end
            return
        end
        -- Get atlas for talk-to-me NPC icons
        if QuestUtil and QuestUtil.GetTalkToMeQuestIcon then
            atlas, desaturate = QuestUtil.GetTalkToMeQuestIcon(talkToMe)
        end
        -- Fallback if no atlas returned
        if not atlas and QuestUtil and QuestUtil.GetQuestStatusIcon then
            atlas, desaturate = QuestUtil.GetQuestStatusIcon(questStatus)
        end
    -- Quest status can also represent pickup/turnin/trivial NPC icons when talkToMe is empty.
    elseif questStatus then
        if Quest.IsObjectiveStatus(questStatus) then
            if not ns.c_showQuestObjectives then
                if myPlate.questIcon then myPlate.questIcon:Hide() end
                return
            end
        elseif not ns.c_showQuestNPCs then
            if myPlate.questIcon then myPlate.questIcon:Hide() end
            return
        end
        -- Get atlas for quest status icons
        if QuestUtil and QuestUtil.GetQuestStatusIcon then
            atlas, desaturate = QuestUtil.GetQuestStatusIcon(questStatus)
        end
    else
        if myPlate.questIcon then myPlate.questIcon:Hide() end
        return
    end

    -- Create quest icon on-demand (only when actually showing something)
    EnsureQuestIcon(myPlate)

    -- Override kill objective icon
    if atlas == "questkill" then atlas = "tormentors-boss" end

    -- Apply atlas texture (UseAtlasSize = true to get base size)
    myPlate.questIcon:SetAtlas(atlas or "questnormal", true)
    local w, h = myPlate.questIcon:GetSize()
    -- Normalize tormentors-boss (43x43) to 32x32 for consistent sizing
    if atlas == "tormentors-boss" then w, h = 32, 32 end
    local scale = ns.c_questIconScale * 0.5  -- Match Ascension's internal scaling (* 0.5)
    myPlate.questIcon:SetSize(w * scale, h * scale)

    -- Apply desaturation if needed
    if myPlate.questIcon.SetDesaturated then
        myPlate.questIcon:SetDesaturated(desaturate or false)
    end

    -- Position based on anchor setting (relative to name text or level text)
    myPlate.questIcon:ClearAllPoints()
    local anchor = ns.c_questIconAnchor
    local xOff, yOff = ns.c_questIconX, ns.c_questIconY
    local nameAnchor = ns.GetNameplateNameAnchor(myPlate, true) or myPlate.hp or myPlate
    if anchor == "LEFT" then
        myPlate.questIcon:SetPoint("RIGHT", nameAnchor, "LEFT", -2 + xOff, yOff)
    elseif anchor == "RIGHT" then
        -- Use Blizzard's visible level/name regions as read-only anchors.
        local rightAnchor = ns.GetNameplateIdentityRightAnchor(myPlate) or nameAnchor
        myPlate.questIcon:SetPoint("LEFT", rightAnchor, "RIGHT", 2 + xOff, yOff)
    else  -- TOP
        myPlate.questIcon:SetPoint("BOTTOM", nameAnchor, "TOP", xOff, 2 + yOff)
    end

    myPlate.questIcon:Show()
end

-- Refresh quest icons on every visible native nameplate.
local function UpdateAllQuestIcons()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = ns.API.GetPlateUnitToken(nameplate)
        if unit then UpdateQuestIcon(unit) end
    end
end
ns.UpdateAllQuestIcons = UpdateAllQuestIcons
-- Expose quest retry state cleanup for nameplate removal
ns.ClearQuestRetryState = function(unit)
    if unit then Quest.retryState[unit] = nil end
end

-- Full augmentation update for a Blizzard-native plate.
function ns:FullPlateUpdate(myPlate, unit)
    if not myPlate or not unit or not UnitExists(unit) then return end

    Quest.retryState[unit] = nil
    if myPlate.questIcon then myPlate.questIcon:Hide() end
    myPlate._lastAbsorb = nil
    myPlate._lastAbsorbHealth = nil
    myPlate._lastAbsorbWidth = nil
    myPlate._lastAbsorbHeight = nil
    myPlate._lastAbsorbFill = nil
    myPlate._lastDotOffset = nil
    myPlate._lastDotWidth = nil
    myPlate._lastDotBottomInset = nil
    myPlate._lastDotR = nil
    myPlate._lastDotG = nil
    myPlate._lastDotB = nil
    myPlate._lastDotA = nil
    myPlate._tfDotGeometryRetries = nil

    local isPersonal = UnitIsUnit(unit, "player")
    myPlate.isPlayer = isPersonal
    if isPersonal then
        if ns.BubbleNameplates then ns.BubbleNameplates:OnFullUpdate(myPlate, unit) end
        myPlate:Hide()
        return
    end

    myPlate.isFriendly = UnitIsFriend("player", unit)

    -- Blizzard 1.15.9 is the only baseline substrate. If its native HP bar is
    -- unavailable, fail open: park TurboFace augmentation rather than constructing
    -- a second custom plate.
    local hp = EnsureFullPlate(myPlate)
    if not hp then
        if ns.unitToPlate[unit] == myPlate then ns.unitToPlate[unit] = nil end
        myPlate:Hide()
        return
    end
    hp._tfOverlaySubstrateDirty = true
    if myPlate.guildText then myPlate.guildText:Hide() end

    if ns.UpdateAuraPositions then ns:UpdateAuraPositions(myPlate) end

    local isTarget = UnitIsUnit(unit, "target")
    if isTarget then
        if ns.currentTargetPlate ~= myPlate then ns.currentTargetPlate = myPlate end
        if ns.RefreshNameplateComboDriver then ns.RefreshNameplateComboDriver() end
    end

    UpdateHealth(unit)
    UpdateQuestIcon(unit)

    if ns.UpdateAuras then ns:UpdateAuras(myPlate, unit) end
    if ns.UpdateTurboDebuff then ns:UpdateTurboDebuff(myPlate, unit) end
    if ns.BubbleNameplates then ns.BubbleNameplates:OnFullUpdate(myPlate, unit) end
end

-- Create the TurboFace augmentation host. It never contains a replacement
-- Blizzard name/level/health/cast surface; those remain native.
function ns:CreatePlateFrame(parentFrame, unit)
    local myPlate = CreateFrame("Frame", nil, parentFrame)

    myPlate:SetAllPoints(parentFrame)
    myPlate:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    myPlate:EnableMouse(false)
    parentFrame.myPlate = myPlate

    myPlate.parentPlate = parentFrame
    myPlate.nativeUnitFrame = parentFrame and parentFrame.UnitFrame or nil
    myPlate.nativeHealthBar = myPlate.nativeUnitFrame and (myPlate.nativeUnitFrame.healthBar
        or (myPlate.nativeUnitFrame.HealthBarsContainer and myPlate.nativeUnitFrame.HealthBarsContainer.healthBar)) or nil
    myPlate._tfUsesNativeIdentity = myPlate.nativeHealthBar ~= nil
    myPlate._tfUsesNativeHealth = myPlate.nativeHealthBar ~= nil
    myPlate.unit = unit
    myPlate.cachedGUID = UnitGUID(unit)

    -- Full-native NPC subtitle supplement. Friendly Name + Title Only uses its
    -- root-level title in Core.lua and does not depend on this hidden host.
    local guildText = myPlate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PixelUtil.SetPoint(guildText, "TOP", myPlate, "BOTTOM", 0, -1, 1, 1)
    guildText:SetTextColor(1, 1, 1)
    guildText:SetJustifyH("CENTER")
    guildText:Hide()
    myPlate.guildText = guildText
    ns:StyleFont(guildText, ns.c_font, ns.NP_TITLE_FONT_SIZE or 8, nil, ns.NP_NAME_TEXT_STYLE)

    if ns.CreateAuraContainers then ns:CreateAuraContainers(myPlate) end
end

-- Event frame for unit events. The object itself is also lazy: disabling the
-- Nameplates master before login should leave no inert unit-event frame behind.
local eventFrame
local NameplateUnitOnEvent
local nameplateUnitEventsActive = false

-- The full nameplate unit pipeline is intentionally inert at file load. Core
-- activates it after saved variables are normalized and only when the Nameplates
-- master is on; otherwise high-frequency UNIT_HEALTH/POWER events never
-- enter TurboFace at all.
function ns.ActivateNameplateUnitEvents()
    if nameplateUnitEventsActive then return end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return end
    nameplateUnitEventsActive = true
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", NameplateUnitOnEvent)
    end

    ns.RegisterEvent(eventFrame, "UNIT_HEALTH")
    ns.RegisterEvent(eventFrame, "UNIT_MAXHEALTH")
    ns.RegisterEvent(eventFrame, "PLAYER_TARGET_CHANGED")
    -- Combo point events do not exist in Classic Era 1.15.8; combo points are
    -- read via GetComboPoints() on PLAYER_TARGET_CHANGED.
    ns.RegisterEvent(eventFrame, "UNIT_FACTION")
    ns.RegisterEvent(eventFrame, "QUEST_LOG_UPDATE")
    ns.RegisterEvent(eventFrame, "QUEST_ACCEPTED")
    ns.RegisterEvent(eventFrame, "QUEST_POI_UPDATE")
    ns.RegisterEvent(eventFrame, "UNIT_QUEST_LOG_CHANGED")
    ns.RegisterEvent(eventFrame, "UNIT_ABSORB_AMOUNT_CHANGED")
    if ns.RefreshNameplatePowerEvents then ns.RefreshNameplatePowerEvents() end
    if ns.caps and ns.caps.healPrediction then
        ns.RegisterEvent(eventFrame, "UNIT_HEAL_PREDICTION")
    end
    if ns.RefreshNameplateThreatEvents then ns.RefreshNameplateThreatEvents() end
end

local function ThreatRuntimeNeeded()
    return ns.c_nameplateThreatNumber ~= false
        or (ns.c_nameplateAggroSounds == true
            and ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())))
end

-- Threat Number and Aggro Audio are additive consumers of Blizzard threat
-- state. The retired health-color engine is not involved. Keep the two hot
-- threat events subscribed only while at least one current consumer has demand;
-- GROUP_ROSTER_UPDATE wakes/parks the audio-only case as group state changes.
function ns.RefreshNameplateThreatEvents()
    if not (nameplateUnitEventsActive and eventFrame) then return end

    if ns.c_nameplateAggroSounds == true then
        ns.RegisterEvent(eventFrame, "GROUP_ROSTER_UPDATE")
    else
        eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end

    if ThreatRuntimeNeeded() then
        ns.RegisterEvent(eventFrame, "UNIT_THREAT_LIST_UPDATE")
        ns.RegisterEvent(eventFrame, "UNIT_THREAT_SITUATION_UPDATE")
    else
        eventFrame:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        eventFrame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        wipe(dirtyThreat)
    end
end

-- The custom NPC resource presentation exists only in overlap mode. Keep all
-- three high-frequency power events parked while its checkbox is off so we do
-- not even query power for a nameplate until the feature has demand.
function ns.RefreshNameplatePowerEvents()
    if not (nameplateUnitEventsActive and eventFrame) then return end
    local register = ns.c_nameplatePowerBarOverlap == true
    local method = register and "RegisterEvent" or "UnregisterEvent"
    eventFrame[method](eventFrame, "UNIT_POWER_UPDATE")
    eventFrame[method](eventFrame, "UNIT_MAXPOWER")
    eventFrame[method](eventFrame, "UNIT_DISPLAYPOWER")
end

-- Fast nameplate check (uses cached strsub)

-- Timer-based throttling with batched updates
-- dirty tables already initialized at top of file

-- Pending timer state (consolidated)
local pendingTimers = {
    health = nil,
    threat = nil,
    quest = nil,
    absorb = nil,
    power = nil,
}

-- Dynamic throttle getters
local function GetHealthThrottle() return THROTTLE.health end
local function GetThreatThrottle() return THROTTLE.threat end
local function GetQuestThrottle() return THROTTLE.quest end

local function ProcessDirtyHealth()
    pendingTimers.health = nil
    local dc = ns.DebugCounters
    if dc then dc.healthTick = dc.healthTick + 1 end
    local unit = next(dirtyHealth)
    while unit do
        local nextUnit = next(dirtyHealth, unit)
        if ns.IsNameplateUnit(unit) and UnitExists(unit) then
            -- Damaged-only friendly plates intentionally drop out of unitToPlate
            -- at full health. Re-evaluate their native presentation directly
            -- from the unit token before the ordinary full-plate health path.
            if (ns.c_nameplateFriendlyPlayerDamagedOnly or ns.c_nameplateFriendlyNPCDamagedOnly)
                and ns.UpdateFriendlyDamagedOnlyUnit then
                ns.UpdateFriendlyDamagedOnlyUnit(unit)
            end
            UpdateHealth(unit)
        end
        dirtyHealth[unit] = nil
        unit = nextUnit
    end
end

local function ProcessQuestUpdate()
    pendingTimers.quest = nil
    -- Only update if quest icons are actually enabled
    if ns.c_questIconsEnabled then
        UpdateAllQuestIcons()
    end
end

local function ProcessDirtyThreat()
    pendingTimers.threat = nil
    local unit = next(dirtyThreat)
    while unit do
        local nextUnit = next(dirtyThreat, unit)
        if ns.IsNameplateUnit(unit) and UnitExists(unit) then
            local plate = ns.unitToPlate[unit]
            if plate and ns.BubbleNameplates then
                ns.BubbleNameplates:OnThreatUpdate(plate, unit)
            end
        end
        dirtyThreat[unit] = nil
        unit = nextUnit
    end
end

-- Kill-trace boundaries wrap the BATCH FLUSH, not the schedulers or the OnEvent
-- dispatcher: those only set a dirty flag and arm a latch, so the post-kill cost
-- (a burst of plates dying/despawning at once) lands in the processors below.
local function TraceHealthBatch() ns.KillTrace("Nameplates/Units:", "HealthBatch", ProcessDirtyHealth) end
local function TraceThreatBatch() ns.KillTrace("Nameplates/Units:", "ThreatBatch", ProcessDirtyThreat) end

local function ScheduleHealthUpdate()
    if not pendingTimers.health then
        -- C_Timer.After does not return a timer handle. Use the field as a
        -- boolean scheduling latch so bursty UNIT_HEALTH traffic coalesces into
        -- one batch instead of queuing one callback per event.
        pendingTimers.health = true
        C_Timer_After(GetHealthThrottle(), TraceHealthBatch)
    end
end

local function ScheduleThreatUpdate(unit)
    if ns.IsNameplateUnit(unit) then
        dirtyThreat[unit] = true
    elseif unit == "target" and ns.currentTargetPlate and ns.currentTargetPlate.unit then
        -- Some Classic paths report the target token instead of the equivalent
        -- nameplate token. Normalize it back to the tracked plate unit.
        dirtyThreat[ns.currentTargetPlate.unit] = true
    else
        -- Threat events can also identify the affected actor (player, pet, or
        -- group member) rather than the hostile unit whose list changed. In
        -- that form every visible hostile plate is potentially affected. The
        -- set and 50ms latch keep a burst to one update per visible plate.
        local found
        for plateUnit, plate in pairs(ns.unitToPlate) do
            if plate and UnitExists(plateUnit) then
                dirtyThreat[plateUnit] = true
                found = true
            end
        end
        if not found then return end
    end
    if not pendingTimers.threat then
        pendingTimers.threat = true
        C_Timer_After(GetThreatThrottle(), TraceThreatBatch)
    end
end

local function ProcessDirtyAbsorb()
    pendingTimers.absorb = nil
    local unit = next(dirtyAbsorb)
    while unit do
        local nextUnit = next(dirtyAbsorb, unit)
        if ns.IsNameplateUnit(unit) and UnitExists(unit) then
            local myPlate = ns.unitToPlate[unit]
            if myPlate and myPlate.hp then
                UpdateAbsorb(unit, myPlate)
            end
        end
        dirtyAbsorb[unit] = nil
        unit = nextUnit
    end
end

local function ProcessDirtyPower()
    pendingTimers.power = nil
    local unit = next(dirtyPower)
    while unit do
        local nextUnit = next(dirtyPower, unit)
        if ns.c_nameplatePowerBarOverlap == true and ns.IsNameplateUnit(unit)
            and UnitExists(unit) and ns.BubbleNameplates then
            ns.BubbleNameplates:OnPowerUpdate(ns.unitToPlate[unit], unit)
        end
        dirtyPower[unit] = nil
        unit = nextUnit
    end
end

-- Declared AFTER ProcessDirtyAbsorb: a closure created above it would capture
-- the name as a global, not the local defined later.
local function TraceAbsorbBatch() ns.KillTrace("Nameplates/Units:", "AbsorbBatch", ProcessDirtyAbsorb) end
local function TraceQuestBatch() ns.KillTrace("Nameplates/Units:", "QuestBatch", ProcessQuestUpdate) end

local function ScheduleAbsorbUpdate()
    if not pendingTimers.absorb then
        pendingTimers.absorb = true
        C_Timer_After(GetHealthThrottle(), TraceAbsorbBatch)
    end
end

local function SchedulePowerUpdate(unit)
    if not (unit and ns.IsNameplateUnit(unit)) then return end
    if not (ns.NameplateProviderDeferPowerUpdates and ns.NameplateProviderDeferPowerUpdates()) then
        if ns.c_nameplatePowerBarOverlap == true and UnitExists(unit) and ns.BubbleNameplates then
            ns.BubbleNameplates:OnPowerUpdate(ns.unitToPlate[unit], unit)
        end
        return
    end
    dirtyPower[unit] = true
    if pendingTimers.power then return end
    pendingTimers.power = true
    if ns.NameplateProviderScheduleBatch then
        ns.NameplateProviderScheduleBatch(ProcessDirtyPower)
    else
        C_Timer_After(0, ProcessDirtyPower)
    end
end

ns.RegisterCPUProfileTarget("Nameplates/Units:HealthBatch", ProcessDirtyHealth)
ns.RegisterCPUProfileTarget("Nameplates/Units:ThreatBatch", ProcessDirtyThreat)
ns.RegisterCPUProfileTarget("Nameplates/Units:AbsorbBatch", ProcessDirtyAbsorb)
ns.RegisterCPUProfileTarget("Nameplates/Units:PowerBatch", ProcessDirtyPower)
ns.RegisterCPUProfileTarget("Nameplates/Units:QuestBatch", ProcessQuestUpdate)

NameplateUnitOnEvent = function(self, event, unit)
    -- HOTTEST BRANCH FIRST. This frame is unfiltered (nameplate units cannot be
    -- expressed in RegisterUnitEvent's two-token limit), so UNIT_HEALTH arrives
    -- for every visible plate plus player/party/target. It used to sit 14 string
    -- comparisons deep. Branches select on `event` equality and are mutually
    -- exclusive, so ordering is purely a cost decision.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if ns.IsNameplateUnit(unit) then
            dirtyHealth[unit] = true
            ScheduleHealthUpdate()
        end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if ns.NameplateProviderAfterNativeUpdate then
            ns.NameplateProviderAfterNativeUpdate(UpdateTarget)
        else
            UpdateTarget()
        end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        ScheduleThreatUpdate(unit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.RefreshNameplateThreatEvents()
        -- Re-seed current-target audio transition state on group joins/leaves.
        if ns.NameplateProviderAfterNativeUpdate then
            ns.NameplateProviderAfterNativeUpdate(UpdateTarget)
        else
            UpdateTarget()
        end
    elseif event == "QUEST_LOG_UPDATE"
           or event == "QUEST_ACCEPTED" or event == "QUEST_POI_UPDATE"
           or event == "UNIT_QUEST_LOG_CHANGED" then
        -- Quest data changed - throttle updates (quest events can fire rapidly).
        -- Kill-traced: UNIT_QUEST_LOG_CHANGED fires on every kill that advances
        -- a quest objective, which is exactly the intermittent post-kill case.
        if not pendingTimers.quest then
            pendingTimers.quest = true
            C_Timer_After(GetQuestThrottle(), TraceQuestBatch)
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        -- Absorb shield changed
        if ns.IsNameplateUnit(unit) then
            dirtyAbsorb[unit] = true
            ScheduleAbsorbUpdate()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if ns.c_nameplatePowerBarOverlap == true then
            SchedulePowerUpdate(unit)
        end
    elseif event == "UNIT_HEAL_PREDICTION" then
        if ns.IsNameplateUnit(unit)
            and ns.NameplateProviderDeferHealPrediction
            and ns.NameplateProviderDeferHealPrediction() then
            dirtyHealth[unit] = true
            ScheduleHealthUpdate()
        elseif ns.IsNameplateUnit(unit) and ns.BubbleNameplates then
            ns.BubbleNameplates:OnHealthUpdate(ns.unitToPlate[unit], unit, true)
        end
    elseif event == "UNIT_FACTION" and ns.IsNameplateUnit(unit) then
        -- FACTION CHANGE: Unit became hostile/friendly - re-evaluate entire plate type.
        local function RefreshFactionAfterBlizzard()
            if ns.RefreshPlateForUnit then ns:RefreshPlateForUnit(unit) end
        end
        if ns.NameplateProviderAfterNativeUpdate then
            ns.NameplateProviderAfterNativeUpdate(RefreshFactionAfterBlizzard)
        else
            RefreshFactionAfterBlizzard()
        end
    end
end
ns.RegisterCPUProfileTarget("Nameplates/Units:Events", NameplateUnitOnEvent)
