local _, ns = ...

-- Nameplates/NameplateVisuals.lua -- target combo dots, additive layout, health/absorb/DoT rendering.
-- Split from Nameplates.lua (G3 refactor). Shared nameplate internals live in
-- ns.NP, created by Nameplates.lua (loads first in the TOC).

local NP = ns.NP

-- Hot-path aliases (upvalues are cheaper than global lookups)
local UnitExists = ns.API.ReadUnitExists
local UnitGUID = ns.API.ReadUnitGUID
local UnitClass = ns.API.ReadUnitClass
local UnitHealth = ns.API.ReadUnitHealth
local UnitHealthMax = ns.API.ReadUnitHealthMax
local UnitPowerMax = ns.API.ReadUnitPowerMax
local UnitIsUnit = ns.API.ReadUnitIsUnit
local CreateFrame = CreateFrame
local math_abs = math.abs
local math_max = math.max
-- Defensive fallback keeps the cadence client safe if the shared substrate is
-- ever refactored again without publishing the Classic Era capacity first.
local MAX_CP = tonumber(NP and NP.MAX_CP) or 5
local GetComboPoints = ns.API.GetComboPoints
local UnitGetTotalAbsorbs = ns.API.ReadUnitTotalAbsorbs
local GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit

-- Minimal native-health bindings used only when DoT Prediction requests the
-- nameplate surface while the optional Nameplates enhancement family is off.
-- These are plain state tables, not replacement frames: Blizzard continues to
-- own the plate and health bar, and only the existing additive DoT textures are
-- attached to that native StatusBar.
local dotOnlyStates = {}

local function ResolveNativeDotHealth(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    return uf and (uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)) or nil
end

function NP.ResolveDotPredictionPlate(unit)
    local full = ns.unitToPlate and ns.unitToPlate[unit]
    if full then
        dotOnlyStates[unit] = nil
        return full
    end

    local state = dotOnlyStates[unit]
    if state and state.hp then return state end

    -- The ordinary Nameplates lifecycle owns full augmentation whenever its
    -- master is enabled. Do not race it by constructing a parallel binding.
    if (not ns.DotPrediction or not ns.DotPrediction:ShowOnNameplates())
        or (ns.ModuleEnabled and ns.ModuleEnabled("nameplates"))
        or not unit or not UnitExists(unit) or UnitIsUnit(unit, "player")
        or not GetNamePlateForUnit then
        return nil
    end

    local nameplate = GetNamePlateForUnit(unit)
    local hp = ResolveNativeDotHealth(nameplate)
    local guid = UnitGUID(unit)
    if not nameplate or not hp or not guid then return nil end

    state = nameplate._tfDotOnlyState or {}
    if state.unit and state.unit ~= unit and dotOnlyStates[state.unit] == state then
        dotOnlyStates[state.unit] = nil
    end
    state._tfDotOnly = true
    state.parentPlate = nameplate
    state.nativeUnitFrame = nameplate.UnitFrame
    state.nativeHealthBar = hp
    state.hp = hp
    state.unit = unit
    state.cachedGUID = guid
    state.isPlayer = false
    state.isFriendly = UnitIsFriend("player", unit)
    state._lastDotOffset, state._lastDotWidth, state._lastDotBottomInset = nil, nil, nil
    state._lastDotR, state._lastDotG, state._lastDotB, state._lastDotA = nil, nil, nil, nil
    nameplate._tfDotOnlyState = state
    dotOnlyStates[unit] = state
    return state
end

function NP.ReleaseDotPredictionPlate(unit)
    local state = unit and dotOnlyStates[unit]
    if not state then return end
    dotOnlyStates[unit] = nil

    local nameplate = state.parentPlate
    local liveUnit = nameplate and ns.API.GetPlateUnitToken(nameplate)
    if liveUnit and liveUnit ~= unit then return end

    local hp = state.hp
    if hp then
        if hp._tfDotBar then hp._tfDotBar:Hide() end
        if hp._tfDotBarBG then hp._tfDotBarBG:Hide() end
        if NP.RestoreDotRenderOrder then NP.RestoreDotRenderOrder(hp) end
    end
    state.unit = nil
    state.cachedGUID = nil
end

