local _, ns = ...

-- =============================================================================
-- TurboFace client policy / feature registry
--
-- This file answers one question only: what implementation class is valid for
-- a TurboFace feature on the current client?  It is deliberately separate from
-- Core/Compat.lua (API-shape normalization) and from TurboFaceDB (user choices).
--
-- A stored setting may remain enabled while this registry says the current
-- client cannot safely implement it.  That preserves portable profiles without
-- turning capability state into another user preference system.
-- =============================================================================

local Client = {}
ns.Client = Client

-- Validation vocabulary is deliberately finite.  These values describe how
-- much in-client proof exists for an implementation; they are not feature
-- enable/disable gates and are never persisted as user configuration.
Client.VALIDATION = {
    CLASSIC_BASELINE = "classic-baseline",
    PREPARED         = "prepared",
    LIVE_PARTIAL     = "live-partial",
    LIVE_VALIDATED   = "live-validated",
    BLOCKED          = "blocked",
}

local VALIDATION = Client.VALIDATION

Client.GROUP_ORDER = {
    "quicksetup",
    "auras",
    "unitframes",
    "nameplates",
    "combat",
    "movers",
    "inventory",
    "hud",
    "predictions",
    "training",
    "plus",
}

local version, build, buildDate, interface
if type(GetBuildInfo) == "function" then
    version, build, buildDate, interface = GetBuildInfo()
end

local isForever = ns.Compat and ns.Compat.IS_TARGET_FOREVER_BUILD == true
Client.flavor = isForever and "forever" or "classic"
Client.isForever = isForever
-- Client-owned visual assets live in policy rather than in shared consumers.
-- This keeps presentation modules physically common while preserving each
-- client's validated artwork choice.
Client.assets = {
    bankIconTexture = isForever
        and "Interface\\Minimap\\Tracking\\Banker"
        or "Interface\\AddOns\\TurboFace\\Textures\\BankIcon.tga",
}

function Client:GetAsset(key, fallback)
    local value = self.assets and self.assets[key]
    if value == nil then return fallback end
    return value
end

-- Options policy captures presentation/lifecycle differences that are not
-- user-facing feature availability. Shared OptionsGUI consumes this table so
-- it never needs to branch on build identity directly.
Client.optionPolicy = {
    detachedNameplates = isForever,
    requireDetachedNameplateAdapter = isForever,
    liveAdapterFamilies = isForever,
    centerHealthLabel = isForever and "Center Health Text" or "Center Blizzard Health Text",
}

function Client:GetOptionPolicy(key)
    return self.optionPolicy and self.optionPolicy[key]
end

-- Development restrictions keep known-incomplete Forever surfaces visible in
-- Options without presenting them as supported. The bypass is deliberately
-- stored outside portable profiles so enabling a test path never changes what
-- another client sees after importing the same profile.
Client.DEVELOPMENT_DISABLED_TOOLTIP = "This feature is currently disabled on Forever"
Client.developmentRestrictedSettings = isForever and {
    ["dotPredictionEnabled"] = "global.dotPrediction",
    ["healPredictionEnabled"] = "global.healPrediction",
    ["bubbleNameplates.friendlyNPCNameTitleOnly"] = "nameplates.friendlyNPCTitle",
    ["bubbleNameplates.friendlyPlayerDamagedOnly"] = "nameplates.friendlyPlayerDamagedOnly",
    ["bubbleNameplates.friendlyNPCDamagedOnly"] = "nameplates.friendlyNPCDamagedOnly",
} or {}
Client.developmentRestrictedGates = isForever and {
    unitframes = "unitframes.master",
    class = "class.master",
} or {}

function Client:IsDevBypassActive()
    return self.isForever == true
        and type(TurboFaceCompatDB) == "table"
        and TurboFaceCompatDB.devFeatureBypass == true
end

function Client:SetDevBypass(active)
    if not self.isForever then return false end
    TurboFaceCompatDB = type(TurboFaceCompatDB) == "table" and TurboFaceCompatDB or {}
    TurboFaceCompatDB.devFeatureBypass = active == true or nil
    return self:IsDevBypassActive()
end

function Client:GetSettingDevelopmentRestriction(path)
    return type(path) == "string" and self.developmentRestrictedSettings[path] or nil
end

function Client:GetGateDevelopmentRestriction(family)
    if type(family) == "table" and family.dbKey then
        return self:GetSettingDevelopmentRestriction(family.dbKey)
    end
    return type(family) == "string" and self.developmentRestrictedGates[family] or nil
end

function Client:IsDevelopmentRestrictionActive(key)
    return key ~= nil and self.isForever == true and not self:IsDevBypassActive()
end

function Client:IsSettingDevelopmentRestricted(path)
    return self:IsDevelopmentRestrictionActive(self:GetSettingDevelopmentRestriction(path))
end

function Client:IsGateDevelopmentRestricted(family)
    return self:IsDevelopmentRestrictionActive(self:GetGateDevelopmentRestriction(family))
