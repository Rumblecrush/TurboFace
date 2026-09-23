local _, ns = ...

-- TurboFace Plus: focused Blizzard-interface presentation controls.
-- The module owns only the small visual changes exposed in TurboFace's Plus
-- options and implements them directly against Blizzard frames.

local M = {}
ns.PlusInterface = M

local function Settings()
    return ns.PlusSettings()
end

local OnAddonReady = ns.API.OnAddonReady

local function HideWhileEnabled(frame, settingKey)
    if not frame or not frame.Hide then return end
    frame:Hide()
    if frame.HookScript then
        frame._tfHideWhileEnabled = frame._tfHideWhileEnabled or {}
        if not frame._tfHideWhileEnabled[settingKey] then
            frame._tfHideWhileEnabled[settingKey] = true
            frame:HookScript("OnShow", function(self)
                if Settings()[settingKey] then self:Hide() end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Small stock-frame visibility controls
-- ---------------------------------------------------------------------------

local function ApplyHitIndicators()
    if not Settings().hideHitIndicators then return end
    HideWhileEnabled(PlayerHitIndicator, "hideHitIndicators")
    HideWhileEnabled(PetHitIndicator, "hideHitIndicators")
end

local function ApplyZoneAnnouncements()
    if not Settings().hideZoneText then return end
    HideWhileEnabled(ZoneTextFrame, "hideZoneText")
    HideWhileEnabled(SubZoneTextFrame, "hideZoneText")
end

local ACTION_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button",
}

local function ApplyActionButtonText()
    local p = Settings()
    local hideHotkeys, hideNames = p.hideKeybindText, p.hideMacroText
    if not hideHotkeys and not hideNames then return end
    for _, prefix in ipairs(ACTION_PREFIXES) do
        for i = 1, 12 do
            if hideHotkeys then
                local hotkey = _G[prefix .. i .. "HotKey"]
                if hotkey then hotkey:SetAlpha(0) end
            end
            if hideNames then
                local name = _G[prefix .. i .. "Name"]
                if name then name:SetAlpha(0) end
            end
        end
    end
end

local playerRaidLabelHooked = false
local legacyRaidLabelHooked = false
local compactRaidLabelHooked = false

local function HideRaidGroupLabelsNow()
    if not Settings().hideRaidGroupLabels then return end
    if PlayerFrameGroupIndicator then PlayerFrameGroupIndicator:Hide() end

    -- Compact groups can exist before the player actually joins a raid. Sweep
    -- all eight containers so the option can be verified and applied without
    -- depending on GROUP_ROSTER_UPDATE timing.
    for index = 1, (NUM_RAID_GROUPS or 8) do
        local group = _G["CompactRaidGroup" .. tostring(index)]
        local title = group and group.title or _G["CompactRaidGroup" .. tostring(index) .. "Title"]
        if title then title:Hide() end
    end
end

local function HookLegacyRaidLabels()
    if legacyRaidLabelHooked or type(RaidPullout_Update) ~= "function" then return end
    legacyRaidLabelHooked = true
    hooksecurefunc("RaidPullout_Update", function(frame)
        if not Settings().hideRaidGroupLabels then return end
        local name = frame and frame.GetName and frame:GetName()
        local title = name and _G[name .. "Name"]
        if title then title:Hide() end
    end)
end

local function HookCompactRaidLabels()
    if compactRaidLabelHooked or type(CompactRaidGroup_GenerateForGroup) ~= "function" then
        HideRaidGroupLabelsNow()
        return
    end
    compactRaidLabelHooked = true
    hooksecurefunc("CompactRaidGroup_GenerateForGroup", HideRaidGroupLabelsNow)
    HideRaidGroupLabelsNow()
end

local function ApplyRaidLabels()
    if not Settings().hideRaidGroupLabels then return end
    HideRaidGroupLabelsNow()

    if not playerRaidLabelHooked and type(PlayerFrame_UpdateGroupIndicator) == "function" then
        playerRaidLabelHooked = true
        hooksecurefunc("PlayerFrame_UpdateGroupIndicator", HideRaidGroupLabelsNow)
    end

    -- Legacy pullout frames and compact raid frames are separate load-on-demand
    -- addons in Classic. Register for both; OnAddonReady also runs immediately
    -- when either addon was loaded before TurboFace initialized.
    OnAddonReady("Blizzard_RaidUI", HookLegacyRaidLabels)
    OnAddonReady("Blizzard_CompactRaidFrames", HookCompactRaidLabels)
