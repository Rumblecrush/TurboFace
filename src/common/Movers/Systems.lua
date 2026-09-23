local _, ns = ...

-- Movers/Systems.lua -- FPS, tooltip, quest tracker, loot movers; slash commands; Init.
-- Split from Movers.lua (G3 refactor). M is the shared mover module table
-- (ns.Movers); underscore members are family-internal shared helpers.

local M = ns.Movers
local elements = M._elements
local DB = M._DB
local ElementDB = M._ElementDB
local Chat = M._Chat
local After = ns.After
local IsProtected = M._IsProtected
local FrameWidth = M._FrameWidth
local FrameHeight = M._FrameHeight
local EnsureMoverParent = M._EnsureMoverParent
local ApplyInteractionState = M._ApplyInteractionState
local CapturePoint = M._CapturePoint
local EnsureAuraDriver = M._EnsureAuraDriver
local AuraRuntimeNeeded = M._AuraRuntimeNeeded
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local pairs = pairs
local EnsureAnchor = M._EnsureAnchor
local EnsureEventFrame = M._EnsureEventFrame
local AddUniqueFrame = M._AddUniqueFrame
local order = M._order
local PointFromCenter = M._PointFromCenter
local QUEST_TRACKER_MOVER_AVAILABLE = ns.FeatureAvailable("movers.questTracker", true)

-- System-mover state (owned by this file)
local tooltipAnchor
local tooltipHooksInstalled = false
local tooltipApplying = false
local questTrackerAnchor
local questTrackerHooksInstalled = false
local questTrackerApplying = false
local questTrackerHookedFrames = {}
local questTrackerQueued = false
local lootFrameShowHooked = false
local groupLootUpdateHooked = false
local groupLootContainerHooked = false
local groupLootAnchor
local groupLootApplying = false
local groupLootReapplyQueued = false
local lfgAnchor
local lfgApplying = false
local lfgReapplyQueued = false
local hooksInstalled = false
local QueueQuestTrackerApply  -- forward declaration (assigned below)

local function FirstExistingFrame(names)
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame then return frame end
    end
    return nil
end


local function EnsureTooltipMoverAnchor()
    if tooltipAnchor then return tooltipAnchor end
    tooltipAnchor = EnsureAnchor("TurboFaceTooltipMoverAnchor", 140, 48)
    return tooltipAnchor
end

local function TooltipMoverActive()
    local db = DB()
    local edb = ElementDB("GameTooltip")
    return db.enabled ~= false and edb.enabled ~= false
end

local function TooltipShouldUseAnchor()
    if not GameTooltip or not GameTooltip.GetPoint or not TooltipMoverActive() then return false end
    local edb = ElementDB("GameTooltip")
    if edb.hidden == true then return false end

    local point, rel, relPoint = GameTooltip:GetPoint(1)
    if rel == tooltipAnchor then return false end
    if not point then return true end

    local defaultContainer = _G.GameTooltipDefaultContainer
    local world = _G.WorldFrame
    if rel == nil then return true end

    -- Match MoveAny's safer fixed-tooltip behavior: only replace Blizzard's
    -- default bottom-right tooltip anchor. Cursor/tooltips explicitly anchored
    -- to buttons/items should keep their requested anchor.
    if (rel == UIParent or rel == defaultContainer or rel == world) and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT" then
        return true
    end

    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if (owner == nil or owner == UIParent or owner == defaultContainer or owner == world) and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT" then
        return true
    end

    return false
end

local function ApplyTooltipPosition(force)
    if not GameTooltip or not TooltipMoverActive() then return end
    local edb = ElementDB("GameTooltip")
    if edb.hidden == true then
        if GameTooltip.Hide then GameTooltip:Hide() end
        return
    end
    if not force and not TooltipShouldUseAnchor() then return end

    local anchor = EnsureTooltipMoverAnchor()
    tooltipApplying = true
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    if GameTooltip.EnableMouse then GameTooltip:EnableMouse(edb.clickThrough ~= true) end
    tooltipApplying = false
end

local function InstallTooltipHooks()
    if tooltipHooksInstalled or not GameTooltip then return end
    tooltipHooksInstalled = true

    if hooksecurefunc and GameTooltip.SetPoint then
        hooksecurefunc(GameTooltip, "SetPoint", function()
            if tooltipApplying or not M.active then return end
            if not TooltipShouldUseAnchor() then return end
            ApplyTooltipPosition(false)
        end)
    end

    if hooksecurefunc and GameTooltip.SetOwner then
        hooksecurefunc(GameTooltip, "SetOwner", function()
            if tooltipApplying or not M.active then return end
            ApplyTooltipPosition(false)
        end)
    end

    if hooksecurefunc and _G.GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
            if tooltipApplying or not M.active then return end
            if tooltip == GameTooltip and TooltipMoverActive() then
                ApplyTooltipPosition(true)
            end
        end)
    end

    if GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function()
            if not TooltipMoverActive() then return end
            if ElementDB("GameTooltip").hidden == true then
                GameTooltip:Hide()
                return
            end
            ApplyTooltipPosition(false)
        end)
    end
end

local function ApplyTooltipMover(info, edb, enabled)
    InstallTooltipHooks()
    if not GameTooltip then return end
    if not enabled or not edb or edb.hidden == true then
        if GameTooltip.Hide then GameTooltip:Hide() end
        return
    end
    if GameTooltip.EnableMouse then GameTooltip:EnableMouse(edb.clickThrough ~= true) end
    if GameTooltip.IsShown and GameTooltip:IsShown() then
        ApplyTooltipPosition(false)
    end