end

-- Core runtime policy isolates lifecycle/ownership differences that cannot be
-- inferred safely from API presence alone. Shared Core.lua consumes these
-- capabilities rather than branching on client/build identity.
Client.corePolicy = {
    detachedNameplateAdapter = isForever,
    deferNativeNameplateCallbacks = isForever,
    staticFriendlyIdentityRestore = isForever,
    styleNativeNameplateCastbar = isForever,
    installNativeDriverAddedHook = not isForever,
    combatMeterBeforeBadge = isForever,
    extendedDiagnostics = isForever,
    developmentFeatureBypass = isForever,
}

function Client:GetCorePolicy(key)
    return self.corePolicy and self.corePolicy[key]
end

-- Quick Setup policy isolates persistence and modern action/Edit Mode semantics.
-- The shared engine consumes these capabilities without checking client identity.
Client.quickSetupPolicy = {
    modernMacroLimits = isForever,
    cvarBaseline = isForever,
    oneBasedEditModeLayout = isForever,
    macroScopeBySnapshot = isForever,
    preserveUnsupportedActions = isForever,
    externalPersistence = isForever,
    immediateManualApply = isForever,
    immediateResetRetry = isForever,
}

function Client:GetQuickSetupPolicy(key)
    return self.quickSetupPolicy and self.quickSetupPolicy[key]
end

Client.identity = {
    flavor = Client.flavor,
    version = tostring(version or ""),
    build = tostring(build or ""),
    buildDate = tostring(buildDate or ""),
    interface = tonumber(interface),
    projectID = WOW_PROJECT_ID,
}

local function Row(implementation, available, validation, owner, detail)
    return {
        implementation = implementation,
        available = available ~= false,
        validation = validation,
        owner = owner,
        detail = detail,
    }
end

