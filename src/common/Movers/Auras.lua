local _, ns = ...

-- MoverNameplates/Auras.lua -- player/target aura button layout anchors and growth.
-- Split from Movers.lua (G3 refactor). M is the shared mover module table
-- (ns.Movers); underscore members are family-internal shared helpers.

local M = ns.Movers
local elements = M._elements
local DB = M._DB
local ElementDB = M._ElementDB
local After = ns.After
local IsProtected = M._IsProtected
local FrameWidth = M._FrameWidth
local FrameHeight = M._FrameHeight
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local pairs = pairs
local AuraDB = M._AuraDB
local PointFromCenter = M._PointFromCenter
local math_max = math.max
local math_floor = math.floor

-- Aura-layout state (owned by this file)
local auraApplying = false
local auraButtonHooks = {}

local function EnsureAnchor(name, width, height)
    local f = _G[name]
    if not f then
        f = CreateFrame("Frame", name, UIParent)
        _G[name] = f
    end
    f:SetSize(width or 120, height or 32)
    f:EnableMouse(false)
    f:Show()
    return f
end

local function AnchorFallback(id)
    if id == "TargetBuffs" then
        return PointFromCenter(_G.TargetFrameBuff1) or { "TOPLEFT", _G.TargetFrame or UIParent, "BOTTOMLEFT", 6, -4 }
    elseif id == "TargetDebuffs" then
        return PointFromCenter(_G.TargetFrameDebuff1) or { "TOPLEFT", _G.TurboFaceTargetBuffMoverAnchor or UIParent, "BOTTOMLEFT", 0, -10 }
    elseif id == "ToTDebuffs" then
        -- Not PointFromCenter(TargetFrameToTDebuff1): Blizzard anchors that frame
        -- inside the ToT button's 93x45 footprint, which TurboFace's 98x48 fixed
        -- artwork now overdraws. Default clear of the art's right edge instead,
        -- relative to the ToT so the group follows it until the user drags.
        return { "TOPLEFT", _G.TargetFrameToT or UIParent, "TOPLEFT", 102, -6 }
    end
    return { "CENTER", UIParent, "CENTER", 0, 0 }
end

local function BuildNames(prefix, fromIndex, toIndex, into)
    for i = fromIndex, toIndex do
        into[#into + 1] = prefix .. i
    end
end

-- Player buff/debuff movers removed: 1.15.9's Edit Mode places the player
-- BuffFrame/DebuffFrame natively. AuraStyle.lua still styles the icons.
-- Target auras keep TurboFace movers (Edit Mode has no target-aura option).
local targetBuffNames = {}
BuildNames("TargetFrameBuff", 1, 32, targetBuffNames)

local targetDebuffNames = {}
BuildNames("TargetFrameDebuff", 1, 32, targetDebuffNames)

-- Blizzard's ToT has exactly four debuff slots, declared statically in
-- TargetFrame.xml (TargetofTargetFrameTemplate -> $parentDebuff1..4). There is
-- no lazy creation past 4, so this list is fixed rather than over-allocated
-- like the target lists above.
local totDebuffNames = {}
BuildNames("TargetFrameToTDebuff", 1, 4, totDebuffNames)

local function ButtonSize(button)
    local w = (button.GetWidth and button:GetWidth()) or 32
    local h = (button.GetHeight and button:GetHeight()) or 32
    local s = (button.GetScale and button:GetScale()) or 1
    if not w or w <= 0 then w = 32 end
    if not h or h <= 0 then h = 32 end
    if not s or s <= 0 then s = 1 end
    return w * s, h * s
end

local function PositionAuraButton(button, anchor, index, perRow, spacingX, spacingY, growth)
    if not button or not anchor or not button.ClearAllPoints then return end
    if IsProtected(button) and InCombatLockdown and InCombatLockdown() then return end
    perRow = math_max(1, tonumber(perRow) or 10)
    spacingX = tonumber(spacingX) or 0
    spacingY = tonumber(spacingY) or 0

    local col = (index - 1) % perRow
    local row = math_floor((index - 1) / perRow)
    local bw, bh = ButtonSize(button)
    -- bw/bh and the spacing options are screen-space (anchor-space) pixels, but
    -- SetPoint offsets on a scaled button are interpreted in the BUTTON's own
    -- scaled coordinate space. Divide by the button scale so spacing stays
    -- constant instead of growing with the aura scale option.
    local s = (button.GetScale and button:GetScale()) or 1
    if not s or s <= 0 then s = 1 end
    local x = (col * (bw + spacingX)) / s
    local y = (row * (bh + spacingY)) / s

    if growth == "RIGHT_UP" then
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, y)
    elseif growth == "LEFT_UP" then
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
    elseif growth == "RIGHT_DOWN" then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
    else -- LEFT_DOWN
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -x, -y)
    end
end

local function ApplyAuraButtonOptions(names, hidden, clickThrough)
    for _, name in ipairs(names) do
        local button = _G[name]
        if button then
            if button.SetAlpha then button:SetAlpha(hidden and 0 or 1) end
            if button.EnableMouse then button:EnableMouse((not hidden) and (not clickThrough)) end
        end
    end
end

local function HookAuraButtonPoints(names)
    if not hooksecurefunc then return end
    for _, name in ipairs(names or {}) do
        local button = _G[name]
        if button and not auraButtonHooks[button] and button.SetPoint then
            auraButtonHooks[button] = true
            hooksecurefunc(button, "SetPoint", function()
                if auraApplying or not M.active then return end
                if DB().enabled == false or DB().auraLayout == false then return end
                M:RequestAuraUpdate(true)
            end)
        end
    end
