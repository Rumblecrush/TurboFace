local _, ns = ...

-- TurboFace presentation hook for the optional UnstuckSkips addon.
-- UnstuckSkips remains the sole owner of target selection and route data;
-- this module calls its notifier's public UpdateTarget method and displays the
-- resulting text in a compact TurboFace/Hearthstone-style row.
local US = {}
ns.UnstuckSkipVisual = US

local CreateFrame = CreateFrame
local math_ceil, math_floor, math_max = math.ceil, math.floor, math.max
local string_format = string.format
local type, pcall = type, pcall
local _G = _G

local COOLDOWN_SECONDS = 4 * 60 * 60
local UPDATE_INTERVAL = 1.0
local FALLBACK_POINT = { "CENTER", UIParent, "CENTER", 0, -280 }

local display, statusText, targetText, usedCheck, eventFrame
local cadenceActive, nativeFrame
local cadenceKey = {}
local lastWidth, lastHeight

local function DB() return ns.DB() end

local function Enabled()
    return ns.MoverDependentEnabled(DB().unstuckSkipVisualEnabled == true)
end

local function MoverVisible()
    local movers = DB().movers
    local elements = type(movers) == "table" and movers.elements
    local entry = type(elements) == "table" and elements.UnstuckSkips
    return type(entry) ~= "table" or (entry.enabled ~= false and entry.hidden ~= true)
end

local function WallNow()
    local now
    if GetServerTime then now = tonumber(GetServerTime()) end
    if not now and time then now = tonumber(time()) end
    return now or 0
end

local function CharacterStore()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.unstuckSkip) ~= "table" then
        TurboFaceCharDB.unstuckSkip = {}
    end
    return TurboFaceCharDB.unstuckSkip
end

function US:GetRemaining()
    local store = CharacterStore()
    local readyAt = tonumber(store.readyAt)
    if not readyAt then return 0 end
    local remaining = readyAt - WallNow()
    if remaining <= 0 then
        store.readyAt = nil
        return 0
    end
    return remaining
end

function US:MarkUsed()
    CharacterStore().readyAt = WallNow() + COOLDOWN_SECONDS
    self:Update()
end

function US:ClearTimer()
    CharacterStore().readyAt = nil
    self:Update()
end

local function FindNativeFrame()
    local frame = _G.UnstuckSkipsFrame
    if frame and type(frame.UpdateTarget) == "function"
        and frame.text and type(frame.text.GetText) == "function" then
        nativeFrame = frame
        return frame
    end
end

local function RestoreNativeNotifier()
    local frame = nativeFrame or FindNativeFrame()
    if not frame then return end
    local settings = _G.unstuck_skip_settings
    if type(settings) ~= "table" or settings.show_unstuck_skip_notifier ~= false then
        if frame.Show then frame:Show() end
    end
end

local function TargetName(frame)
    local ok = pcall(frame.UpdateTarget, frame)
    local value = ok and frame.text:GetText()
    if frame.Hide then frame:Hide() end
    if type(value) == "string" and value ~= "" and value ~= "UnstuckSkip Target" then
        return value
    end
    return "Unknown"
end

local function FormatRemaining(seconds)
    seconds = math_max(0, math_ceil(tonumber(seconds) or 0))
    local hours = math_floor(seconds / 3600)
    local minutes = math_floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string_format("%d:%02d:%02d", hours, minutes, secs)
end

local function SetCadence(active)
    active = active == true
    if cadenceActive == active then return end
    cadenceActive = active
    if not ns.Cadence then return end
    if active then
        ns.Cadence:Add(cadenceKey, UPDATE_INTERVAL, function() US:Update() end, false)
    else
        ns.Cadence:Remove(cadenceKey)
    end
end

local function ApplyCheckInteraction(edb, elementEnabled)
    if not usedCheck then return end
    local interactive = elementEnabled ~= false and Enabled()
        and FindNativeFrame() ~= nil and not (edb and edb.hidden == true)
    if usedCheck.EnableMouse then usedCheck:EnableMouse(interactive) end
    if usedCheck.SetMouseClickEnabled then usedCheck:SetMouseClickEnabled(interactive) end
    if usedCheck.SetMouseMotionEnabled then usedCheck:SetMouseMotionEnabled(interactive) end
end

function US:GetFrame() return display end
function US:GetChildren()
    if usedCheck then return { display, usedCheck } end
    return display and { display } or {}