end

-- ---------------------------------------------------------------------------
-- Compact raid manager toggle
-- ---------------------------------------------------------------------------

local raidToggleBackdrop
local raidToggleHooked = false
local function ApplyRaidToggle()
    if not Settings().showRaidToggle then return end
    OnAddonReady("Blizzard_CompactRaidFrames", function()
        local raidParts = ns.API.GetCompactRaidManagerParts and ns.API.GetCompactRaidManagerParts() or {}
        local manager = raidParts.manager
        local toggle = raidParts.hiddenModeToggle
        if not toggle or not manager then return end

        if not raidToggleBackdrop then
            raidToggleBackdrop = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
            raidToggleBackdrop:SetAllPoints()
            raidToggleBackdrop:SetBackdrop({
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 12,
            })
        end

        local function Reposition()
            if not Settings().showRaidToggle then return end
            local _, _, _, _, y = manager:GetPoint()
            toggle:SetParent(UIParent)
            toggle:SetWidth(40)
            toggle:ClearAllPoints()
            toggle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, (y or 0) + 22)
            toggle:Show()
        end
        Reposition()
        if not raidToggleHooked and type(CompactRaidFrameManager_UpdateOptionsFlowContainer) == "function" then
            raidToggleHooked = true
            hooksecurefunc("CompactRaidFrameManager_UpdateOptionsFlowContainer", Reposition)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Quest list difficulty tags
-- Forever owns quest-level presentation natively. TurboFace only decorates
-- quest titles with compact classification tags (D/R/+/P).
-- ---------------------------------------------------------------------------

local modernQuestDifficultyHooked = false
local legacyQuestDifficultyHooked = false

local function DifficultySuffix(suggestedGroup)
    if not Settings().enhanceQuestDifficulty then return "" end
    if suggestedGroup == LFG_TYPE_DUNGEON then return "D" end
    if suggestedGroup == RAID then return "R" end
    if suggestedGroup == PVP then return "P" end
    if suggestedGroup == ELITE or suggestedGroup == GROUP then return "+" end
    return ""
end

local function ModernDifficultySuffix(info)
    if not Settings().enhanceQuestDifficulty or type(info) ~= "table" then return "" end

    -- Mainline/Forever can expose the numeric quest type directly. These are
    -- longstanding quest type IDs, not LFG activity enums.
    local questType
    if info.questID and C_QuestLog and type(C_QuestLog.GetQuestType) == "function" then
        local ok, value = pcall(C_QuestLog.GetQuestType, info.questID)
        if ok then questType = value end
    end
    if questType == 81 then return "D" end                -- Dungeon
    if questType == 62 or questType == 88 or questType == 89 then return "R" end
    if questType == 41 or questType == 113 then return "P" end
    if questType == 1 then return "+" end                 -- Group

    local suggested = tonumber(info.suggestedGroup)
    if suggested and suggested > 0 then return "+" end
    return DifficultySuffix(info.suggestedGroup)
end

local function AddDifficultyTag(text, tag)
    if not text or text == "" or not tag or tag == "" then return text end
    -- Blizzard owns the native level/title formatting in Forever. Keep that
    -- text intact and add only TurboFace's classification token.
    return ("[%s] %s"):format(tag, text)
end