end

-- Durability doll mover removed: Edit Mode owns its placement on 1.15.9+.

local function EnsureQuestTrackerAnchor()
    if questTrackerAnchor then return questTrackerAnchor end

    local f = _G.TurboFaceQuestTrackerMoverAnchor
    if not f then
        f = CreateFrame("Frame", "TurboFaceQuestTrackerMoverAnchor", UIParent)
        _G.TurboFaceQuestTrackerMoverAnchor = f
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -85, -180)
    end
    f:SetSize(240, 600)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false)
    f:Show()
    questTrackerAnchor = f
    return f
end

local function QuestieTrackerAvailable()
    return _G.Questie_BaseFrame ~= nil
end

local function QuestTrackerUsesAnchor()
    -- MoveAny's Vanilla path uses a helper anchor for legacy WatchFrame /
    -- QuestWatchFrame clients, and also for Questie when its tracker is active.
    -- If Classic exposes ObjectiveTrackerFrame directly, keep that native frame
    -- as the movable element instead of reparenting it.
    if QuestieTrackerAvailable() then return true end
    return _G.ObjectiveTrackerFrame == nil
end

local function GetQuestTrackerFrames()
    local list, seen = {}, {}

    if QuestieTrackerAvailable() then
        AddUniqueFrame(list, seen, _G.Questie_BaseFrame)
        return list
    end

    if _G.ObjectiveTrackerFrame and not QuestTrackerUsesAnchor() then
        AddUniqueFrame(list, seen, _G.ObjectiveTrackerFrame)
        return list
    end

    AddUniqueFrame(list, seen, _G.QuestWatchFrame)
    AddUniqueFrame(list, seen, _G.WatchFrame)
    return list
end

local function QuestTrackerDefaultPoint(frame)
    return PointFromCenter(frame) or CapturePoint(frame) or { "TOPRIGHT", UIParent, "TOPRIGHT", -85, -180 }
end

local function AttachQuestTrackerFrame(frame, anchor)
    if not frame or not anchor or frame == anchor then return true end
    if IsProtected(frame) and InCombatLockdown and InCombatLockdown() then return false end

    questTrackerApplying = true
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.SetUserPlaced and frame.IsMovable and frame:IsMovable() then
        frame:SetUserPlaced(false)
    end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
    if frame.SetParent and frame.GetParent and frame:GetParent() ~= anchor then
        frame:SetParent(anchor)
    end
    if frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
    if frame.SetSize and anchor.GetSize then
        frame:SetSize(anchor:GetSize())
    else
        if frame.SetWidth and anchor.GetWidth then frame:SetWidth(anchor:GetWidth()) end
        if frame.SetHeight and anchor.GetHeight then frame:SetHeight(anchor:GetHeight()) end
    end
    questTrackerApplying = false
    return true
end

QueueQuestTrackerApply = function(immediate)
    local currentInfo = elements.QuestTracker
    if questTrackerApplying or (currentInfo and currentInfo.applying) then return end

    local function Run()
        questTrackerQueued = false
        if not M.active then return end
        if M.RegisterSystemFrameMovers then M.RegisterSystemFrameMovers(M) end
        if elements.QuestTracker then
            M:ApplyElement("QuestTracker")
            M:UpdateOverlay("QuestTracker")
        end
    end

    if immediate == true then
        Run()
        return
    end

    if questTrackerQueued then return end
    questTrackerQueued = true
    After(0, Run)
end
M._QueueQuestTrackerApply = function(...) if QueueQuestTrackerApply then QueueQuestTrackerApply(...) end end

local function HookQuestTrackerFrame(frame)
    if not frame or questTrackerHookedFrames[frame] then return end
    questTrackerHookedFrames[frame] = true

    if hooksecurefunc and frame.SetPoint then
        hooksecurefunc(frame, "SetPoint", function()
            local currentInfo = elements.QuestTracker
            if questTrackerApplying or (currentInfo and currentInfo.applying) or not M.active then return end
            QueueQuestTrackerApply(true)
        end)
    end

    if frame.HookScript then
        frame:HookScript("OnShow", function()
            local currentInfo = elements.QuestTracker
            if questTrackerApplying or (currentInfo and currentInfo.applying) or not M.active then return end
            QueueQuestTrackerApply(false)
        end)
        frame:HookScript("OnSizeChanged", function()
            local currentInfo = elements.QuestTracker
            if questTrackerApplying or (currentInfo and currentInfo.applying) or not M.active then return end
            QueueQuestTrackerApply(false)
        end)
    end
end

local function InstallQuestTrackerHooks()
    -- Forever's native Objective Tracker performs secret aura reads while
    -- laying out scenario/Maw modules. Any addon callback attached to its
    -- SetPoint/update path can taint that still-running Blizzard execution.
    -- Edit Mode owns this frame on the modern client; TurboFace must not hook it.
    if not QUEST_TRACKER_MOVER_AVAILABLE then return end

    if not questTrackerHooksInstalled then
        questTrackerHooksInstalled = true
        local funcs = {
            "WatchFrame_Update",
            "QuestWatch_Update",
            "QuestWatchFrame_Update",
            "ObjectiveTracker_Update",
            "ObjectiveTrackerFrame_Update",
        }
        if hooksecurefunc then
            for _, fnName in ipairs(funcs) do
                if _G[fnName] then
                    hooksecurefunc(fnName, function() QueueQuestTrackerApply(true) end)
                end
            end
        end
    end

    for _, frame in ipairs(GetQuestTrackerFrames()) do
        HookQuestTrackerFrame(frame)
    end
