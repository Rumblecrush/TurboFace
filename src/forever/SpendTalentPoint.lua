local _, ns = ...

-- =============================================================================
-- TurboFace Spend Talent Point Reminder
-- Standalone Speedrun HUD. This deliberately does not belong to ClassBuffs:
-- talent spending is a route/leveling reminder, not a missing-buff state.
-- =============================================================================

local TPR = {}
ns.TalentPointReminder = TPR

local CreateFrame = CreateFrame
local tonumber = tonumber

local display, text, eventFrame
local refreshSerial = 0
local FALLBACK_POINT = { "CENTER", UIParent, "CENTER", 0, -120 }
local MESSAGE = "SPEND TALENT POINT"

local function DB()
    return ns.DB and ns.DB() or TurboFaceDB or {}
end

local function Enabled()
    return DB().talentReminderEnabled ~= false
end

local function MoverHidden()
    if not ns.MoversEnabled or not ns.MoversEnabled() then return false end
    local movers = DB().movers
    local elements = type(movers) == "table" and movers.elements
    local entry = type(elements) == "table" and elements.SpendTalentPoint
    return type(entry) == "table" and entry.hidden == true
end

local function UnspentPoints()
    if ns.API and ns.API.GetUnspentTalentPoints then
        local points = ns.API.GetUnspentTalentPoints()
        return tonumber(points) or 0
    end
    return 0
end

local function TalentPointState()
    if ns.API and ns.API.GetUnspentTalentPoints then
        local points, source = ns.API.GetUnspentTalentPoints()
        return tonumber(points) or 0, source or "unknown"
    end
    return 0, "missing"
end

local function ApplyFont()
    if not text then return end
    local db = DB()
    if ns.StyleFeatureFont then
        ns:StyleFeatureFont(text, tonumber(db.talentReminderFontSize) or 18,
            "talentReminderFont", "talentReminderTextStyle")
    elseif ns.StyleFont then
        ns:StyleFont(text, db.talentReminderFont, tonumber(db.talentReminderFontSize) or 18,
            nil, db.talentReminderTextStyle or "OUTLINE")
    end
    text:SetTextColor(1, 0.82, 0, 1)
end

local function EnsureFrame()
    if display then return display end

    display = CreateFrame("Frame", "TurboFaceSpendTalentPointFrame", UIParent)
    display:SetSize(240, 26)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)

    text = display:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", display, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText(MESSAGE)
    ApplyFont()

    display:Hide()
    return display
end

function TPR:GetFrame()
    return display
end

function TPR:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("SpendTalentPoint", display, {
        label = "Spend Talent Point",
        overlayWidth = 240,
        overlayHeight = 26,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = FALLBACK_POINT,
        getChildren = function() return { display } end,
        isAvailable = Enabled,
        onApply = function() TPR:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("SpendTalentPoint") end
end

function TPR:Update()
    if not display then return end
    if not Enabled() or MoverHidden() then
        display:Hide()
        return
    end

    -- The warning is state-driven only: mover mode must never synthesize a
    -- talent warning when the character has no point available to spend.
    if UnspentPoints() > 0 then
        text:SetText(MESSAGE)
        display:Show()
    else
        display:Hide()
    end
end

function TPR:Refresh()
    if not display then
        if Enabled() then self:Init() end
        return
    end
    ApplyFont()
    if Enabled() then
        self:RegisterMover()
        self:Update()
    else
        display:Hide()
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("SpendTalentPoint") end
    end
end

local function OnTalentEvent(_, event, unit)
    if event == "UNIT_LEVEL" and unit and unit ~= "player" then return end
    TPR:Update()

    -- PLAYER_LEVEL_UP and modern trait events can precede the refreshed talent
    -- currency state on Forever. Recheck a bounded three times rather than
    -- polling; a later event supersedes stale callbacks from an earlier one.
    if C_Timer and C_Timer.After then
        refreshSerial = refreshSerial + 1
        local serial = refreshSerial
        for _, delay in ipairs({ 0, 0.25, 1.0 }) do
            C_Timer.After(delay, function()
                if serial == refreshSerial then TPR:Update() end
            end)
        end
    end
end

function TPR:Status()
    local points, source = TalentPointState()
    local shown = display and display.IsShown and display:IsShown() or false
    if ns.Chat then
        ns:Chat("Talent", ("points=%s source=%s enabled=%s moverHidden=%s frame=%s shown=%s"):format(
            tostring(points), tostring(source), tostring(Enabled()), tostring(MoverHidden()),
            tostring(display ~= nil), tostring(shown)))
    end
end

function TPR:Init()
    if not Enabled() and not display then return end
    EnsureFrame()
    self:RegisterMover()

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnTalentEvent)
        local register = ns.API and ns.API.RegisterEvent
        if register then
            register(eventFrame, "PLAYER_ENTERING_WORLD")
            register(eventFrame, "CHARACTER_POINTS_CHANGED")
            register(eventFrame, "PLAYER_LEVEL_UP")
            register(eventFrame, "UNIT_LEVEL")
            register(eventFrame, "PLAYER_TALENT_UPDATE")
            register(eventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
            register(eventFrame, "TRAIT_CONFIG_UPDATED")
            register(eventFrame, "TRAIT_NODE_CHANGED")
            register(eventFrame, "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        else
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
            eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        end
    end

    self:Update()
end
