local _, ns = ...

-- =============================================================================
-- TurboFace Net Worth display
-- Shows your money + the vendor value of junk in your bags, computed by
-- TurboFace's own InventoryManager (ns.Inv) -- no RXPGuides dependency.
-- Positioning, hide, and click-through are handled by the shared mover system.
-- =============================================================================

local NW = {}
ns.NW = NW

local GetMoney      = GetMoney
local CreateFrame   = CreateFrame
local pcall         = pcall
local floor         = math.floor
local tostring      = tostring
local type          = type
local BreakUpLargeNumbers = BreakUpLargeNumbers

local display
local eventFrame
local lastWidth, lastHeight
local fontSize = 14

local labelText
local goldText, silverText, copperText
local goldIcon, silverIcon, copperIcon
local textPieces = {}

local DB = ns.DB   -- shared root accessor (Config.lua), never nil

-- `== true` keeps the opt-in default AND guarantees a real boolean reaches the
-- gate. The previous `TurboFaceDB and ...` form yielded nil when the root did
-- not exist yet, and nil fails OPEN in ns.MoverDependentEnabled.
local function Enabled()
    local on = DB().netWorthEnabled == true
    return ns.MoverDependentEnabled(on)
end

-- ---------------------------------------------------------------------------
-- Net worth = money + vendor value of bag junk, from TurboFace's InventoryManager
-- (pcall-guarded so a missing/early ns.Inv can never error the display).
-- ---------------------------------------------------------------------------
local function ComputeNetWorth()
    if ns.Inv and ns.Inv.GetNetWorth then
        local ok, value = pcall(ns.Inv.GetNetWorth, ns.Inv)
        if ok and type(value) == "number" then
            return value
        end
    end
    return GetMoney() or 0
end

-- ---------------------------------------------------------------------------
-- Mover integration
-- ---------------------------------------------------------------------------
local function LegacyPoint()
    local d = TurboFaceDB or {}
    local point = d.netWorthPoint or "CENTER"
    return { point, UIParent, point, d.netWorthX or 0, d.netWorthY or -220 }
end

local function HasMoverPoint()
    local movers = TurboFaceDB and TurboFaceDB.movers
    local elements = movers and movers.elements
    local edb = elements and elements.NetWorth
    return edb and edb.point ~= nil
end

local function ApplyLegacyPositionIfNeeded()
    if not display or HasMoverPoint() then return end
    local p = LegacyPoint()
    display:ClearAllPoints()
    display:SetPoint(p[1], p[2], p[3], p[4], p[5])
end

function NW:GetFrame()
    return display
end

function NW:GetChildren()
    return display and { display } or {}
end