-- =============================================================================
-- TARGET NAMEPLATE COMBO POINTS (Rogue / Druid) -- 5 red dots between the name
-- and the debuff row on the current target's nameplate. Single red when filled,
-- dim when empty; all 5 slots shown. A Nameplates-owned singleton driver runs
-- only while an eligible target plate exists; Unit Frames are not a dependency.
-- =============================================================================
local TF_CP_TEX    = "Interface\\AddOns\\TurboFace\\Textures\\Circle_White"
local TF_CP_FILLED = { 0.90, 0.10, 0.10, 1.00 }
local TF_CP_EMPTY  = { 0.35, 0.35, 0.35, 0.45 }
local _, TF_PLAYER_CLASS = ns.API.ReadUnitClass("player")
local TF_COMBO_CLASS = (TF_PLAYER_CLASS == "ROGUE" or TF_PLAYER_CLASS == "DRUID")
local TF_IS_DRUID    = (TF_PLAYER_CLASS == "DRUID")

local function EnsureTargetCombo(plate)
    if plate.tfCombo then return plate.tfCombo end
    if not plate then return nil end
    local c = CreateFrame("Frame", nil, plate)
    c:SetFrameLevel((plate:GetFrameLevel() or 1) + 15)
    c:EnableMouse(false)
    c.dots = {}
    local size = 7 -- fixed 7px dots
    local gap = 2
    c:SetSize(MAX_CP * size + (MAX_CP - 1) * gap, size)
    for i = 1, MAX_CP do
        local d = c:CreateTexture(nil, "OVERLAY")
        d:SetTexture(TF_CP_TEX)
        d:SetSize(size, size)
        d:SetPoint("LEFT", c, "LEFT", (i - 1) * (size + gap), 0)
        c.dots[i] = d
    end
    plate.tfCombo = c
    return c
end

local function TargetComboShouldShow(plate)
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    if not TF_COMBO_CLASS or not ns.c_showComboPoints then return false end
    if not plate or plate.isPlayer then return false end
    if not UnitExists("target") then return false end
    if TF_IS_DRUID then
        -- Combo points are only usable in Cat Form.
        return GetShapeshiftFormID and GetShapeshiftFormID() == (CAT_FORM or 1)
    end
    return true
end

-- Vertical space the combo dots occupy above the name. Nameplates/Auras.lua adds this to
-- the debuff/buff row offset so they don't overlap the dots. 0 when none shown.
function ns.ComboDebuffOffset(plate)
    if plate and plate.tfCombo and plate.tfCombo:IsShown() then
        return (plate.tfCombo:GetHeight() or 0) + 3
    end
    return 0
end

-- Re-run the aura layout so the debuff/buff rows pick up (or release) the combo
-- reservation. Only called when the dots' visibility actually changes.
local function ComboReflowDebuffs(plate)
    if plate and plate.unit and UnitExists(plate.unit) and ns.UpdateAuras then
        ns:UpdateAuras(plate, plate.unit)
    end
end

function ns.UpdateTargetComboPoints()
    local plate = ns.currentTargetPlate

    -- A plate that is no longer the target: hide its dots, restore its debuffs.
    local old = ns._tfLastComboPlate
    if old and old ~= plate and old.tfCombo and old._tfComboShown then
        old.tfCombo:Hide()
        old._tfComboShown = false
        ComboReflowDebuffs(old)
    end
    ns._tfLastComboPlate = plate

    if not TargetComboShouldShow(plate) then
        if plate and plate.tfCombo and plate._tfComboShown then
            plate.tfCombo:Hide()
            plate._tfComboShown = false
            ComboReflowDebuffs(plate)
        end
        return
    end

    local c = EnsureTargetCombo(plate)
    if not c then return end
    c:ClearAllPoints()
    local nameAnchor = ns.GetNameplateNameAnchor(plate, true) or plate.hp or plate
    c:SetPoint("BOTTOM", nameAnchor, "TOP", 0, 3)   -- above Blizzard name, below debuffs

    local cp = GetComboPoints("player", "target") or 0
    for i = 1, MAX_CP do
        local col = (i <= cp) and TF_CP_FILLED or TF_CP_EMPTY
        c.dots[i]:SetVertexColor(col[1], col[2], col[3], col[4])
    end
    c:Show()
    if not plate._tfComboShown then
        plate._tfComboShown = true
        ComboReflowDebuffs(plate)   -- push debuffs up to clear the new dots
    end