-- Classic remains the semantic baseline for portable settings.  These rows are
-- intentionally high level: the registry describes implementation ownership,
-- not every API capability (Core/Compat.lua owns that lower-level inventory).
local FEATURES = {
    quicksetup = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic Quick Setup implementation"),
    auras = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic aura presentation"),
    unitframes = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic TurboFace Unit Frames"),
    nameplates = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic native-nameplate augmentation"),
    combat = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic combat systems"),
    movers = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "TurboFace-owned mover surfaces"),
    inventory = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Inventory, bank, grocery and bag utilities"),
    hud = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Speedrun and utility HUD features"),
    predictions = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic DoT/heal/absorb prediction inputs are readable"),
    training = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic trainer, Skills and profession presentation"),
    plus = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic QoL feature family"),

    ["hotbarPower"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "shared", "Classic readable-resource action overlay"),
    ["hud.spendTalentPoint"] = Row("shared", false, VALIDATION.CLASSIC_BASELINE, "none", "Classic retains the ClassBuffs unspent-talent icon reminder"),
    ["plus.questLevels"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace quest-level prefix and difficulty tags"),
    ["plus.combinedBagMovable"] = Row("shared", false, VALIDATION.CLASSIC_BASELINE, "none", "Classic uses separate bag-window ownership"),
    ["plus.vendorPrice"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace vendor-price tooltip augmentation"),
    ["combat.classBuffTalentReminder"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "Classic ClassBuffs unspent-talent icon reminder"),
    ["combat.reactiveNameplateIndicator"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "Classic reactive ability indicator on Era nameplates"),
    ["combat.localMeterWindow"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace CLEU Combat Meter window"),
    ["nameplates.nameTextShadow"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace native-name FontObject amendment"),
    ["plus.mapEnhancedZoom"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace windowed-map zoom amendment"),
    ["plus.mapRememberZoom"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace windowed-map pan/zoom persistence"),
    ["movers.questTracker"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "TurboFace Objective Tracker mover"),
    ["predictions.dotRendering"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "Classic DoT prediction rendering"),
    ["predictions.healRendering"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "Classic heal prediction rendering"),
    ["unitframes.nanShield"] = Row("shared", true, VALIDATION.CLASSIC_BASELINE, "turboface", "Classic custom absorb reconstruction"),
}

local function Override(key, implementation, available, validation, owner, detail)
    FEATURES[key] = Row(implementation, available, validation, owner, detail)
end

if isForever then
    Override("quicksetup", "adapted", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "Modern macro limits/action placement and Edit Mode adapters; destructive restore remains guarded")
    Override("auras", "adapted", true, VALIDATION.LIVE_PARTIAL, "forever", "Forever nameplate auras use detached Blizzard AuraContainers; other aura consumers remain independently gated")
    Override("unitframes", "reduced", true, VALIDATION.PREPARED, "shared+forever", "Shared UnitFrame policy selects the Forever native-safe provider; Blizzard owns secure frames/bars/values while detached TurboFace artwork remains supported and Classic-only prediction/absorb/Druid auxiliary renderers stay dormant")
    Override("nameplates", "reduced", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "Shared nameplate policy selects the Forever detached provider; Blizzard owns pooled CompactUnitFrames while TurboFace uses external side tables and UIParent-owned overlays")
    Override("combat", "reduced", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "PLAYER_SWING and public C_DamageMeter replace several Classic data paths")
    Override("movers", "reduced", true, VALIDATION.LIVE_PARTIAL, "shared", "Addon-owned surfaces remain movable; protected Blizzard-native surfaces may be yielded to Edit Mode")
    Override("inventory", "adapted", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "Modern pooled bags/bank and structured merchant data are adapted behind shared policy")
    Override("hud", "adapted", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "Most TurboFace-owned HUD widgets remain shared; secret-resource consumers require individual adapters")
    Override("predictions", "blocked", false, VALIDATION.BLOCKED, "none", "Classic prediction renderers require health/aura/absorb values that can be secret on Forever")
    Override("training", "adapted", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "Detached Spellbook/Professions presentation and modern spell/trainer APIs preserve the shared queue/data model")
    Override("plus", "reduced", true, VALIDATION.LIVE_PARTIAL, "shared+forever", "QoL remains feature-by-feature; protected MapCanvas/Objective Tracker ownership is yielded to Blizzard")

    Override("hotbarPower", "adapted", true, VALIDATION.LIVE_VALIDATED, "forever", "Detached action overlays, native macro spell resolution and secret-safe power curves")
    Override("hud.spendTalentPoint", "adapted", true, VALIDATION.LIVE_VALIDATED, "forever", "Standalone Speedrun text reminder replaces the Classic ClassBuffs icon reminder")
    Override("plus.questLevels", "blizzard-owned", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Forever owns quest-level presentation natively; TurboFace retains difficulty tags only")
    Override("plus.combinedBagMovable", "adapted", true, VALIDATION.LIVE_VALIDATED, "forever", "TurboFace can move Blizzard's combined bag through the Forever Interface adapter")
    Override("plus.vendorPrice", "blizzard-owned", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Forever tooltip ownership replaces TurboFace's legacy vendor-price augmentation")
    Override("combat.classBuffTalentReminder", "adapted", false, VALIDATION.LIVE_VALIDATED, "forever", "Forever owns unspent talent points through the standalone Speedrun text reminder")
    Override("combat.reactiveNameplateIndicator", "blocked", false, VALIDATION.BLOCKED, "none", "Forever pooled CompactUnitFrames forbid the Classic reactive-indicator ownership model")
    Override("combat.localMeterWindow", "blizzard-owned", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Forever uses Blizzard C_DamageMeter; TurboFace retains only the independent DPS/HPS badge bridge")
    Override("nameplates.nameTextShadow", "blizzard-owned", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Forever's native nameplate name already supplies its own shadow")
    Override("plus.mapEnhancedZoom", "blocked", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Protected MapCanvas/provider/pin ownership remains Blizzard-exclusive")
    Override("plus.mapRememberZoom", "blocked", false, VALIDATION.LIVE_VALIDATED, "blizzard", "TurboFace does not sample or restore protected Forever MapCanvas pan/zoom state")
    Override("movers.questTracker", "blizzard-owned", false, VALIDATION.LIVE_VALIDATED, "blizzard", "Use Blizzard Edit Mode; TurboFace does not hook or mutate the Forever Objective Tracker")
    Override("predictions.dotRendering", "blocked", false, VALIDATION.BLOCKED, "none", "Secret health/aura inputs prevent the Classic numeric renderer")
    Override("predictions.healRendering", "blocked", false, VALIDATION.BLOCKED, "none", "Secret health/incoming-heal inputs prevent the Classic numeric renderer")
    Override("unitframes.nanShield", "blocked", false, VALIDATION.BLOCKED, "none", "Secret absorb/health state and protected native bars prevent the Classic reconstruction path")
end

Client.features = FEATURES

function Client:GetFeature(key)
    if type(key) ~= "string" then return nil end
    return FEATURES[key]
end

function Client:IsFeatureAvailable(key, fallback)
    local row = self:GetFeature(key)
    if row == nil then
        if fallback == nil then return true end
        return fallback == true
    end
    return row.available ~= false
end

function Client:IsForever()
    return self.isForever == true
end

function Client:GetPortMatrix()
    local out = {}
    for _, key in ipairs(self.GROUP_ORDER) do
        local row = FEATURES[key]
        out[key] = {
            state = row and string.upper(row.implementation or "unknown") or "UNKNOWN",
            implementation = row and row.implementation or "unknown",
            validation = row and row.validation or "unknown",
            available = row and row.available ~= false or false,
            owner = row and row.owner or nil,
            detail = row and row.detail or "not classified",
        }
    end
    return out
end

-- Lightweight shared call site for code that should not care which client
-- selected the implementation.  This is capability state only; user enable/
-- disable state remains in TurboFaceDB and must still be checked separately.
function ns.FeatureAvailable(key, fallback)
    return Client:IsFeatureAvailable(key, fallback)
end
