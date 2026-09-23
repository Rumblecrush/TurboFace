local _, ns = ...

-- TurboFace Plus: small, event-driven convenience automations.
-- This implementation is expressed directly in terms of Blizzard's public
-- Classic Era APIs.  No NPC catalog or third-party automation table is used.

local M = {}
ns.PlusAutomation = M

local function Settings()
    return ns.PlusSettings()
end

local frames = {}
local function EventFrame(key, handler)
    local frame = frames[key]
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", handler)
        frames[key] = frame
    end
    return frame
end

local function SetEvents(key, enabled, handler, ...)
    local frame = frames[key]
    if enabled then
        frame = EventFrame(key, handler)
        frame:UnregisterAllEvents()
        for i = 1, select("#", ...) do
            local event = select(i, ...)
            if event then ns.API.RegisterEvent(frame, event) end
        end
    elseif frame then
        frame:UnregisterAllEvents()
    end
end

-- StaticPopup_Show can only be hooked, not unhooked.  Install it lazily and
-- keep the permanent hook inert unless a current listener is registered.
local popupHooked = false
local popupListeners = {}

local function EnsurePopupHook()
    if popupHooked then return end
    popupHooked = true
    hooksecurefunc("StaticPopup_Show", function(which)
        if ns.DebugPopupTrace then
            ns:Chat("Popups", "StaticPopup_Show: " .. tostring(which))
        end
        for callback in pairs(popupListeners) do
            callback(which)
        end
    end)
end

local function ListenForPopups(callback, active)
    if active then
        popupListeners[callback] = true
        EnsurePopupHook()
    else
        popupListeners[callback] = nil
    end
end

function M:EnsurePopupHook()
    EnsurePopupHook()
end

-- ---------------------------------------------------------------------------
-- Single-option gossip
-- ---------------------------------------------------------------------------

local function HasGossipQuests()
    if C_GossipInfo then
        if C_GossipInfo.GetNumAvailableQuests and C_GossipInfo.GetNumAvailableQuests() > 0 then return true end
        if C_GossipInfo.GetNumActiveQuests and C_GossipInfo.GetNumActiveQuests() > 0 then return true end
        local available = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()
        if type(available) == "table" and next(available) then return true end
        local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
        if type(active) == "table" and next(active) then return true end
    end
    if GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() > 0 then return true end
    if GetNumGossipActiveQuests and GetNumGossipActiveQuests() > 0 then return true end
    return false
end

local function SelectSingleQuestFreeOption()
    if HasGossipQuests() then return false end

    -- Primary 1.15.9 path. Some Classic entries omit
    -- selectOptionWhenOnlyOption, so exact cardinality plus the no-quest guard
    -- is the complete automation policy. Select by stable option ID when the
    -- client supplies one, otherwise use Blizzard's order index.
    if C_GossipInfo and C_GossipInfo.GetOptions then
        local options = C_GossipInfo.GetOptions()
        if type(options) ~= "table" or #options ~= 1 then return false end
        local option = options[1]
        if type(option) ~= "table" then return false end
        if option.gossipOptionID and C_GossipInfo.SelectOption then
            C_GossipInfo.SelectOption(option.gossipOptionID)
            return true
        end
        if C_GossipInfo.SelectOptionByIndex then
            C_GossipInfo.SelectOptionByIndex(option.orderIndex or 1)
            return true
        end
        return false
    end

    -- Compatibility path for Classic clients or UI replacements still using
    -- the legacy title/type pair API.
    if GetGossipOptions and SelectGossipOption then
        local values = { GetGossipOptions() }
        if #values == 2 then
            SelectGossipOption(1)
            return true
        end
    end
    return false
end

local function OnGossipShow()
    local p = Settings()
    if not p.automateGossip then return end
    if p.automateSpiritHealer and UnitIsGhost("player") then return end

    SelectSingleQuestFreeOption()
end

