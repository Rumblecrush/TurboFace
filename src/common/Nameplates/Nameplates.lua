local _, ns = ...

-- ns.NP: shared internals for the Blizzard-native nameplate augmentation family.
-- Cross-file functions/state are published here; each file aliases only what it
-- needs. Blizzard 1.15.9 is the sole baseline renderer/substrate.
local NP = {}
ns.NP = NP

-- Classic Era has five combo-point slots. Publish this on the shared nameplate
-- substrate so split augmentation files never depend on an undeclared global or
-- load-order side effect.
NP.MAX_CP = 5

-- Event-driven nameplate system - no OnUpdate polling

-- Cached globals used by this substrate/augmentation boundary.
local UnitGUID = ns.API.ReadUnitGUID
local C_NamePlate = C_NamePlate

-- EnumerateActiveNamePlates -> C_NamePlate.GetNamePlates() in Classic Era
-- GetNamePlateSize -> read nameplateWidth/nameplateHeight CVars directly in Classic Era


local PixelUtil = PixelUtil

local db

-- Forward declarations for throttle tables (defined later, needed for zone cleanup)
local dirtyHealth = {}; NP.dirtyHealth = dirtyHealth
local dirtyAbsorb = {}; NP.dirtyAbsorb = dirtyAbsorb
local dirtyThreat = {}; NP.dirtyThreat = dirtyThreat

-- =============================================================================
-- SHARED TEXTURE BORDER SYSTEM
-- Uses 4 separate textures (top, bottom, left, right) for pixel-perfect borders
-- =============================================================================
local BORDER_TEX = "Interface\\Buttons\\WHITE8X8"
local BORDER_ALPHA = 0.6  -- Prevents 1px dropout in 3.3.5

-- Shared border methods
local BorderMethods = {}
BorderMethods.__index = BorderMethods

function BorderMethods:SetColor(r, g, b, a, forceAlpha)
    -- Clamp alpha to BORDER_ALPHA max to maintain anti-dropout behavior (unless forced)
    if not forceAlpha then
        a = a and math.min(a, BORDER_ALPHA) or BORDER_ALPHA
    end
    self.top:SetVertexColor(r, g, b, a or 1)
    self.bottom:SetVertexColor(r, g, b, a or 1)
    self.left:SetVertexColor(r, g, b, a or 1)
    self.right:SetVertexColor(r, g, b, a or 1)
end

function BorderMethods:Show()
    self.top:Show()
    self.bottom:Show()
    self.left:Show()
    self.right:Show()
end

function BorderMethods:Hide()
    self.top:Hide()
    self.bottom:Hide()
    self.left:Hide()
    self.right:Hide()
end

function BorderMethods:GetColor()
    return self.top:GetVertexColor()
end

function BorderMethods:UpdateScale(parent, thickness)
    thickness = thickness or 1
    local pixelSize = PixelUtil.GetNearestPixelSize(thickness, parent:GetEffectiveScale(), 1)

    -- Update top edge
    self.top:ClearAllPoints()
    self.top:SetPoint("TOPLEFT", parent, "TOPLEFT", -pixelSize, pixelSize)
    self.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pixelSize, pixelSize)
    PixelUtil.SetHeight(self.top, pixelSize, 1)

    -- Update bottom edge
    self.bottom:ClearAllPoints()
    self.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -pixelSize, -pixelSize)
    self.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pixelSize, -pixelSize)
    PixelUtil.SetHeight(self.bottom, pixelSize, 1)

    -- Update left edge
    self.left:ClearAllPoints()
    self.left:SetPoint("TOPLEFT", parent, "TOPLEFT", -pixelSize, 0)
    self.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -pixelSize, 0)
    PixelUtil.SetWidth(self.left, pixelSize, 1)

    -- Update right edge
    self.right:ClearAllPoints()
    self.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pixelSize, 0)
    self.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pixelSize, 0)
    PixelUtil.SetWidth(self.right, pixelSize, 1)