end

-- Combo-point changes have no reliable dedicated event on this Classic client, so
-- this singleton polls at 10 Hz only while there is an actual target plate to
-- render. The native cadence scheduler prevents high-FPS clients from entering
-- Lua hundreds of times per second just to throttle this 10 Hz job.
local comboPollActive = false

local function ComboDriverAllowed()
    if not comboPollActive then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    return TF_COMBO_CLASS and ns.c_showComboPoints and ns.currentTargetPlate and UnitExists("target")
end

local function ComboTick()
    if not ComboDriverAllowed() then
        ns.RefreshNameplateComboDriver()
        return
    end
    ns.UpdateTargetComboPoints()
end

function ns.RefreshNameplateComboDriver()
    if ComboDriverAllowed() then
        ns.Cadence:Add("TurboFaceNameplateCombo", 0.10, ComboTick, true)
        ns.UpdateTargetComboPoints()
    else
        ns.Cadence:Remove("TurboFaceNameplateCombo")
        ns.UpdateTargetComboPoints() -- hide/reflow any previously visible dots
    end
end

function ns.ActivateNameplateComboDriver()
    if comboPollActive then return end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return end
    comboPollActive = true
    ns.RefreshNameplateComboDriver()
end


ns.RegisterCPUProfileTarget("Nameplates/Combo:Tick", ComboTick)

function ns:RefreshNameplateAugments(myPlate)
    if not myPlate or not myPlate.hp then return end

    if not myPlate.isPlayer and ns.UpdateAuraPositions then
        ns:UpdateAuraPositions(myPlate)
    end
    if myPlate.unit and ns.UpdateAuras then
        local auraNeedsRefresh = myPlate._lastDebuffW ~= ns.c_debuffIconWidth
            or myPlate._lastDebuffH ~= ns.c_debuffIconHeight
            or myPlate._lastBuffW ~= ns.c_buffIconWidth
            or myPlate._lastBuffH ~= ns.c_buffIconHeight
            or myPlate._lastDebuffSpacing ~= ns.c_iconSpacing
            or myPlate._lastBuffSpacing ~= ns.c_buffIconSpacing
            or myPlate._lastMaxDebuffs ~= ns.c_maxDebuffs
            or myPlate._lastMaxBuffs ~= ns.c_maxBuffs
        if auraNeedsRefresh then
            ns:UpdateAuras(myPlate, myPlate.unit)
            myPlate._lastDebuffW = ns.c_debuffIconWidth
            myPlate._lastDebuffH = ns.c_debuffIconHeight
            myPlate._lastBuffW = ns.c_buffIconWidth
            myPlate._lastBuffH = ns.c_buffIconHeight
            myPlate._lastDebuffSpacing = ns.c_iconSpacing
            myPlate._lastBuffSpacing = ns.c_buffIconSpacing
            myPlate._lastMaxDebuffs = ns.c_maxDebuffs
            myPlate._lastMaxBuffs = ns.c_maxBuffs
        end
    end

    if myPlate.questIcon and myPlate.questIcon:IsShown() then
        local needsUpdate = myPlate._lastQuestAnchor ~= ns.c_questIconAnchor
            or myPlate._lastQuestScale ~= ns.c_questIconScale
            or myPlate._lastQuestX ~= ns.c_questIconX
            or myPlate._lastQuestY ~= ns.c_questIconY
        if needsUpdate then
            myPlate.questIcon:ClearAllPoints()
            local nameAnchor = ns.GetNameplateNameAnchor(myPlate, true) or myPlate.hp or myPlate
            local xOff, yOff = ns.c_questIconX, ns.c_questIconY
            if ns.c_questIconAnchor == "RIGHT" then
                local rightAnchor = ns.GetNameplateIdentityRightAnchor(myPlate) or nameAnchor
                myPlate.questIcon:SetPoint("LEFT", rightAnchor, "RIGHT", 2 + xOff, yOff)
            elseif ns.c_questIconAnchor == "TOP" then
                myPlate.questIcon:SetPoint("BOTTOM", nameAnchor, "TOP", xOff, 2 + yOff)
            else
                myPlate.questIcon:SetPoint("RIGHT", nameAnchor, "LEFT", -2 + xOff, yOff)
            end
            myPlate._lastQuestAnchor = ns.c_questIconAnchor
            myPlate._lastQuestScale = ns.c_questIconScale
            myPlate._lastQuestX = ns.c_questIconX
            myPlate._lastQuestY = ns.c_questIconY
        end
    end