local function UpdateLegacyQuestDifficultyTags()
    if not Settings().enhanceQuestDifficulty or not ns.API.GetNumQuestLogEntries then return end
    local offset = FauxScrollFrame_GetOffset and QuestLogListScrollFrame
        and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
    local entries = ns.API.GetNumQuestLogEntries()
    for row = 1, (QUESTS_DISPLAYED or 6) do
        local index = offset + row
        if index <= entries then
            local title, _, suggestedGroup, isHeader = ns.API.GetQuestLogTitle(index)
            local label = _G["QuestLogTitle" .. row]
            if label and title and not isHeader then
                local tag = DifficultySuffix(suggestedGroup)
                if tag ~= "" then
                    local text = AddDifficultyTag(title, tag)
                    label:SetText(text)
                    if QuestLogDummyText then QuestLogDummyText:SetText(text) end
                    local check = _G["QuestLogTitle" .. row .. "Check"]
                    local normal = _G["QuestLogTitle" .. row .. "NormalText"]
                    if check and normal and normal.GetStringWidth then
                        local width = normal:GetStringWidth() or 0
                        check:ClearAllPoints()
                        check:SetPoint("LEFT", label, "LEFT", math.min(width + 24, 210), 0)
                    end
                end
            end
        end
    end
end

local function UpdateModernQuestDifficultyTags()
    if not Settings().enhanceQuestDifficulty then return end
    local scroll = _G.QuestScrollFrame
    local pool = scroll and scroll.titleFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end

    for button in pool:EnumerateActive() do
        local info = button and button.info
        local label = button and button.Text
        if info and label and not info.isHeader then
            local tag = ModernDifficultySuffix(info)
            if tag ~= "" then
                -- QuestLogQuests_Update has just rebuilt Blizzard's title,
                -- including Forever's native level and any questline/replay
                -- decorations. Prefix only the TurboFace classification tag.
                local current = label:GetText() or info.title
                label:SetText(AddDifficultyTag(current, tag))
            end
        end
    end
end

local function HookModernQuestDifficultyTags()
    if modernQuestDifficultyHooked or not Settings().enhanceQuestDifficulty then return end
    if type(_G.QuestLogQuests_Update) ~= "function" then return end
    modernQuestDifficultyHooked = true
    hooksecurefunc("QuestLogQuests_Update", UpdateModernQuestDifficultyTags)
    _G.QuestLogQuests_Update()
end

local function HookLegacyQuestDifficultyTags()
    if legacyQuestDifficultyHooked or not Settings().enhanceQuestDifficulty then return end
    if type(_G.QuestLog_Update) ~= "function" then return end
    legacyQuestDifficultyHooked = true
    hooksecurefunc("QuestLog_Update", UpdateLegacyQuestDifficultyTags)
    UpdateLegacyQuestDifficultyTags()
end

local function ApplyQuestDifficultyTags()
    if not Settings().enhanceQuestDifficulty then return end

    -- Forever/Mainline path: decorate Blizzard's pooled quest-title frames after
    -- Blizzard has rendered the native level/title text.
    HookModernQuestDifficultyTags()
    OnAddonReady("Blizzard_UIPanels_Game", HookModernQuestDifficultyTags)
    OnAddonReady("Blizzard_WorldMap", HookModernQuestDifficultyTags)

    -- Era/older Classic fallback. Kept only for hybrid compatibility; it never
    -- injects quest levels in the Forever branch.
    HookLegacyQuestDifficultyTags()
end

-- ---------------------------------------------------------------------------
-- Movable Blizzard combined bag
--
-- This is intentionally not a TurboFace mover. Blizzard keeps the combined
-- bag's contents, sizing, strata and open/close behavior; TurboFace adds only
-- drag handling plus one saved UIParent-relative anchor. Individual numbered
-- ContainerFrames are never touched.
-- ---------------------------------------------------------------------------

local combinedBagInstalled = setmetatable({}, { __mode = "k" })
local combinedBagRestoreQueued = false
local combinedBagPendingFrame
local combinedBagLoader
local combinedBagCombatWaiter
local InstallCombinedBagDrag

local VALID_ANCHOR = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function CombinedBagDB()
    if type(TurboFaceDB) ~= "table" then TurboFaceDB = {} end
    if type(TurboFaceDB.combinedBag) ~= "table" then
        TurboFaceDB.combinedBag = {}
    end
    return TurboFaceDB.combinedBag
end

local function SaveCombinedBagPosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not VALID_ANCHOR[point] or not VALID_ANCHOR[relativePoint]
        or type(x) ~= "number" or type(y) ~= "number" then return false end
    local db = CombinedBagDB()
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
    return true
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local QueueCombinedBagRestore