end

local function LayoutAuraList(names, anchor, perRow, spacingX, spacingY, growth, clickThrough, positionAll)
    if not anchor then return end
    local visibleIndex = 1
    for i, name in ipairs(names) do
        local button = _G[name]
        if button and (positionAll or (button.IsShown and button:IsShown())) then
            if button.SetAlpha then button:SetAlpha(1) end
            if button.EnableMouse then button:EnableMouse(not clickThrough) end
            -- positionAll: lay every slot out by its fixed index instead of by
            -- visible order. Blizzard fills a frame set like the ToT debuffs as a
            -- contiguous prefix (1..n), so index order and visible order agree --
            -- but a hidden slot never gets a point under visible-only layout, so
            -- it would pop up at its stock XML anchor the moment it shows. There
            -- is no SetPoint hook to re-flow from either: nothing re-anchors ToT
            -- debuffs after load.
            PositionAuraButton(button, anchor, positionAll and i or visibleIndex,
                perRow, spacingX, spacingY, growth)
            visibleIndex = visibleIndex + 1
        end
    end
end

local function UpdateAuraGroup(self, id, names, perRow, spacingX, spacingY, growth, positionAll)
    local info = elements[id]
    local edb = ElementDB(id)
    if not info or edb.enabled == false then return end

    self:ApplyElement(id)
    if edb.hidden == true then
        ApplyAuraButtonOptions(names, true, true)
        return
    end

    ApplyAuraButtonOptions(names, false, edb.clickThrough == true)
    LayoutAuraList(names, info.frame, perRow, spacingX, spacingY, growth,
        edb.clickThrough == true, positionAll)
end

function M:UpdateAuraLayout()
    local db = DB()
    if db.enabled == false or db.auraLayout == false then return end
    local a = AuraDB()

    if ElementDB("TargetBuffs").enabled ~= false then
        HookAuraButtonPoints(targetBuffNames)
    end
    if ElementDB("TargetDebuffs").enabled ~= false then
        HookAuraButtonPoints(targetDebuffNames)
    end
    if ElementDB("ToTDebuffs").enabled ~= false then
        HookAuraButtonPoints(totDebuffNames)
    end

    auraApplying = true
    UpdateAuraGroup(self, "TargetBuffs", targetBuffNames, a.targetPerRow, a.spacingX, a.spacingY, a.targetBuffGrowth)
    UpdateAuraGroup(self, "TargetDebuffs", targetDebuffNames, a.targetPerRow, a.spacingX, a.spacingY, a.targetDebuffGrowth)
    UpdateAuraGroup(self, "ToTDebuffs", totDebuffNames, 4, a.spacingX, a.spacingY, a.totDebuffGrowth, true)
    auraApplying = false
end

-- Unit-frame movers removed: HUD Edit Mode owns Blizzard unit-frame placement
-- on 1.15.9+. TurboFace still restyles the frames in place (UnitFrames/UnitFrames.lua).
--
-- EXCEPTION: Target of Target keeps its TurboFace mover because Edit Mode
-- exposes a Target option but no separate Target of Target placement.
local function RegisterToTMover(self)
    local frame = _G.TargetFrameToT
    if not frame then return end
    self:RegisterElement("TargetFrameToT", frame, {
        label = "Target of Target",
        overlayWidth = FrameWidth(frame, 120),
        overlayHeight = FrameHeight(frame, 42),
    })
end

local function RegisterAuraMovers(self)
    if ElementDB("TargetBuffs").enabled ~= false then
        local tb = EnsureAnchor("TurboFaceTargetBuffMoverAnchor", 150, 34)
        self:RegisterElement("TargetBuffs", tb, {
            label = "Target Buffs",
            overlayWidth = 150,
            overlayHeight = 34,
            fallbackPoint = AnchorFallback("TargetBuffs"),
            defaultPoint = AnchorFallback("TargetBuffs"),
        })
    end

    if ElementDB("TargetDebuffs").enabled ~= false then
        local td = EnsureAnchor("TurboFaceTargetDebuffMoverAnchor", 150, 34)
        self:RegisterElement("TargetDebuffs", td, {
            label = "Target Debuffs",
            overlayWidth = 150,
            overlayHeight = 34,
            fallbackPoint = AnchorFallback("TargetDebuffs"),
            defaultPoint = AnchorFallback("TargetDebuffs"),
        })
    end

    -- ToT has exactly four debuff slots and TurboFace always lays them out
    -- as one compact row, so size the mover for the full four-icon strip.
    if ElementDB("ToTDebuffs").enabled ~= false then
        local tot = EnsureAnchor("TurboFaceToTDebuffMoverAnchor", 100, 30)
        self:RegisterElement("ToTDebuffs", tot, {
            label = "Target of Target Debuffs",
            overlayWidth = 100,
            overlayHeight = 30,
            fallbackPoint = AnchorFallback("ToTDebuffs"),
            defaultPoint = AnchorFallback("ToTDebuffs"),
        })
    end
end



-- Published for Movers/Systems.lua (Init runs there, after all files load)
M._RegisterAuraMovers = RegisterAuraMovers
M._RegisterToTMover = RegisterToTMover


-- EnsureAnchor is used by Movers/Systems.lua (tooltip/quest-tracker anchors)
M._EnsureAnchor = EnsureAnchor