end

-- Update absorb bar display
-- DoT prediction region. Kept separate from UpdateAbsorb because it is driven
-- by a different signal: absorbs change on damage events, projections change on
-- aura application and on every tick. Cheap enough to run on the same throttled
-- health pass -- the engine is event-invalidated with a 0.50s safety TTL, so
-- several consumers asking in the same interval reuse the cached summary.
-- Nameplate DoT render-order contract. Blizzard's native health fill normally
-- occupies ARTWORK:0 and its chassis border ARTWORK:1. TurboFace historically
-- created both the black prediction underlay and coloured prediction at
-- ARTWORK:0 too, relying on creation order. WoW does not define ordering among
-- overlapping textures that share the same layer/sublevel, so a valid, shown
-- prediction could intermittently wind up behind either the native fill or its
-- own black underlay.
--
-- Give every overlapping pass a deterministic slot while the DoT nameplate
-- surface is active:
--   native health fill  ARTWORK:-2
--   DoT black underlay  ARTWORK:-1
--   DoT colour          ARTWORK: 0
--   native border       ARTWORK: 1 (Blizzard-owned and untouched)
--
-- The native fill's original draw layer is snapshotted and restored when the
-- surface is released. Geometry, texture, colour and StatusBar value remain
-- Blizzard-owned.
local function RestoreDotRenderOrder(hp)
    if not hp then return end
    local fill = hp._tfDotFillLayerRegion
    if fill and hp._tfDotFillLayerOwned and fill.SetDrawLayer then
        local layer = hp._tfDotFillOrigLayer
        local sublevel = hp._tfDotFillOrigSublevel
        if layer then
            if sublevel ~= nil then fill:SetDrawLayer(layer, sublevel)
            else fill:SetDrawLayer(layer) end
        end
    end
    hp._tfDotFillLayerRegion = nil
    hp._tfDotFillOrigLayer = nil
    hp._tfDotFillOrigSublevel = nil
    hp._tfDotFillLayerOwned = nil
end
NP.RestoreDotRenderOrder = RestoreDotRenderOrder

local function EnsureDotRenderOrder(hp)
    if not hp then return end
    local fill = hp.GetStatusBarTexture and hp:GetStatusBarTexture()
    if not fill then return end

    if hp._tfDotFillLayerRegion ~= fill then
        RestoreDotRenderOrder(hp)
        hp._tfDotFillLayerRegion = fill
        if fill.GetDrawLayer then
            hp._tfDotFillOrigLayer, hp._tfDotFillOrigSublevel = fill:GetDrawLayer()
        end
        hp._tfDotFillLayerOwned = true
    end

    -- Blizzard may reapply native styling to the same StatusBarTexture without
    -- replacing the Texture object, so verify the owned sublevel each render.
    if fill.GetDrawLayer and fill.SetDrawLayer then
        local layer, sublevel = fill:GetDrawLayer()
        if layer ~= "ARTWORK" or sublevel ~= -2 then
            fill:SetDrawLayer("ARTWORK", -2)
        end
    end

    local bg = hp._tfDotBarBG
    if bg and bg.GetDrawLayer and bg.SetDrawLayer then
        local layer, sublevel = bg:GetDrawLayer()
        if layer ~= "ARTWORK" or sublevel ~= -1 then
            bg:SetDrawLayer("ARTWORK", -1)
        end
    end
    local bar = hp._tfDotBar
    if bar and bar.GetDrawLayer and bar.SetDrawLayer then
        local layer, sublevel = bar:GetDrawLayer()
        if layer ~= "ARTWORK" or sublevel ~= 0 then
            bar:SetDrawLayer("ARTWORK", 0)
        end
    end