local function EnsureCombinedBagCombatWaiter()
    if combinedBagCombatWaiter then return end
    combinedBagCombatWaiter = CreateFrame("Frame")
    combinedBagCombatWaiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local frame = combinedBagPendingFrame
        combinedBagPendingFrame = nil
        if frame and Settings().combinedBagMovable then
            if combinedBagInstalled[frame] then
                QueueCombinedBagRestore(frame)
            else
                InstallCombinedBagDrag(frame)
            end
        end
    end)
end

local function RestoreCombinedBagPosition(frame)
    if not frame or not Settings().combinedBagMovable then return false end
    if InCombat() then
        combinedBagPendingFrame = frame
        EnsureCombinedBagCombatWaiter()
        combinedBagCombatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    local db = CombinedBagDB()
    if not VALID_ANCHOR[db.point] or not VALID_ANCHOR[db.relativePoint]
        or type(db.x) ~= "number" or type(db.y) ~= "number" then return false end

    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    -- UserPlaced keeps Blizzard's container anchor pass from immediately
    -- reclaiming the frame. TurboFace remains the persistence owner.
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    if frame.SetUserPlaced then frame:SetUserPlaced(true) end
    return true
end

QueueCombinedBagRestore = function(frame)
    if not frame or not Settings().combinedBagMovable then return end
    combinedBagPendingFrame = frame
    if InCombat() then
        EnsureCombinedBagCombatWaiter()
        combinedBagCombatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if combinedBagRestoreQueued then return end
    combinedBagRestoreQueued = true
    local NextFrame = RunNextFrame or function(callback) C_Timer.After(0, callback) end
    NextFrame(function()
        combinedBagRestoreQueued = false
        local pending = combinedBagPendingFrame
        combinedBagPendingFrame = nil
        if pending then RestoreCombinedBagPosition(pending) end
    end)
end

local function CombinedBagDragHandle(frame)
    local function Usable(candidate)
        return candidate and type(candidate.RegisterForDrag) == "function"
            and type(candidate.HookScript) == "function"
            and type(candidate.EnableMouse) == "function"
    end
    if Usable(frame.TitleContainer) then return frame.TitleContainer end
    if Usable(frame.Header) then return frame.Header end
    if Usable(frame) then return frame end
end

InstallCombinedBagDrag = function(frame)
    if not frame or combinedBagInstalled[frame] then return false end
    if type(frame.SetMovable) ~= "function"
        or type(frame.StartMoving) ~= "function"
        or type(frame.StopMovingOrSizing) ~= "function"
        or type(frame.HookScript) ~= "function" then return false end
    if InCombat() then
        combinedBagPendingFrame = frame
        EnsureCombinedBagCombatWaiter()
        combinedBagCombatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    local handle = CombinedBagDragHandle(frame)
    if not handle then return false end
    combinedBagInstalled[frame] = true

    frame:SetMovable(true)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:HookScript("OnDragStart", function()
        if not Settings().combinedBagMovable or InCombat() then return end
        frame:StartMoving()
    end)
    handle:HookScript("OnDragStop", function()
        if not Settings().combinedBagMovable or InCombat() then return end
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then frame:SetUserPlaced(true) end
        SaveCombinedBagPosition(frame)
    end)
    frame:HookScript("OnShow", function()
        if Settings().combinedBagMovable then QueueCombinedBagRestore(frame) end
    end)

    QueueCombinedBagRestore(frame)
    return true
end

