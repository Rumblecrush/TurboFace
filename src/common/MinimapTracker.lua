local _, ns = ...

-- =============================================================================
-- TurboFace Minimap Tracking Icon
-- A TurboFace-owned replacement for Blizzard's minimap tracking indicator
-- (the little icon that shows Find Herbs / Find Minerals / a hunter tracking).
--
--   * Shows the active tracking texture through ns.API, using the client
--     compatibility boundary to resolve modern or legacy tracking surfaces.
--   * When nothing is tracked, shows a dimmed/desaturated placeholder so you
--     notice tracking dropped (e.g. after a death) -- optional.
--   * Size / border+background / opacity options in the QoL tab.
--   * Position, hide, and click-through via the mover system ("TrackingIcon").
--   * Optionally hides Blizzard's own MiniMapTracking button (replaces the
--     third-party minimap-hiding options).
--
-- Display-only: Classic Era tracking is toggled by casting the skill, so the
-- icon deliberately has no click behavior and stays mouse-transparent.
-- =============================================================================

local TR = {}
ns.Tracker = TR

local GetTrackingTexture = ns.API.GetTrackingTexture
local CreateFrame        = CreateFrame
local hooksecurefunc     = hooksecurefunc
local tonumber           = tonumber
local math_max           = math.max

-- Guaranteed-in-era icon for the "nothing tracked" placeholder (the vanilla
-- tracking-ability icon).
local PLACEHOLDER_TEXTURE = "Interface\\Icons\\Ability_Tracking"

local frame       -- the mover target / icon holder
local icon        -- the tracking texture
local backdrop    -- shared-style border+background frame (1px larger)
local eventFrame
local blizzHooked = false
local blizzSuppressed = false

-- ---------------------------------------------------------------------------
-- DB helpers (flat tracker* keys, defaults in Core/Config.lua)
-- ---------------------------------------------------------------------------

local function Enabled()
    local on = ns.Opt("trackerEnabled", true) ~= false
    return ns.MoverDependentEnabled(on)
end

-- ---------------------------------------------------------------------------
-- Blizzard tracking button (MinimapCluster.Tracking.Button on modern UI;
-- legacy MiniMapTracking globals on older clients). Hidden via a Show post-hook so Blizzard re-showing it
-- on tracking changes doesn't bring it back.
-- ---------------------------------------------------------------------------
local function BlizzButton()
    local parts = ns.API.GetMinimapParts()
    return parts and parts.trackingButton
end

local function HideBlizzWanted()
    return Enabled() and ns.Opt("trackerHideBlizzard", true)
end

local function ApplyBlizzard()
    local blizz = BlizzButton()
    if not blizz then return end
    if HideBlizzWanted() then
        if not blizzHooked then
            blizzHooked = true
            hooksecurefunc(blizz, "Show", function(self)
                if HideBlizzWanted() then self:Hide() end
            end)
        end
        blizzSuppressed = true
        blizz:Hide()
    elseif blizzSuppressed then
        -- Only restore state TurboFace actually suppressed this session.
        blizzSuppressed = false
        if GetTrackingTexture and GetTrackingTexture() then blizz:Show() end
    end
end

-- ---------------------------------------------------------------------------
-- Mover integration (mirrors NetWorth.lua)
-- ---------------------------------------------------------------------------
local function FallbackPoint()
    -- Just left of the default minimap spot.
    return { "TOPRIGHT", UIParent, "TOPRIGHT", -200, -35 }
end

function TR:GetFrame()
    return frame
end

function TR:GetChildren()
    return frame and { frame } or {}
end

function TR:RegisterMover()
    if not frame or not ns.Movers or not ns.Movers.RegisterElement then return end
    local fallback = FallbackPoint()
    ns.Movers:RegisterElement("TrackingIcon", frame, {
        label = "Tracking Icon",
        overlayWidth = (frame.GetWidth and frame:GetWidth()) or 20,
        overlayHeight = (frame.GetHeight and frame:GetHeight()) or 20,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        getChildren = function() return TR:GetChildren() end,
        onApply = function() TR:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("TrackingIcon") end
end

-- ---------------------------------------------------------------------------
-- Layout / styling
-- ---------------------------------------------------------------------------
local function ApplyStyle()
    if not frame then return end

    local size = math_max(10, tonumber(ns.Opt("trackerSize", 20)) or 20)
    frame:SetSize(size, size)
    frame:SetAlpha(ns.Clamp and ns.Clamp(ns.Opt("trackerAlpha", 1), 0.1, 1)
                   or (ns.Opt("trackerAlpha", 1)))

    if ns.Opt("trackerBorder", true) then
        if not backdrop then
            backdrop = BackdropTemplateMixin
                and CreateFrame("Frame", nil, frame, "BackdropTemplate")
                or  CreateFrame("Frame", nil, frame)
            backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
            backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
            backdrop:SetFrameLevel(math_max(0, frame:GetFrameLevel() - 1))
            ns:ApplyBarBackdrop(backdrop)
        end
        backdrop:Show()
    elseif backdrop then
        backdrop:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
function TR:Update()
    if not frame or not icon then return end

    if not Enabled() then
        frame:Hide()
        return
    end

    local tex = GetTrackingTexture and GetTrackingTexture()
    if tex then
        icon:SetTexture(tex)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 1)
        frame:Show()
    elseif ns.Opt("trackerShowInactive", true) then
        -- Dimmed placeholder: a reminder that tracking dropped (deaths clear it).
        icon:SetTexture(PLACEHOLDER_TEXTURE)
        if icon.SetDesaturated then icon:SetDesaturated(true) end
        icon:SetVertexColor(0.6, 0.6, 0.6, 0.5)
        frame:Show()
    else
        frame:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Init / Refresh
-- ---------------------------------------------------------------------------
local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    ns.API.RegisterEvent(eventFrame, "MINIMAP_UPDATE_TRACKING")
    ns.API.RegisterEvent(eventFrame, "SPELLS_CHANGED")
    ns.API.RegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD")
end

function TR:Init()
    if frame or not Enabled() then return end

    frame = CreateFrame("Frame", "TurboFaceTrackingIcon", UIParent)
    frame:SetSize(20, 20)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
    local p = FallbackPoint()
    frame:SetPoint(p[1], p[2], p[3], p[4], p[5])

    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- square-crop like aura icons

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function()
        TR:Update()
        ApplyBlizzard()
    end)

    self:Refresh()
end

function TR:Refresh()
    if not frame then
        -- If the feature is effectively disabled, still hand Blizzard's
        -- tracking button back in case TurboFace owned it earlier this session.
        ApplyBlizzard()
        if Enabled() then self:Init() end
        return
    end

    local active = Enabled()
    SetEvents(active)
    ApplyStyle()
    ApplyBlizzard()

    if active then
        self:RegisterMover()
    end
    self:Update()
    if not active and ns.Movers and ns.Movers.UpdateOverlay then
        ns.Movers:UpdateOverlay("TrackingIcon")
    end
end