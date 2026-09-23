local _, ns = ...

-- =============================================================================
-- TurboFace Hearthstone display
-- Movable status widget showing the current Hearthstone bind location with
-- independently optional cooldown and one-shot innkeeper auto-bind helpers.
--
-- Layout:  [<cooldown>]  Hearth: <bind location>  [<auto-bind checkbox>]
--
-- The optional cooldown uses the shared cadence scheduler at 1 Hz only while
-- the real Hearthstone item cooldown is active. Optional innkeeper automation
-- is event-driven: arming the checkbox makes the next binder gossip
-- select/confirmation happen automatically, then the checkbox clears itself.
-- =============================================================================

local HS = {}
ns.HS = HS

local CreateFrame     = CreateFrame
local GetBindLocation = GetBindLocation
local GetTime         = GetTime
local pcall           = pcall
local math_ceil       = math.ceil
local math_floor      = math.floor
local string_format   = string.format
local type            = type
local ipairs          = ipairs
local _G              = _G

local HEARTHSTONE_ITEM_ID = 6948
local COOLDOWN_INTERVAL    = 1.0
local BINDER_ICON_TYPE     = 5 -- legacy/raw Classic gossip icon type
local BINDER_ICON_PATH     = "Interface/GossipFrame/BinderGossipIcon"

local display, hearthText, cooldownText, autoBindCheck, eventFrame
local lastWidth, lastHeight
local autoBindArmed = false
local cooldownCadenceActive = false
local cooldownCadenceKey = {}

local DB = ns.DB   -- shared root accessor (Config.lua)

local binderIconFileID
if GetFileIDFromPath then
    binderIconFileID = GetFileIDFromPath(BINDER_ICON_PATH)
end

local ConfirmBinder
if C_PlayerInteractionManager and C_PlayerInteractionManager.ConfirmationInteraction
        and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Binder then
    ConfirmBinder = function()
        return C_PlayerInteractionManager.ConfirmationInteraction(Enum.PlayerInteractionType.Binder)
    end
else
    ConfirmBinder = _G.ConfirmBinder
end

local function Enabled()
    local on = DB().hearthEnabled ~= false
    return ns.MoverDependentEnabled(on)
end

local function TimerEnabled()
    return DB().hearthTimerEnabled ~= false
end

local function AutoBindEnabled()
    return DB().hearthAutoBindEnabled ~= false
end

local function Fallback()
    return { "CENTER", UIParent, "CENTER", 0, -250 }
end

local function SetAutoBindChecked(checked)
    autoBindArmed = checked == true
    if autoBindCheck and autoBindCheck.SetChecked then
        autoBindCheck:SetChecked(autoBindArmed)
    end
end

local function ApplyCheckInteraction(edb, elementEnabled)
    if not autoBindCheck then return end
    -- The tiny one-shot checkbox is intentionally interactive even when the
    -- status widget itself is configured click-through. Hidden/disabled mover
    -- states, plus the dedicated Auto-Bind option, suppress it so an invisible
    -- control can never eat clicks.
    local interactive = elementEnabled ~= false and Enabled() and AutoBindEnabled()
        and not (edb and edb.hidden == true)
    if autoBindCheck.EnableMouse then autoBindCheck:EnableMouse(interactive) end
    if autoBindCheck.SetMouseClickEnabled then autoBindCheck:SetMouseClickEnabled(interactive) end
    if autoBindCheck.SetMouseMotionEnabled then autoBindCheck:SetMouseMotionEnabled(interactive) end
end

function HS:GetFrame() return display end
function HS:GetChildren()
    if autoBindCheck then return { display, autoBindCheck } end
    return display and { display } or {}
end