end

-- Create pixel-perfect texture-based border
local function CreateTextureBorder(parent, thickness)
    thickness = thickness or 1
    local pixelSize = PixelUtil.GetNearestPixelSize(thickness, parent:GetEffectiveScale(), 1)

    local border = setmetatable({}, BorderMethods)

    -- Use OVERLAY layer so borders render ABOVE StatusBar fill texture (ARTWORK layer)
    -- Top edge
    border.top = parent:CreateTexture(nil, "OVERLAY")
    border.top:SetTexture(BORDER_TEX)
    border.top:SetPoint("TOPLEFT", parent, "TOPLEFT", -pixelSize, pixelSize)
    border.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pixelSize, pixelSize)
    PixelUtil.SetHeight(border.top, pixelSize, 1)

    -- Bottom edge
    border.bottom = parent:CreateTexture(nil, "OVERLAY")
    border.bottom:SetTexture(BORDER_TEX)
    border.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -pixelSize, -pixelSize)
    border.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pixelSize, -pixelSize)
    PixelUtil.SetHeight(border.bottom, pixelSize, 1)

    -- Left edge
    border.left = parent:CreateTexture(nil, "OVERLAY")
    border.left:SetTexture(BORDER_TEX)
    border.left:SetPoint("TOPLEFT", parent, "TOPLEFT", -pixelSize, 0)
    border.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -pixelSize, 0)
    PixelUtil.SetWidth(border.left, pixelSize, 1)

    -- Right edge
    border.right = parent:CreateTexture(nil, "OVERLAY")
    border.right:SetTexture(BORDER_TEX)
    border.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pixelSize, 0)
    border.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pixelSize, 0)
    PixelUtil.SetWidth(border.right, pixelSize, 1)

    -- Default to black with alpha bias (prevents 1px dropout)
    border:SetColor(0, 0, 0, BORDER_ALPHA)

    return border
end

-- Blizzard's rounded-square debuff ring, as a drop-in for CreateTextureBorder.
--
-- This is NOT a duplicate of the pixel border §11.8 forbids copying: it is a
-- second, genuinely different style behind the same method surface, so callers
-- keep using :SetColor and nothing in the aura colour path changes.
--
-- The texcoords are the debuff-ring region of UI-Debuff-Overlays, the same art
-- and region Blizzard's own target/ToT debuff buttons use -- which is why
-- AuraStyle.lua only ever re-tints that border instead of drawing one.
--
-- The ring is drawn one pixel OUTSIDE the icon so its corner art covers the
-- square corners of the zoom-cropped icon texture underneath. One pixel is
-- what Blizzard's own debuff buttons use; at two the ring's inner edge lifts
-- clear of the icon and leaves a visible gap between the two.
--
-- The offset is snapped to a whole device pixel for the same reason
-- CreateTextureBorder snaps its thickness: nameplate icons sit at fractional
-- effective scales, so a raw offset lands on a half pixel and rounds
-- inconsistently, showing up as a gap on one edge only.
local BLIZZ_BORDER_TEX = "Interface\\Buttons\\UI-Debuff-Overlays"
local BLIZZ_BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
local BLIZZ_BORDER_OUTSET = 1

local BlizzardBorderMethods = {}
BlizzardBorderMethods.__index = BlizzardBorderMethods

function BlizzardBorderMethods:SetColor(r, g, b, a)
    self.ring:SetVertexColor(r, g, b, a or 1)
end

function BlizzardBorderMethods:GetColor()
    return self.ring:GetVertexColor()
end

function BlizzardBorderMethods:Show() self.ring:Show() end
function BlizzardBorderMethods:Hide() self.ring:Hide() end

-- Present so this satisfies the same contract as the pixel border. The ring is
-- anchored to the parent's corners, so it rescales without recomputing points.
function BlizzardBorderMethods:UpdateScale() end

