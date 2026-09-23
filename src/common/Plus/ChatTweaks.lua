local _, ns = ...

-- TurboFace Plus: compact chat presentation helpers.  These operate only on
-- Blizzard chat frames and are installed once when their reload-applied option
-- is enabled.

local M = {}
ns.PlusChat = M

local function Settings()
    return ns.PlusSettings()
end

local function EachChatFrame(fn)
    ns.API.ForEachChatFrame(function(frame)
        local name = frame and frame.GetName and frame:GetName()
        fn(frame, name)
    end)
end

local temporaryWindowHooked = false
local temporaryWindowCallbacks = {}
local function RegisterTemporaryWindowCallback(callback)
    temporaryWindowCallbacks[callback] = true
    if temporaryWindowHooked or type(FCF_OpenTemporaryWindow) ~= "function" then return end
    temporaryWindowHooked = true
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        local frame = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
        for fn in pairs(temporaryWindowCallbacks) do fn(frame) end
    end)
end

local function AddOutline(frame)
    if not frame or not frame.GetFont or not frame.SetFont then return end
    local file, size, flags = frame:GetFont()
    if not file or not size then return end
    flags = flags or ""
    if flags:find("OUTLINE", 1, true) then return end
    frame:SetFont(file, size, flags == "" and "OUTLINE" or (flags .. ",OUTLINE"))
end

local function ApplyOutline()
    if not Settings().chatTextOutline then return end
    EachChatFrame(AddOutline)
    RegisterTemporaryWindowCallback(function(frame)
        if Settings().chatTextOutline then AddOutline(frame) end
    end)
end

local function Unclamp(frame)
    if not frame then return end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
    if frame.SetClampRectInsets then frame:SetClampRectInsets(0, 0, 0, 0) end
end

local function ApplyUnclamp()
    if not Settings().unclampChat then return end
    EachChatFrame(Unclamp)
    RegisterTemporaryWindowCallback(function(frame)
        if Settings().unclampChat then Unclamp(frame) end
    end)
    if type(FloatingChatFrame_UpdateBackgroundAnchors) == "function" then
        hooksecurefunc("FloatingChatFrame_UpdateBackgroundAnchors", function(frame)
            if Settings().unclampChat then Unclamp(frame) end
        end)
    end
end

local function DisableFade(frame)
    if frame and frame.SetFading then frame:SetFading(false) end
end

local function ApplyNoFade()
    if not Settings().noChatFade then return end
    EachChatFrame(DisableFade)
    RegisterTemporaryWindowCallback(function(frame)
        if Settings().noChatFade then DisableFade(frame) end
    end)
end

local hiddenButtonParent
local function HiddenParent()
    if not hiddenButtonParent then
        hiddenButtonParent = CreateFrame("Frame")
        hiddenButtonParent:Hide()
    end
    return hiddenButtonParent
end

local function HideWidget(widget)
    if not widget then return end
    if widget.SetParent then widget:SetParent(HiddenParent()) end
    if widget.Hide then widget:Hide() end
end

local function ConfigureMouseWheel(frame)
    if not frame then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsControlKeyDown() then self:ScrollToTop()
            elseif IsShiftKeyDown() then self:PageUp()
            else self:ScrollUp() end
        else
            if IsControlKeyDown() then self:ScrollToBottom()
            elseif IsShiftKeyDown() then self:PageDown()
            else self:ScrollDown() end
        end
    end)
end

local function HideFrameButtons(frame, name)
    if not frame or not name then return end
    HideWidget(_G[name .. "ButtonFrameUpButton"])
    HideWidget(_G[name .. "ButtonFrameDownButton"])
    HideWidget(_G[name .. "MinimizeButton"])
    local buttonFrame = _G[name .. "ButtonFrame"]
    if buttonFrame and buttonFrame.SetSize then buttonFrame:SetSize(0.1, 0.1) end
    local bottom = _G[name .. "ButtonFrameBottomButton"]
    if bottom and bottom.SetSize then bottom:SetSize(0.1, 0.1) end
    ConfigureMouseWheel(frame)
end

local function ApplyNoButtons()
    if not Settings().noChatButtons then return end
    HideWidget(ChatFrameMenuButton)
    HideWidget(ChatFrameChannelButton)
    if FriendsMicroButton and FriendsMicroButton.Hide then FriendsMicroButton:Hide() end
    EachChatFrame(HideFrameButtons)
    RegisterTemporaryWindowCallback(function(frame)
        if not Settings().noChatButtons or not frame then return end
        local name = frame.GetName and frame:GetName()
        HideFrameButtons(frame, name)
    end)
end

local function ApplyNoCombatLog()
    if not Settings().noCombatLogTab then return end
    local tab = ChatFrame2Tab
    if not tab then return end
    if ChatFrame2 and not ChatFrame2.isDocked then
        C_Timer.After(1, function() ns:Chat("Plus", "Combat log cannot be hidden while undocked.") end)
        return
    end

    local function CollapseTab()
        if not Settings().noCombatLogTab or not tab then return end
        if tab.EnableMouse then tab:EnableMouse(false) end
        if tab.SetText then tab:SetText(" ") end
        if tab.SetScale then tab:SetScale(0.01) end
        if tab.SetSize then tab:SetSize(0.01, 0.01) end
    end

    local frame = CreateFrame("Frame")
    ns.API.RegisterEvent(frame, "UPDATE_CHAT_WINDOWS")
    frame:SetScript("OnEvent", CollapseTab)
    if type(FCF_SetTabPosition) == "function" then
        hooksecurefunc("FCF_SetTabPosition", function()
            if Settings().noCombatLogTab and ChatFrame1Tab then
                tab:ClearAllPoints()
                tab:SetPoint("BOTTOMLEFT", ChatFrame1Tab, "BOTTOMRIGHT", 0, 0)
            end
        end)
    end
    CollapseTab()
end

function M:Init()
    ApplyOutline()
    ApplyUnclamp()
    ApplyNoFade()
    ApplyNoButtons()
    ApplyNoCombatLog()
end

function M:Refresh() end
