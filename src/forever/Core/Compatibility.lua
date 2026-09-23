local addonName, ns = ...

-- =============================================================================
-- TurboFace Forever compatibility diagnostics
--
-- Runtime activation is owned exclusively by the normal TurboFace option/module
-- gates. This file provides API/capability diagnostics, secret-state tracking,
-- protected-action incident capture, and isolated initialization calls; it does
-- NOT maintain a second safe-boot/staging policy.
-- =============================================================================

local Compat = {}
ns.Compat = Compat

local type, tostring, pairs, ipairs, pcall = type, tostring, pairs, ipairs, pcall
local tinsert, sort, concat = table.insert, table.sort, table.concat
local MAX_INCIDENTS = 250
local MAX_INIT_HISTORY = 250

local function EnsureDB()
    if type(TurboFaceCompatDB) ~= "table" then TurboFaceCompatDB = {} end
    local db = TurboFaceCompatDB
    db.schemaVersion = 2
    -- Prep30 removed the independent safe-boot/staging control plane. Old
    -- fields are intentionally discarded so stale SavedVariables cannot gate
    -- feature activation after upgrading.
    db.mode = nil
    db.autoUnknownSafeBoot = nil
    db.staged = nil
    db.incidents = type(db.incidents) == "table" and db.incidents or {}
    db.initHistory = type(db.initHistory) == "table" and db.initHistory or {}
    db.exports = type(db.exports) == "table" and db.exports or {}
    return db
end

local db = EnsureDB()