-- Saved-variable prefix for the reactive nameplate indicator, per class.
-- Mirrors CLASS_CONFIG in Combat/ClassFeatures.lua; a class missing here just
-- falls back and its settings block is simply never shown.
local REACTIVE_PREFIX = {
    WARRIOR = "warriorOverpower",
    HUNTER  = "hunterCounterattack",
}

local function CreateBlizzardAuraBorder(parent, outset)
    outset = outset or BLIZZ_BORDER_OUTSET
    local px = PixelUtil.GetNearestPixelSize(outset, parent:GetEffectiveScale(), 1)

    local border = setmetatable({}, BlizzardBorderMethods)
    border.ring = parent:CreateTexture(nil, "OVERLAY")
    border.ring:SetTexture(BLIZZ_BORDER_TEX)
    border.ring:SetTexCoord(unpack(BLIZZ_BORDER_COORDS))
    border.ring:SetPoint("TOPLEFT", parent, "TOPLEFT", -px, px)
    border.ring:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", px, -px)
    border:SetColor(0, 0, 0, BORDER_ALPHA)

    return border
end

-- Export for aura/debuff renderers.
ns.CreateTextureBorder = CreateTextureBorder
ns.CreateBlizzardAuraBorder = CreateBlizzardAuraBorder
ns.BorderMethods = BorderMethods

-- =============================================================================
-- THROTTLE CONSTANTS
-- =============================================================================
local THROTTLE = {  -- published as NP.THROTTLE below
    health = 0.05,      -- 20 FPS (50ms) - fast enough for burst windows
    threat = 0.05,      -- coalesce threat-list/situation bursts across plates
    quest = 0.5,        -- 2 FPS (500ms) - give API time to update after quest events
}
NP.THROTTLE = THROTTLE

