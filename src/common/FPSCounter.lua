local _, ns = ...

-- =============================================================================
-- TurboFace FPS Counter
-- Standalone Speedrun HUD. Movers may reposition/hide it, but the counter has a
-- deterministic fallback point and remains usable when the Movers master is off.
-- Hearthstone Batching requires this feature and may append its success estimate.
-- =============================================================================

local FPS = {}
ns.FPSCounter = FPS

local CreateFrame = CreateFrame
local tonumber = tonumber
local math_floor = math.floor
local string_format = string.format

local display
local text

local FALLBACK_POINT = { "TOPLEFT", UIParent, "TOPLEFT", 0, -40 }

local function Enabled()
    return TurboFaceDB and TurboFaceDB.fpsCounterEnabled == true
end

local function MoverHidden()
    -- Hidden is a Movers-owned preference. Disabling Movers returns the counter
    -- to its standalone fallback behavior rather than disabling the feature.
    if not ns.MoversEnabled() then return false end
    local movers = TurboFaceDB and TurboFaceDB.movers
    local elements = movers and movers.elements
    local db = elements and elements.FPSCounter
    return db and db.hidden == true
end

local function ApplyFont()
    if not text then return end
    if ns.StyleFont then ns:StyleFont(text, nil, 14, nil, "SHADOW") end
    text:SetTextColor(1, 1, 1, 1)
end

local function UpdateText()
    if not text then return end
    local fps = 0
    if GetFramerate then fps = tonumber(GetFramerate()) or 0 end
    local value = math_floor(fps + 0.5)

    -- Batching's probability belongs beside FPS because frame interval is one
    -- of the model inputs. Runtime batching itself is gated by this feature.
    local suffix = ""
    local root = TurboFaceDB or {}
    if root.hearthBatchEnabled == true and root.hearthBatchOnFPS ~= false
            and ns.HearthBatch and ns.HearthBatch.SuccessChance then
        local ok, p = pcall(ns.HearthBatch.SuccessChance, ns.HearthBatch)
        if ok and type(p) == "number" then
            local pct = math_floor(p * 100 + 0.5)
            local colour = (pct >= 85) and "ff40ff40" or (pct >= 60) and "ffffd100" or "ffff4040"
            suffix = string_format("  |cff3FC7EBHS|r: |c%s%d%%|r", colour, pct)
        end
    end

    text:SetText(string_format("|cff3FC7EBFPS|r: %4d%s", value, suffix))
end

local function Tick()
    UpdateText()
end

local function EnsureFrame()
    if display then return display end

    display = CreateFrame("Frame", "TurboFaceFPSCounterFrame", UIParent)
    display:SetSize(100, 20)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])
    display:SetFrameStrata("LOW")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)

    text = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", display, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    ApplyFont()

    display:SetScript("OnShow", function(self)
        if ns.Cadence then ns.Cadence:Add(self, 1.0, Tick) end
    end)
    display:SetScript("OnHide", function(self)
        if ns.Cadence then ns.Cadence:Remove(self) end
    end)

    display:Hide()
    return display
end

function FPS:GetFrame()
    return display
end

function FPS:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("FPSCounter", display, {
        label = "FPS Counter",
        overlayWidth = 100,
        overlayHeight = 20,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = FALLBACK_POINT,
        getChildren = function() return { display } end,
        isAvailable = Enabled,
        onApply = function() FPS:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("FPSCounter") end
end

function FPS:Update()
    if not display then return end
    if not Enabled() or MoverHidden() then
        display:Hide()
        return
    end
    UpdateText()
    display:Show()
end

function FPS:Init()
    if display or not Enabled() then return end
    EnsureFrame()
    self:Refresh()
end

function FPS:Refresh()
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
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("FPSCounter") end
    end
end

if ns.RegisterCPUProfileTarget then
    ns.RegisterCPUProfileTarget("FPSCounter:Tick", Tick)
end