function NW:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    local fallback = LegacyPoint()
    ns.Movers:RegisterElement("NetWorth", display, {
        label = "Net Worth",
        overlayWidth = (display.GetWidth and display:GetWidth()) or 120,
        overlayHeight = (display.GetHeight and display:GetHeight()) or 20,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        getChildren = function() return NW:GetChildren() end,
        onApply = function() NW:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("NetWorth") end
end

-- ---------------------------------------------------------------------------
-- Text rendering. Each piece is a single FontString; Shadow/Outline/None are
-- carried by the feature-local FontObject assigned in ApplyFont().
-- ---------------------------------------------------------------------------
local function CreateShadowedText(parent)
    local piece = {}

    piece.main = parent:CreateFontString(nil, "OVERLAY")

    -- A newly-created FontString has no font. Set a game-bundled fallback
    -- immediately so any early Update()/SetText() path is always valid; the
    -- configured feature-local Blizzard font is applied later by ApplyFont().
    piece.main:SetFont(ns.DEFAULT_FONT_PATH, fontSize, "")
    piece.main:SetJustifyH("LEFT")

    textPieces[#textPieces + 1] = piece
    return piece
end

local function SetPieceText(piece, text)
    piece.main:SetText(text)
end

local function SetPieceShown(piece, shown)
    if shown then piece.main:Show() else piece.main:Hide() end
end

local function PlacePiece(piece, x)
    piece.main:ClearAllPoints()
    piece.main:SetPoint("LEFT", display, "CENTER", x, 0)
end

local function ApplyFont()
    if not display then return end
    local d = TurboFaceDB
    local path = ns.GetFont(d.netWorthFont)
    fontSize = d.netWorthFontSize or 14

    for i = 1, #textPieces do
        local piece = textPieces[i]
        ns:StyleFont(piece.main, path, fontSize, nil, d.netWorthTextStyle)
    end

    local iconSize = fontSize
    goldIcon:SetSize(iconSize, iconSize)
    silverIcon:SetSize(iconSize, iconSize)
    copperIcon:SetSize(iconSize, iconSize)
end

local function ResizeDisplay(width, height)
    if not display then return end
    if width == lastWidth and height == lastHeight then return end
    lastWidth, lastHeight = width, height
    display:SetSize(width, height)
    NW:RegisterMover()
end

local function FormatGold(value)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

local function PieceWidth(piece)
    return piece.main:GetStringWidth() or 0
end

local function PlaceIcon(texture, x)
    texture:ClearAllPoints()
    texture:SetPoint("LEFT", display, "CENTER", x, 0)
end

function NW:Update()
    if not display or not labelText then return end

    if not Enabled() then
        display:Hide()
        return
    end

    local totalCopper = ComputeNetWorth()
    local gold = floor(totalCopper / 10000)
    local silver = floor(totalCopper / 100) % 100
    local copper = totalCopper % 100

    local showGold = gold > 0
    local showSilver = showGold or silver > 0
    local showLabel = TurboFaceDB.netWorthLabel == true

    SetPieceText(labelText, "NW:")
    SetPieceText(goldText, FormatGold(gold))
    SetPieceText(silverText, tostring(silver))
    SetPieceText(copperText, tostring(copper))

    local c = TurboFaceDB.netWorthColor or { r = 1, g = 0.82, b = 0 }
    labelText.main:SetTextColor(c.r or 1, c.g or 0.82, c.b or 0)
    goldText.main:SetTextColor(1, 1, 1)
    silverText.main:SetTextColor(1, 1, 1)
    copperText.main:SetTextColor(1, 1, 1)

    SetPieceShown(labelText, showLabel)
    SetPieceShown(goldText, showGold)
    if showGold then goldIcon:Show() else goldIcon:Hide() end
    SetPieceShown(silverText, showSilver)
    if showSilver then silverIcon:Show() else silverIcon:Hide() end
    SetPieceShown(copperText, true)
    copperIcon:Show()

    local iconSize = fontSize
    local gap = 3
    local labelGap = 5
    local totalWidth = 0

    if showLabel then
        totalWidth = totalWidth + PieceWidth(labelText) + labelGap
    end
    if showGold then
        totalWidth = totalWidth + PieceWidth(goldText) + 1 + iconSize + gap
    end
    if showSilver then
        totalWidth = totalWidth + PieceWidth(silverText) + 1 + iconSize + gap
    end
    totalWidth = totalWidth + PieceWidth(copperText) + 1 + iconSize

    ResizeDisplay(totalWidth + 12, (fontSize > iconSize and fontSize or iconSize) + 8)

    local x = -totalWidth / 2
    if showLabel then
        PlacePiece(labelText, x)
        x = x + PieceWidth(labelText) + labelGap
    end
    if showGold then
        PlacePiece(goldText, x)
        x = x + PieceWidth(goldText) + 1
        PlaceIcon(goldIcon, x)
        x = x + iconSize + gap
    end
    if showSilver then
        PlacePiece(silverText, x)
        x = x + PieceWidth(silverText) + 1
        PlaceIcon(silverIcon, x)
        x = x + iconSize + gap
    end
    PlacePiece(copperText, x)
    x = x + PieceWidth(copperText) + 1
    PlaceIcon(copperIcon, x)

    if display:IsShown() ~= true then display:Show() end
end

-- Note: junk-mark changes don't move money or bag contents, so ns.Inv calls
-- NW:Update() directly after ToggleJunk / ResetMarks / delete / sell.

-- ---------------------------------------------------------------------------
-- Init / Refresh
-- ---------------------------------------------------------------------------
local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("PLAYER_MONEY")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:RegisterEvent("MERCHANT_CLOSED")
end

function NW:Init()
    if display or not Enabled() then return end

    display = CreateFrame("Frame", "TurboFaceNetWorth", UIParent)
    display:SetSize(120, 20)
    display:SetFrameStrata("MEDIUM")
    if display.SetClampedToScreen then display:SetClampedToScreen(false) end
    display:EnableMouse(false)
    ApplyLegacyPositionIfNeeded()

    labelText = CreateShadowedText(display)
    goldText = CreateShadowedText(display)
    silverText = CreateShadowedText(display)
    copperText = CreateShadowedText(display)

    goldIcon = display:CreateTexture(nil, "OVERLAY")
    ns.API.SetCoinIcon(goldIcon, "gold")
    silverIcon = display:CreateTexture(nil, "OVERLAY")
    ns.API.SetCoinIcon(silverIcon, "silver")
    copperIcon = display:CreateTexture(nil, "OVERLAY")
    ns.API.SetCoinIcon(copperIcon, "copper")

    local function HandleNetWorthEvent(event)
        -- Money-only changes can reuse the cached junk valuation. Bag changes
        -- invalidate it because item contents/counts may have changed.
        if (event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD")
            and ns.Inv and ns.Inv.InvalidateJunkValue then
            ns.Inv:InvalidateJunkValue()
        end
        NW:Update()
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("Inventory/NetWorth:" .. tostring(event), HandleNetWorthEvent, event)
        else
            HandleNetWorthEvent(event)
        end
    end)

    self:Refresh()

    -- Item info may not be cached at the first login tick; a delayed recompute
    -- catches junk values once the client has populated GetItemInfo.
    if ns.After then
        ns.After(2, function() if Enabled() then NW:Update() end end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(2, function() if Enabled() then NW:Update() end end)
    end
end

function NW:Refresh()
    if not display then
        if Enabled() then self:Init() end
        return
    end

    local active = Enabled()
    SetEvents(active)
    ApplyFont()
    ApplyLegacyPositionIfNeeded()

    if active then
        self:RegisterMover()
        display:Show()
        self:Update()
    else
        display:Hide()
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("NetWorth") end
    end
end

ns.RegisterCPUProfileTarget("Inventory/NetWorth:Update", NW.Update)