-- Update cached db reference (called after settings change)
function ns:UpdateDBCache()
    db = TurboFaceDB or ns.defaults

    local nameplatesEnabled = (not ns.ModuleEnabled) or ns.ModuleEnabled("nameplates")

    local bubble = db.bubbleNameplates or ns.defaults.bubbleNameplates

    -- TurboFace augments Blizzard's native nameplate chassis while the Nameplates
    -- module is active. Baseline augmentation pieces remain module-owned, while
    -- Threat Number, Job Icon, and Nameplate Swing Timer have their own live
    -- feature gates.
    ns.c_nameplatesEnabled        = nameplatesEnabled
    ns.c_nameplateJobIcon        = bubble.jobIcon ~= false
    ns.c_nameplateRarityIconRight = bubble.rarityIconRight == true
    ns.c_nameplateCenterHealthText  = bubble.centerHealthText ~= false
    ns.c_nameplateCenterHealthTextOnNameplate = bubble.centerHealthTextOnNameplate ~= false
    ns.c_nameplateNameTextShadow = bubble.nameTextShadow ~= false
    ns.c_nameplatePowerBarOverlap = bubble.powerBarOverlap == true
    local powerBarHeightPct = tonumber(bubble.powerBarHeightPct) or 0.30
    if powerBarHeightPct < 0.10 then powerBarHeightPct = 0.10 elseif powerBarHeightPct > 0.40 then powerBarHeightPct = 0.40 end
    ns.c_nameplatePowerBarHeightPct = powerBarHeightPct
    ns.c_nameplateFriendlyNPCNameTitleOnly = bubble.friendlyNPCNameTitleOnly == true
    ns.c_nameplateFriendlyPlayerDamagedOnly = bubble.friendlyPlayerDamagedOnly == true
    ns.c_nameplateFriendlyNPCDamagedOnly = bubble.friendlyNPCDamagedOnly == true
    ns.c_nameplateThreatNumber  = bubble.threatNumber ~= false
    local threatTextFontSize = tonumber(bubble.threatTextFontSize) or 6
    if threatTextFontSize < 6 then threatTextFontSize = 6 elseif threatTextFontSize > 16 then threatTextFontSize = 16 end
    ns.c_nameplateThreatFontSize = threatTextFontSize
    ns.c_nameplateSwingTimer     = bubble.swingTimer ~= false
    ns.c_nameplateAggroSounds       = bubble.muteAggroSounds ~= true
    ns.c_nameplateAggroGainVolume        = tonumber(bubble.gainVolume) or 1
    ns.c_nameplateAggroLossVolume        = tonumber(bubble.lossVolume) or 1
    local overlapV = tonumber(bubble.overlapV) or 1.00
    if overlapV < 0.5 then overlapV = 0.5 elseif overlapV > 2 then overlapV = 2 end
    ns.c_nameplateOverlapV          = overlapV
    local overlapH = tonumber(bubble.overlapH) or 1.35
    if overlapH < 0.5 then overlapH = 0.5 elseif overlapH > 2 then overlapH = 2 end
    ns.c_nameplateOverlapH          = overlapH
    local selectedScale = tonumber(bubble.selectedScale) or 1
    if selectedScale < 0.5 then selectedScale = 0.5 elseif selectedScale > 2 then selectedScale = 2 end
    ns.c_nameplateSelectedScale     = selectedScale
    local selectedAlpha = tonumber(bubble.selectedAlpha) or 1
    if selectedAlpha < 0 then selectedAlpha = 0 elseif selectedAlpha > 1 then selectedAlpha = 1 end
    ns.c_nameplateSelectedAlpha     = selectedAlpha
    local notSelectedAlpha = tonumber(bubble.notSelectedAlpha) or 0.80
    if notSelectedAlpha < 0 then notSelectedAlpha = 0 elseif notSelectedAlpha > 1 then notSelectedAlpha = 1 end
    ns.c_nameplateNotSelectedAlpha  = notSelectedAlpha

    -- Shared font/marker implementation constants used only by TurboFace-owned
    -- additive regions. Blizzard owns native name/level/health/cast geometry.
    ns.c_font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    ns.c_fontOutline = ""

    -- Reactive-ability nameplate indicator (Combat/ClassFeatures.lua).
    local _, playerClass = ns.API.ReadUnitClass("player")
    local rp = REACTIVE_PREFIX[playerClass] or "warriorOverpower"
    local function RS(suffix, fallback)
        local v = db[rp .. suffix]
        if type(fallback) == "boolean" then return v ~= false end
        return v or fallback
    end
    ns.c_reactiveIndicator = RS("Indicator", true)
    ns.c_reactiveSize      = RS("Size", 20)
    ns.c_reactiveDuration  = RS("Duration", 5)
    ns.c_reactivePosition  = RS("Position", "LEFT")
    ns.c_reactiveShowTimer = RS("ShowTimer", true)
    ns.c_reactiveSwipe     = RS("Swipe", true)
    ns.c_reactiveMargin    = RS("Margin", 4)
    ns.c_reactiveOffsetX   = RS("OffsetX", 0)
    ns.c_reactiveOffsetY   = RS("OffsetY", 0)

    ns.c_showComboPoints = db.showComboPoints ~= false
    ns.c_npcTitleCache = (TurboFaceCacheDB and TurboFaceCacheDB.npcTitles) or {}

    -- Quest objective icon settings remain independent augmentation.
    ns.c_showQuestNPCs = db.showQuestNPCs ~= false
    ns.c_showQuestObjectives = db.showQuestObjectives ~= false
    local rawScale = db.questIconScale or 100
    if rawScale < 10 then rawScale = (rawScale / 1.2) * 100 end
    ns.c_questIconScale = (rawScale / 100) * 1.2
    ns.c_questIconAnchor = db.questIconAnchor or "LEFT"
    ns.c_questIconX = db.questIconX or 0
    ns.c_questIconY = db.questIconY or 0
    ns.c_questIconsEnabled = ns.c_showQuestNPCs or ns.c_showQuestObjectives

    -- Cache aura settings (defined in Nameplates/Auras.lua)
    if ns.CacheAuraSettings then
        ns:CacheAuraSettings()
    end

    -- Cache TurboDebuffs settings
    if ns.CacheTurboDebuffsSettings then
        ns:CacheTurboDebuffsSettings()
    end


    -- Invalidate per-plate augmentation caches so the next refresh re-applies
    -- aura and quest-icon layout from the current settings.
    for unit, myPlate in pairs(ns.unitToPlate or {}) do
        if myPlate then
            -- Aura icon caches
            myPlate._lastDebuffW = nil
            myPlate._lastDebuffH = nil
            myPlate._lastBuffW = nil
            myPlate._lastBuffH = nil
            myPlate._lastDebuffSpacing = nil
            myPlate._lastBuffSpacing = nil
            myPlate._lastMaxDebuffs = nil
            myPlate._lastMaxBuffs = nil
            -- Quest icon caches
            myPlate._lastQuestAnchor = nil
            myPlate._lastQuestScale = nil
            myPlate._lastQuestX = nil
            myPlate._lastQuestY = nil
        end
    end
