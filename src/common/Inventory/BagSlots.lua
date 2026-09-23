local _, ns = ...

-- =============================================================================
-- TurboFace Free Bag Slots display
-- Shows only the number of empty slots across the backpack and equipped bags.
-- The feature is standalone from InventoryManager. Movers may reposition/hide
-- it when enabled, but the counter still works at its fallback point without
-- the Movers runtime.
-- =============================================================================

local BS = {}
ns.BagSlots = BS

local CreateFrame = CreateFrame
local tostring = tostring
local tonumber = tonumber
local NUM_BAGS = _G.NUM_BAG_SLOTS or 4
local API = ns.API

local display
local eventFrame
local mainText
local vendorIcon

local FALLBACK_POINT = { "TOPLEFT", UIParent, "TOPLEFT", 0, -62 }

local function Enabled()
    return TurboFaceDB and TurboFaceDB.bagSlotsEnabled == true
end

local function MoverHidden()
    -- Hidden is a Movers-owned preference. If the Movers framework itself is
    -- disabled, the standalone counter should remain usable at its fallback.
    -- NOTE: BagSlots is deliberately mover-INTEGRATED but not mover-DEPENDENT
    -- (it has FALLBACK_POINT), so it must not use ns.MoverDependentEnabled.
    if not ns.MoversEnabled() then return false end
    local movers = TurboFaceDB and TurboFaceDB.movers
    local elements = movers and movers.elements
    local db = elements and elements.BagSlots
    return db and db.hidden == true
end

local function CountFreeSlots()
    local total = 0
    local getFree = API and API.GetContainerNumFreeSlots
    if not getFree then return total end

    for bag = 0, NUM_BAGS do
        local free = getFree(bag)
        total = total + (tonumber(free) or 0)
    end
    return total
end

local function ApplyFont()
    if not mainText then return end
    if ns.StyleFont then ns:StyleFont(mainText, nil, 18, nil, "SHADOW") end
    mainText:SetTextColor(1, 1, 1, 1)
end

function BS:GetFrame()
    return display
end

function BS:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("BagSlots", display, {
        label = "Free Bag Slots",
        overlayWidth = 48,
        overlayHeight = 20,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = FALLBACK_POINT,
        getChildren = function() return { display } end,
        onApply = function() BS:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("BagSlots") end
end

function BS:Update()
    if not display then return end
    if not Enabled() or MoverHidden() then
        display:Hide()
        return
    end

    local value = tostring(CountFreeSlots())
    mainText:SetText(value)

    -- Center the vendor icon + free-slot number as one compact unit. Reuse
    -- the exact vendor job artwork/crop used by BubbleNameplates.
    local textWidth = mainText:GetStringWidth() or 0
    local iconWidth = vendorIcon and vendorIcon:GetWidth() or 10
    local gap = 1
    local groupWidth = iconWidth + gap + textWidth
    local left = (display:GetWidth() - groupWidth) * 0.5

    if vendorIcon then
        vendorIcon:ClearAllPoints()
        vendorIcon:SetPoint("LEFT", display, "LEFT", left, 0)
        vendorIcon:Show()
    end

    mainText:ClearAllPoints()
    mainText:SetPoint("LEFT", vendorIcon, "RIGHT", gap, 0)

    display:Show()
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function BS:Init()
    if display or not Enabled() then return end

    display = CreateFrame("Frame", "TurboFaceBagSlots", UIParent)
    display:SetSize(48, 20)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)

    vendorIcon = display:CreateTexture(nil, "OVERLAY")
    vendorIcon:SetSize(16, 16)
    vendorIcon:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
    vendorIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mainText = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainText:SetJustifyH("LEFT")

    ApplyFont()

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function()
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("Inventory/BagSlots:Update", BS.Update, BS)
        else
            BS:Update()
        end
    end)

    self:Refresh()
end

function BS:Refresh()
    if not display then
        if Enabled() then self:Init() end
        return
    end

    local active = Enabled()
    SetEvents(active)
    ApplyFont()

    if active then
        self:RegisterMover()
        self:Update()
    else
        display:Hide()
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("BagSlots") end
    end
end

ns.RegisterCPUProfileTarget("Inventory/BagSlots:Update", BS.Update)
