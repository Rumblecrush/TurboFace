local _, ns = ...

-- =============================================================================
-- TurboFace Minimap Button
-- A small TurboFace-owned button that rides the edge of the minimap and gives
-- non-command-line users a way to reach the config and the movers:
--
--   * Left-click  -> open/close the TurboFace config panel (ns:ToggleGUI).
--   * Right-click -> toggle the movers. First right-click unlocks (shows the
--                    cyan mover overlays); the next right-click locks them again
--                    (ns.Movers:ToggleLock).
--   * Drag        -> slide the button around the minimap edge; the angle is
--                    saved in TurboFaceDB (flat minimapButton* keys).
--
-- Not a protected frame, so show/hide/anchor is combat-safe.
--
-- The button is ALWAYS ON and has no enable setting. It used to have one, but
-- sitting in the Speedrun tab next to the minimap TRACKING icon option it read as
-- the same thing and confused people. The button is also the primary way to
-- reach the config panel and the mover lock, so hiding it mostly stranded
-- users. Only the position (minimapButtonAngle) is persisted now.
-- =============================================================================

local MB = {}
ns.MinimapButton = MB

local CreateFrame = CreateFrame
local Minimap     = Minimap
local GameTooltip = GameTooltip
local GetCursorPosition = GetCursorPosition
local math_rad    = math.rad
local math_deg    = math.deg
local math_cos    = math.cos
local math_sin    = math.sin
local atan2       = atan2   -- WoW global (Classic Lua 5.1); math.atan2 also exists
local tonumber    = tonumber

-- Canonical TurboFace branding icon (Blizzard FileID).
local ICON_TEXTURE = 237572

local button   -- the minimap button frame
local dragging = false

-- ---------------------------------------------------------------------------
-- DB helpers (flat minimapButton* keys, defaults in Core/Defaults.lua)
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- Position: ride the edge of the (round) minimap at the saved angle.
-- ---------------------------------------------------------------------------
local function UpdatePosition()
    if not button then return end
    local angle  = math_rad(tonumber(ns.Opt("minimapButtonAngle", 200)) or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math_cos(angle) * radius
    local y = math_sin(angle) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale  = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    local angle = math_deg(atan2(py - my, px - mx)) % 360
    ns.SetOpt("minimapButtonAngle", angle)
    UpdatePosition()
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
local function OnEnter(self)
    if dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ccffTurbo|cffffffffFace|r")
    GameTooltip:AddLine("Left-click: open the config panel", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right-click: toggle movers (unlock / lock)", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

-- ---------------------------------------------------------------------------
-- Clicks
-- ---------------------------------------------------------------------------
local function OnClick(_, mouseButton)
    if mouseButton == "RightButton" then
        -- First right-click unlocks the movers, next locks them again.
        if ns.Movers and ns.Movers.ToggleLock then
            ns.Movers:ToggleLock()
        end
    else
        -- Left-click (default) opens/closes the config panel.
        if ns.ToggleGUI then ns:ToggleGUI() end
    end
end

-- ---------------------------------------------------------------------------
-- Init / Refresh
-- ---------------------------------------------------------------------------
function MB:Init()
    if button then return end
    if not Minimap then return end

    button = CreateFrame("Button", "TurboFaceMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:SetClampedToScreen(false)

    -- Icon (drawn first / underneath the ring).
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- square-crop like aura icons
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon = icon

    -- Standard minimap button border ring (drawn over the icon).
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.overlay = overlay

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", OnLeave)
    button:SetScript("OnDragStart", function(btn)
        dragging = true
        GameTooltip:Hide()
        btn:LockHighlight()
        btn:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(btn)
        dragging = false
        btn:UnlockHighlight()
        btn:SetScript("OnUpdate", nil)
    end)

    self:Refresh()
end

function MB.Refresh()
    if not button then
        MB:Init()
        return
    end
    UpdatePosition()
    button:Show()
end