end

local function ApplyQuestTracker(info, edb, enabled)
    if not info then return end
    if not QUEST_TRACKER_MOVER_AVAILABLE then return end
    InstallQuestTrackerHooks()

    if not enabled or not edb then
        return
    end

    if QuestTrackerUsesAnchor() then
        local anchor = EnsureQuestTrackerAnchor()
        local allAttached = true
        for _, frame in ipairs(GetQuestTrackerFrames()) do
            if not AttachQuestTrackerFrame(frame, anchor) then
                allAttached = false
            end
        end
        if not allAttached then
            info.pending = true
        end
    end

    ApplyInteractionState("QuestTracker", info)
end

local function RegisterQuestTrackerMover(self)
    if not QUEST_TRACKER_MOVER_AVAILABLE then return end
    if ElementDB("QuestTracker").enabled == false then return end
    local frame
    local usingAnchor = QuestTrackerUsesAnchor()
    if usingAnchor then
        frame = EnsureQuestTrackerAnchor()
    else
        frame = _G.ObjectiveTrackerFrame
    end
    if not frame then return end

    InstallQuestTrackerHooks()
    local p = QuestTrackerDefaultPoint(frame)
    self:RegisterElement("QuestTracker", frame, {
        label = "Quest Tracker",
        overlayWidth = FrameWidth(frame, 240),
        overlayHeight = FrameHeight(frame, 600),
        fallbackPoint = p,
        defaultPoint = p,
        getChildren = GetQuestTrackerFrames,
        onApply = ApplyQuestTracker,
    })
end

local function GetGroupLootFrames()
    local frames = {}
    local count = tonumber(_G.NUM_GROUP_LOOT_FRAMES) or 4
    for i = 1, count do
        local frame = _G["GroupLootFrame" .. i]
        if frame then frames[#frames + 1] = frame end
    end
    return frames
end

local function GetGroupLootMoverChildren()
    local frames, seen = {}, {}
    local container = _G.GroupLootContainer
    AddUniqueFrame(frames, seen, container)
    if container and type(container.rollFrames) == "table" then
        for _, frame in pairs(container.rollFrames) do
            AddUniqueFrame(frames, seen, frame)
        end
    end
    for _, frame in ipairs(GetGroupLootFrames()) do
        AddUniqueFrame(frames, seen, frame)
    end
    return frames
end

local function EnsureGroupLootAnchor()
    if groupLootAnchor then return groupLootAnchor end
    groupLootAnchor = EnsureAnchor("TurboFaceGroupLootMoverAnchor", 256, 100)
    return groupLootAnchor
end

local function GroupLootStockAnchorPoint()
    local container = _G.GroupLootContainer
    if not container or type(container.rollFrames) ~= "table" then return nil end
    local reserved = tonumber(container.reservedSize) or 100
    local maxIndex = tonumber(container.maxIndex) or 0

    -- rollFrames can temporarily contain holes.  Derive the container's true
    -- bottom-slot center from any indexed frame rather than assuming the first
    -- visible frame occupies slot one.
    for i = 1, maxIndex do
        local frame = container.rollFrames[i]
        local p = frame and PointFromCenter(frame)
        if p then
            p[5] = (p[5] or 0) - (reserved * (i - 1))
            return p
        end
    end
    return nil
end

local function SyncGroupLootAnchorToStock()
    local p = GroupLootStockAnchorPoint()
    if not p then return false end
    local anchor = EnsureGroupLootAnchor()

    groupLootApplying = true
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], p[2], p[3], p[4], p[5])
    groupLootApplying = false
    return true
end

local function AttachGroupLootContainer(anchor)
    local container = _G.GroupLootContainer
    if not container or not anchor then return false end
    if IsProtected(container) and InCombatLockdown and InCombatLockdown() then return false end

    -- Blizzard grows the roll stack upward from the container's BOTTOM.  Keep
    -- that bottom edge attached to a fixed 256x100 mover so the first roll
    -- popup never shifts when additional GroupLootFrames join the stack.
    groupLootApplying = true
    container:ClearAllPoints()
    container:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    groupLootApplying = false
    return true
end

local function ApplyGroupLootMover(info, edb, enabled)
    if not info or not info.frame or not edb or not enabled then return end
    if edb.point then
        if not AttachGroupLootContainer(info.frame) then info.pending = true end
    else
        -- Until the user saves a TurboFace position, leave Blizzard's managed
        -- placement untouched and merely keep the mover overlay synchronized.
        SyncGroupLootAnchorToStock()
    end
end

local function ReapplyBlizzardLootMover()
    local id = "BlizzardLootFrame"
    if not M.active or not elements[id] then return end
    local edb = ElementDB(id)
    if edb.enabled == false or DB().enabled == false then return end
    if edb.point then M:ApplyElement(id) end
    M:UpdateOverlay(id)
end

local function ReapplyGroupLootMover()
    local id = "GroupLootRolls"
    if not M.active or not elements[id] then return end
    local edb = ElementDB(id)
    if edb.enabled == false or DB().enabled == false then return end
    if edb.point then
        M:ApplyElement(id)
    else
        SyncGroupLootAnchorToStock()
        M:UpdateOverlay(id)
    end