function M:RefreshGossip()
    SetEvents("gossip", Settings().automateGossip == true, OnGossipShow, "GOSSIP_SHOW")
end

-- ---------------------------------------------------------------------------
-- Quest accept / turn-in
-- ---------------------------------------------------------------------------

-- One NPC can expose several quest states at once, and accepting/turning in one
-- quest can reveal another without Classic emitting a fresh GOSSIP_SHOW. Keep a
-- small interaction-local processed set so post-action rescans can advance the
-- stack without reopening a stale entry returned by the client cache.
local questNPCGUID
local questProcessedActive = {}
local questProcessedAvailable = {}
local questPumpSerial = 0
local questInteractionOpen = false
local questPendingKind
local questPendingID
local questPendingSerial = 0
local ScheduleQuestSelectionPump

local function ClearQuestSet(set)
    for key in pairs(set) do set[key] = nil end
end

local function ResetQuestInteraction(guid)
    questNPCGUID = guid
    ClearQuestSet(questProcessedActive)
    ClearQuestSet(questProcessedAvailable)
    questPendingKind = nil
    questPendingID = nil
    questPendingSerial = questPendingSerial + 1
    questPumpSerial = questPumpSerial + 1
end

local function RefreshQuestInteractionIdentity()
    local guid = UnitGUID and UnitGUID("npc") or nil
    if guid and guid ~= questNPCGUID then ResetQuestInteraction(guid) end
end

local function QuestEntryComplete(quest)
    if type(quest) ~= "table" then return false end
    if quest.isComplete == true or quest.isComplete == 1 then return true end

    -- Classic gossip data can lag or omit isComplete when one NPC offers a
    -- mixture of completed and in-progress quests. Reconcile the quest ID with
    -- the authoritative quest-log state before deciding which entry to open.
    local questID = quest.questID
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsComplete then
        local complete = C_QuestLog.IsComplete(questID)
        if complete == true or complete == 1 then return true end
    end
    -- Forever can leave both gossip isComplete and C_QuestLog.IsComplete false
    -- for an NPC turn-in while its explicit readiness query is authoritative.
    if ns.API.QuestReadyForTurnIn then
        local ready = ns.API.QuestReadyForTurnIn(questID)
        if ready == true or ready == 1 then return true end
    end
    if IsQuestComplete then
        local complete = IsQuestComplete(questID)
        if complete == true or complete == 1 then return true end
    end
    return false
end

local function ConfirmPendingQuest(kind)
    if questPendingKind ~= kind or not questPendingID then return end
    local processed = kind == "active" and questProcessedActive or questProcessedAvailable
    processed[questPendingID] = true
    questPendingKind = nil
    questPendingID = nil
    questPendingSerial = questPendingSerial + 1
end

local function SelectQuestWithConfirmation(kind, questKey, selector, selectionArg)
    if questPendingID or not questKey or type(selector) ~= "function" then return false end

    questPendingKind = kind
    questPendingID = questKey
    questPendingSerial = questPendingSerial + 1
    local serial = questPendingSerial
    local ok = pcall(selector, selectionArg ~= nil and selectionArg or questKey)
    if not ok then
        questPendingKind = nil
        questPendingID = nil
        return false
    end

    -- Retail can drop a selection while its gossip options are refreshing.
    -- QUEST_DETAIL / QUEST_PROGRESS confirms success. If neither arrives, make
    -- the quest eligible again instead of leaving it permanently processed.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, function()
            if serial ~= questPendingSerial or questPendingID ~= questKey then return end
            questPendingKind = nil
            questPendingID = nil
            if questInteractionOpen and ScheduleQuestSelectionPump then
                ScheduleQuestSelectionPump()
            end
        end)
    end
    return true
end