end

local function SyncHealthOverlaySubstrate(hp)
    if not hp then return end
    local fill = hp.GetStatusBarTexture and hp:GetStatusBarTexture()
    local atlas = fill and fill.GetAtlas and fill:GetAtlas()
    local path = fill and fill.GetTexture and fill:GetTexture()
    if not path and not atlas then path = "Interface\\TargetingFrame\\UI-StatusBar" end

    if not hp._tfOverlaySubstrateDirty
        and hp._tfOverlayFill == fill
        and hp._tfOverlayAtlas == atlas
        and hp._tfOverlayTexturePath == path then
        return
    end

    hp._tfOverlaySubstrateDirty = nil
    hp._tfOverlayFill = fill
    hp._tfOverlayAtlas = atlas
    hp._tfOverlayTexturePath = path

    local function Apply(tex)
        if not tex then return end
        if atlas and tex.SetAtlas then
            tex:SetAtlas(atlas, false)
        else
            tex:SetTexture(path)
        end

        -- Native styles can crop or rotate the same source texture without
        -- changing its file path. Copy Blizzard's live coordinates onto the
        -- TurboFace overlay; this reads the substrate and never writes to it.
        if fill and fill.GetTexCoord and tex.SetTexCoord then
            local a, b, c, d, e, f, g, h = fill:GetTexCoord()
            if h ~= nil then
                tex:SetTexCoord(a, b, c, d, e, f, g, h)
            elseif d ~= nil then
                tex:SetTexCoord(a, b, c, d)
            end
        end
    end

    Apply(hp._tfAbsorbBar)
    Apply(hp._tfDotBarBG)
    Apply(hp._tfDotBar)
end