local function ApplyCombinedBagMovement()
    if not Settings().combinedBagMovable then return end
    local frame = ns.API.GetCombinedBagFrame and ns.API.GetCombinedBagFrame()
    if frame then
        InstallCombinedBagDrag(frame)
        return
    end

    -- The container UI can be load-on-demand. Listen only until the dedicated
    -- combined frame materializes; no polling or OnUpdate driver is required.
    if combinedBagLoader then return end
    combinedBagLoader = CreateFrame("Frame")
    combinedBagLoader:RegisterEvent("ADDON_LOADED")
    combinedBagLoader:SetScript("OnEvent", function(self)
        if not Settings().combinedBagMovable then return end
        local loaded = ns.API.GetCombinedBagFrame and ns.API.GetCombinedBagFrame()
        if loaded and InstallCombinedBagDrag(loaded) then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------

local function MinimapParts()
    return ns.API.GetMinimapParts and ns.API.GetMinimapParts() or {}
end

local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local minimapBorderFrame
local zoneBanner
local toggleShowHooked = false

local function Place(frame, point, relative, relativePoint, x, y, scale)
    if not frame then return end
    if scale and frame.SetScale then frame:SetScale(scale) end
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if frame.SetPoint then frame:SetPoint(point, relative, relativePoint, x, y) end
end

local function SetZoneFont(width)
    local zoneText = MinimapParts().zoneText
    if not zoneText then return end
    local file, current = zoneText:GetFont()
    local size = tonumber(Settings().minimapZoneTextSize)
    if not size or size <= 0 then size = current end
    if file and size then zoneText:SetFont(file, size, "THINOUTLINE") end
    if width and zoneText.SetWidth then zoneText:SetWidth(width) end
end

function M:ApplySquareMinimap()
    local parts = MinimapParts()
    local minimap = parts.minimap
    if not minimap then return end
    local p = Settings()
    _G.GetMinimapShape = function()
        return Settings().minimapShape == "square" and "SQUARE" or "ROUND"
    end
    if p.minimapShape ~= "square" then
        if minimap.SetMaskTexture then minimap:SetMaskTexture(ROUND_MASK) end
        if ns.API.SetNativeMinimapBorderShown then
            ns.API.SetNativeMinimapBorderShown(true)
        else
            if parts.border then parts.border:Show() end
            if parts.northTag then parts.northTag:Show() end
        end
        if minimapBorderFrame then minimapBorderFrame:Hide() end
        return
    end

    _G.GetMinimapShape = function() return "SQUARE" end
    if minimap.SetMaskTexture then minimap:SetMaskTexture(SQUARE_MASK) end
    if ns.API.SetNativeMinimapBorderShown then
        ns.API.SetNativeMinimapBorderShown(false)
    else
        if parts.border then parts.border:Hide() end
        if parts.northTag then parts.northTag:Hide() end
    end

    local size = tonumber(p.minimapSize) or 140
    minimap:SetSize(size, size)

    if not minimapBorderFrame then
        minimapBorderFrame = CreateFrame("Frame", nil, minimap, "BackdropTemplate")
        minimapBorderFrame:SetAlpha(0.8)
    end
    minimapBorderFrame:Show()
    local edge = tonumber(p.minimapBorderWidth) or 3
    local inset = ns.GetBorderInset and ns:GetBorderInset(p.minimapBorderTexture) or 0
    local offset = edge * inset + (tonumber(p.minimapBorderOffset) or 0)
    minimapBorderFrame:ClearAllPoints()
    minimapBorderFrame:SetPoint("TOPLEFT", minimap, "TOPLEFT", -offset, offset)
    minimapBorderFrame:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", offset, -offset)
    minimapBorderFrame:SetBackdrop({
        edgeFile = ns.ResolveBorderTexture and ns.ResolveBorderTexture(p.minimapBorderTexture)
            or "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = edge,
    })

    -- Force the map tile to redraw after a live size change.
    if minimap.GetZoom and minimap.SetZoom then
        local zoom = minimap:GetZoom()
        local other = zoom == 5 and 4 or zoom + 1
        minimap:SetZoom(other)
        minimap:SetZoom(zoom)
    end

    local mailMoved = ns.Movers and ns.Movers.IsMinimapMailMoverActive
        and ns.Movers:IsMinimapMailMoverActive()
    if not mailMoved then Place(parts.mailFrame, "TOPLEFT", minimap, "TOPLEFT", -19, -53, 0.75) end
    if parts.battlefieldFrame then
        if mailMoved then
            Place(parts.battlefieldFrame, "TOPLEFT", minimap, "TOPLEFT", -19, -53, 0.75)
        elseif parts.mailFrame then
            Place(parts.battlefieldFrame, "TOP", parts.mailFrame, "BOTTOM", 0, 0, 0.75)
        end
    end
    Place(parts.zoomIn, "TOPRIGHT", minimap, "TOPRIGHT", 19, -120, 0.75)
    if parts.zoomIn then Place(parts.zoomOut, "TOP", parts.zoomIn, "BOTTOM", 0, 0, 0.75) end
    local gameTimeFrame = parts.gameTimeFrame or _G.GameTimeFrame
    if gameTimeFrame and parts.zoomIn then
        Place(gameTimeFrame, "BOTTOM", parts.zoomIn, "TOP", 0, 1)
        if parts.backdrop and gameTimeFrame.SetParent then gameTimeFrame:SetParent(parts.backdrop) end
        if gameTimeFrame.SetSize then gameTimeFrame:SetSize(23, 23) end
    end

    if parts.zoneButton and not p.minimapZoneBanner and not p.hideMiniZoneText then
        parts.zoneButton:SetParent(minimap)
        Place(parts.zoneButton, "TOP", minimap, "TOP", 0, -5)
        parts.zoneButton:SetWidth(size)
        parts.zoneButton:SetFrameStrata("MEDIUM")
        parts.zoneButton:SetFrameLevel((minimap:GetFrameLevel() or 0) + 5)
        SetZoneFont(size)
    end
end

local function ApplyZoneBanner()
    local p = Settings()
    local parts = MinimapParts()
    local minimap, zoneButton = parts.minimap, parts.zoneButton
    if not p.minimapZoneBanner or p.hideMiniZoneText or not minimap or not zoneButton then return end

    if not zoneBanner then
        zoneBanner = CreateFrame("Frame", nil, parts.cluster or UIParent, "BackdropTemplate")
        zoneBanner:SetSize(150, 28)
        zoneBanner:SetFrameStrata("MEDIUM")
        zoneBanner:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        zoneBanner:SetBackdropColor(0.02, 0.02, 0.02, 0.78)
        zoneBanner:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end
    zoneBanner:ClearAllPoints()
    zoneBanner:SetPoint("TOP", minimap, "TOP", 0, 12)
    zoneBanner:SetFrameLevel((minimap:GetFrameLevel() or 0) + 10)
    zoneBanner:Show()

    zoneButton:SetParent(zoneBanner)
    Place(zoneButton, "CENTER", zoneBanner, "CENTER", 0, 0)
    zoneButton:SetFrameStrata("MEDIUM")
    zoneButton:SetFrameLevel(zoneBanner:GetFrameLevel() + 1)
    SetZoneFont(130)
end

local function NeuterMinimapToggle()
    local button = MinimapParts().toggleButton
    if not button then return end
    if button.SetNormalTexture then button:SetNormalTexture(0) end
    if button.SetPushedTexture then button:SetPushedTexture(0) end
    if button.SetHighlightTexture then button:SetHighlightTexture(0) end
    if button.EnableMouse then button:EnableMouse(false) end

    if not toggleShowHooked then
        toggleShowHooked = true
        hooksecurefunc(button, "Show", function(self)
            local p = Settings()
            if p.minimapShape == "square" or p.minimapZoneBanner or p.hideMiniZoneText then
                if self.SetNormalTexture then self:SetNormalTexture(0) end
                if self.SetPushedTexture then self:SetPushedTexture(0) end
                if self.SetHighlightTexture then self:SetHighlightTexture(0) end
                if self.EnableMouse then self:EnableMouse(false) end
            end
        end)
    end
end

local dayNightObjectHooks = setmetatable({}, { __mode = "k" })
local dayNightFrameShowHooked = false
local dayNightDateHooked = false

local function HideDayNightObject(object)
    if not object or type(object.Hide) ~= "function" then return false end
    object:Hide()

    -- Blizzard/Forever may re-show either a Texture or a Frame after calendar
    -- and time-of-day updates. Hook the actual object's Show method when it is
    -- hookable instead of depending on one generated global name.
    if not dayNightObjectHooks[object] and type(hooksecurefunc) == "function"
        and type(object.Show) == "function" then
        local ok = pcall(hooksecurefunc, object, "Show", function(self)
            if Settings().hideMiniDayNight and type(self.Hide) == "function" then
                self:Hide()
            end
        end)
        if ok then dayNightObjectHooks[object] = true end
    end
    return true
end

local function Lower(value)
    return type(value) == "string" and string.lower(value) or nil
end

local function IsDayNightRegion(region)
    if not region then return false end

    local name
    if type(region.GetName) == "function" then
        local ok, value = pcall(region.GetName, region)
        if ok then name = Lower(value) end
    end
    if name and (name:find("gametime", 1, true)
        or name:find("daynight", 1, true)
        or name:find("timeofday", 1, true)
        or name:find("todindicator", 1, true)) then
        return true
    end

    if type(region.GetTexture) == "function" then
        local ok, texture = pcall(region.GetTexture, region)
        texture = ok and Lower(texture) or nil
        if texture and (texture:find("ui%-tod%-indicator")
            or texture:find("tod%-indicator")
            or texture:find("daynight")) then
            return true
        end
    end

    if type(region.GetAtlas) == "function" then
        local ok, atlas = pcall(region.GetAtlas, region)
        atlas = ok and Lower(atlas) or nil
        if atlas and (atlas:find("daynight", 1, true)
            or atlas:find("time%-of%-day")) then
            return true
        end
    end
    return false
end

local function SuppressEntireGameTimeTree(frame, seen, depth)
    if not frame or (depth or 0) > 5 then return end
    seen = seen or {}
    if seen[frame] then return end
    seen[frame] = true

    -- Everything below the known GameTime owner is presentation for that
    -- control (calendar/date/day-night/invite art), so hiding its texture tree
    -- is safe and covers anonymous Forever regions as well as named globals.
    if type(frame.GetRegions) == "function" then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and type(region.GetObjectType) == "function"
                and region:GetObjectType() == "Texture" then
                HideDayNightObject(region)
            end
        end
    end
    if type(frame.GetChildren) == "function" then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            SuppressEntireGameTimeTree(children[i], seen, (depth or 0) + 1)
        end
    end
end

local function ScanForDetachedDayNight(root, seen, depth)
    if not root or (depth or 0) > 5 then return end
    seen = seen or {}
    if seen[root] then return end
    seen[root] = true

    -- Forever is a hybrid client and can place the old UI-TOD-Indicator outside
    -- GameTimeFrame. Search the actual minimap tree by object/texture identity
    -- rather than assuming the Mainline XML parentage.
    if IsDayNightRegion(root) then HideDayNightObject(root) end
    if type(root.GetRegions) == "function" then
        local regions = { root:GetRegions() }
        for i = 1, #regions do
            if IsDayNightRegion(regions[i]) then HideDayNightObject(regions[i]) end
        end
    end
    if type(root.GetChildren) == "function" then
        local children = { root:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if IsDayNightRegion(child) then
                HideDayNightObject(child)
                SuppressEntireGameTimeTree(child)
            end
            ScanForDetachedDayNight(child, seen, (depth or 0) + 1)
        end
    end
end

local function SuppressResolvedDayNightObjects()
    if not Settings().hideMiniDayNight then return end
    local parts = MinimapParts()
    local frame = parts.gameTimeFrame or _G.GameTimeFrame

    HideDayNightObject(frame)
    SuppressEntireGameTimeTree(frame)
    HideDayNightObject(parts.gameTimeTexture or _G.GameTimeTexture)

    -- Known historical/hybrid globals seen across Blizzard minimap generations.
    local names = {
        "GameTimeTexture", "GameTimeDayNightTexture",
        "MinimapDayNight", "MinimapDayNightFrame", "MinimapDayNightTexture",
        "MinimapTimeOfDay", "MinimapTimeOfDayTexture",
    }
    for i = 1, #names do HideDayNightObject(_G[names[i]]) end

    -- Finally inspect the live minimap tree for a detached UI-TOD-Indicator.
    local seen = {}
    ScanForDetachedDayNight(parts.cluster, seen, 0)
    ScanForDetachedDayNight(parts.backdrop, seen, 0)
    ScanForDetachedDayNight(parts.minimap, seen, 0)
end

local function ApplyDayNightVisibility()
    if not Settings().hideMiniDayNight then return end
    local parts = MinimapParts()
    local frame = parts.gameTimeFrame or _G.GameTimeFrame

    SuppressResolvedDayNightObjects()

    if frame and not dayNightFrameShowHooked and type(frame.HookScript) == "function" then
        dayNightFrameShowHooked = true
        frame:HookScript("OnShow", function()
            if Settings().hideMiniDayNight then SuppressResolvedDayNightObjects() end
        end)
    end

    -- Mainline calls this when its calendar/date presentation changes. Forever
    -- may also use it to revive the old TOD texture; re-scan once after each
    -- date refresh rather than polling every frame.
    if not dayNightDateHooked and type(hooksecurefunc) == "function"
        and type(_G.GameTimeFrame_SetDate) == "function" then
        dayNightDateHooked = true
        hooksecurefunc("GameTimeFrame_SetDate", function()
            if Settings().hideMiniDayNight then SuppressResolvedDayNightObjects() end
        end)
    end
end

local function ApplyMinimapElements()
    local p = Settings()
    M:ApplySquareMinimap()
    ApplyZoneBanner()

    local parts = MinimapParts()
    if p.minimapShape == "square" or p.minimapZoneBanner or p.hideMiniZoneText then
        NeuterMinimapToggle()
    end
    if p.hideMiniZoomBtns then
        HideWhileEnabled(parts.zoomIn, "hideMiniZoomBtns")
        HideWhileEnabled(parts.zoomOut, "hideMiniZoomBtns")
    end
    if p.hideMiniDayNight then ApplyDayNightVisibility() end
    if p.hideMiniZoneText and parts.zoneButton then
        parts.zoneButton:Hide()
        -- Forever/Mainline BorderTop is a NineSliceCodeTemplate *Frame*, not a
        -- texture. Treat it as Blizzard-owned frame visibility; calling
        -- :SetTexture() here crashes because that method does not exist.
        HideWhileEnabled(parts.borderTop or (parts.cluster and parts.cluster.BorderTop), "hideMiniZoneText")
    end

    if p.hideMiniClock then
        OnAddonReady("Blizzard_TimeManager", function()
            HideWhileEnabled(MinimapParts().clockButton, "hideMiniClock")
        end)
    end

    if p.hideMiniLFG then
        local function HideLFGWhenIdle()
            local button = MinimapParts().lfgButton
            if not button or not Settings().hideMiniLFG then return end
            local queued = C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
            if queued then button:Show() else button:Hide() end
        end
        OnAddonReady("Blizzard_GroupFinder", function()
            local button = MinimapParts().lfgButton
            if button and button.HookScript then button:HookScript("OnEvent", HideLFGWhenIdle) end
            HideLFGWhenIdle()
        end)
        OnAddonReady("Blizzard_GroupFinder_VanillaStyle", function()
            local button = MinimapParts().lfgButton
            if button and button.HookScript then button:HookScript("OnEvent", HideLFGWhenIdle) end
            HideLFGWhenIdle()
        end)
    end
end

function M:Refresh()
    -- Minimap size/border controls are live, and enabled hide-controls should
    -- take effect immediately as well. Reload is still required to fully restore
    -- Blizzard-owned elements after turning a one-way hide option back off.
    ApplyCombinedBagMovement()
    ApplyMinimapElements()
end

function M:Init()
    ApplyHitIndicators()
    ApplyZoneAnnouncements()
    ApplyActionButtonText()
    ApplyRaidLabels()
    ApplyRaidToggle()
    ApplyQuestDifficultyTags()
    ApplyCombinedBagMovement()
    ApplyMinimapElements()

    -- Some Forever builds create/reparent GameTime presentation late in the
    -- Blizzard_Minimap load. Reapply against the final live tree when that
    -- addon announces itself. OnAddonReady runs immediately if it is loaded.
    OnAddonReady("Blizzard_Minimap", function()
        if Settings().hideMiniDayNight then ApplyDayNightVisibility() end
    end)
end