local GROUP_ORDER = {
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
Compat.GROUP_ORDER = GROUP_ORDER


local TAG_GROUP = {
    ["QuickSetup:Init"] = "quicksetup",

    ["Auras:Init"] = "auras",
    ["PartyPetAuras:Init"] = "auras",
    ["AuraStyle:Init"] = "auras",

    ["UnitFrames:Init"] = "unitframes",
    ["NanShield:Init"] = "unitframes",
    ["DruidPowerBar:Init"] = "unitframes",

    ["Nameplates:CVarOwnership"] = "nameplates",
    ["Nameplates:CoreEvents"] = "nameplates",
    ["Nameplates:UnitEvents"] = "nameplates",
    ["Nameplates:ComboDriver"] = "nameplates",
    ["Nameplates:CVarRuntime"] = "nameplates",

    ["ClassBuffs:Init"] = "combat",
    ["ClassFeatures:Init"] = "combat",
    ["SwingTimers:Init"] = "combat",
    ["Castbars:Init"] = "combat",
    ["DPSBadge:Init"] = "combat",
    ["CombatMeterProvider:Init"] = "combat",
    ["LeashTimer:Init"] = "combat",

    ["Movers:Init"] = "movers",

    ["Inventory:Init"] = "inventory",
    ["Bank:Init"] = "inventory",
    ["NetWorth:Init"] = "inventory",
    ["BagSlots:Init"] = "inventory",
    ["Grocery:Init"] = "inventory",

    ["FPSCounter:Init"] = "hud",
    ["Hearthstone:Init"] = "hud",
    ["UnstuckSkipsVisual:Init"] = "hud",
    ["HearthBatch:Init"] = "hud",
    ["Tracker:Init"] = "hud",
    ["MinimapButton:Init"] = "hud",
    ["Power:Init"] = "hud",
    ["Loot:Init"] = "hud",
    ["ExperienceBar:Init"] = "hud",
    ["SpeedrunSplits:Init"] = "hud",

    ["DotPrediction:Init"] = "predictions",
    ["HealPrediction:Init"] = "predictions",
    ["UnitFrames:InitDotPrediction"] = "predictions",
    ["UnitFrames:InitHealPrediction"] = "predictions",

    ["Skills:Init"] = "training",
    ["Trainer:Init"] = "training",

    ["PlusAutomation:Init"] = "plus",
    ["PlusSocial:Init"] = "plus",
    ["PlusInterface:Init"] = "plus",
    ["PlusMap:Init"] = "plus",
    ["PlusSystem:Init"] = "plus",
    ["PlusChat:Init"] = "plus",
    ["PlusFlight:Init"] = "plus",
}


-- Forever identity ---------------------------------------------------------------
-- Client-specific adapters may use this identity check, but it is NOT an
-- activation gate. The user's normal Options-panel gates decide what runs.
--
-- The beta's hotfix build advanced from 69913 to 69977 without changing its
-- product version, interface number, or project identity. Build-number equality
-- therefore cannot be an ownership/safety boundary: it silently disabled the
-- detached profession UI and re-enabled unsafe native-frame paths. The stable
-- Forever identity is the full version/interface/project tuple; retain the
-- numeric build only for diagnostics and live-validation records.
local IS_TARGET_FOREVER_BUILD = false
local FOREVER_BUILD
do
    local v, b, buildDate, toc
    if type(GetBuildInfo) == "function" then
        v, b, buildDate, toc = GetBuildInfo()
    end
    FOREVER_BUILD = tostring(b or "")
    if tostring(v) == "1.60.1"
        and tonumber(toc) == 16001 and WOW_PROJECT_ID == 1 then
        IS_TARGET_FOREVER_BUILD = true
    end
end
Compat.IS_TARGET_FOREVER_BUILD = IS_TARGET_FOREVER_BUILD
Compat.FOREVER_BUILD = FOREVER_BUILD

local function Trim(list, max)
    while #list > max do table.remove(list, 1) end
end

function Compat:RecordIncident(kind, tag, detail)
    local row = {
        t = GetTime and GetTime() or 0,
        combat = InCombatLockdown and InCombatLockdown() or false,
        kind = tostring(kind or "unknown"),
        tag = tostring(tag or ""),
        detail = tostring(detail or ""),
    }
    db.incidents[#db.incidents + 1] = row
    Trim(db.incidents, MAX_INCIDENTS)
end

function Compat:RecordInit(tag, group, status, detail)
    local row = {
        t = GetTime and GetTime() or 0,
        tag = tostring(tag or ""),
        group = tostring(group or TAG_GROUP[tag] or "unmapped"),
        status = status,
        detail = detail and tostring(detail) or nil,
    }
    db.initHistory[#db.initHistory + 1] = row
    Trim(db.initHistory, MAX_INIT_HISTORY)
    db.initLatest = db.initLatest or {}
    db.initLatest[row.tag] = row
end

function ns.CompatSafeCall(tag, fn, ...)
    if type(fn) ~= "function" then return nil end
    local group = TAG_GROUP[tag] or "core"
    local ok, err = pcall(fn, ...)
    if ok then
        Compat:RecordInit(tag, group, "PASS")
    else
        Compat:RecordInit(tag, group, "FAIL", err)
        Compat:RecordIncident("init-error", tag, err)
        if ns.Chat then ns:Chat("Compat", ("|cffff5555%s failed:|r %s"):format(tostring(tag), tostring(err))) end
    end
    return ok
end

local function ResolveGlobal(path)
    local value = _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
        if value == nil then return nil end
    end
    return value
end

local function Has(path, expected)
    local v = ResolveGlobal(path)
    if expected then return type(v) == expected, type(v) end
    return v ~= nil, type(v)
end

local CONTRACTS = {
    core = {
        all = {
            { "CreateFrame", "function" }, { "C_Timer.After", "function" },
            { "GetBuildInfo", "function" }, { "InCombatLockdown", "function" },
        },
    },
    auras = {
        any = {
            { "C_UnitAuras.GetAuraDataByIndex", "function" },
            { "UnitBuff", "function" },
        },
        optional = { "BuffFrame", "DebuffFrame" },
    },
    unitframes = {
        all = { { "PlayerFrame" }, { "TargetFrame" }, { "UnitHealth", "function" }, { "UnitPower", "function" } },
        optional = { "TargetFrameToT", "PetFrame", "PartyFrame" },
    },
    nameplates = {
        all = { { "C_NamePlate.GetNamePlateForUnit", "function" }, { "C_NamePlate.GetNamePlates", "function" } },
        optional = { "NamePlateDriverFrame" },
        runtimeVerify = { "nameplate.UnitFrame", "UnitFrame.healthBar", "restricted native FontStrings" },
    },
    combat = {
        all = { { "UnitAttackSpeed", "function" }, { "UnitCastingInfo", "function" } },
        any = { { "CombatLogGetCurrentEventInfo", "function" } },
        runtimeVerify = { "public combat-log readability; private C_CombatLogInternal is intentionally unsupported" },
    },
    inventory = {
        any = { { "C_Container.GetContainerItemInfo", "function" }, { "GetContainerItemInfo", "function" } },
        optional = { "MerchantFrame", "LootFrame" },
    },
    predictions = {
        all = { { "UnitHealth", "function" }, { "UnitHealthMax", "function" } },
        optional = { "UnitGetIncomingHeals", "UnitGetTotalAbsorbs" },
    },
    training = {
        all = {
            { "GetNumTrainerServices", "function" },
            { "GetTrainerServiceInfo", "function" },
            { "BuyTrainerService", "function" },
        },
        optional = {
            "C_TooltipInfo.GetTrainerService",
            "C_Spell.IsSpellDataCached", "C_Spell.RequestLoadSpellData",
            "ClassTrainerFrame", "PlayerSpellsFrame.SpellBookFrame", "SpellBookFrame",
            "C_SpellBook.GetNumSpellBookSkillLines", "GetNumSpellTabs",
        },
    },
    movers = { all = { { "UIParent" }, { "CreateFrame", "function" } }, optional = { "EditModeManagerFrame" } },
    hud = { all = { { "UIParent" }, { "CreateFrame", "function" } } },
    quicksetup = { optional = { "C_EditMode", "Settings", "SetActionBarToggles" }, runtimeVerify = { "protected action-bar state" } },
    plus = { optional = { "C_Map", "C_GossipInfo", "WorldMapFrame", "ChatFrame1" } },
}
Compat.Contracts = CONTRACTS

local function EvalContract(name, contract)
    local row = { group = name, status = "PASS", missing = {}, optionalMissing = {}, present = {}, runtimeVerify = contract.runtimeVerify }
    local function testOne(spec)
        local path, expected = spec[1], spec[2]
        local ok, actual = Has(path, expected)
        if ok then row.present[#row.present + 1] = path else row.missing[#row.missing + 1] = { path = path, expected = expected, actual = actual } end
        return ok
    end
    if contract.all then
        for _, spec in ipairs(contract.all) do testOne(spec) end
        if #row.missing > 0 then row.status = "BLOCKED" end
    end
    if contract.any then
        local any = false
        local failures = {}
        for _, spec in ipairs(contract.any) do
            local path, expected = spec[1], spec[2]
            local ok, actual = Has(path, expected)
            if ok then any = true; row.present[#row.present + 1] = path else failures[#failures + 1] = { path = path, expected = expected, actual = actual } end
        end
        if not any then row.status = "BLOCKED"; for _, f in ipairs(failures) do row.missing[#row.missing + 1] = f end end
    end
    if contract.optional then
        for _, path in ipairs(contract.optional) do if ResolveGlobal(path) == nil then row.optionalMissing[#row.optionalMissing + 1] = path end end
        if row.status == "PASS" and (#row.optionalMissing > 0 or contract.runtimeVerify) then row.status = "VERIFY" end
    elseif contract.runtimeVerify and row.status == "PASS" then
        row.status = "VERIFY"
    end
    return row
end

function Compat:EvaluateCapabilities()
    db.capabilities = {}
    for name, contract in pairs(CONTRACTS) do db.capabilities[name] = EvalContract(name, contract) end
    return db.capabilities
end

local function ClientIdentity()
    local version, build, buildDate, toc = "?", "?", "?", nil
    if GetBuildInfo then version, build, buildDate, toc = GetBuildInfo() end
    return {
        clientVersion = version, build = tostring(build or "?"), buildDate = buildDate,
        tocVersion = tonumber(toc), projectID = WOW_PROJECT_ID,
        locale = GetLocale and GetLocale() or nil,
        expansionLevel = GetExpansionLevel and GetExpansionLevel() or nil,
    }
end

function Compat:OnLogin()
    db = EnsureDB()
    db.lastLogin = {
        at = date and date("%Y-%m-%d %H:%M:%S") or tostring(GetTime and GetTime() or 0),
        client = ClientIdentity(),
        activation = "options-only",
    }
    self:EvaluateCapabilities()
    self:UpdateSecretRestrictions("PLAYER_LOGIN")
end

function Compat:UpdateSecretRestrictions(reason)
    local api = ns.API or {}
    local auras = type(api.ShouldAurasBeSecret) == "function" and api.ShouldAurasBeSecret() or false
    local cooldowns = type(api.ShouldCooldownsBeSecret) == "function" and api.ShouldCooldownsBeSecret() or false
    local previous = db.secretRestrictions
    db.secretRestrictions = {
        auras = auras == true,
        cooldowns = cooldowns == true,
        active = auras == true or cooldowns == true,
        at = GetTime and GetTime() or 0,
        reason = tostring(reason or "probe"),
    }
    if previous and (previous.auras ~= db.secretRestrictions.auras or previous.cooldowns ~= db.secretRestrictions.cooldowns) then
        self:RecordIncident("restriction-change", reason,
            ("auras=%s cooldowns=%s"):format(tostring(auras), tostring(cooldowns)))
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if ns.AuraStyle and ns.AuraStyle.ApplySettings then ns.AuraStyle:ApplySettings() end
                if ns.PartyAuras and ns.PartyAuras.Refresh then ns.PartyAuras:Refresh() end
                if ns.UpdateAllPlates then ns:UpdateAllPlates() end
            end)
        end
    end
    return db.secretRestrictions
end

function Compat:GetSecretRestrictions()
    return db.secretRestrictions or self:UpdateSecretRestrictions("query")
end

local diagnosticFrame = CreateFrame("Frame")
diagnosticFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, func = ...
        if addon == addonName then Compat:RecordIncident("protected-action", event, tostring(func)) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        db.combatState = "combat"
    elseif event == "PLAYER_REGEN_ENABLED" then
        db.combatState = "ooc"
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_IN_COMBAT_CHANGED"
        or event == "ENCOUNTER_STATE_CHANGED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET"
        or event == "PVP_MATCH_ACTIVE"
        or event == "PVP_MATCH_COMPLETE" then
        Compat:UpdateSecretRestrictions(event)
        -- Activating restrictions may settle after the notification itself.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() Compat:UpdateSecretRestrictions(event .. ":next-frame") end)
        end
    end
end)
for _, e in ipairs({
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_IN_COMBAT_CHANGED",
    "ENCOUNTER_STATE_CHANGED", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE",
}) do
    pcall(diagnosticFrame.RegisterEvent, diagnosticFrame, e)
end

local function Chat(msg) if ns.Chat then ns:Chat("Compat", msg) elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("TurboFace Compat: "..msg) end end

local function Status()
    local caps = db.capabilities or Compat:EvaluateCapabilities()
    local parts = {}
    for _, g in ipairs(GROUP_ORDER) do
        local row = caps[g]
        parts[#parts + 1] = g .. "=" .. (row and row.status or "?")
    end
    Chat(("activation=options-only project=%s forever=%s build=%s"):format(
        tostring(WOW_PROJECT_ID), tostring(IS_TARGET_FOREVER_BUILD), tostring(FOREVER_BUILD)))
    local secrets = Compat:GetSecretRestrictions()
    Chat(("secrets: active=%s auras=%s cooldowns=%s reason=%s"):format(
        tostring(secrets.active), tostring(secrets.auras), tostring(secrets.cooldowns), tostring(secrets.reason)))
    Chat("caps: " .. concat(parts, " "))
end

function Compat:GetPortMatrix()
    local client = ns.Client
    if client and type(client.GetPortMatrix) == "function" then
        return client:GetPortMatrix()
    end
    return {}
end

local function Plan()
    Chat("Client feature matrix (implementation ownership + live-validation state):")
    local matrix = Compat:GetPortMatrix()
    local order = ns.Client and ns.Client.GROUP_ORDER or GROUP_ORDER
    for _, group in ipairs(order) do
        local row = matrix[group]
        Chat(("%s=%s validation=%s available=%s - %s"):format(
            group,
            row and row.state or "UNKNOWN",
            row and row.validation or "unknown",
            tostring(row and row.available == true),
            row and row.detail or "not classified"))
    end
    if ns.Providers then
        Chat(("providers: combatMeter=%s combatUI=%s swingTimers=%s nameplates=%s unitframes=%s plusUI=%s trainerUI=%s"):format(
            tostring(ns.Providers:GetName("combatMeter") or "none"),
            tostring(ns.Providers:GetName("combatUI") or "none"),
            tostring(ns.Providers:GetName("swingTimers") or "none"),
            tostring(ns.Providers:GetName("nameplates") or "none"),
            tostring(ns.Providers:GetName("unitframes") or "none"),
            tostring(ns.Providers:GetName("plusUI") or "none"),
            tostring(ns.Providers:GetName("trainerUI") or "none")))
    end
end

local function Export()
    local key = tostring((db.lastLogin and db.lastLogin.client and db.lastLogin.client.build) or "unknown") .. "-" .. tostring(time and time() or math.floor(GetTime and GetTime() or 0))
    db.exports[key] = {
        schemaVersion = db.schemaVersion,
        tool = "TurboFace ForeverPrep",
        client = db.lastLogin and db.lastLogin.client or ClientIdentity(),
        activation = "options-only",
        capabilities = ns.DeepCopy and ns.DeepCopy(db.capabilities or {}) or db.capabilities,
        initLatest = ns.DeepCopy and ns.DeepCopy(db.initLatest or {}) or db.initLatest,
        initHistory = ns.DeepCopy and ns.DeepCopy(db.initHistory or {}) or db.initHistory,
        incidents = ns.DeepCopy and ns.DeepCopy(db.incidents or {}) or db.incidents,
        portMatrix = ns.DeepCopy and ns.DeepCopy(Compat:GetPortMatrix()) or Compat:GetPortMatrix(),
        providers = ns.Providers and {
            combatMeter = ns.Providers:GetName("combatMeter"),
            combatUI = ns.Providers:GetName("combatUI"),
            swingTimers = ns.Providers:GetName("swingTimers"),
            nameplates = ns.Providers:GetName("nameplates"),
            unitframes = ns.Providers:GetName("unitframes"),
            plusUI = ns.Providers:GetName("plusUI"),
            trainerUI = ns.Providers:GetName("trainerUI"),
        } or nil,
        secretRestrictions = ns.DeepCopy and ns.DeepCopy(Compat:GetSecretRestrictions()) or Compat:GetSecretRestrictions(),
    }
    db.latestExport = key
    Chat("diagnostic export frozen in TurboFaceCompatDB.exports[" .. key .. "]; upload TurboFace saved variables")
end

function Compat:HandleSlash(args)
    args = (args or ""):lower():match("^%s*(.-)%s*$") or ""
    local cmd = args:match("^(%S+)") or "status"
    if cmd == "status" or cmd == "report" then Status(); return true end
    if cmd == "plan" or cmd == "matrix" then Plan(); return true end
    if cmd == "caps" then self:EvaluateCapabilities(); Status(); return true end
    if cmd == "export" then Export(); return true end
    Chat("activation is controlled only by TurboFace Options; commands: status | caps | plan | export")
    return true
end

ns.CompatSafeCall = ns.CompatSafeCall