local function UpdateDotPrediction(unit, myPlate)
    if not myPlate or not myPlate.hp then return end
    local hp = myPlate.hp
    local DP = ns.DotPrediction

    if not DP or not DP.GetBarRegion or not DP:ShowOnNameplates() then
        local existing = hp._tfDotBar
        if existing and existing:IsShown() then existing:Hide() end
        -- The underlay must go with it: left showing, it paints an opaque
        -- black stripe across the health bar after the feature is turned off.
        local existingBG = hp._tfDotBarBG
        if existingBG and existingBG:IsShown() then existingBG:Hide() end
        RestoreDotRenderOrder(hp)
        myPlate._lastDotOffset, myPlate._lastDotWidth, myPlate._lastDotBottomInset = nil, nil, nil
        return
    end

    -- Lazy creation: a player who never enables DoT Prediction pays no texture
    -- allocation on every nameplate merely because the addon file is loaded.
    local dotBar = hp._tfDotBar
    if not dotBar then
        -- Opaque underlay beneath the translucent prediction region.
        --
        -- Without it the region composites against the HEALTH BAR COLOUR, so
        -- the same purple lands differently per faction: fine over a red
        -- hostile bar, washed out and muddy over a yellow neutral one, because
        -- yellow shares its red channel and adds green. Compositing against a
        -- constant instead makes the colour mean the same thing on every mob.
        --
        -- Render order is made deterministic by EnsureDotRenderOrder(): the
        -- native fill is temporarily moved to ARTWORK:-2, this black underlay
        -- uses -1, the coloured region uses 0, and Blizzard's untouched native
        -- border remains at 1. Do not collapse these back onto one sublevel; WoW
        -- does not define ordering for overlapping textures at equal sublevels.
        local dotBarBG = hp:CreateTexture(nil, "ARTWORK", nil, -1)
        dotBarBG:SetTexture(NP.HealthSubstrateTexture and NP.HealthSubstrateTexture(hp) or "Interface\\TargetingFrame\\UI-StatusBar")
        dotBarBG:SetVertexColor(0, 0, 0, 1)
        dotBarBG:Hide()
        hp._tfDotBarBG = dotBarBG

        dotBar = hp:CreateTexture(nil, "ARTWORK", nil, 0)
        dotBar:SetTexture(NP.HealthSubstrateTexture and NP.HealthSubstrateTexture(hp) or "Interface\\TargetingFrame\\UI-StatusBar")
        dotBar:Hide()
        hp._tfDotBar = dotBar

    end
    local dotBarBG = hp._tfDotBarBG
    SyncHealthOverlaySubstrate(hp)

    local rawBarWidth = hp:GetWidth() or 0
    if rawBarWidth <= 1 then
        -- NAME_PLATE_UNIT_ADDED can precede the final native StatusBar geometry.
        -- A zero/placeholder width would make a valid prediction resolve to no
        -- drawable region and, without another health event, remain invisible.
        -- Retry only while geometry is actually unsettled, capped per binding.
        local retries = myPlate._tfDotGeometryRetries or 0
        if retries < 3 and DP.RequestNameplateReconcile then
            myPlate._tfDotGeometryRetries = retries + 1
            DP:RequestNameplateReconcile(unit)
        end
        if dotBar:IsShown() then dotBar:Hide() end
        if dotBarBG and dotBarBG:IsShown() then dotBarBG:Hide() end
        RestoreDotRenderOrder(hp)
        myPlate._lastDotOffset, myPlate._lastDotWidth, myPlate._lastDotBottomInset = nil, nil, nil
        return
    end
    myPlate._tfDotGeometryRetries = nil

    local barWidth = math_max(1, rawBarWidth)
    -- Third return is the lethal flag: projected DoT damage meets or exceeds
    -- current health, i.e. the target dies to ticks already out.
    local offset, width, lethal = DP:GetBarRegion(unit, barWidth)

    -- Embedded power owns the bottom band of a powered native HP bar. Do not
    -- ask ARTWORK:0 creation order to decide whether DoT or power wins there:
    -- reserve that vertical band for power and constrain DoT to the health-only
    -- area above it. Blizzard's ARTWORK:1 border remains above both systems.
    local bottomInset = 0
    local powerMax = UnitPowerMax(unit)
    if not myPlate._tfDotOnly and ns.c_nameplatePowerBarOverlap == true
        and powerMax and powerMax > 0 then
        local bubble = ns.BubbleNameplates
        if bubble and bubble.GetEmbeddedResourceHeight then
            bottomInset = bubble:GetEmbeddedResourceHeight(myPlate) or 0
        end
    end

    if not offset then
        if dotBar:IsShown() then dotBar:Hide() end
        if dotBarBG and dotBarBG:IsShown() then dotBarBG:Hide() end
        RestoreDotRenderOrder(hp)
        myPlate._lastDotOffset, myPlate._lastDotWidth, myPlate._lastDotBottomInset = nil, nil, nil
        return
    end

    -- Only claim the native fill's sublevel while a prediction is actually
    -- drawable. Plates without active predictable DoTs remain fully native.
    EnsureDotRenderOrder(hp)

    -- Color/alpha are live settings and may change while geometry does not.
    -- Lethality needs no cache key of its own: a flip changes the colour and
    -- the comparison below is on the colour itself. The cached values are only
    -- an optimization hint: pooled/native frame churn can reset a live Texture
    -- without updating our myPlate cache, so validate the actual region too.
    local r, g, b, a = DP:GetColor(lethal)
    local colorDirty = myPlate._lastDotR ~= r or myPlate._lastDotG ~= g
        or myPlate._lastDotB ~= b or myPlate._lastDotA ~= a
    if not colorDirty and dotBar.GetVertexColor then
        local liveR, liveG, liveB, liveA = dotBar:GetVertexColor()
        colorDirty = liveR == nil or math_abs(liveR - r) > 0.001
            or liveG == nil or math_abs(liveG - g) > 0.001
            or liveB == nil or math_abs(liveB - b) > 0.001
            or (liveA ~= nil and math_abs(liveA - a) > 0.001)
    end
    if colorDirty then
        dotBar:SetVertexColor(r, g, b, a)
        myPlate._lastDotR, myPlate._lastDotG, myPlate._lastDotB, myPlate._lastDotA = r, g, b, a
    end

    -- dotPredictionAlpha lives in the vertex colour above. The region's own
    -- alpha is therefore an invariant 1; if pooled-frame cleanup/native churn
    -- zeroed it, leaving it cached would make a shown, correctly layered region
    -- fully transparent (the exact state reported by /tf debug dots).
    if dotBar.GetAlpha and dotBar.SetAlpha and dotBar:GetAlpha() ~= 1 then
        dotBar:SetAlpha(1)
    end
    if dotBarBG and dotBarBG.GetAlpha and dotBarBG.SetAlpha and dotBarBG:GetAlpha() ~= 1 then
        dotBarBG:SetAlpha(1)
    end

    -- Skip the SetPoint churn when nothing moved; this runs per plate per
    -- health tick.
    if myPlate._lastDotOffset == offset
        and myPlate._lastDotWidth == width
        and myPlate._lastDotBottomInset == bottomInset then
        if not dotBar:IsShown() then dotBar:Show() end
        if dotBarBG and not dotBarBG:IsShown() then dotBarBG:Show() end
        return
    end
    myPlate._lastDotOffset, myPlate._lastDotWidth, myPlate._lastDotBottomInset = offset, width, bottomInset

    -- Underlay tracks the region exactly; any mismatch would show the bar
    -- colour along one edge.
    if dotBarBG then
        dotBarBG:ClearAllPoints()
        dotBarBG:SetPoint("TOPLEFT", hp, "TOPLEFT", offset, 0)
        dotBarBG:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", offset, bottomInset)
        dotBarBG:SetWidth(width)
        dotBarBG:Show()
    end

    dotBar:ClearAllPoints()
    dotBar:SetPoint("TOPLEFT", hp, "TOPLEFT", offset, 0)
    dotBar:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", offset, bottomInset)
    dotBar:SetWidth(width)
    dotBar:Show()