end

local function QueueGroupLootMoverApply()
    if groupLootApplying or groupLootReapplyQueued then return end
    groupLootReapplyQueued = true
    After(0, function()
        groupLootReapplyQueued = false
        ReapplyGroupLootMover()
    end)
end

local function InstallLootMoverHooks()
    if ElementDB("BlizzardLootFrame").enabled ~= false
        and not lootFrameShowHooked and hooksecurefunc and _G.LootFrame_Show then
        lootFrameShowHooked = true
        hooksecurefunc("LootFrame_Show", ReapplyBlizzardLootMover)
    end

    local groupEnabled = ElementDB("GroupLootRolls").enabled ~= false
    if groupEnabled and not groupLootUpdateHooked and hooksecurefunc and _G.GroupLootContainer_Update then
        groupLootUpdateHooked = true
        hooksecurefunc("GroupLootContainer_Update", ReapplyGroupLootMover)
    end

    local container = _G.GroupLootContainer
    if groupEnabled and not groupLootContainerHooked and hooksecurefunc and container and container.SetPoint then
        groupLootContainerHooked = true
        hooksecurefunc(container, "SetPoint", function()
            if groupLootApplying or not M.active then return end
            local edb = ElementDB("GroupLootRolls")
            if edb.enabled == false or DB().enabled == false then return end
            QueueGroupLootMoverApply()
        end)
    end
end

local function RegisterBlizzardLootMovers(self)
    local lootFrame = _G.LootFrame
    if lootFrame and ElementDB("BlizzardLootFrame").enabled ~= false then
        local existing = elements.BlizzardLootFrame
        local p = (existing and existing.defaultPoint)
            or CapturePoint(lootFrame)
            or { "TOPLEFT", UIParent, "TOPLEFT", 16, -116 }
        self:RegisterElement("BlizzardLootFrame", lootFrame, {
            label = "Blizzard Loot Window",
            overlayWidth = FrameWidth(lootFrame, 170),
            overlayHeight = FrameHeight(lootFrame, 240),
            fallbackPoint = { "TOPLEFT", UIParent, "TOPLEFT", 16, -116 },
            defaultPoint = p,
        })
    end

    local container = _G.GroupLootContainer
    if container and ElementDB("GroupLootRolls").enabled ~= false then
        local anchor = EnsureGroupLootAnchor()
        local existing = elements.GroupLootRolls
        local p = (existing and existing.defaultPoint)
            or GroupLootStockAnchorPoint()
            or { "BOTTOM", UIParent, "BOTTOM", 0, 215 }
        self:RegisterElement("GroupLootRolls", anchor, {
            label = "Loot Roll Frames",
            overlayWidth = 256,
            overlayHeight = 100,
            fallbackPoint = { "BOTTOM", UIParent, "BOTTOM", 0, 215 },
            defaultPoint = p,
            getChildren = GetGroupLootMoverChildren,
            onApply = ApplyGroupLootMover,
        })
    end

    InstallLootMoverHooks()
end

-- =============================================================================
-- Minimap mail notification
--
-- MiniMapMailFrame is only shown when mail is waiting, so registering it
-- directly would leave the mover overlay ungrabbable most of the time. Register
-- a TurboFace anchor instead -- the same pattern as the tooltip and group-loot
-- movers -- and re-anchor the real frame onto it whenever it appears.
-- =============================================================================
local mailAnchor

local function EnsureMailMoverAnchor()
    if mailAnchor then return mailAnchor end
    mailAnchor = EnsureAnchor("TurboFaceMailMoverAnchor", 32, 32)
    return mailAnchor
end

-- True when the mover owns the frame's position, which is the signal
-- InterfaceTweaks uses to stop its square-minimap layout from fighting us.
function M:IsMinimapMailMoverActive()
    local db = DB()
    if db.enabled == false then return false end
    local edb = ElementDB("MinimapMail")
    return edb.enabled ~= false and elements.MinimapMail ~= nil
end

local function GetMinimapMailChildren()
    local f = _G.MiniMapMailFrame
    return f and { f } or {}
end

local function ApplyMinimapMailMover(info, edb, enabled)
    local frame = _G.MiniMapMailFrame
    if not frame then return end

    if not enabled or not edb or edb.hidden == true then
        if edb and edb.hidden == true and frame.Hide then frame:Hide() end
        return
    end

    local anchor = EnsureMailMoverAnchor()
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if frame.SetPoint then frame:SetPoint("CENTER", anchor, "CENTER", 0, 0) end
    if frame.SetScale and tonumber(edb.scale) then frame:SetScale(tonumber(edb.scale)) end

    -- The mail frame's alert animation and the "you have new mail" border are
    -- children, so they follow the re-anchor without extra work.
end

local function InstallMinimapMailHooks()
    local frame = _G.MiniMapMailFrame
    if not frame or frame._tfMailMoverHooked then return end
    frame._tfMailMoverHooked = true

    -- Blizzard re-anchors the frame when the minimap cluster relayouts, and the
    -- square-minimap tweak used to as well. Re-apply on show rather than
    -- fighting every SetPoint: this frame appears rarely and briefly.
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            if not M:IsMinimapMailMoverActive() then return end
            local info = elements.MinimapMail
            if info then ApplyMinimapMailMover(info, ElementDB("MinimapMail"), true) end
        end)
    end