end

function US:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("UnstuckSkips", display, {
        label = "UnstuckSkips",
        overlayWidth = (display.GetWidth and display:GetWidth()) or 260,
        overlayHeight = (display.GetHeight and display:GetHeight()) or 20,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = FALLBACK_POINT,
        getChildren = function() return US:GetChildren() end,
        isAvailable = function() return FindNativeFrame() ~= nil end,
        onApply = function(_, edb, elementEnabled)
            US:Update()
            ApplyCheckInteraction(edb, elementEnabled)
        end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("UnstuckSkips") end
end

local function ResizeDisplay(width, height)
    if not display or (width == lastWidth and height == lastHeight) then return end
    lastWidth, lastHeight = width, height
    display:SetSize(width, height)
    US:RegisterMover()
end

function US:Update()
    if not display then return end
    local frame = FindNativeFrame()
    if not Enabled() or not frame then
        SetCadence(false)
        display:Hide()
        if not Enabled() then RestoreNativeNotifier() end
        return
    end
    if not MoverVisible() then
        SetCadence(false)
        display:Hide()
        if frame.Hide then frame:Hide() end
        return
    end

    local remaining = self:GetRemaining()
    if remaining > 0 then
        statusText:SetText(FormatRemaining(remaining))
        statusText:SetTextColor(1, 1, 1)
        usedCheck:SetChecked(true)
    else
        statusText:SetText("Ready")
        statusText:SetTextColor(0, 1, 0)
        usedCheck:SetChecked(false)
    end

    targetText:SetText("|cffffd100UnstuckSkip:|r " .. TargetName(frame))

    local statusW = statusText:GetStringWidth() or 35
    local targetW = targetText:GetStringWidth() or 130
    local checkW = usedCheck:GetWidth() or 18
    local textH = math.max(statusText:GetStringHeight() or 14, targetText:GetStringHeight() or 14)
    local height = math.max(textH, usedCheck:GetHeight() or 18) + 6
    ResizeDisplay(4 + statusW + 7 + targetW + 5 + checkW + 4, math.max(20, height))
    ApplyCheckInteraction(nil, true)
    if display:IsShown() ~= true then display:Show() end
    SetCadence(true)
end

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "TurboFaceUnstuckSkips", UIParent)
    display:SetSize(260, 20)
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])

    statusText = display:CreateFontString(nil, "OVERLAY")
    statusText:SetPoint("LEFT", display, "LEFT", 4, 0)
    statusText:SetJustifyH("RIGHT")

    targetText = display:CreateFontString(nil, "OVERLAY")
    targetText:SetPoint("LEFT", statusText, "RIGHT", 7, 0)
    targetText:SetJustifyH("LEFT")

    usedCheck = CreateFrame("CheckButton", nil, display, "UICheckButtonTemplate")
    usedCheck:SetSize(18, 18)
    usedCheck:SetPoint("LEFT", targetText, "RIGHT", 5, 0)
    usedCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then US:MarkUsed() else US:ClearTimer() end
    end)
    usedCheck:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Track Unstuck service cooldown", 1, 0.82, 0)
        GameTooltip:AddLine("Check this immediately after using Blizzard's Unstuck service. TurboFace starts a four-hour real-time estimate, including time spent logged out. Uncheck to clear it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    usedCheck:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    ns:StyleFeatureFont(statusText, DB().unstuckSkipFontSize or 12, "unstuckSkipFont", "unstuckSkipTextStyle")
    ns:StyleFeatureFont(targetText, DB().unstuckSkipFontSize or 12, "unstuckSkipFont", "unstuckSkipTextStyle")
    return display
end

local function OnEvent(_, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "UnstuckSkips" then return end
    nativeFrame = nil
    US:Refresh()
end

function US:Refresh()
    if not DB().unstuckSkipVisualEnabled then
        SetCadence(false)
        if display then display:Hide() end
        RestoreNativeNotifier()
        return
    end

    EnsureDisplay()
    ns:StyleFeatureFont(statusText, DB().unstuckSkipFontSize or 12, "unstuckSkipFont", "unstuckSkipTextStyle")
    ns:StyleFeatureFont(targetText, DB().unstuckSkipFontSize or 12, "unstuckSkipFont", "unstuckSkipTextStyle")
    self:RegisterMover()
    self:Update()
end

function US:Init()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    self:Refresh()
end