end

-- DotPrediction invalidates and notifies on UNIT_AURA. Unit-frame bars already
-- consume that notification directly; nameplates must do the same instead of
-- waiting for an unrelated UNIT_HEALTH event to happen to repaint the plate.
-- That old incidental path made a known DoT applied between damage events look
-- intermittent: the prediction existed, but its nameplate texture was not asked
-- to render until some later health change.
--
-- Resolve the plate from the current unit-token map at notification time. Never
-- retain a pooled plate in this closure, and verify its cached GUID before
-- touching it so a late aura event cannot repaint a recycled nameplate.
local function OnDotPredictionInvalidated(unit)
    if not unit or not ns.IsNameplateUnit or not ns.IsNameplateUnit(unit) then return end
    local myPlate = NP.ResolveDotPredictionPlate and NP.ResolveDotPredictionPlate(unit)
    if not myPlate or myPlate._tfNativeFriendlyIdentityOnly then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    if myPlate.cachedGUID ~= guid or myPlate.unit ~= unit then
        -- Rare pooled-frame races can change the live GUID for a stable
        -- nameplate token before the 0.5 s lifecycle guard runs. Do not merely
        -- discard the DoT repaint: repair through the canonical nameplate
        -- classifier, which refreshes cachedGUID and every other augmentation.
        if myPlate._tfDotOnly then
            dotOnlyStates[unit] = nil
            myPlate = NP.ResolveDotPredictionPlate(unit)
        elseif ns.RefreshPlateForUnit then
            ns:RefreshPlateForUnit(unit)
            myPlate = ns.unitToPlate and ns.unitToPlate[unit]
        end
        if not myPlate or myPlate._tfNativeFriendlyIdentityOnly
            or myPlate.cachedGUID ~= guid or myPlate.unit ~= unit then
            return
        end
    end

    UpdateDotPrediction(unit, myPlate)
end

if ns.DotPrediction and ns.DotPrediction.RegisterConsumer then
    ns.DotPrediction:RegisterConsumer(OnDotPredictionInvalidated)
end