end

-- =============================================================================
-- Minimap clock
--
-- Blizzard's TimeManagerClockButton, not a replacement: keeping it preserves
-- the right-click alarm and stopwatch menu. The square-minimap layout in
-- Plus/InterfaceTweaks.lua repositions the mail, PvP, zoom and calendar buttons
-- around the new shape but never touched the clock, which is why it sits wrong
-- once the minimap stops being round.
--
-- Blizzard_TimeManager is load-on-demand, so the button does not exist at
-- login and registration has to be deferred.
-- =============================================================================
local clockAnchor

local function EnsureClockMoverAnchor()
    if clockAnchor then return clockAnchor end
    clockAnchor = EnsureAnchor("TurboFaceClockMoverAnchor", 60, 20)
    return clockAnchor
end

-- Same contract as IsMinimapMailMoverActive: tells InterfaceTweaks the mover
-- owns this frame's position so its minimap layout leaves the clock alone.
function M:IsMinimapClockMoverActive()
    local db = DB()
    if db.enabled == false then return false end
    local edb = ElementDB("MinimapClock")
    return edb.enabled ~= false and elements.MinimapClock ~= nil
end

local function GetMinimapClockChildren()
    local f = _G.TimeManagerClockButton
    return f and { f } or {}
end

local function ApplyMinimapClockMover(info, edb, enabled)
    local frame = _G.TimeManagerClockButton
    if not frame then return end

    if not enabled or not edb or edb.hidden == true then
        if edb and edb.hidden == true and frame.Hide then frame:Hide() end
        return
    end

    local anchor = EnsureClockMoverAnchor()
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if frame.SetPoint then frame:SetPoint("CENTER", anchor, "CENTER", 0, 0) end
    if frame.SetScale and tonumber(edb.scale) then frame:SetScale(tonumber(edb.scale)) end
end

local function InstallMinimapClockHooks()
    local frame = _G.TimeManagerClockButton
    if not frame or frame._tfClockMoverHooked then return end
    frame._tfClockMoverHooked = true

    -- Blizzard re-anchors the clock whenever the minimap cluster relayouts.
    -- Re-apply on show rather than fighting every SetPoint.
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            if not M:IsMinimapClockMoverActive() then return end
            local info = elements.MinimapClock
            if info then ApplyMinimapClockMover(info, ElementDB("MinimapClock"), true) end
        end)
    end
end

-- =============================================================================
-- Looking For Group minimap tracker
--
-- Classic Era's green LFG eye lives in the load-on-demand
-- Blizzard_GroupFinder_VanillaStyle addon. Register a stable TurboFace anchor
-- instead of the Blizzard frame itself: the button can be hidden by Blizzard
-- when unavailable and Blizzard may re-run its own minimap positioning logic.
-- Re-anchoring the stock frame preserves its click, tooltip, animation, and
-- visibility behavior while Movers owns only its position.
-- =============================================================================
local function GetMinimapLFGFrame()
    return _G.LFGMinimapFrame or _G.MiniMapLFGFrame or _G.QueueStatusMinimapButton
end

local function EnsureLFGMoverAnchor()
    if lfgAnchor then return lfgAnchor end
    lfgAnchor = EnsureAnchor("TurboFaceLFGMoverAnchor", 32, 32)
    return lfgAnchor
end

function M:IsMinimapLFGMoverActive()
    local db = DB()
    if db.enabled == false then return false end
    local edb = ElementDB("MinimapLFG")
    return edb.enabled ~= false and elements.MinimapLFG ~= nil
end

local function GetMinimapLFGChildren()
    local f = GetMinimapLFGFrame()
    return f and { f } or {}
end

local function ApplyMinimapLFGMover(info, edb, enabled)
    local frame = GetMinimapLFGFrame()
    if not frame then return end

    if not enabled or not edb or edb.hidden == true then
        if edb and edb.hidden == true and frame.Hide then frame:Hide() end
        return
    end

    local anchor = EnsureLFGMoverAnchor()
    lfgApplying = true
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if frame.SetPoint then frame:SetPoint("CENTER", anchor, "CENTER", 0, 0) end
    if frame.SetScale and tonumber(edb.scale) then frame:SetScale(tonumber(edb.scale)) end
    lfgApplying = false
end

local function QueueMinimapLFGReapply()
    if lfgApplying or lfgReapplyQueued or not M:IsMinimapLFGMoverActive() then return end
    lfgReapplyQueued = true
    After(0, function()
        lfgReapplyQueued = false
        if not M:IsMinimapLFGMoverActive() then return end
        local info = elements.MinimapLFG
        if info then ApplyMinimapLFGMover(info, ElementDB("MinimapLFG"), true) end
    end)
end

local function InstallMinimapLFGHooks()
    local frame = GetMinimapLFGFrame()
    if not frame or frame._tfLFGMoverHooked then return end
    frame._tfLFGMoverHooked = true

    if frame.HookScript then
        frame:HookScript("OnShow", QueueMinimapLFGReapply)
    end

    -- Blizzard's LFG minimap mixin can restore its stock anchor while updating
    -- the button. Follow those changes instead of permanently replacing any
    -- Blizzard methods.
    if hooksecurefunc and frame.SetPoint then
        hooksecurefunc(frame, "SetPoint", function()
            if not lfgApplying then QueueMinimapLFGReapply() end
        end)
    end
end

