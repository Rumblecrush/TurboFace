local _, ns = ...

-- =============================================================================
-- Forever beta hardcoded development preset
--
-- Forever 1.60.1 currently fails to reliably reload addon SavedVariables. Prep67
-- can preload a deliberate external snapshot through ForeverRestoreData.lua.
-- When no valid snapshot exists, the exact-build client falls back to this
-- code-defined preset on every login/reload. Session changes still work, but
-- require the external save step before a reload if they should persist.
--
-- This is NOT a compatibility/staging gate.  It is simply the source of the
-- normal TurboFaceDB settings table on the affected beta build.
-- =============================================================================

local Dev = {
    name = "TurboFace Dev Preset",
    description = "Forever 1.60.1 hardcoded handoff/QoL baseline",
    schemaVersion = ns.DB_VERSION,
    applied = false,
    applyCount = 0,
    restored = false,
    baseName = "Rumblecrush's Preset",
}
ns.ForeverDevPreset = Dev

local function IsTargetBuild()
    if ns.Compat and ns.Compat.IS_TARGET_FOREVER_BUILD ~= nil then
        return ns.Compat.IS_TARGET_FOREVER_BUILD == true
    end
    if type(GetBuildInfo) ~= "function" then return false end
    local version, _, _, toc = GetBuildInfo()
    return WOW_PROJECT_ID == 1
        and tostring(version) == "1.60.1"
        and tonumber(toc) == 16001
end

local function Copy(value)
    if ns.DeepCopy then return ns.DeepCopy(value) end
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[Copy(k)] = Copy(v) end
    return out
end

local function RestoreDataAvailable()
    local meta = _G.TurboFaceForeverRestoreMeta
    return IsTargetBuild()
        and type(meta) == "table"
        and meta.enabled == true
        and tonumber(meta.format) == 1
        and type(_G.TurboFaceDB) == "table"
end

local function BaseData()
    local profiles = ns.Profiles
    if profiles and profiles.GetPreset then
        local base = profiles:GetPreset(Dev.baseName)
        if base and type(base.data) == "table" then
            return Copy(base.data), tonumber(base.schemaVersion) or ns.DB_VERSION
        end
    end
    return Copy(ns.defaults or {}), ns.DB_VERSION
end

local function SetModule(data, family, enabled, children)
    data.modules = type(data.modules) == "table" and data.modules or {}
    local row = { enabled = enabled == true }
    if type(children) == "table" then
        for k, v in pairs(children) do row[k] = v == true end
    end
    data.modules[family] = row
end

local BASE_DATA, BASE_SCHEMA = BaseData()
Dev.schemaVersion = tonumber(BASE_SCHEMA) or ns.DB_VERSION

