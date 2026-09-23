local _, ns = ...

-- =============================================================================
-- TurboFace Combat/DPSBadge.lua
-- Independent PlayerFrame DPS/HPS badge.  Blizzard owns the PlayerFrame and
-- level text; TurboFace owns only this independent UIParent overlay surface.
--
-- The historical unitframes.showPlayerDPS/playerDPSColor/playerHPSColor saved
-- paths are retained for profile compatibility.  Runtime ownership does NOT
-- inherit the Unit Frames module gate.
-- =============================================================================

local Badge = {}
ns.DPSBadge = Badge

local DB = ns.DB
local PLAYER_DPS_BADGE_OFFSET_X = 44
local PLAYER_DPS_STALE_AFTER = 30
local PLAYER_DPS_REFRESH = 0.25
local LEVEL_BADGE_RING_TEXTURE = "Interface\\CharacterFrame\\TotemBorder"
local LEVEL_BADGE_BG_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BADGE_BG_ALPHA = 0.60
local BADGE_RING_ALPHA = 0.95
-- MEDIUM keeps the badge above the PlayerFrame art/glow and baked combat rows
-- through its UIParent ownership plus level floor, while allowing Blizzard's
-- HIGH/DIALOG menu surfaces to cover it normally.
local BADGE_FRAME_STRATA = "MEDIUM"
local BADGE_FRAME_LEVEL_FLOOR = 100
local MENU_COLOR_SELECTED = "|cff00ffff"
local MENU_COLOR_NORMAL = "|cffffffff"

local frameData
local menuFrame
local eventFrame
local pendingLayout = false

local function Settings()
    local db = DB()
    local uf = db.unitframes or {}
    return db, uf
end

function Badge:Enabled()
    local _, uf = Settings()
    return uf.showPlayerDPS ~= false
end

-- The selected combat-meter provider may ask this separately from any movable
-- window gate. Badge ON means a provider is allowed to maintain the accounting
-- or event state needed to render this independent surface.
function Badge:NeedsCombatData()
    return self:Enabled()
end

local function ResolvePlayerLevelText()
    return PlayerLevelText
        or (PlayerFrame and (PlayerFrame.levelText or PlayerFrame.LevelText))
        or (PlayerFrame and PlayerFrame.PlayerFrameContent
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelText)
end

local function ResolveOwner(levelText)
    if not levelText then return nil end
    return (PlayerStatusTexture and PlayerStatusTexture:GetParent())
        or (PlayerFrameTexture and PlayerFrameTexture:GetParent())
        or PlayerFrame
        or (levelText.GetParent and levelText:GetParent())
end

local function SetTextColor(fontString, color)
    if fontString and color then
        fontString:SetTextColor(ns:Color(color, 1, 1, 1))
    end
end

local function MeterProvider()
    if ns.Providers then return ns.Providers:Get("combatMeter") end
    return ns.CombatMeter
end

local function MeterCall(method, ...)
    local meter = MeterProvider()
    if meter and meter[method] then meter[method](meter, ...) end
end

local function MeterState(method)
    local meter = MeterProvider()
    if not meter or not meter[method] then return nil end
    return meter[method](meter)
end

local MENU = {
    {
        label = "Damage",
        selected = function() return MeterState("GetMetric") ~= "healing" end,
        func = function() MeterCall("SetMetric", "damage") end,
    },
    {
        label = "Healing",
        selected = function() return MeterState("GetMetric") == "healing" end,
        func = function() MeterCall("SetMetric", "healing") end,
    },
    {
        label = "Current",
        selected = function() return MeterState("GetView") ~= "overall" end,
        func = function() MeterCall("SetView", "current") end,
    },
    {
        label = "Overall",
        selected = function() return MeterState("GetView") == "overall" end,
        func = function() MeterCall("SetView", "overall") end,
    },
    {
        label = "Reset",
        func = function() MeterCall("Reset") end,
    },
}

