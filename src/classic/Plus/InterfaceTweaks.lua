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
        frame:HookScript("OnShow", function(self)
            if Settings()[settingKey] then self:Hide() end
        end)
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
        local toggle = CompactRaidFrameManagerDisplayFrameHiddenModeToggle
        if not toggle or not CompactRaidFrameManager then return end

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
            local _, _, _, _, y = CompactRaidFrameManager:GetPoint()
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
-- Quest list level/difficulty prefix
-- ---------------------------------------------------------------------------

local questLevelHooked = false
local function DifficultySuffix(suggestedGroup)
    if not Settings().enhanceQuestDifficulty then return "" end
    if suggestedGroup == LFG_TYPE_DUNGEON then return "D" end
    if suggestedGroup == RAID then return "R" end
    if suggestedGroup == PVP then return "P" end
    if suggestedGroup == ELITE or suggestedGroup == GROUP then return "+" end
    return ""
end

local function UpdateQuestLevelLabels()
    if not Settings().enhanceQuestLevels or not GetNumQuestLogEntries then return end
    local offset = FauxScrollFrame_GetOffset and QuestLogListScrollFrame
        and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
    local entries = GetNumQuestLogEntries()
    for row = 1, (QUESTS_DISPLAYED or 6) do
        local index = offset + row
        if index <= entries then
            local title, level, suggestedGroup, isHeader = GetQuestLogTitle(index)
            local label = _G["QuestLogTitle" .. row]
            if label and title and level and not isHeader then
                local text = ("  [%d%s] %s"):format(level, DifficultySuffix(suggestedGroup), title)
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

local function ApplyQuestLevels()
    if questLevelHooked or not Settings().enhanceQuestLevels or type(QuestLog_Update) ~= "function" then return end
    questLevelHooked = true
    hooksecurefunc("QuestLog_Update", UpdateQuestLevelLabels)
    UpdateQuestLevelLabels()
end

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------

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
    if not MinimapZoneText then return end
    local file, current = MinimapZoneText:GetFont()
    local size = tonumber(Settings().minimapZoneTextSize)
    if not size or size <= 0 then size = current end
    if file and size then MinimapZoneText:SetFont(file, size, "THINOUTLINE") end
    if width and MinimapZoneText.SetWidth then MinimapZoneText:SetWidth(width) end
end

function M:ApplySquareMinimap()
    if not Minimap then return end
    local p = Settings()
    _G.GetMinimapShape = function()
        return Settings().minimapShape == "square" and "SQUARE" or "ROUND"
    end
    if p.minimapShape ~= "square" then
        if Minimap.SetMaskTexture then Minimap:SetMaskTexture(ROUND_MASK) end
        if MinimapBorder then MinimapBorder:Show() end
        if MinimapNorthTag then MinimapNorthTag:Show() end
        if minimapBorderFrame then minimapBorderFrame:Hide() end
        return
    end

    _G.GetMinimapShape = function() return "SQUARE" end
    if Minimap.SetMaskTexture then Minimap:SetMaskTexture(SQUARE_MASK) end
    if MinimapBorder then MinimapBorder:Hide() end
    if MinimapNorthTag then MinimapNorthTag:Hide() end

    local size = tonumber(p.minimapSize) or 140
    Minimap:SetSize(size, size)

    if not minimapBorderFrame then
        minimapBorderFrame = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
        minimapBorderFrame:SetAlpha(0.8)
    end
    minimapBorderFrame:Show()
    local edge = tonumber(p.minimapBorderWidth) or 3
    local inset = ns.GetBorderInset and ns:GetBorderInset(p.minimapBorderTexture) or 0
    local offset = edge * inset + (tonumber(p.minimapBorderOffset) or 0)
    minimapBorderFrame:ClearAllPoints()
    minimapBorderFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -offset, offset)
    minimapBorderFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", offset, -offset)
    minimapBorderFrame:SetBackdrop({
        edgeFile = ns.ResolveBorderTexture and ns.ResolveBorderTexture(p.minimapBorderTexture)
            or "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = edge,
    })

    -- Force the map tile to redraw after a live size change.
    if Minimap.GetZoom and Minimap.SetZoom then
        local zoom = Minimap:GetZoom()
        local other = zoom == 5 and 4 or zoom + 1
        Minimap:SetZoom(other)
        Minimap:SetZoom(zoom)
    end

    local mailMoved = ns.Movers and ns.Movers.IsMinimapMailMoverActive
        and ns.Movers:IsMinimapMailMoverActive()
    if not mailMoved then Place(MiniMapMailFrame, "TOPLEFT", Minimap, "TOPLEFT", -19, -53, 0.75) end
    if MiniMapBattlefieldFrame then
        if mailMoved then
            Place(MiniMapBattlefieldFrame, "TOPLEFT", Minimap, "TOPLEFT", -19, -53, 0.75)
        elseif MiniMapMailFrame then
            Place(MiniMapBattlefieldFrame, "TOP", MiniMapMailFrame, "BOTTOM", 0, 0, 0.75)
        end
    end
    Place(MinimapZoomIn, "TOPRIGHT", Minimap, "TOPRIGHT", 19, -120, 0.75)
    if MinimapZoomIn then Place(MinimapZoomOut, "TOP", MinimapZoomIn, "BOTTOM", 0, 0, 0.75) end
    if GameTimeFrame and MinimapZoomIn then
        Place(GameTimeFrame, "BOTTOM", MinimapZoomIn, "TOP", 0, 1)
        if MinimapBackdrop and GameTimeFrame.SetParent then GameTimeFrame:SetParent(MinimapBackdrop) end
        if GameTimeFrame.SetSize then GameTimeFrame:SetSize(23, 23) end
    end

    if MinimapZoneTextButton and not p.minimapZoneBanner and not p.hideMiniZoneText then
        MinimapZoneTextButton:SetParent(Minimap)
        Place(MinimapZoneTextButton, "TOP", Minimap, "TOP", 0, -5)
        MinimapZoneTextButton:SetWidth(size)
        MinimapZoneTextButton:SetFrameStrata("MEDIUM")
        MinimapZoneTextButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
        SetZoneFont(size)
    end