end

-- Resolve Blizzard's native nameplate substrate. TurboFace does not create a
-- fallback health/name/level/cast renderer. If the expected 1.15.9 substrate is
-- unavailable, callers fail open and leave the plate entirely to Blizzard.
local function ResolveNativeUnitFrame(myPlate)
    local nameplate = myPlate and (myPlate.parentPlate or myPlate:GetParent())
    return (nameplate and nameplate.UnitFrame) or (myPlate and myPlate.nativeUnitFrame) or nil
end

local function ResolveNativeHealthBar(myPlate)
    local uf = ResolveNativeUnitFrame(myPlate)
    return uf and (uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)) or nil
end

local function RegionIsShown(region)
    return region and (not region.IsShown or region:IsShown()) or false
end

-- Identity-anchor boundary. Callers may anchor TurboFace-owned regions to
-- Blizzard identity regions, but must not rewrite/recolor/hide those regions.
function ns.GetNameplateNameAnchor(myPlate, shownOnly)
    if not myPlate then return nil end
    local uf = ResolveNativeUnitFrame(myPlate)
    local name = uf and uf.name
    if name and (not shownOnly or RegionIsShown(name)) then return name end
    return myPlate.hp or myPlate
end

local function GetNameplateLevelAnchor(myPlate, shownOnly)
    if not myPlate then return nil end
    local uf = ResolveNativeUnitFrame(myPlate)
    local playerDiff = uf and uf.PlayerLevelDiffFrame
    if playerDiff and (not shownOnly or RegionIsShown(playerDiff)) then return playerDiff end
    local level = uf and uf.LevelFrame
    if level and (not shownOnly or RegionIsShown(level)) then return level end
    return nil
end

function ns.GetNameplateIdentityRightAnchor(myPlate)
    return GetNameplateLevelAnchor(myPlate, true)
        or ns.GetNameplateNameAnchor(myPlate, true)
        or (myPlate and (myPlate.hp or myPlate))
end

local function HealthSubstrateTexture(hp)
    local texture = hp and hp.GetStatusBarTexture and hp:GetStatusBarTexture()
    local path = texture and texture.GetTexture and texture:GetTexture()
    return path or "Interface\\TargetingFrame\\UI-StatusBar"
end
NP.HealthSubstrateTexture = HealthSubstrateTexture