function HS:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    local fallback = Fallback()
    ns.Movers:RegisterElement("Hearthstone", display, {
        label = "Hearthstone",
        overlayWidth = (display.GetWidth and display:GetWidth()) or 180,
        overlayHeight = (display.GetHeight and display:GetHeight()) or 20,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        getChildren = function() return HS:GetChildren() end,
        onApply = function(_, edb, elementEnabled)
            HS:Update()
            ApplyCheckInteraction(edb, elementEnabled)
        end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("Hearthstone") end
end

local function ResizeDisplay(width, height)
    if not display then return end
    if width == lastWidth and height == lastHeight then return end
    lastWidth, lastHeight = width, height
    display:SetSize(width, height)
    -- Re-register so the cyan mover hit area matches the enabled timer/text/check.
    HS:RegisterMover()
end

local function ApplySubfeatureLayout()
    if not display or not cooldownText or not hearthText or not autoBindCheck then return end

    local timerOn = TimerEnabled()
    local bindOn = AutoBindEnabled()

    cooldownText:ClearAllPoints()
    cooldownText:SetPoint("LEFT", display, "LEFT", 4, 0)
    if timerOn then
        cooldownText:Show()
        hearthText:ClearAllPoints()
        hearthText:SetPoint("LEFT", cooldownText, "RIGHT", 7, 0)
    else
        cooldownText:Hide()
        hearthText:ClearAllPoints()
        hearthText:SetPoint("LEFT", display, "LEFT", 4, 0)
    end

    autoBindCheck:ClearAllPoints()
    autoBindCheck:SetPoint("LEFT", hearthText, "RIGHT", 5, 0)
    if bindOn then
        autoBindCheck:Show()
    else
        SetAutoBindChecked(false)
        autoBindCheck:Hide()
        if autoBindCheck.EnableMouse then autoBindCheck:EnableMouse(false) end
    end
end

local function HearthCooldown()
    local startTime, duration, enabled
    if C_Container and C_Container.GetItemCooldown then
        startTime, duration, enabled = C_Container.GetItemCooldown(HEARTHSTONE_ITEM_ID)
    elseif _G.GetItemCooldown then
        startTime, duration, enabled = _G.GetItemCooldown(HEARTHSTONE_ITEM_ID)
    end

    startTime = tonumber(startTime) or 0
    duration = tonumber(duration) or 0
    if enabled == false or enabled == 0 or startTime <= 0 or duration <= 2 then
        return 0
    end

    local remaining = (startTime + duration) - (GetTime and GetTime() or 0)
    return remaining > 0 and remaining or 0
end

local function FormatCooldown(remaining)
    remaining = math_ceil(remaining or 0)
    if remaining < 0 then remaining = 0 end
    local minutes = math_floor(remaining / 60)
    local seconds = remaining - (minutes * 60)
    return string_format("%d:%02d", minutes, seconds)
end

local function SetCooldownCadence(active)
    active = active == true
    if active == cooldownCadenceActive then return end
    cooldownCadenceActive = active

    if not ns.Cadence then return end
    if active then
        ns.Cadence:Add(cooldownCadenceKey, COOLDOWN_INTERVAL, function()
            HS:Update()
        end, false)
    else
        ns.Cadence:Remove(cooldownCadenceKey)
    end
end

local function IsBinderOption(info)
    if not info then return false end
    if info.type == "binder" then return true end

    local icon = info.icon
    if icon == BINDER_ICON_TYPE then return true end
    if binderIconFileID and icon == binderIconFileID then return true end

    local overrideIcon = info.overrideIconID
    if binderIconFileID and overrideIcon == binderIconFileID then return true end
    return false
end

local function SelectBinderOption()
    if not autoBindArmed then return false end

    -- 1.15.9's primary gossip surface. The Binder icon is localized-independent.
    if C_GossipInfo and C_GossipInfo.GetOptions then
        local options = C_GossipInfo.GetOptions()
        if type(options) == "table" then
            for index, info in ipairs(options) do
                if IsBinderOption(info) then
                    if info.gossipOptionID and C_GossipInfo.SelectOption then
                        C_GossipInfo.SelectOption(info.gossipOptionID)
                        return true
                    end
                    if C_GossipInfo.SelectOptionByIndex then
                        C_GossipInfo.SelectOptionByIndex(info.orderIndex or index)
                        return true
                    end
                end
            end
        end
    end

    -- Compatibility fallback for clients/addon shims that still expose the
    -- legacy title/type pairs. The type token "binder" is locale-independent.
    if _G.GetGossipOptions and _G.SelectGossipOption then
        local values = { _G.GetGossipOptions() }
        local optionIndex = 0
        for i = 1, #values, 2 do
            optionIndex = optionIndex + 1
            if values[i + 1] == "binder" then
                _G.SelectGossipOption(optionIndex)
                return true
            end
        end
    end

    return false
end

local binderConfirmScheduled = false

local function AcceptBinderPopup()
    binderConfirmScheduled = false
    if not autoBindArmed then return false end

    -- CONFIRM_BINDER is also consumed by Blizzard's UIParent, which creates the
    -- StaticPopup. Our event frame can run before or after UIParent depending on
    -- registration order, so the reliable path is to defer one frame and click
    -- the popup's real Accept button. StaticPopup_OnClick runs the dialog's
    -- OnAccept (ConfirmBinder) AND dismisses the popup, exactly like a player
    -- click. Calling ConfirmBinder directly can leave the Blizzard popup behind.
    if _G.StaticPopup_Visible and _G.StaticPopup_OnClick then
        local dialogName = _G.StaticPopup_Visible("CONFIRM_BINDER")
        local dialog = dialogName and _G[dialogName]
        if dialog then
            SetAutoBindChecked(false)
            _G.StaticPopup_OnClick(dialog, 1)
            return true
        end
    end

    -- Defensive fallback for a client/UI replacement that does not expose the
    -- stock popup. Prefer Classic's legacy ConfirmBinder when present; only use
    -- the interaction-manager shim when that legacy API is unavailable.
    local confirm = _G.ConfirmBinder or ConfirmBinder
    if not confirm then return false end

    SetAutoBindChecked(false)
    local ok = pcall(confirm)
    if not ok then
        SetAutoBindChecked(true)
        return false
    end
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("CONFIRM_BINDER")
    end
    return true
end

local function ConfirmArmedBind()
    if not autoBindArmed then return false end
    if binderConfirmScheduled then return true end

    -- Let Blizzard finish processing CONFIRM_BINDER and construct the popup
    -- before we answer it. This mirrors TurboFace's proven spirit-healer popup
    -- automation and removes event-order dependence.
    if C_Timer and C_Timer.After then
        binderConfirmScheduled = true
        C_Timer.After(0, AcceptBinderPopup)
        return true
    end

    return AcceptBinderPopup()
end

function HS:Update()
    if not hearthText or not cooldownText or not display then return end

    if not Enabled() then
        SetCooldownCadence(false)
        display:Hide()
        return
    end

    ApplySubfeatureLayout()

    local timerOn = TimerEnabled()
    local remaining = 0
    if timerOn then
        remaining = HearthCooldown()
        if remaining > 0 then
            cooldownText:SetText(FormatCooldown(remaining))
            cooldownText:SetTextColor(1, 1, 1)
        else
            cooldownText:SetText("Ready")
            cooldownText:SetTextColor(0, 1, 0)
        end
    end
    SetCooldownCadence(timerOn and remaining > 0)

    local loc = GetBindLocation and GetBindLocation()
    if loc and loc ~= "" then
        hearthText:SetText("|cffffd100Hearth:|r " .. loc)
    else
        hearthText:SetText("|cffffd100Hearth:|r |cff888888Unknown|r")
    end

    -- Dynamic width keeps the mover target tight to only the enabled pieces.
    local bindOn = AutoBindEnabled()
    local cooldownW = timerOn and (cooldownText:GetStringWidth() or 30) or 0
    local timerGap = timerOn and 7 or 0
    local textW = (hearthText:GetStringWidth() or 80)
    local checkW = bindOn and (autoBindCheck:GetWidth() or 18) or 0
    local checkGap = bindOn and 5 or 0
    local w = 4 + cooldownW + timerGap + textW + checkGap + checkW + 4
    local cooldownH = timerOn and (cooldownText:GetStringHeight() or 14) or 0
    local textH = math.max(cooldownH, hearthText:GetStringHeight() or 14)
    local checkH = bindOn and (autoBindCheck:GetHeight() or 18) or 0
    local h = math.max(textH, checkH) + 6
    ResizeDisplay(w > 80 and w or 80, h > 20 and h or 20)

    if display:IsShown() ~= true then display:Show() end
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then
        SetCooldownCadence(false)
        SetAutoBindChecked(false)
        return
    end

    pcall(eventFrame.RegisterEvent, eventFrame, "HEARTHSTONE_BOUND")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if TimerEnabled() then
        eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    else
        SetCooldownCadence(false)
    end

    if AutoBindEnabled() then
        eventFrame:RegisterEvent("GOSSIP_SHOW")
        pcall(eventFrame.RegisterEvent, eventFrame, "CONFIRM_BINDER")
    else
        SetAutoBindChecked(false)
    end
end

local function OnEvent(_, event, ...)
    if event == "GOSSIP_SHOW" then
        SelectBinderOption()
        return
    end

    if event == "CONFIRM_BINDER" then
        ConfirmArmedBind()
        return
    end

    HS:Update()
end

function HS:Init()
    if display or not Enabled() then return end

    display = CreateFrame("Frame", "TurboFaceHearthstone", UIParent)
    display:SetSize(180, 20)
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)
    local p = Fallback()
    display:SetPoint(p[1], p[2], p[3], p[4], p[5])

    cooldownText = display:CreateFontString(nil, "OVERLAY")
    cooldownText:SetPoint("LEFT", display, "LEFT", 4, 0)
    cooldownText:SetJustifyH("RIGHT")

    hearthText = display:CreateFontString(nil, "OVERLAY")
    hearthText:SetPoint("LEFT", cooldownText, "RIGHT", 7, 0)
    hearthText:SetJustifyH("LEFT")

    autoBindCheck = CreateFrame("CheckButton", nil, display, "UICheckButtonTemplate")
    autoBindCheck:SetSize(18, 18)
    autoBindCheck:SetPoint("LEFT", hearthText, "RIGHT", 5, 0)
    autoBindCheck:SetChecked(false)
    autoBindCheck:SetScript("OnClick", function(self)
        autoBindArmed = self:GetChecked() == true
    end)
    autoBindCheck:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-bind next innkeeper", 1, 0.82, 0)
        GameTooltip:AddLine("One-shot: automatically selects 'Make this inn my home' and accepts the bind confirmation, then turns itself off.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoBindCheck:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)

    self:Refresh()
end

function HS:Refresh()
    if not display then
        if Enabled() then self:Init() end
        return
    end

    local active = Enabled()
    SetEvents(active)
    ApplySubfeatureLayout()
    ns:StyleFeatureFont(cooldownText, DB().hearthFontSize or 12, "hearthFont", "hearthTextStyle")
    ns:StyleFeatureFont(hearthText, DB().hearthFontSize or 12, "hearthFont", "hearthTextStyle")

    if active then
        self:RegisterMover()
        display:Show()
        self:Update()
    else
        display:Hide()
        if autoBindCheck then autoBindCheck:EnableMouse(false) end
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("Hearthstone") end
    end
end