local function RegisterMinimapLFGMover(self)
    local frame = GetMinimapLFGFrame()
    if not frame then return end
    if ElementDB("MinimapLFG").enabled == false then return end

    local anchor = EnsureLFGMoverAnchor()
    local existing = elements.MinimapLFG
    local p = (existing and existing.defaultPoint)
        or PointFromCenter(frame)
        or CapturePoint(frame)
        or { "TOPRIGHT", UIParent, "TOPRIGHT", -180, -180 }

    self:RegisterElement("MinimapLFG", anchor, {
        label = "Looking For Group Tracker",
        overlayWidth = FrameWidth(frame, 32),
        overlayHeight = FrameHeight(frame, 32),
        fallbackPoint = p,
        defaultPoint = p,
        getChildren = GetMinimapLFGChildren,
        onApply = ApplyMinimapLFGMover,
    })

    InstallMinimapLFGHooks()
end

local function RegisterMinimapClockMover(self)
    local frame = _G.TimeManagerClockButton
    if not frame then return end
    if ElementDB("MinimapClock").enabled == false then return end

    local anchor = EnsureClockMoverAnchor()
    local existing = elements.MinimapClock
    local p = (existing and existing.defaultPoint)
        or PointFromCenter(frame)
        or CapturePoint(frame)
        or { "TOPRIGHT", UIParent, "TOPRIGHT", -220, -20 }

    self:RegisterElement("MinimapClock", anchor, {
        label = "Minimap Clock",
        overlayWidth = FrameWidth(frame, 60),
        overlayHeight = FrameHeight(frame, 20),
        fallbackPoint = p,
        defaultPoint = p,
        getChildren = GetMinimapClockChildren,
        onApply = ApplyMinimapClockMover,
    })

    InstallMinimapClockHooks()
end

local function RegisterMinimapMailMover(self)
    local frame = _G.MiniMapMailFrame
    if not frame then return end
    if ElementDB("MinimapMail").enabled == false then return end

    local anchor = EnsureMailMoverAnchor()
    local existing = elements.MinimapMail
    local p = (existing and existing.defaultPoint)
        or PointFromCenter(frame)
        or CapturePoint(frame)
        or { "TOPLEFT", UIParent, "TOPLEFT", 200, -40 }

    self:RegisterElement("MinimapMail", anchor, {
        label = "Minimap Mail Icon",
        overlayWidth = 32,
        overlayHeight = 32,
        fallbackPoint = p,
        defaultPoint = p,
        getChildren = GetMinimapMailChildren,
        onApply = ApplyMinimapMailMover,
    })

    InstallMinimapMailHooks()
end

M.RegisterSystemFrameMovers = function(self)
    if not M.active then return end
    if ns.ST and ns.ST.RegisterTimerMovers then ns.ST:RegisterTimerMovers(self) end
    if ns.Castbars and ns.Castbars.RegisterTimerMovers then ns.Castbars:RegisterTimerMovers(self) end
    local latency = FirstExistingFrame({
        "MainMenuBarPerformanceBarFrame",
        "MainMenuBarPerformanceBar",
        "MainMenuBarPerformanceBarFrameButton",
    })
    if latency then
        local p = PointFromCenter(latency) or CapturePoint(latency) or { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -280, 80 }
        self:RegisterElement("LatencyBar", latency, {
            label = "Latency Bar",
            overlayWidth = FrameWidth(latency, 120),
            overlayHeight = FrameHeight(latency, 20),
            fallbackPoint = p,
            defaultPoint = p,
        })
    end


    RegisterQuestTrackerMover(self)

    if ElementDB("GameTooltip").enabled ~= false then
        local tooltip = EnsureTooltipMoverAnchor()
        self:RegisterElement("GameTooltip", tooltip, {
            label = "Tooltip",
            overlayWidth = 140,
            overlayHeight = 48,
            fallbackPoint = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100 },
            defaultPoint = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100 },
            getChildren = function() return GameTooltip and { GameTooltip } or {} end,
            onApply = ApplyTooltipMover,
        })
        InstallTooltipHooks()
    end

    RegisterBlizzardLootMovers(self)
    RegisterMinimapMailMover(self)

    -- Blizzard_TimeManager is load-on-demand, so TimeManagerClockButton
    -- usually does not exist yet at this point. Register when it arrives
    -- instead of silently skipping the mover for the whole session.
    if ns.API and ns.API.OnAddonReady then
        ns.API.OnAddonReady("Blizzard_TimeManager", function()
            if M.active then RegisterMinimapClockMover(self) end
        end)
    else
        RegisterMinimapClockMover(self)
    end

    -- The Classic Era LFG eye is also load-on-demand. Do not force-load the
    -- Blizzard addon solely for Movers; register as soon as Blizzard loads it.
    if ns.API and ns.API.OnAddonReady then
        ns.API.OnAddonReady("Blizzard_GroupFinder_VanillaStyle", function()
            if M.active then RegisterMinimapLFGMover(self) end
        end)
    else
        RegisterMinimapLFGMover(self)
    end

    if ns.Loot and ns.Loot.GetFrame then
        local loot = ns.Loot:GetFrame()
        if loot then
            local lw = (ns.Loot.GetMoverWidth and ns.Loot:GetMoverWidth()) or FrameWidth(loot, 260)
            local lh = (ns.Loot.GetMoverHeight and ns.Loot:GetMoverHeight()) or FrameHeight(loot, 34)
            self:RegisterElement("LootFrame", loot, {
                label = "TurboFace Loot Frame",
                overlayWidth = lw,
                overlayHeight = lh,
                fallbackPoint = { "CENTER", UIParent, "CENTER", 0, 180 },
                defaultPoint = { "CENTER", UIParent, "CENTER", 0, 180 },
                getChildren = function() return (ns.Loot and ns.Loot.GetChildren and ns.Loot:GetChildren()) or {} end,
                onApply = function() if ns.Loot and ns.Loot.Layout then ns.Loot:Layout() end end,
            })
        end
    end

    if ns.NW and ns.NW.RegisterMover then
        ns.NW:RegisterMover()
    end

    if ns.HS and ns.HS.RegisterMover then
        ns.HS:RegisterMover()
    end

    if ns.UnstuckSkipVisual and ns.UnstuckSkipVisual.RegisterMover then
        ns.UnstuckSkipVisual:RegisterMover()
    end

    if ns.Skills and ns.Skills.RegisterMover then
        ns.Skills:RegisterMover()
    end

    if ns.CombatMeter and ns.CombatMeter.RegisterMover then
        ns.CombatMeter:RegisterMover()
    end

    if ns.LeashTimer and ns.LeashTimer.RegisterMover then
        ns.LeashTimer:RegisterMover()
    end

    if ns.SpeedrunSplits and ns.SpeedrunSplits.RegisterMover then
        ns.SpeedrunSplits:RegisterMover()
    end

    if ns.TalentPointReminder and ns.TalentPointReminder.RegisterMover then
        ns.TalentPointReminder:RegisterMover()
    end

    if ns.Tracker and ns.Tracker.RegisterMover then
        ns.Tracker:RegisterMover()
    end

    if ns.ClassBuffs and ns.ClassBuffs.RegisterMover then
        ns.ClassBuffs:RegisterMover()
    end

    if ns.DruidPowerBar and ns.DruidPowerBar.RegisterMover then
        ns.DruidPowerBar:RegisterMover()
    end