local function SelectModernGossipQuest(p)
    if not C_GossipInfo then return false end
    if questPendingID then return true end

    -- Completed quests take priority so an NPC with both turn-ins and new
    -- quests cannot make the new work obscure a pending reward.
    if p.autoQuestTurnIn and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
        local active = C_GossipInfo.GetActiveQuests()
        if type(active) == "table" then
            local count = C_GossipInfo.GetNumActiveQuests and C_GossipInfo.GetNumActiveQuests() or #active
            for i = 1, count do
                local quest = active[i]
                if QuestEntryComplete(quest) and quest.questID
                    and not questProcessedActive[quest.questID] then
                    return SelectQuestWithConfirmation(
                        "active", quest.questID, C_GossipInfo.SelectActiveQuest)
                end
            end
        end
    end

    if p.autoQuestAccept and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
        local available = C_GossipInfo.GetAvailableQuests()
        if type(available) == "table" then
            for i = 1, #available do
                local quest = available[i]
                if type(quest) == "table" and quest.questID
                    and not questProcessedAvailable[quest.questID] then
                    return SelectQuestWithConfirmation(
                        "available", quest.questID, C_GossipInfo.SelectAvailableQuest)
                end
            end
        end
    end
    return false
end

local function SelectLegacyGossipQuest(p)
    if p.autoQuestTurnIn and GetNumGossipActiveQuests and GetGossipActiveQuests
        and SelectGossipActiveQuest then
        local count = GetNumGossipActiveQuests() or 0
        if count > 0 then
            local values = { GetGossipActiveQuests() }
            local stride = math.floor(#values / count)
            -- Classic's fourth value per active quest is isComplete. Deriving
            -- the stride retains compatibility with clients that append fields.
            if stride >= 4 then
                for i = 1, count do
                    local offset = (i - 1) * stride
                    local title = values[offset + 1]
                    local key = type(title) == "string" and ("legacy:" .. title) or nil
                    if values[offset + 4] and (not key or not questProcessedActive[key]) then
                        if key then questProcessedActive[key] = true end
                        SelectGossipActiveQuest(i)
                        return true
                    end
                end
            end
        end
    end

    if p.autoQuestAccept and GetNumGossipAvailableQuests and SelectGossipAvailableQuest then
        local count = GetNumGossipAvailableQuests() or 0
        if count > 0 then
            local values = GetGossipAvailableQuests and { GetGossipAvailableQuests() } or nil
            local stride = values and math.floor(#values / count) or 0
            for i = 1, count do
                local title = stride > 0 and values[((i - 1) * stride) + 1] or nil
                local key = type(title) == "string" and ("legacy:" .. title) or nil
                if not key or not questProcessedAvailable[key] then
                    if key then questProcessedAvailable[key] = true end
                    SelectGossipAvailableQuest(i)
                    return true
                end
            end
        end
    end
    return false
end


local function SelectQuestGreeting(p)
    if questPendingID then return true end

    if p.autoQuestTurnIn and GetNumActiveQuests and SelectActiveQuest then
        local count = GetNumActiveQuests() or 0
        for i = 1, count do
            -- Forever's Mainline-derived QuestFrame gets completion as return #2
            -- from GetActiveTitle and gets the quest ID separately. The older
            -- IsActiveQuestComplete helper may be absent entirely.
            local title, titleComplete
            if GetActiveTitle then title, titleComplete = GetActiveTitle(i) end
            local questID = GetActiveQuestID and GetActiveQuestID(i) or nil
            local ready = titleComplete == true or titleComplete == 1
            if not ready and IsActiveQuestComplete then
                local value = IsActiveQuestComplete(i)
                ready = value == true or value == 1
            end
            if not ready and questID and ns.API.QuestReadyForTurnIn then
                local value = ns.API.QuestReadyForTurnIn(questID)
                ready = value == true or value == 1
            end
            local key = questID and ("greeting-id:" .. questID)
                or (type(title) == "string" and ("greeting:" .. title) or nil)
            if ready and (not key or not questProcessedActive[key]) then
                key = key or ("greeting-active-index:" .. i)
                return SelectQuestWithConfirmation("active", key, SelectActiveQuest, i)
            end
        end
    end

    if p.autoQuestAccept and GetNumAvailableQuests and SelectAvailableQuest then
        local count = GetNumAvailableQuests() or 0
        for i = 1, count do
            local title = GetAvailableTitle and GetAvailableTitle(i) or nil
            local questID = GetAvailableQuestID and GetAvailableQuestID(i) or nil
            local key = questID and ("greeting-id:" .. questID)
                or (type(title) == "string" and ("greeting:" .. title))
                or ("greeting-available-index:" .. i)
            if not questProcessedAvailable[key] then
                return SelectQuestWithConfirmation("available", key, SelectAvailableQuest, i)
            end
        end
    end
    return false
end

local function DriveQuestSelection(p)
    RefreshQuestInteractionIdentity()
    if SelectModernGossipQuest(p) then return true end
    if SelectLegacyGossipQuest(p) then return true end
    return SelectQuestGreeting(p)
end

-- Server/UI ordering differs between NPCs: some return to gossip immediately,
-- some update their quest lists a few frames later, and some do not send a new
-- GOSSIP_SHOW at all. Retry briefly after a completed accept/reward transition.
-- Selecting a quest ends this pump; that quest's next lifecycle event schedules
-- the following pass, keeping the chain serialized rather than clicking ahead.
ScheduleQuestSelectionPump = function()
    questPumpSerial = questPumpSerial + 1
    local serial = questPumpSerial
    local attempt = 0

    local function Pump()
        if serial ~= questPumpSerial then return end
        if not questInteractionOpen then return end
        local p = Settings()
        if IsShiftKeyDown and IsShiftKeyDown() then return end
        if not (p.autoQuestAccept or p.autoQuestTurnIn) then return end
        attempt = attempt + 1
        if DriveQuestSelection(p) then return end
        if attempt < 8 and C_Timer and C_Timer.After then
            C_Timer.After(0.10, Pump)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, Pump)
    else
        Pump()
    end
end

local function OnQuestAutomation(_, event, arg1)
    local p = Settings()
    if IsShiftKeyDown and IsShiftKeyDown() then return end

    if event == "GOSSIP_SHOW" then
        local guid = UnitGUID and UnitGUID("npc") or nil
        if not questInteractionOpen then
            ResetQuestInteraction(guid)
        else
            RefreshQuestInteractionIdentity()
        end
        questInteractionOpen = true
        questPumpSerial = questPumpSerial + 1
        DriveQuestSelection(p)
    elseif event == "GOSSIP_CLOSED" then
        if arg1 then
            questInteractionOpen = true
        else
            questInteractionOpen = false
            ResetQuestInteraction(nil)
        end
    elseif event == "GOSSIP_OPTIONS_REFRESHED" then
        ScheduleQuestSelectionPump()
    elseif event == "QUEST_GREETING" then
        local guid = UnitGUID and UnitGUID("npc") or nil
        if not questInteractionOpen then ResetQuestInteraction(guid) end
        questInteractionOpen = true
        questPumpSerial = questPumpSerial + 1
        RefreshQuestInteractionIdentity()
        SelectQuestGreeting(p)
    elseif event == "QUEST_DETAIL" then
        if p.autoQuestAccept and AcceptQuest then
            ConfirmPendingQuest("available")
            AcceptQuest()
            ScheduleQuestSelectionPump()
        end
    elseif event == "QUEST_PROGRESS" then
        ConfirmPendingQuest("active")
        if p.autoQuestTurnIn and IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
            CompleteQuest()
        end
    elseif event == "QUEST_COMPLETE" and p.autoQuestTurnIn and GetNumQuestChoices and GetQuestReward then
        local choices = GetNumQuestChoices() or 0
        -- One choice is not a choice in practice; two or more must remain
        -- manual so TurboFace never guesses between meaningful rewards.
        if choices <= 1 then
            GetQuestReward(choices == 1 and 1 or 0)
            ScheduleQuestSelectionPump()
        end
    elseif event == "QUEST_ACCEPTED" then
        if arg1 then questProcessedAvailable[arg1] = true end
        if questPendingKind == "available" and (not arg1 or arg1 == questPendingID) then
            ConfirmPendingQuest("available")
        end
        ScheduleQuestSelectionPump()
    elseif event == "QUEST_TURNED_IN" then
        if arg1 then questProcessedActive[arg1] = true end
        if questPendingKind == "active" and (not arg1 or arg1 == questPendingID) then
            ConfirmPendingQuest("active")
        end
        ScheduleQuestSelectionPump()
    elseif event == "QUEST_REMOVED" then
        if arg1 and arg1 == questPendingID then
            questPendingKind = nil
            questPendingID = nil
            questPendingSerial = questPendingSerial + 1
        end
        ScheduleQuestSelectionPump()
    end
end

local function QuestProbeValue(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, value = pcall(fn, ...)
    if not ok then return "error" end
    return tostring(value)
end

function M:QuestProbe()
    local guid = UnitGUID and UnitGUID("npc") or nil
    local active = C_GossipInfo and C_GossipInfo.GetActiveQuests
        and C_GossipInfo.GetActiveQuests() or {}
    local available = C_GossipInfo and C_GossipInfo.GetAvailableQuests
        and C_GossipInfo.GetAvailableQuests() or {}
    ns:Chat("Quest", ("npc=%s open=%s pending=%s:%s active=%d available=%d"):format(
        tostring(guid), tostring(questInteractionOpen), tostring(questPendingKind),
        tostring(questPendingID), type(active) == "table" and #active or 0,
        type(available) == "table" and #available or 0))

    if type(active) == "table" then
        for i, quest in ipairs(active) do
            local questID = type(quest) == "table" and quest.questID or nil
            ns:Chat("Quest", ("A[%d] id=%s title=%s gossipComplete=%s isComplete=%s readyModern=%s readyLegacy=%s readyCompat=%s processed=%s"):format(
                i, tostring(questID), tostring(quest and quest.title),
                tostring(quest and quest.isComplete),
                QuestProbeValue(C_QuestLog and C_QuestLog.IsComplete, questID),
                QuestProbeValue(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID),
                QuestProbeValue(QuestReadyForTurnIn, questID),
                QuestProbeValue(ns.API.QuestReadyForTurnIn, questID),
                tostring(questID and questProcessedActive[questID] or false)))
        end
    end
    if type(available) == "table" then
        for i, quest in ipairs(available) do
            local questID = type(quest) == "table" and quest.questID or nil
            ns:Chat("Quest", ("V[%d] id=%s title=%s processed=%s"):format(
                i, tostring(questID), tostring(quest and quest.title),
                tostring(questID and questProcessedAvailable[questID] or false)))
        end
    end

    local greetingActive = GetNumActiveQuests and GetNumActiveQuests() or 0
    local greetingAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    ns:Chat("Quest", ("greetingActive=%d greetingAvailable=%d"):format(
        greetingActive or 0, greetingAvailable or 0))
    for i = 1, (greetingActive or 0) do
        local title, titleComplete
        if GetActiveTitle then title, titleComplete = GetActiveTitle(i) end
        local questID = GetActiveQuestID and GetActiveQuestID(i) or nil
        ns:Chat("Quest", ("GA[%d] id=%s title=%s titleComplete=%s indexComplete=%s readyCompat=%s"):format(
            i, tostring(questID), tostring(title), tostring(titleComplete),
            QuestProbeValue(IsActiveQuestComplete, i),
            QuestProbeValue(ns.API.QuestReadyForTurnIn, questID)))
    end
    for i = 1, (greetingAvailable or 0) do
        local questID = GetAvailableQuestID and GetAvailableQuestID(i) or nil
        local title = GetAvailableTitle and GetAvailableTitle(i) or nil
        local key = questID and ("greeting-id:" .. questID)
            or (type(title) == "string" and ("greeting:" .. title))
            or ("greeting-available-index:" .. i)
        ns:Chat("Quest", ("GV[%d] id=%s title=%s processed=%s"):format(
            i, tostring(questID), tostring(title),
            tostring(questProcessedAvailable[key] or false)))
    end
end

function M:RefreshQuests()
    local p = Settings()
    local active = p.autoQuestAccept == true or p.autoQuestTurnIn == true
    if not active then ResetQuestInteraction(nil) end
    SetEvents("quests", active, OnQuestAutomation,
        "GOSSIP_SHOW", "GOSSIP_CLOSED", "GOSSIP_OPTIONS_REFRESHED", "QUEST_GREETING",
        "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED",
        "QUEST_TURNED_IN", "QUEST_REMOVED")
end

-- ---------------------------------------------------------------------------
-- Summons
-- ---------------------------------------------------------------------------

local function OnSummonRequest()
    if UnitAffectingCombat("player") then return end
    if not C_SummonInfo then return end

    local summoner = C_SummonInfo.GetSummonConfirmSummoner and C_SummonInfo.GetSummonConfirmSummoner()
    local area = C_SummonInfo.GetSummonConfirmAreaName and C_SummonInfo.GetSummonConfirmAreaName()
    ns:Chat("Plus", ("Summon from %s (%s) will be accepted in 10 seconds unless cancelled."):format(
        tostring(summoner or "?"), tostring(area or "?")))

    C_Timer.After(10, function()
        if not Settings().acceptSummon or UnitAffectingCombat("player") then return end
        if not C_SummonInfo or not C_SummonInfo.ConfirmSummon then return end
        local nowSummoner = C_SummonInfo.GetSummonConfirmSummoner and C_SummonInfo.GetSummonConfirmSummoner()
        local nowArea = C_SummonInfo.GetSummonConfirmAreaName and C_SummonInfo.GetSummonConfirmAreaName()
        if summoner == nowSummoner and area == nowArea then
            C_SummonInfo.ConfirmSummon()
            if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
        end
    end)
end

function M:RefreshSummon()
    SetEvents("summon", Settings().acceptSummon == true, OnSummonRequest, "CONFIRM_SUMMON")
end

-- ---------------------------------------------------------------------------
-- Spirit healer
-- ---------------------------------------------------------------------------

local sicknessPopups = { XP_LOSS = true, XP_LOSS_NO_SICKNESS = true }
local lastSpiritAccept = 0

local function ClickSpiritConfirmation()
    if not Settings().automateSpiritHealer or IsShiftKeyDown() then return false end

    -- Forever/Mainline: the spirit-healer penalty confirmation is a player
    -- interaction action, not a StaticPopup button. Compat owns the legacy
    -- AcceptXPLoss fallback for older clients.
    if GetTime() - lastSpiritAccept > 0.25 and ns.API.ConfirmSpiritHealer() then
        lastSpiritAccept = GetTime()
        return true
    end

    -- Last-resort visual fallback for an older client that exposes neither
    -- action API. Keep this behind the API attempt rather than making popup
    -- ownership part of the normal Forever path.
    for which in pairs(sicknessPopups) do
        local dialog = StaticPopup_Visible and StaticPopup_Visible(which)
        if dialog and _G[dialog] and StaticPopup_OnClick then
            lastSpiritAccept = GetTime()
            StaticPopup_OnClick(_G[dialog], 1)
            return true
        end
    end
    return false
end

local function OnSpiritPopup(which)
    if not sicknessPopups[which] then return end
    C_Timer.After(0, ClickSpiritConfirmation)
end

local function OnSpiritEvent(_, event)
    if not Settings().automateSpiritHealer or IsShiftKeyDown() then return end

    if event == "GOSSIP_SHOW" then
        if not UnitIsGhost("player") then return end
        SelectSingleQuestFreeOption()
        return
    end

    if event == "CONFIRM_XP_LOSS" then
        C_Timer.After(0, function()
            if not Settings().automateSpiritHealer or IsShiftKeyDown() then return end
            ClickSpiritConfirmation()
        end)
    end
end

function M:RefreshSpiritHealer()
    local active = Settings().automateSpiritHealer == true
    ListenForPopups(OnSpiritPopup, active)
    SetEvents("spirit", active, OnSpiritEvent, "GOSSIP_SHOW", "CONFIRM_XP_LOSS")
end

-- ---------------------------------------------------------------------------
-- Incoming resurrection
-- ---------------------------------------------------------------------------

local function AcceptRequestedResurrection(caster)
    local p = Settings()
    if not p.acceptRes then return end
    if p.acceptResNoCombat and caster and UnitAffectingCombat(caster) then return end
    if AcceptResurrect then AcceptResurrect() end
    if StaticPopup_Hide then StaticPopup_Hide("RESURRECT_NO_TIMER") end
end

local function OnResurrectionRequest(_, _, caster)
    -- Zul'Gurub's Chained Spirit offers a strategically different resurrection;
    -- leave that one under player control.
    if caster == "Chained Spirit" then return end
    local delay = GetCorpseRecoveryDelay and GetCorpseRecoveryDelay() or 0
    if delay and delay > 0 then
        C_Timer.After(delay + 1, function() AcceptRequestedResurrection(caster) end)
    else
        AcceptRequestedResurrection(caster)
    end
end

function M:RefreshRes()
    SetEvents("res", Settings().acceptRes == true, OnResurrectionRequest, "RESURRECT_REQUEST")
end

-- ---------------------------------------------------------------------------
-- Battleground release
-- ---------------------------------------------------------------------------

local function HasSelfResurrection()
    if not C_DeathInfo or not C_DeathInfo.GetSelfResurrectOptions then return false end
    local choices = C_DeathInfo.GetSelfResurrectOptions()
    return type(choices) == "table" and #choices > 0
end

local releaseSerial = 0
local function OnPlayerDead()
    local p = Settings()
    if not p.releasePvP or HasSelfResurrection() then return end

    local inside, instanceType = IsInInstance()
    if not inside or instanceType ~= "pvp" then return end
    if p.releaseNoAlterac and C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetBestMapForUnit("player") == 1459 then
        return
    end

    releaseSerial = releaseSerial + 1
    local serial = releaseSerial
    local delay = math.max(0, tonumber(p.releaseDelay) or 200) / 1000
    C_Timer.After(delay, function()
        if serial ~= releaseSerial or not Settings().releasePvP then return end
        if not UnitIsDeadOrGhost("player") then return end
        if IsShiftKeyDown() then
            ns:Chat("Plus", "Automatic release cancelled.")
            return
        end
        ns.API.ReleaseSpirit()
    end)
end

function M:RefreshReleasePvP()
    releaseSerial = releaseSerial + 1
    SetEvents("releasePvP", Settings().releasePvP == true, OnPlayerDead, "PLAYER_DEAD")
end

-- ---------------------------------------------------------------------------
-- Merchant repair
-- ---------------------------------------------------------------------------

local function OnMerchantShow()
    local p = Settings()
    if not p.autoRepair or IsShiftKeyDown() then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 or GetMoney() < cost then return end
    RepairAllItems()
    if p.autoRepairSummary then
        ns:Chat("Plus", "Repaired for " .. ns.API.GetCoinText(cost) .. ".")
    end
end

function M:RefreshRepair()
    SetEvents("repair", Settings().autoRepair == true, OnMerchantShow, "MERCHANT_SHOW")
end

function M:Refresh()
    self:RefreshGossip()
    self:RefreshQuests()
    self:RefreshSummon()
    self:RefreshSpiritHealer()
    self:RefreshRes()
    self:RefreshReleasePvP()
    self:RefreshRepair()
end

function M:Init()
    self:Refresh()
end
