local _, ns = ...

-- Blizzard 1.15.9 owns whether a rarity icon is shown, which classification it
-- represents, its atlas, scale, and visibility lifecycle. TurboFace owns only
-- an optional anchor amendment for the existing PvE classification texture.
--
-- Move the texture rather than ClassificationFrame itself. Blizzard anchors
-- its native buff list to ClassificationFrame, so moving the parent would also
-- move unrelated Blizzard aura geometry.

local C_NamePlate = C_NamePlate
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local tostring = tostring
local type = type

local PVE_RARITY_ATLASES = {
    ["nameplates-icon-elite-gold"] = true,
    ["UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"] = true,
    ["nameplates-icon-elite-silver"] = true,
}

-- Weak keys follow Blizzard's pooled classification textures.
local rarityIconState = setmetatable({}, { __mode = "k" })
local ApplyNativeRarityIconPositionInternal

local function ResolveNativeRarityIcon(nameplate)
    local unitFrame = nameplate and nameplate.UnitFrame
    local classificationFrame = unitFrame and unitFrame.ClassificationFrame
    local indicator = classificationFrame and classificationFrame.classificationIndicator
    local healthContainer = unitFrame and unitFrame.HealthBarsContainer
    if not (unitFrame and classificationFrame and indicator and healthContainer) then return nil end
    return unitFrame, classificationFrame, indicator, healthContainer
end

local function IsPvERarityIcon(classificationFrame)
    return classificationFrame
        and PVE_RARITY_ATLASES[classificationFrame.classificationAtlasElement] == true
end

local function ShouldMoveRarityIcon(classificationFrame)
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    if ns.c_nameplateRarityIconRight ~= true then return false end
    return IsPvERarityIcon(classificationFrame)
end

local function ApplyBlizzardAnchor(state)
    local indicator = state.indicator
    indicator:ClearAllPoints()
    indicator:SetPoint("CENTER", state.classificationFrame, "CENTER", 0, 0)
    state.moved = false
    return true
end

local function ApplyRightAnchor(state)
    local indicator = state.indicator
    indicator:ClearAllPoints()
    indicator:SetPoint("LEFT", state.healthContainer, "RIGHT", 0, 0)
    state.moved = true
    return true
end

local function ResolveNameplateFromUnitFrame(unitFrame, fallback)
    if unitFrame and type(unitFrame.GetNamePlateFrame) == "function" and securecall then
        local ok, nameplate = pcall(securecall, unitFrame.GetNamePlateFrame, unitFrame)
        if ok and nameplate then return nameplate end
    end
    return fallback
end

local function InstallClassificationHook(state)
    local classificationFrame = state.classificationFrame
    if state.hooked or not (hooksecurefunc and classificationFrame)
        or type(classificationFrame.UpdateClassificationIndicator) ~= "function"
    then
        return
    end

    local ok, err = pcall(hooksecurefunc, classificationFrame, "UpdateClassificationIndicator", function(frame)
        if state.syncing then return end
        state.nameplate = ResolveNameplateFromUnitFrame(state.unitFrame, state.nameplate)
        if state.nameplate and ApplyNativeRarityIconPositionInternal then
            ApplyNativeRarityIconPositionInternal(state.nameplate)
        end
    end)
    if ok then
        state.hooked = true
        state.lastHookError = nil
    else
        state.lastHookError = tostring(err)
    end
end

local function EnsureState(nameplate)
    local unitFrame, classificationFrame, indicator, healthContainer = ResolveNativeRarityIcon(nameplate)
    if not indicator then return nil end

    local state = rarityIconState[indicator]
    if not state then
        state = { moved = false, syncing = false, applyCount = 0 }
        rarityIconState[indicator] = state
    end
    state.nameplate = nameplate
    state.unitFrame = unitFrame
    state.classificationFrame = classificationFrame
    state.indicator = indicator
    state.healthContainer = healthContainer
    InstallClassificationHook(state)
    return state
end

ApplyNativeRarityIconPositionInternal = function(nameplate)
    local state = EnsureState(nameplate)
    if not state or state.syncing then return false end

    state.syncing = true
    local shouldMove = ShouldMoveRarityIcon(state.classificationFrame)
    local ok, result = pcall(shouldMove and ApplyRightAnchor or ApplyBlizzardAnchor, state)
    state.syncing = false
    if not ok then
        state.lastError = tostring(result)
        return false
    end
    state.applyCount = (state.applyCount or 0) + 1
    state.lastError = nil
    return result == true
end

function ns.ApplyNativeRarityIconPosition(nameplate)
    return ApplyNativeRarityIconPositionInternal(nameplate)
end

function ns.RestoreNativeRarityIconPosition(nameplate)
    local _, _, indicator = ResolveNativeRarityIcon(nameplate)
    local state = indicator and rarityIconState[indicator]
    if not state or state.syncing then return false end

    state.syncing = true
    local ok, result = pcall(ApplyBlizzardAnchor, state)
    state.syncing = false
    if not ok then
        state.lastError = tostring(result)
        return false
    end
    state.lastError = nil
    return result == true
end

function ns.RefreshNativeRarityIconPositions()
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if not plates then return end
    for _, nameplate in pairs(plates) do
        ApplyNativeRarityIconPositionInternal(nameplate)
    end
end