function Dev:BuildData()
    local data = Copy(BASE_DATA or {})

    -- Handoff baseline: keep the two large visual port families parked while
    -- we exercise the already-prepared utility/runtime surfaces.  SavedVariables
    -- are unreliable on build 69913, so every reload intentionally returns here.
    SetModule(data, "unitframes", false, {
        player = false, target = false, tot = false, party = false, pet = false,
    })
    SetModule(data, "nameplates", false)
    SetModule(data, "auras", false, {
        tot = false, party = false, pet = false,
    })
    SetModule(data, "hotbarPower", false)
    SetModule(data, "playerTicks", true)
    SetModule(data, "swingTimers", true)
    SetModule(data, "castBars", false)
    SetModule(data, "class", false)

    -- QoL/Plus handoff baseline: every section master starts ON.  The flat
    -- TurboFaceDB.plus table is still the source of each individual feature.
    data.modules.plus = {
        enabled = true,
        automation = true,
        social = true,
        interface = true,
        minimap = true,
        chat = true,
        system = true,
        flightBar = true,
        map = true,
    }

    -- "All QoL on" means every BOOLEAN option in the QoL/Plus table starts
    -- true.  Preserve non-boolean tuning (sizes, widths, keywords, zoom/weather
    -- values, textures) from Rumblecrush's Preset/defaults.
    data.plus = type(data.plus) == "table" and data.plus or {}
    local plusDefaults = ns.defaults and ns.defaults.plus
    if type(plusDefaults) == "table" then
        for key, defaultValue in pairs(plusDefaults) do
            if type(defaultValue) == "boolean" then
                data.plus[key] = true
            end
        end
    end

    -- Known-unfinished consumers that can otherwise wake independently of the
    -- module tree.  These remain explicit so defaults cannot silently re-enable
    -- them when the schema grows.
    data.dotPredictionEnabled = false
    data.healPredictionEnabled = false
    data.druidPowerBarEnabled = false
    data.classBuffEnabled = false
    data.combatMeterEnabled = false
    -- Explicit handoff requests: Trainer Spells and both Hearthstone systems
    -- are part of the forced beta baseline.
    data.trainerEnabled = true
    data.hearthEnabled = true
    data.hearthTimerEnabled = true
    data.hearthAutoBindEnabled = true
    data.hearthBatchEnabled = true
    data.leashTimerEnabled = false
    data.trackerEnabled = false
    data.unstuckSkipVisualEnabled = false
    data.warriorOverpowerIndicator = false
    data.hunterCounterattackIndicator = false
    data.auraEnabled = false

    data.quickSetup = type(data.quickSetup) == "table" and data.quickSetup or {}
    data.quickSetup.enabled = false

    -- Preserve the already-working speedrun/HUD surfaces from the development
    -- layout so the handoff build remains useful while QoL is exercised.
    data.groceryEnabled = true
    data.groceryAutoBuy = true
    data.groceryShowButton = true
    data.bagSlotsEnabled = true
    data.netWorthEnabled = true
    data.fpsCounterEnabled = true
    data.talentReminderEnabled = true
    data.lootFrame = type(data.lootFrame) == "table" and data.lootFrame or {}
    data.lootFrame.enabled = true
    data.experienceBar = type(data.experienceBar) == "table" and data.experienceBar or {}
    data.experienceBar.enabled = true

    -- Keep the independent PlayerFrame badge out of the handoff baseline while
    -- Unit Frames are parked.  The Blizzard C_DamageMeter bridge remains in the
    -- codebase for dedicated validation later.
    data.unitframes = type(data.unitframes) == "table" and data.unitframes or {}
    data.unitframes.showPlayerDPS = false

    -- Nameplates are OFF in the handoff baseline.  Keep their stored child
    -- values conservative so a developer who enables the master during a single
    -- session starts from the detached-safe subset rather than native mutation.
    data.showComboPoints = true
    local bubble = type(data.bubbleNameplates) == "table" and data.bubbleNameplates or {}
    data.bubbleNameplates = bubble
    bubble.nameTextShadow = true
    bubble.jobIcon = true
    bubble.friendlyNPCNameTitleOnly = true
    bubble.threatNumber = true
    bubble.threatTextFontSize = tonumber(bubble.threatTextFontSize) or 14
    bubble.swingTimer = true
    bubble.muteAggroSounds = false
    bubble.rarityIconRight = false
    bubble.friendlyPlayerDamagedOnly = false
    bubble.friendlyNPCDamagedOnly = false
    bubble.centerHealthText = true
    bubble.centerHealthTextOnNameplate = true
    bubble.powerBarOverlap = false

    return data
end

function Dev:IsActive()
    return IsTargetBuild()
end

function Dev:ApplyAtLogin()
    if not IsTargetBuild() then return false end
    if RestoreDataAvailable() then
        self.restored = true
        self.applied = false
        return false
    end
    self.restored = false
    TurboFaceDB = self:BuildData()
    TurboFaceDB.dbVersion = tonumber(self.schemaVersion) or ns.DB_VERSION
    self.applied = true
    self.applyCount = (self.applyCount or 0) + 1
    return true
end

function Dev:GetDiagnostics()
    return {
        active = IsTargetBuild(),
        applied = self.applied == true,
        applyCount = self.applyCount or 0,
        restored = self.restored == true or RestoreDataAvailable(),
        restoreGeneratedAt = type(_G.TurboFaceForeverRestoreMeta) == "table"
            and _G.TurboFaceForeverRestoreMeta.generatedAt or nil,
        name = self.name,
        base = self.baseName,
        schemaVersion = self.schemaVersion,
    }
end

-- Surface the code-defined baseline in the normal Profiles tab as documentation
-- and for manual re-application during the same session. On the target beta it
-- is authoritative only when no valid external restore snapshot was preloaded.
if ns.Profiles and type(ns.Profiles.Presets) == "table" then
    local entry = {
        name = Dev.name,
        desc = Dev.description .. " (Forever fallback)",
        schemaVersion = Dev.schemaVersion,
        data = Dev:BuildData(),
    }
    if IsTargetBuild() and not RestoreDataAvailable() then
        -- Without a restore snapshot, the beta client cannot persist a
        -- meaningful preset selection. Show only the fallback baseline.
        ns.Profiles.Presets = { entry }
    else
        ns.Profiles.Presets[#ns.Profiles.Presets + 1] = entry
    end
end