end

local function ApplyZoneBanner()
    local p = Settings()
    if not p.minimapZoneBanner or p.hideMiniZoneText or not Minimap or not MinimapZoneTextButton then return end

    if not zoneBanner then
        zoneBanner = CreateFrame("Frame", nil, MinimapCluster or UIParent, "BackdropTemplate")
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
    zoneBanner:SetPoint("TOP", Minimap, "TOP", 0, 12)
    zoneBanner:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    zoneBanner:Show()

    MinimapZoneTextButton:SetParent(zoneBanner)
    Place(MinimapZoneTextButton, "CENTER", zoneBanner, "CENTER", 0, 0)
    MinimapZoneTextButton:SetFrameStrata("MEDIUM")
    MinimapZoneTextButton:SetFrameLevel(zoneBanner:GetFrameLevel() + 1)
    SetZoneFont(130)
end

local function NeuterMinimapToggle()
    local button = MinimapToggleButton
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

local function ApplyMinimapElements()
    local p = Settings()
    M:ApplySquareMinimap()
    ApplyZoneBanner()

    if p.minimapShape == "square" or p.minimapZoneBanner or p.hideMiniZoneText then
        NeuterMinimapToggle()
    end
    if p.hideMiniZoomBtns then
        HideWhileEnabled(MinimapZoomIn, "hideMiniZoomBtns")
        HideWhileEnabled(MinimapZoomOut, "hideMiniZoomBtns")
    end
    if p.hideMiniDayNight then HideWhileEnabled(GameTimeFrame, "hideMiniDayNight") end
    if p.hideMiniZoneText and MinimapZoneTextButton then
        MinimapZoneTextButton:Hide()
        if MinimapCluster and MinimapCluster.BorderTop then MinimapCluster.BorderTop:SetTexture("") end
    end

    if p.hideMiniClock then
        OnAddonReady("Blizzard_TimeManager", function()
            HideWhileEnabled(TimeManagerClockButton, "hideMiniClock")
        end)
    end

    if p.hideMiniLFG then
        OnAddonReady("Blizzard_GroupFinder_VanillaStyle", function()
            local button = LFGMinimapFrame or MiniMapLFGFrame or QueueStatusMinimapButton
            if not button then return end
            local function Update()
                if not Settings().hideMiniLFG then return end
                local queued = C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
                if queued then button:Show() else button:Hide() end
            end
            if button.HookScript then button:HookScript("OnEvent", Update) end
            Update()
        end)
    end
end

function M:Refresh()
    self:ApplySquareMinimap()
end

function M:Init()
    ApplyHitIndicators()
    ApplyZoneAnnouncements()
    ApplyActionButtonText()
    ApplyRaidLabels()
    ApplyRaidToggle()
    ApplyQuestLevels()
    ApplyMinimapElements()
end