local function UpdateAbsorb(unit, myPlate)
    if not myPlate or not myPlate.hp then return end
    local hp = myPlate.hp
    if not hp._tfAbsorbBar then return end

    SyncHealthOverlaySubstrate(hp)
    local fill = hp:GetStatusBarTexture()
    if fill and hp._tfAbsorbBar._tfFillAnchor ~= fill then
        hp._tfAbsorbBar:ClearAllPoints()
        hp._tfAbsorbBar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        hp._tfAbsorbBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        hp._tfAbsorbBar._tfFillAnchor = fill
    end

    local absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    if absorb == nil or health == nil or maxHealth == nil then
        hp._tfAbsorbBar:Hide()
        if hp._tfAbsorbOverlay then hp._tfAbsorbOverlay:Hide() end
        hp._tfOverAbsorbGlow:Hide()
        return
    end
    local barWidth = math_max(1, hp:GetWidth() or 1)
    local barHeight = math_max(1, hp:GetHeight() or 1)

    -- Include live substrate dimensions and fill identity in the cache. Native
    -- style/size changes can alter geometry without changing health or absorbs.
    if myPlate._lastAbsorb == absorb
        and myPlate._lastAbsorbHealth == health
        and myPlate._lastAbsorbWidth == barWidth
        and myPlate._lastAbsorbHeight == barHeight
        and myPlate._lastAbsorbFill == fill then
        return
    end
    myPlate._lastAbsorb = absorb
    myPlate._lastAbsorbHealth = health
    myPlate._lastAbsorbWidth = barWidth
    myPlate._lastAbsorbHeight = barHeight
    myPlate._lastAbsorbFill = fill

    if absorb == 0 then
        hp._tfAbsorbBar:Hide()
        if hp._tfAbsorbOverlay then hp._tfAbsorbOverlay:Hide() end
        hp._tfOverAbsorbGlow:Hide()
        return
    end

    if maxHealth == 0 then return end

    local healthPercent = health / maxHealth
    local absorbPercent = absorb / maxHealth

    -- Calculate how much space is left in the bar after health
    local missingHealthPercent = 1 - healthPercent

    -- Absorb bar fills from health edge towards right
    -- Clamp to remaining bar space (overflow shows glow instead)
    local displayPercent = math.min(absorbPercent, missingHealthPercent)
    local absorbWidth = displayPercent * barWidth

    -- Show absorb bar if there's any width to display
    if absorbWidth >= 1 then
        hp._tfAbsorbBar:SetWidth(absorbWidth)
        hp._tfAbsorbBar:Show()
        -- Update tiled overlay texcoord
        if hp._tfAbsorbOverlay and hp._tfAbsorbOverlay.tileSize then
            hp._tfAbsorbOverlay:SetTexCoord(0, absorbWidth / hp._tfAbsorbOverlay.tileSize, 0, barHeight / hp._tfAbsorbOverlay.tileSize)
            hp._tfAbsorbOverlay:Show()
        end
    else
        hp._tfAbsorbBar:Hide()
        if hp._tfAbsorbOverlay then hp._tfAbsorbOverlay:Hide() end
    end

    -- Show overflow glow when absorb exceeds remaining bar space (health + absorb > max)
    if absorbPercent > missingHealthPercent and missingHealthPercent >= 0 then
        hp._tfOverAbsorbGlow:Show()
    else
        hp._tfOverAbsorbGlow:Hide()
    end
end

-- Direct health update (called frequently for regular nameplates)
local function UpdateHealth(unit)
    local myPlate = ns.unitToPlate[unit]
    if not myPlate or not myPlate.hp then return end

    -- Player's own plate is not TurboFace-styled
    if myPlate.isPlayer then return end

    -- Blizzard owns native health min/max/value updates.

    -- Update absorb bar (health changes affect absorb display position)
    UpdateAbsorb(unit, myPlate)

    -- Projected DoT damage sits inside the health fill, so it must follow the
    -- same health changes.
    UpdateDotPrediction(unit, myPlate)

    if ns.BubbleNameplates then
        ns.BubbleNameplates:OnHealthUpdate(myPlate, unit)
    end
end

NP.UpdateHealth = UpdateHealth
-- Additional opt-in CPU targets for burst attribution. These are plain function
-- references and impose no runtime timing overhead unless scriptProfile is active.
ns.RegisterCPUProfileTarget("Nameplates/Visuals:RefreshNameplateAugments", ns.RefreshNameplateAugments)
ns.RegisterCPUProfileTarget("Nameplates/Visuals:HealthUpdate", UpdateHealth)
ns.RegisterCPUProfileTarget("Nameplates/Visuals:AbsorbUpdate", UpdateAbsorb)
ns.RegisterCPUProfileTarget("Nameplates/Visuals:DotPrediction", UpdateDotPrediction)