-- Release only TurboFace-owned children. Blizzard's StatusBar geometry, scale,
-- texture, color, value, background, border, name, level, and cast surfaces are
-- never captured/restored because TurboFace never owns them.
function ns:CleanupNativeNameplateAugments(nameplate)
    if not nameplate then return end
    local myPlate = nameplate.myPlate
    local uf = nameplate.UnitFrame
    local hp = uf and (uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar))
    if hp then
        if hp._tfAbsorbBar then hp._tfAbsorbBar:Hide() end
        if hp._tfAbsorbOverlay then hp._tfAbsorbOverlay:Hide() end
        if hp._tfOverAbsorbGlow then hp._tfOverAbsorbGlow:Hide() end
        if hp._tfDotBar then hp._tfDotBar:Hide() end
        if hp._tfDotBarBG then hp._tfDotBarBG:Hide() end
        if NP.RestoreDotRenderOrder then NP.RestoreDotRenderOrder(hp) end
        if hp._tfBubbleSpend then hp._tfBubbleSpend:Hide() end
        if hp._tfBubbleArc then hp._tfBubbleArc:Hide() end
        if hp._tfBubbleIncoming then hp._tfBubbleIncoming:Hide() end
        if hp._tfBubbleIncomingText then hp._tfBubbleIncomingText:Hide() end
        if hp._tfBubbleEmbeddedPower then hp._tfBubbleEmbeddedPower:Hide() end
    end
    if myPlate and myPlate.guildText then myPlate.guildText:Hide() end
end

local function EnsureFullPlate(myPlate)
    if not myPlate then return nil end
    if myPlate.hp and myPlate._tfUsesNativeHealth then return myPlate.hp end

    local hp = ResolveNativeHealthBar(myPlate)
    if not hp then
        myPlate.hp = nil
        myPlate.nativeHealthBar = nil
        myPlate._tfUsesNativeHealth = nil
        myPlate._tfUsesNativeIdentity = nil
        return nil
    end

    myPlate.nativeUnitFrame = ResolveNativeUnitFrame(myPlate)
    myPlate.nativeHealthBar = hp
    myPlate.hp = hp
    myPlate._tfUsesNativeHealth = true
    myPlate._tfUsesNativeIdentity = true

    if not hp._tfAbsorbBar then
        local absorbBar = hp:CreateTexture(nil, "ARTWORK", nil, 1)
        absorbBar:SetTexture(HealthSubstrateTexture(hp))
        absorbBar:SetVertexColor(0.66, 1, 1, 0.7)
        absorbBar:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", hp:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        absorbBar:SetWidth(1)
        absorbBar:Hide()
        hp._tfAbsorbBar = absorbBar

        local absorbOverlay = hp:CreateTexture(nil, "ARTWORK", nil, 2)
        absorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        absorbOverlay:SetAllPoints(absorbBar)
        absorbOverlay.tileSize = 32
        absorbOverlay:Hide()
        hp._tfAbsorbOverlay = absorbOverlay

        local overAbsorbGlow = hp:CreateTexture(nil, "ARTWORK", nil, 3)
        overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        overAbsorbGlow:SetBlendMode("ADD")
        overAbsorbGlow:SetAlpha(0.7)
        PixelUtil.SetWidth(overAbsorbGlow, 15, 1)
        PixelUtil.SetPoint(overAbsorbGlow, "TOPLEFT", hp, "TOPRIGHT", -7, 2, 1, 1)
        PixelUtil.SetPoint(overAbsorbGlow, "BOTTOMLEFT", hp, "BOTTOMRIGHT", -7, -2, 1, 1)
        overAbsorbGlow:Hide()
        hp._tfOverAbsorbGlow = overAbsorbGlow
    end

    return hp
end
NP.EnsureFullPlate = EnsureFullPlate

-- Current target's plate and GUID (GUID is source of truth for identity)
ns.currentTargetPlate = nil
ns.currentTargetGUID = nil

-- Helper: Find myPlate by GUID (for GUID-based target validation)
local function GetPlateByGUID(guid)
    if not guid then return nil end
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = ns.API.GetPlateUnitToken(nameplate)
        if unit and UnitGUID(unit) == guid then
            local myPlate = nameplate.myPlate
            -- Skip the personal plate and identity-only presentations.
            if myPlate and not myPlate.isPlayer and not myPlate._tfNativeFriendlyIdentityOnly then
                return myPlate
            end
        end
    end
    return nil
end
NP.GetPlateByGUID = GetPlateByGUID
