local _, ns = ...

-- Blizzard owns native full-plate identity: text, color, anchors, visibility,
-- truncation, and update lifecycle. TurboFace's optional name-shadow setting
-- augments only the font presentation.
--
-- Classic Era testing showed that direct FontString SetShadow* state can be
-- retained by the SLUG name renderer without producing a visible shadow, while
-- Blizzard-style FontObject inheritance renders native shadows correctly. This
-- implementation therefore clones the live Blizzard font presentation into a
-- private runtime FontObject, preserves the source face/size/flags (including
-- SLUG), adds TurboFace's black 2,-2 native shadow, and assigns that FontObject
-- back to the Blizzard-owned name FontString. No duplicate glyph underlay is
-- used in this test path.

local C_NamePlate = C_NamePlate
local UnitExists = ns.API.ReadUnitExists
local UnitIsPlayer = ns.API.ReadUnitIsPlayer
local UnitPlayerControlled = ns.API.ReadUnitPlayerControlled
local UnitIsUnit = ns.API.ReadUnitIsUnit
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local tostring = tostring
local type = type

local SHADOW_X, SHADOW_Y = 2, -2

-- Blizzard name FontStrings are pooled, so weak keys keep the state bounded to
-- the lifetime of those native regions.
local nativeNameShadowState = setmetatable({}, { __mode = "k" })
local nativeShadowFontSerial = 0

local function ResolveNativeName(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    return uf and uf.name or nil
end

local function UnitBelongsToNameplate(nameplate, unit)
    if not (nameplate and unit and UnitExists(unit)) then return false end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local assigned = C_NamePlate.GetNamePlateForUnit(unit)
        if assigned ~= nil then return assigned == nameplate end
    end
    return true
end

local function ResolveUnit(nameplate, preferredUnit)
    if UnitBelongsToNameplate(nameplate, preferredUnit) then return preferredUnit end

    local uf = nameplate and nameplate.UnitFrame
    local nativeUnit = uf and uf.unit
    if UnitBelongsToNameplate(nameplate, nativeUnit) then return nativeUnit end

    local api = ns.API
    local mappedUnit = api and api.GetPlateUnitToken and api.GetPlateUnitToken(nameplate) or nil
    if UnitBelongsToNameplate(nameplate, mappedUnit) then return mappedUnit end
    return nil
end

local function ShouldStyleNativeName(nameplate, unit)
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    if ns.c_nameplateNameTextShadow == false then return false end
    if not (nameplate and (nameplate._tfTurboNativeHealthChassis == true or nameplate._tfTurboNativeIdentityOnly == true)) then return false end

    unit = ResolveUnit(nameplate, unit)
    if not unit then return false end

    -- Player characters are valid shadow targets on both friendly and hostile
    -- native nameplates. Player-controlled non-player units (pets/guardians)
    -- remain excluded, and the player's own personal plate is not augmented.
    if UnitIsPlayer(unit) then
        if UnitIsUnit and UnitIsUnit(unit, "player") then return false end
    elseif UnitPlayerControlled and UnitPlayerControlled(unit) then
        return false
    end
    return ResolveNativeName(nameplate) ~= nil
end

local function CapturePresentation(source)
    local p = {}
    if source.GetTextColor then p.r, p.g, p.b, p.a = source:GetTextColor() end
    if source.GetJustifyH then p.justifyH = source:GetJustifyH() end
    if source.GetJustifyV then p.justifyV = source:GetJustifyV() end
    if source.GetSpacing then p.spacing = source:GetSpacing() end
    return p
end

local function RestorePresentation(source, p)
    if not (source and p) then return end
    if p.r ~= nil and source.SetTextColor then source:SetTextColor(p.r, p.g, p.b, p.a) end
    if p.justifyH and source.SetJustifyH then source:SetJustifyH(p.justifyH) end
    if p.justifyV and source.SetJustifyV then source:SetJustifyV(p.justifyV) end
    if p.spacing ~= nil and source.SetSpacing then source:SetSpacing(p.spacing) end
end

local function CaptureBlizzardFontState(state)
    local source = state.source
    if not (source and source.GetFont) then return false end

    local currentObject = source.GetFontObject and source:GetFontObject() or nil
    if currentObject and currentObject == state.shadowFontObject then
        -- Our FontObject is already active; the last captured Blizzard state is
        -- still the restoration/configuration source of truth.
        return state.basePath ~= nil and state.baseSize ~= nil
    end

    local path, size, flags = source:GetFont()
    if not path or not size then return false end

    state.baseFontObject = currentObject
    state.basePath = path
    state.baseSize = size
    state.baseFlags = flags or ""

    if source.GetShadowColor then
        state.baseShadowR, state.baseShadowG, state.baseShadowB, state.baseShadowA = source:GetShadowColor()
    end
    if source.GetShadowOffset then
        state.baseShadowX, state.baseShadowY = source:GetShadowOffset()
    end
    return true
end

local function EnsureShadowFontObject(state)
    if state.shadowFontObject then return state.shadowFontObject end
    if not CreateFont then return nil end

    nativeShadowFontSerial = nativeShadowFontSerial + 1
    state.shadowFontObject = CreateFont("TurboFaceNativeNameShadowFont" .. nativeShadowFontSerial)
    return state.shadowFontObject
end

local function ConfigureShadowFontObject(state)
    local obj = EnsureShadowFontObject(state)
    if not obj then
        state.lastError = "CreateFont unavailable"
        return false
    end

    local path, size, flags = state.basePath, state.baseSize, state.baseFlags or ""
    if not path or not size then
        state.lastError = "missing captured Blizzard font"
        return false
    end

    local called, result = pcall(obj.SetFont, obj, path, size, flags)
    if not called or result == false then
        -- Do not strip SLUG or otherwise alter Blizzard's name-rendering flags
        -- just to force the test through. If the exact live font cannot be
        -- cloned, leave Blizzard's name untouched and report the failure.
        state.lastError = "runtime FontObject rejected live font flags=" .. tostring(flags)
        return false
    end

    if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 1) end
    if obj.SetShadowOffset then obj:SetShadowOffset(SHADOW_X, SHADOW_Y) end
    return true