local function EnsureMenu()
    if menuFrame then return menuFrame end
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_CreateInfo then return nil end

    menuFrame = CreateFrame("Frame", "TurboFacePlayerDPSMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menuFrame, function(_, level)
        for i = 1, #MENU do
            local entry = MENU[i]
            local info = UIDropDownMenu_CreateInfo()
            local active = entry.selected and entry.selected() or false
            info.text = (active and MENU_COLOR_SELECTED or MENU_COLOR_NORMAL) .. entry.label .. "|r"
            info.notCheckable = true
            info.func = entry.func
            UIDropDownMenu_AddButton(info, level)
        end
        local info = UIDropDownMenu_CreateInfo()
        info.text = MENU_COLOR_NORMAL .. (CANCEL or "Cancel") .. "|r"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    return menuFrame
end

local function Hide()
    if not frameData then return end
    if GameTooltip and GameTooltip:IsOwned(frameData.frame) then GameTooltip:Hide() end
    frameData.frame:Hide()
end

-- The badge is UIParent-owned for deterministic strata ordering, but visually
-- belongs to PlayerFrame. Mirror the art owner's effective scale so TurboFace's
-- PlayerFrame scale option (or Blizzard UI scale) does not change badge size or
-- its local anchor offset compared with the historical child-frame behavior.
local function SyncOwnerScale(frame, owner)
    if not frame or not owner or not frame.SetScale then return end
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local ownerScale = owner.GetEffectiveScale and owner:GetEffectiveScale() or uiScale
    if not uiScale or uiScale <= 0 then uiScale = 1 end
    if not ownerScale or ownerScale <= 0 then ownerScale = uiScale end
    local wanted = ownerScale / uiScale
    if math.abs((frame._tfOwnerScale or -1) - wanted) > 0.0001 then
        frame:SetScale(wanted)
        frame._tfOwnerScale = wanted
    end
end

local function EnsureFrame()
    if frameData then return frameData end
    local levelText = ResolvePlayerLevelText()
    local owner = ResolveOwner(levelText)
    if not levelText or not owner or not owner.CreateTexture then return nil end

    -- Preserve the existing conservative first-creation rule around PlayerFrame
    -- anchoring. The badge itself is unprotected/UIParent-owned, but first layout
    -- still waits until combat ends if the surface does not yet exist.
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        return nil
    end

    -- Keep the badge out of Blizzard's PlayerFrame render hierarchy entirely.
    -- The baked combat rows are also UIParent-owned, so making the badge a true
    -- UIParent sibling gives frame strata/level deterministic meaning. A child
    -- of the Blizzard art owner can remain effectively trapped in that parent's
    -- render order even after SetFrameStrata("HIGH"), which live validation
    -- exposed in 0.15.31. MEDIUM is intentional: the level floor wins over the
    -- PlayerFrame presentation without escaping above Blizzard menu strata.
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata(BADGE_FRAME_STRATA)
    frame:SetFrameLevel(BADGE_FRAME_LEVEL_FLOOR)
    frame:SetSize(32, 32)
    SyncOwnerScale(frame, owner)
    frame:Hide()
    frame:EnableMouse(true)

    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            local menu = EnsureMenu()
            if not menu or not ToggleDropDownMenu then return end
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
            if DropDownList1 then
                DropDownList1:SetFrameStrata("TOOLTIP")
                DropDownList1:SetFrameLevel(600)
            end
            return
        end
        if button ~= "LeftButton" then return end
        local meter = MeterProvider()
        if meter and meter.CanToggleDisplay and meter:CanToggleDisplay() and meter.ToggleDisplay then
            meter:ToggleDisplay()
        end
    end)

    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMRIGHT", GameTooltipDefaultContainer or UIParent,
            "BOTTOMRIGHT", -13, 93)
        local meter = MeterProvider()
        local view = meter and meter.GetView and meter:GetView()
        local metric = meter and meter.GetMetric and meter:GetMetric()
        GameTooltip:AddLine(string.format("%s %s",
            view == "overall" and "Overall" or "Current",
            metric == "healing" and "HPS" or "DPS"))
        local hint = meter and meter.GetBadgeTooltipHint and meter:GetBadgeTooltipHint()
        if hint then GameTooltip:AddLine(hint, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine("Right-click for options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(LEVEL_BADGE_BG_TEXTURE)
    background:SetSize(24, 24)
    background:SetVertexColor(0, 0, 0, 1)
    background:SetAlpha(BADGE_BG_ALPHA)
    background:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local ring = frame:CreateTexture(nil, "BORDER")
    ring:SetTexture(LEVEL_BADGE_RING_TEXTURE)
    ring:SetSize(32, 32)
    ring:SetVertexColor(0.95, 0.92, 0.75, 1)
    ring:SetAlpha(BADGE_RING_ALPHA)
    ring:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if text.SetWordWrap then text:SetWordWrap(false) end

    frameData = { frame = frame, background = background, ring = ring, text = text, owner = owner }
    return frameData
end

function Badge:GetFrame()
    return frameData and frameData.frame or nil
end

function Badge:Update()
    if not self:Enabled() then
        Hide()
        return
    end

    local badge = frameData or EnsureFrame()
    if not badge then return end
    if PlayerFrame and PlayerFrame.IsVisible and not PlayerFrame:IsVisible() then
        Hide()
        return
    end
    local _, uf = Settings()
    local meter = MeterProvider()
    local metric = meter and meter.GetMetric and meter:GetMetric()
    SetTextColor(badge.text, metric == "healing" and uf.playerHPSColor or uf.playerDPSColor)

    if meter and meter.RenderPlayerRate then meter:RenderPlayerRate(badge.text, PLAYER_DPS_STALE_AFTER)
    else badge.text:SetText("-") end
    badge.frame:Show()
end

local function StartTicker()
    if not ns.Cadence or not Badge:Enabled() then return end
    ns.Cadence:Add(Badge, PLAYER_DPS_REFRESH, function() Badge:Update() end, true)
end

local function StopTicker()
    if ns.Cadence then ns.Cadence:Remove(Badge) end
    Badge:Update()
    if C_Timer and C_Timer.After then
        C_Timer.After(PLAYER_DPS_STALE_AFTER + 0.5, function()
            if Badge:Enabled() then Badge:Update() end
        end)
    end
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Badge:Refresh()
    local enabled = self:Enabled()
    SetEvents(enabled)
    if not enabled then
        if ns.Cadence then ns.Cadence:Remove(self) end
        Hide()
        return
    end

    local badge = frameData or EnsureFrame()
    if not badge then return end
    pendingLayout = false

    local levelText = ResolvePlayerLevelText()
    local owner = ResolveOwner(levelText)
    if not levelText or not owner then
        Hide()
        return
    end

    -- Reassert true top-level ownership and ordering. SetParent is intentionally
    -- defensive for reload-era/profile code paths that may retain a frame built
    -- by an earlier implementation during development.
    if badge.frame.GetParent and badge.frame:GetParent() ~= UIParent and badge.frame.SetParent then
        badge.frame:SetParent(UIParent)
    end
    if badge.frame.SetFrameStrata then badge.frame:SetFrameStrata(BADGE_FRAME_STRATA) end
    if badge.frame.SetFrameLevel then badge.frame:SetFrameLevel(BADGE_FRAME_LEVEL_FLOOR) end
    SyncOwnerScale(badge.frame, owner)
    badge.owner = owner
    badge.frame:ClearAllPoints()
    badge.frame:SetPoint("CENTER", levelText, "CENTER", PLAYER_DPS_BADGE_OFFSET_X, 0)

    local db = DB()
    ns:StyleFont(badge.text, nil, tonumber(db.playerDPSBadgeFontSize) or 9, nil, "SHADOW")

    -- SwingTimers/Castbars initialize before the independent badge.  If a baked
    -- row was already visible, immediately re-place it so it stays on the art
    -- strata and cannot inherit/compete with the badge's HIGH strata.
    if ns.ST and ns.ST.ReanchorPlayer then ns.ST:ReanchorPlayer() end

    self:Update()
    if UnitAffectingCombat and UnitAffectingCombat("player") then StartTicker() else StopTicker() end
end

function Badge:Init()
    eventFrame = eventFrame or CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            StartTicker()
        elseif event == "PLAYER_REGEN_ENABLED" then
            StopTicker()
            if pendingLayout or not frameData then self:Refresh() end
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:Refresh()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if Badge:Enabled() then Badge:Refresh() end end)
            end
        end
    end)
    self:Refresh()
end