end

function M:FindElement(token)
    if not token or token == "" then return nil end
    token = token:lower()
    for _, id in ipairs(order) do
        local info = elements[id]
        local label = info and info.label and info.label:lower() or ""
        if id:lower() == token or label == token then return id end
    end
    for _, id in ipairs(order) do
        local info = elements[id]
        local label = info and info.label and info.label:lower() or ""
        if id:lower():find(token, 1, true) or label:find(token, 1, true) then return id end
    end
    return nil
end

local function HookAuraUpdates(self)
    local db = DB()
    if db.auraLayout == false then return end
    if ElementDB("TargetBuffs").enabled == false and ElementDB("TargetDebuffs").enabled == false then return end
    if hooksInstalled then return end
    hooksInstalled = true

    local function Request()
        self:RequestAuraUpdate(true)
    end

    -- Player BuffFrame hooks removed with the player aura movers; only target
    -- aura layout still needs a Blizzard-update nudge.
    local funcs = {
        "TargetFrame_Update",
        "TargetFrame_UpdateAuras",
    }

    for _, fnName in ipairs(funcs) do
        if _G[fnName] and hooksecurefunc then
            hooksecurefunc(fnName, Request)
        end
    end
end
M._HookAuraUpdates = HookAuraUpdates

local function ParseElementAndState(args)
    args = args or ""
    local name = args:gsub("^%s+", ""):gsub("%s+$", "")
    local state
    local last = name:match("(%S+)$")
    if last then
        local v = last:lower()
        if v == "on" or v == "true" or v == "1" or v == "yes" then
            state = true
            name = name:sub(1, #name - #last):gsub("%s+$", "")
        elseif v == "off" or v == "false" or v == "0" or v == "no" then
            state = false
            name = name:sub(1, #name - #last):gsub("%s+$", "")
        elseif v == "toggle" then
            state = nil
            name = name:sub(1, #name - #last):gsub("%s+$", "")
        end
    end
    return name, state
end

local function ElementLabel(id)
    local info = elements[id]
    return (info and info.label) or id
end


function M:HandleSlash(cmd, args)
    cmd = cmd and cmd:lower() or ""
    args = args or ""


    if cmd == "move" or cmd == "movers" then
        if args ~= "" then self:HandleCommand(args) else self:Unlock() end
        return true
    elseif cmd == "lock" or cmd == "unlock" or cmd == "reset" or cmd == "snap" or cmd == "grid" or cmd == "coords" or cmd == "coordinates" or cmd == "nudge" or cmd == "hide" or cmd == "show" or cmd == "click" or cmd == "clickthrough" then
        local msg = cmd
        if args ~= "" then msg = msg .. " " .. args end
        self:HandleCommand(msg)
        return true
    elseif cmd == "resetmovers" or cmd == "resetmove" then
        self:ResetAll()
        return true
    end

    return false
end

function M:HandleCommand(msg)
    msg = msg or ""
    local cmd, args = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    args = args or ""

    if cmd == "" or cmd == "toggle" or cmd == "move" or cmd == "movers" then
        self:ToggleLock()
    elseif cmd == "lock" then
        self:Lock()
    elseif cmd == "unlock" then
        self:Unlock()
    elseif cmd == "hide" then
        if args ~= "" then
            local name, state = ParseElementAndState(args)
            local id = self:FindElement(name)
            if id then
                if state == nil then state = true end
                self:SetElementHidden(id, state)
                Chat(ElementLabel(id) .. (state and " hidden." or " shown."))
            else
                Chat("unknown mover: " .. tostring(name))
            end
        else
            self:Lock()
        end
    elseif cmd == "show" then
        if args ~= "" then
            local id = self:FindElement(args)
            if id then
                self:SetElementHidden(id, false)
                Chat(ElementLabel(id) .. " shown.")
            else
                Chat("unknown mover: " .. tostring(args))
            end
        else
            self:Unlock()
        end
    elseif cmd == "click" or cmd == "clickthrough" then
        local name, state = ParseElementAndState(args)
        local id = self:FindElement(name)
        if id then
            local edb = ElementDB(id)
            if state == nil then state = edb.clickThrough ~= true end
            self:SetElementClickThrough(id, state)
            Chat(ElementLabel(id) .. (state and " click-through enabled." or " click-through disabled."))
        else
            Chat("usage: /tfmove clickthrough playerbuffs on")
        end
    elseif cmd == "reset" then
        local id = self:FindElement(args)
        if id then self:ResetElement(id) else self:ResetAll() end
    elseif cmd == "resetall" then
        self:ResetAll()
    elseif cmd == "snap" then
        local n = tonumber(args)
        if n and n >= 1 then
            DB().snapSize = n
            self:UpdateGrid()
            Chat("snap size set to " .. n .. ".")
        else
            Chat("usage: /tfmove snap 5")
        end
    elseif cmd == "grid" then
        local arg = args and args:lower() or ""
        local n = tonumber(arg)
        if n and n >= 4 then
            DB().gridSize = n
            DB().showGrid = true
            Chat("grid shown with " .. n .. "px spacing.")
        elseif arg == "on" or arg == "show" or arg == "1" then
            DB().showGrid = true
            Chat("grid shown while movers are unlocked.")
        elseif arg == "off" or arg == "hide" or arg == "0" then
            DB().showGrid = false
            Chat("grid hidden.")
        else
            DB().showGrid = not DB().showGrid
            Chat(DB().showGrid and "grid shown while movers are unlocked." or "grid hidden.")
        end
        self:UpdateGrid()
    elseif cmd == "coords" or cmd == "coordinates" then
        local arg = args and args:lower() or ""
        if arg == "on" or arg == "show" or arg == "1" then
            DB().showCoordinates = true
        elseif arg == "off" or arg == "hide" or arg == "0" then
            DB().showCoordinates = false
        else
            DB().showCoordinates = not DB().showCoordinates
        end
        self:UpdateOverlays()
        Chat(DB().showCoordinates and "coordinates shown." or "coordinates hidden.")
    elseif cmd == "nudge" then
        local n = tonumber(args)
        if n and n >= 1 then
            DB().nudgeStep = n
            Chat("nudge step set to " .. n .. ".")
        else
            Chat("usage: /tfmove nudge 1")
        end
    else
        Chat("commands: /tf move, /tf lock, /tf reset playerbuffs, /tfmove hide fps, /tfmove clickthrough playerbuffs, /tfmove grid, /tfmove snap 5, /tfmove nudge 1")
    end
end

function M:RefreshDependents()
    if ns.XP and ns.XP.Refresh then ns.XP:Refresh() end
    if ns.Loot and ns.Loot.Refresh then ns.Loot:Refresh() end
    if ns.NW and ns.NW.Refresh then ns.NW:Refresh() end
    if ns.HS and ns.HS.Refresh then ns.HS:Refresh() end
    if ns.Grocery and ns.Grocery.Refresh then ns.Grocery:Refresh() end
    if ns.Tracker and ns.Tracker.Refresh then ns.Tracker:Refresh() end
    if ns.ClassBuffs and ns.ClassBuffs.Refresh then ns.ClassBuffs:Refresh() end
    if ns.Providers then ns.Providers:Call("combatMeter", "Refresh")
    elseif ns.CombatMeter and ns.CombatMeter.Refresh then ns.CombatMeter:Refresh() end
    if ns.LeashTimer and ns.LeashTimer.Refresh then ns.LeashTimer:Refresh() end
    if ns.PlusFlight and ns.PlusFlight.Refresh then ns.PlusFlight:Refresh() end
end

function M:Init()
    local db = DB()
    if db.enabled == false then
        M.active = false
        return
    end
    if M.initialized then
        M.active = true
        EnsureEventFrame()
        if AuraRuntimeNeeded() then EnsureAuraDriver() end
        return
    end
    M.initialized = true
    M.active = true

    EnsureMoverParent()
    EnsureEventFrame()
    if AuraRuntimeNeeded() then EnsureAuraDriver() end

    M._RegisterAuraMovers(self)
    M._RegisterToTMover(self)
    M.RegisterSystemFrameMovers(self)
    HookAuraUpdates(self)

    self:ApplyAll()
    After(0.2, function() if M.active then M:RequestAuraUpdate() end end)
    After(0.5, function() if M.active then M.RegisterSystemFrameMovers(M); M:ApplyAll() end end)
    After(1.5, function() if M.active and QueueQuestTrackerApply then QueueQuestTrackerApply(false) end end)
end

SLASH_TURBOFACEMOVE1 = "/tfmove"
SLASH_TURBOFACEMOVE2 = "/tfmovers"
SlashCmdList["TURBOFACEMOVE"] = function(msg)
    M:HandleCommand(msg)
end