end

local function ApplyShadowFontObject(state)
    local source = state.source
    if not (source and source.SetFontObject) then
        state.lastError = "native name has no SetFontObject"
        return false
    end

    if not CaptureBlizzardFontState(state) then
        state.lastError = state.lastError or "could not capture Blizzard font"
        return false
    end
    if not ConfigureShadowFontObject(state) then return false end

    local currentObject = source.GetFontObject and source:GetFontObject() or nil
    if currentObject == state.shadowFontObject then
        state.lastError = nil
        return true
    end

    local presentation = CapturePresentation(source)
    state.syncing = true
    local ok, err = pcall(source.SetFontObject, source, state.shadowFontObject)
    state.syncing = false
    RestorePresentation(source, presentation)

    if not ok then
        state.lastError = tostring(err)
        return false
    end

    state.lastError = nil
    return true
end

local function RestoreBlizzardFont(state)
    local source = state and state.source
    if not source then return false end

    local currentObject = source.GetFontObject and source:GetFontObject() or nil
    if currentObject ~= state.shadowFontObject then
        -- Blizzard already replaced our object; nothing remains to restore.
        return true
    end

    local presentation = CapturePresentation(source)
    state.syncing = true
    local ok, err
    if state.baseFontObject and source.SetFontObject then
        ok, err = pcall(source.SetFontObject, source, state.baseFontObject)
    elseif state.basePath and state.baseSize and source.SetFont then
        ok, err = pcall(source.SetFont, source, state.basePath, state.baseSize, state.baseFlags or "")
    else
        ok = false
        err = "no captured Blizzard font to restore"
    end
    state.syncing = false
    RestorePresentation(source, presentation)

    if not ok then
        state.lastError = tostring(err)
        return false
    end

    -- Only the SetFont fallback needs its direct FontString shadow state
    -- restored. A restored Blizzard FontObject owns its own shadow attributes.
    if not state.baseFontObject then
        if source.SetShadowColor and state.baseShadowR ~= nil then
            source:SetShadowColor(state.baseShadowR, state.baseShadowG, state.baseShadowB, state.baseShadowA)
        end
        if source.SetShadowOffset and state.baseShadowX ~= nil then
            source:SetShadowOffset(state.baseShadowX, state.baseShadowY)
        end
    end

    state.lastError = nil
    return true
end

local ApplyNativeShadowState

local SOURCE_FONT_HOOK_METHODS = {
    "SetFont",
    "SetFontObject",
    "SetTextHeight",
}

local function InstallSourceHooks(state)
    if state.hooksInstalled then return end
    state.hooksInstalled = true
    if not hooksecurefunc then return end

    local source = state.source
    local function OnNativeFontChanged()
        if state.syncing then return end
        if state.enabled then ApplyNativeShadowState(state) end
    end
    state.hookCallback = OnNativeFontChanged

    for i = 1, #SOURCE_FONT_HOOK_METHODS do
        local method = SOURCE_FONT_HOOK_METHODS[i]
        if type(source[method]) == "function" then
            pcall(hooksecurefunc, source, method, OnNativeFontChanged)
        end
    end
end

local function EnsureState(nameplate)
    local source = ResolveNativeName(nameplate)
    if not source then return nil end

    local state = nativeNameShadowState[source]
    if state then
        state.nameplate = nameplate
        return state
    end

    state = {
        nameplate = nameplate,
        source = source,
        enabled = false,
        syncing = false,
    }
    nativeNameShadowState[source] = state
    InstallSourceHooks(state)
    return state
end

ApplyNativeShadowState = function(state)
    if not (state and state.source) or state.syncing then return false end

    local unit = ResolveUnit(state.nameplate, state.unit)
    state.unit = unit
    if not (state.enabled and ShouldStyleNativeName(state.nameplate, unit)) then
        return RestoreBlizzardFont(state)
    end

    return ApplyShadowFontObject(state)
end

function ns.RestoreNativeNameplateNameShadow(nameplate)
    local source = ResolveNativeName(nameplate)
    local state = source and nativeNameShadowState[source]
    if not state then return false end

    state.enabled = false
    state.unit = nil
    return RestoreBlizzardFont(state)
end

function ns.ApplyNativeNameShadow(nameplate, unit)
    if not ShouldStyleNativeName(nameplate, unit) then
        ns.RestoreNativeNameplateNameShadow(nameplate)
        return false
    end

    local state = EnsureState(nameplate)
    if not state then return false end
    state.enabled = true
    state.unit = ResolveUnit(nameplate, unit)
    return ApplyNativeShadowState(state)
end

function ns.RefreshNativeNameShadows()
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if not plates then return end

    for _, nameplate in pairs(plates) do
        local unit = ResolveUnit(nameplate)
        if ShouldStyleNativeName(nameplate, unit) then
            ns.ApplyNativeNameShadow(nameplate, unit)
        else
            ns.RestoreNativeNameplateNameShadow(nameplate)
        end
    end
end

function ns.IsNativeNameShadowApplied(nameplate)
    local source = ResolveNativeName(nameplate)
    local state = source and nativeNameShadowState[source]
    if not (state and state.enabled and ShouldStyleNativeName(nameplate, ResolveUnit(nameplate, state.unit))) then
        return false
    end
    local currentObject = source.GetFontObject and source:GetFontObject() or nil
    return currentObject == state.shadowFontObject
end

function ns.IsNativeNameShadowVisible(nameplate)
    if not ns.IsNativeNameShadowApplied(nameplate) then return false end
    local source = ResolveNativeName(nameplate)
    if source and source.IsVisible then return source:IsVisible() end
    return source and source.IsShown and source:IsShown() or false
end

-- Retained for debug-call compatibility. The native FontObject implementation
-- intentionally has no duplicate underlay region.
function ns.GetNativeNameShadowUnderlay(nameplate)
    return nil
end

function ns.GetNativeNameShadowError(nameplate)
    local source = ResolveNativeName(nameplate)
    local state = source and nativeNameShadowState[source]
    return state and state.lastError or nil
end

function ns.GetNativeNameShadowOffset()
    return SHADOW_X, SHADOW_Y
end

function ns.GetNativeNameShadowMode()
    return "native-fontobject"
end
