local _, ns = ...

-- =============================================================================
-- TurboFace Compat.lua — the single API boundary (loads before all modules)
--
-- BASELINE (2026-07): Classic Era 1.15.9. Blizzard's official guidance: the
-- 1.15.9 addon API "very closely matches the addon API from 2.5.6" (TBC
-- Classic) — that 2.5.6-like surface IS the baseline TurboFace is written
-- against. Compat's two jobs under this baseline:
--   1. Adapt the few places module code still speaks an older dialect
--      (renamed events, mixin-ported FrameXML hooks, renamed frame fields).
--   2. Absorb FUTURE drift from this baseline — notably the upcoming fresh
--      Classic launch client — here, in one place, never at call sites.
-- Legacy pre-1.15.9 fallback branches (old global hooks, BuffButton walks,
-- etc.) are kept until the Classic launch client ships and is verified on it;
-- after that they become removable.
--
-- Every WoW API that differs across clients goes through ns.API. Modules
-- alias from here, never from _G:
--
--     local GetSpellInfo = ns.API.GetSpellInfo
--
-- Rules:
--   * FEATURE-DETECT, never version-check. If the native global exists we use
--     it directly (zero overhead — ns.API.X *is* the native function). If only
--     a C_* namespace exists, a thin adapter normalizes returns to the classic
--     signature the modules were written against. If neither exists, a safe
--     stub returns nil so a missing API degrades instead of hard-crashing.
--   * On any new patch, run |cffffff78/tf debug compat|r in-game: it lists
--     every wrapper as native/adapter/MISSING. Newly missing or newly
--     adapted entries are baseline drift — fix them here.
--   * ns.caps holds capability flags for whole features (arenas, absorbs,
--     roles...). Gate speculative features on ns.caps.<x>, not zone checks or
--     hardcoded assumptions.
-- =============================================================================

local API = {}
ns.API = API

-- Shared stub instance so the compat report can identify unresolved APIs.
local function NIL_STUB() return nil end

-- Small helper: prefer the native global, else adapter, else stub.
local function pick(classicFn, adapterFn)
    if type(classicFn) == "function" then return classicFn end
    if adapterFn then return adapterFn end
    return NIL_STUB
end

-- Modern clients can return "secret" scalar values to addon Lua. Merely
-- receiving one is legal, but comparison, arithmetic, formatting, and even
-- some table-field access can fail once the execution path is tainted. Keep
-- the capability check available to every adapter, including the aura wrappers
-- defined near the top of this file.
local rawCanAccessValue = canaccessvalue
local rawIsSecretValue = issecretvalue
local rawHasAnySecretValues = hasanysecretvalues
function API.IsSecretValue(value)
    -- IMPORTANT: issecretvalue() must be the first operation on an unknown
    -- value.  On Forever/Midnight even comparing a secret against nil can be
    -- forbidden, so a conventional `if value == nil` guard is not safe here.
    if type(rawIsSecretValue) == "function" then
        local ok, secret = pcall(rawIsSecretValue, value)
        if ok and secret == true then return true end
    end
    -- Only inspect table contents after the scalar secret check proved that the
    -- value itself is readable.  hasanysecretvalues() lets us reject AuraData
    -- records that contain secret fields before callers index those fields.
    if type(value) == "table" and type(rawHasAnySecretValues) == "function" then
        local ok, secret = pcall(rawHasAnySecretValues, value)
        if ok and secret == true then return true end
    end
    return false
end
function API.CanAccessValue(value)
    -- Do not compare/branch on the candidate until IsSecretValue has cleared it.
    if API.IsSecretValue(value) then return false end
    if value == nil then return true end
    if type(rawCanAccessValue) ~= "function" then return true end
    local ok, accessible = pcall(rawCanAccessValue, value)
    return ok and accessible == true
end
function API.IsReadableNumber(value)
    return API.CanAccessValue(value) and type(value) == "number"
end

function API.SafeToString(value, fallback)
    if not API.CanAccessValue(value) then return fallback or "<secret>" end
    local ok, text = pcall(tostring, value)
    return ok and text or (fallback or "<unreadable>")
end

-- Midnight/Forever can make whole data domains secret while still allowing
-- Blizzard-approved UI objects to consume the opaque values.  Ask the client
-- for that state explicitly: trying an operation and waiting for it to throw
-- is both noisier and too late for scans that have already tainted execution.
local function SecretDomainState(method)
    local secrets = _G.C_Secrets
    local fn = type(secrets) == "table" and secrets[method]
    if type(fn) ~= "function" then return false end
    local ok, restricted = pcall(fn)
    return ok and restricted == true
end

function API.ShouldAurasBeSecret()
    return SecretDomainState("ShouldAurasBeSecret")
end

function API.ShouldCooldownsBeSecret()
    return SecretDomainState("ShouldCooldownsBeSecret")
end

function API.SecretRestrictionsActive()
    return API.ShouldAurasBeSecret() or API.ShouldCooldownsBeSecret()
end

-- Modules that need to distinguish a real API from the safe nil-stub can ask
-- through this boundary instead of probing globals/C_* namespaces themselves.
function API.IsAvailable(name)
    return type(name) == "string" and type(API[name]) == "function" and API[name] ~= NIL_STUB
end

-- =============================================================================
-- SPELLS  (retail 11.0 moved these to C_Spell with table returns)
-- =============================================================================

API.GetSpellInfo = pick(GetSpellInfo, C_Spell and C_Spell.GetSpellInfo and function(spell)
    local t = C_Spell.GetSpellInfo(spell)
    if not t then return nil end
    -- classic: name, rank, icon, castTime, minRange, maxRange, spellID
    return t.name, nil, t.iconID, t.castTime, t.minRange, t.maxRange, t.spellID
end)

API.GetSpellTexture = pick(GetSpellTexture, C_Spell and C_Spell.GetSpellTexture and function(spell)
    return C_Spell.GetSpellTexture(spell)
end)

API.GetSpellSubtext = pick(GetSpellSubtext, C_Spell and C_Spell.GetSpellSubtext and function(spell)
    return C_Spell.GetSpellSubtext(spell)
end)

API.GetSpellPowerCost = pick(GetSpellPowerCost, C_Spell and C_Spell.GetSpellPowerCost and function(spell)
    return C_Spell.GetSpellPowerCost(spell)
end)

-- Retail/Forever moved the current-spell predicate into C_Spell.  Swing timer
-- attack-state and on-next-swing queue detection must never call the removed
-- global directly because those paths run from the cadence driver.
if C_Spell and type(C_Spell.IsCurrentSpell) == "function" then
    API.IsCurrentSpell = C_Spell.IsCurrentSpell
else
    API.IsCurrentSpell = pick(_G.IsCurrentSpell)
end

local modernIsSpellKnown = C_SpellBook and C_SpellBook.IsSpellKnown and function(spellID)
    return C_SpellBook.IsSpellKnown(spellID)
end
API.IsSpellKnown = pick(IsSpellKnown, modernIsSpellKnown)
API.IsPlayerSpell = pick(IsPlayerSpell, modernIsSpellKnown)

-- "Does the player have this spell at all" -- either trained (IsSpellKnown) or
-- granted by talent/form/race (IsPlayerSpell). Neither call alone is sufficient
-- in Classic Era. Was duplicated verbatim in ClassBuffs and ClassFeatures;
-- routed through the shims above rather than the raw globals.
function API.IsKnownSpellID(spellID)
    if not spellID then return false end
    if API.IsSpellKnown and API.IsSpellKnown(spellID) then return true end
    if API.IsPlayerSpell and API.IsPlayerSpell(spellID) then return true end
    return false
end

-- Classic/Forever talent trees and Mainline expose different unspent-point
-- helpers. Keep the Speedrun reminder capability-first instead of tying it to
-- ClassBuffs or one client-family global.
function API.GetUnspentTalentPoints()
    -- Forever inherits Mainline's class-talent service even though its content
    -- uses Classic-style leveling. Prefer the service's explicit unspent-point
    -- result over surviving legacy globals, which can exist but remain stale at
    -- zero on the hybrid client.
    if C_ClassTalents and type(C_ClassTalents.HasUnspentTalentPoints) == "function" then
        local ok, hasPoints, classPoints, specPoints = pcall(C_ClassTalents.HasUnspentTalentPoints)
        if ok then
            local classReadable = API.IsReadableNumber(classPoints)
            local specReadable = API.IsReadableNumber(specPoints)
            if classReadable or specReadable then
                local total = (classReadable and classPoints or 0) + (specReadable and specPoints or 0)
                return total, "C_ClassTalents.HasUnspentTalentPoints"
            end
            if API.CanAccessValue(hasPoints) and hasPoints == true then
                return 1, "C_ClassTalents.HasUnspentTalentPoints:boolean"
            end
            if API.CanAccessValue(hasPoints) and hasPoints == false then
                return 0, "C_ClassTalents.HasUnspentTalentPoints:boolean"
            end
        end
    end
    if type(_G.GetUnspentTalentPoints) == "function" then
        local ok, value = pcall(_G.GetUnspentTalentPoints)
        if ok and API.CanAccessValue(value) then
            return tonumber(value) or 0, "GetUnspentTalentPoints"
        end
    end
    if type(_G.UnitCharacterPoints) == "function" then
        local ok, value = pcall(_G.UnitCharacterPoints, "player")
        if ok and API.CanAccessValue(value) then
            return tonumber(value) or 0, "UnitCharacterPoints"
        end
    end
    if type(_G.GetNumUnspentTalents) == "function" then
        local ok, value = pcall(_G.GetNumUnspentTalents)
        if ok and API.CanAccessValue(value) then
            return tonumber(value) or 0, "GetNumUnspentTalents"
        end
    end
    return 0, "none"
end

-- =============================================================================
-- AURAS  (retail 10.x+ moved to C_UnitAuras with aura-data tables)
-- =============================================================================

local function AuraDataToClassic(a)
    if not a then return nil end
    -- classic: name, icon, count, debuffType, duration, expirationTime, source,
    --          isStealable, nameplateShowPersonal, spellId, canApplyAura,
    --          isBossDebuff, castByPlayer, nameplateShowAll, timeMod
    return a.name, a.icon, a.applications or 0, a.dispelName, a.duration,
           a.expirationTime, a.sourceUnit, a.isStealable, a.nameplateShowPersonal,
           a.spellId, a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet,
           a.nameplateShowAll, a.timeMod
end

local function ResultsAreAccessible(...)
    for i = 1, select("#", ...) do
        if not API.CanAccessValue(select(i, ...)) then return false end
    end
    return true
end

local function SafeAuraDataCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if not API.CanAccessValue(a) or a == nil then return nil end
    local converted, name, icon, count, debuffType, duration, expirationTime,
        source, isStealable, showPersonal, spellID, canApply, bossAura,
        castByPlayer, showAll, timeMod = pcall(AuraDataToClassic, a)
    if not converted then return nil end
    if not ResultsAreAccessible(name, icon, count, debuffType, duration,
        expirationTime, source, isStealable, showPersonal, spellID, canApply,
        bossAura, castByPlayer, showAll, timeMod) then
        return nil
    end
    return name, icon, count, debuffType, duration, expirationTime, source,
        isStealable, showPersonal, spellID, canApply, bossAura, castByPlayer,
        showAll, timeMod
end

-- Table-returning aura access for native-frame stylers. Unlike the opaque
-- spell-ID hook, this is only exposed while the complete AuraData record is
-- readable. Addon-owned sorting/timers must use this path or the classic
-- wrappers below and suspend when it returns nil.
function API.GetReadableAuraDataByIndex(unit, index, filter)
    if API.ShouldAurasBeSecret() then return nil end
    local auras = _G.C_UnitAuras
    local fn = type(auras) == "table" and auras.GetAuraDataByIndex
    if type(fn) ~= "function" then
        fn = type(auras) == "table" and (filter == "HARMFUL"
            and auras.GetDebuffDataByIndex or auras.GetBuffDataByIndex)
    end
    if type(fn) ~= "function" then return nil end
    local ok, auraData = pcall(fn, unit, index, filter)
    if not ok then return nil end
    if not API.CanAccessValue(auraData) or auraData == nil then return nil end
    return auraData
end

function API.GetReadableAuraDataByAuraInstanceID(unit, auraInstanceID)
    if API.ShouldAurasBeSecret() then return nil end
    -- Native pooled aura buttons may carry a secret auraInstanceID even when the
    -- broad aura-domain predicate is false. Never feed an unreadable identifier
    -- back into an addon-side lookup path.
    if not API.CanAccessValue(auraInstanceID) or auraInstanceID == nil then return nil end
    local auras = _G.C_UnitAuras
    local fn = type(auras) == "table" and auras.GetAuraDataByAuraInstanceID
    if type(fn) ~= "function" then return nil end
    local ok, auraData = pcall(fn, unit, auraInstanceID)
    if not ok then return nil end
    if not API.CanAccessValue(auraData) or auraData == nil then return nil end
    return auraData
end

local function SafeLegacyAuraCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, name, icon, count, debuffType, duration, expirationTime, source,
        isStealable, showPersonal, spellID, canApply, bossAura, castByPlayer,
        showAll, timeMod = pcall(fn, ...)
    if not ok then return nil end
    if not ResultsAreAccessible(name, icon, count, debuffType, duration,
        expirationTime, source, isStealable, showPersonal, spellID, canApply,
        bossAura, castByPlayer, showAll, timeMod) then
        return nil
    end
    return name, icon, count, debuffType, duration, expirationTime, source,
        isStealable, showPersonal, spellID, canApply, bossAura, castByPlayer,
        showAll, timeMod
end

-- A secret aura domain cannot be enumerated, but the client may permit a
-- lookup for a spell ID the addon already knows.  The returned AuraData is
-- deliberately opaque: callers must not compare, format, cache, or do math on
-- its fields.  This is the future hook for renderers that pass approved secret
-- fields straight to native UI setters.
function API.GetOpaqueUnitAuraBySpellID(unit, spellID)
    local auras = _G.C_UnitAuras
    local fn = type(auras) == "table" and auras.GetUnitAuraBySpellID
    if type(fn) ~= "function" or spellID == nil then return nil end
    local ok, auraData = pcall(fn, unit, spellID)
    if not ok then return nil end
    return auraData
end

-- Forever is Mainline-derived. Prefer its table-returning C_UnitAuras surface
-- when present, and make both the modern and legacy routes fail closed if any
-- returned field is secret. Consumers see an absent aura for that scan instead
-- of receiving a value that will evict their event/cadence callback.
if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    API.UnitBuff = function(unit, i, filter)
        if API.ShouldAurasBeSecret() then return nil end
        return SafeAuraDataCall(C_UnitAuras.GetBuffDataByIndex, unit, i, filter)
    end
elseif type(UnitBuff) == "function" then
    API.UnitBuff = function(...)
        if API.ShouldAurasBeSecret() then return nil end
        return SafeLegacyAuraCall(UnitBuff, ...)
    end
else
    API.UnitBuff = NIL_STUB
end

if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
    API.UnitDebuff = function(unit, i, filter)
        if API.ShouldAurasBeSecret() then return nil end
        return SafeAuraDataCall(C_UnitAuras.GetDebuffDataByIndex, unit, i, filter)
    end
elseif type(UnitDebuff) == "function" then
    API.UnitDebuff = function(...)
        if API.ShouldAurasBeSecret() then return nil end
        return SafeLegacyAuraCall(UnitDebuff, ...)
    end
else
    API.UnitDebuff = NIL_STUB
end

-- Native incoming-heal prediction. Classic Era 1.15.9 exposes the classic
-- signature UnitGetIncomingHeals(unit [, casterUnit]). Keep it behind Compat so
-- future API movement has one repair point.
API.UnitGetIncomingHeals = pick(UnitGetIncomingHeals)

-- Secret-safe unit-state reads. These intentionally return nil when the client
-- withholds a value. Callers may hide an additive overlay or use Blizzard's
-- native presentation; they must never convert nil back into guessed combat
-- information.
local function ReadableNumberCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not API.IsReadableNumber(value) then return nil end
    return value
end

local function ReadableScalarCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not API.CanAccessValue(value) then return nil end
    return value
end

function API.ReadUnitExists(unit) return ReadableScalarCall(UnitExists, unit) end
function API.ReadUnitIsUnit(unit1, unit2) return ReadableScalarCall(UnitIsUnit, unit1, unit2) end
function API.ReadUnitIsFriend(unit1, unit2) return ReadableScalarCall(UnitIsFriend, unit1, unit2) end
function API.ReadUnitIsPlayer(unit) return ReadableScalarCall(UnitIsPlayer, unit) end
function API.ReadUnitPlayerControlled(unit) return ReadableScalarCall(UnitPlayerControlled, unit) end
function API.ReadUnitCanAttack(unit1, unit2) return ReadableScalarCall(UnitCanAttack, unit1, unit2) end
function API.ReadUnitIsDead(unit) return ReadableScalarCall(UnitIsDead, unit) end
function API.ReadUnitGUID(unit) return ReadableScalarCall(UnitGUID, unit) end
function API.ReadUnitName(unit) return ReadableScalarCall(UnitName, unit) end
function API.ReadUnitCreatureFamily(unit) return ReadableScalarCall(UnitCreatureFamily, unit) end

function API.ReadUnitClass(unit)
    if type(UnitClass) ~= "function" then return nil end
    local ok, localized, token, classID = pcall(UnitClass, unit)
    if not ok or not ResultsAreAccessible(localized, token, classID) then return nil end
    return localized, token, classID
end

function API.ReadUnitHealth(unit)
    return ReadableNumberCall(UnitHealth, unit)
end

function API.ReadUnitHealthMax(unit)
    return ReadableNumberCall(UnitHealthMax, unit)
end

-- Forever may return an opaque/secret UnitHealth scalar for nameplate units.
-- Addon Lua must not compare, format, concatenate, or otherwise inspect it,
-- but Blizzard's own AbbreviateNumbers implementation and an addon-owned
-- FontString may consume it. Keep the entire pass-through inside Compat so no
-- feature can accidentally treat the value as an ordinary Lua number.
function API.WriteUnitHealthText(fontString, unit)
    if not fontString or type(fontString.SetText) ~= "function"
        or type(UnitHealth) ~= "function" or not unit
    then
        return false, "unavailable"
    end

    local ok, value = pcall(UnitHealth, unit)
    if not ok then return false, "UnitHealth failed" end

    if API.CanAccessValue(value) then
        if type(value) ~= "number" then return false, "no readable health" end
        if type(AbbreviateNumbers) == "function" then
            local abbreviated, display = pcall(AbbreviateNumbers, value)
            if abbreviated then value = display end
        end
    elseif type(AbbreviateNumbers) == "function" then
        -- Do not branch on or inspect `display`: it may itself be a secret
        -- string. It is passed directly to the FontString setter below.
        local abbreviated, display = pcall(AbbreviateNumbers, value)
        if abbreviated then value = display end
    end

    local written = pcall(fontString.SetText, fontString, value)
    if written then return true end
    return false, "SetText rejected health value"
end

function API.ReadUnitPower(unit, powerType, unmodified)
    return ReadableNumberCall(UnitPower, unit, powerType, unmodified)
end

-- Secret-safe pass-through companion to ReadUnitPower.  The returned scalar
-- must never be inspected by addon Lua; it exists solely for Blizzard curve/UI
-- consumers such as the detached Forever Hotbar Power StatusBar.
function API.GetUnitPowerOpaque(unit, powerType, unmodified)
    if type(UnitPower) ~= "function" then return false end
    local ok, value = pcall(UnitPower, unit, powerType, unmodified)
    if not ok then return false end
    return true, value
end

-- Secret-safe curve evaluator for unit power. CurveObject:Evaluate itself is
-- not a tainted-call boundary for secret inputs on Forever; UnitPowerPercent
-- explicitly accepts a CurveObject and evaluates it inside Blizzard code.
-- The returned curve result remains opaque and must be passed straight to a
-- native UI sink by the caller.
function API.GetUnitPowerPercentOpaque(unit, powerType, unmodified, curve)
    local fn = _G.UnitPowerPercent
    if type(fn) ~= "function" or curve == nil then return false end
    local ok, value = pcall(fn, unit, powerType, unmodified, curve)
    if not ok then return false end
    return true, value
end

function API.ReadUnitPowerMax(unit, powerType, unmodified)
    return ReadableNumberCall(UnitPowerMax, unit, powerType, unmodified)
end

function API.ReadUnitIncomingHeals(unit, casterUnit)
    return ReadableNumberCall(API.UnitGetIncomingHeals, unit, casterUnit)
end

function API.ReadUnitThreatSituation(unit, mobUnit)
    return ReadableNumberCall(UnitThreatSituation, unit, mobUnit)
end

function API.ReadUnitDetailedThreatSituation(unit, mobUnit)
    if type(UnitDetailedThreatSituation) ~= "function" then return nil end
    local ok, tanking, status, scaled, raw, value = pcall(UnitDetailedThreatSituation, unit, mobUnit)
    if not ok or not ResultsAreAccessible(tanking, status, scaled, raw, value) then return nil end
    return tanking, status, scaled, raw, value
end

-- Forever's stable mob aliases (target/focus/mouseover/group-member targets)
-- can expose a readable relative percentage even when the raw percentage or
-- absolute threat value remains secret. Return only the three fields consumed
-- by the detached nameplate percentage renderer and validate each field
-- independently; one secret unused result must not discard the readable data.
function API.ReadUnitThreatPercent(unit, mobUnit)
    if type(UnitDetailedThreatSituation) ~= "function" then return nil end
    local ok, tanking, status, scaled = pcall(UnitDetailedThreatSituation, unit, mobUnit)
    if not ok then return nil end

    local safeTanking, safeStatus, safeScaled
    if API.CanAccessValue(tanking) and type(tanking) == "boolean" then safeTanking = tanking end
    if API.IsReadableNumber(status) then safeStatus = status end
    if API.IsReadableNumber(scaled) then safeScaled = scaled end
    return safeTanking, safeStatus, safeScaled
end

-- Event names drift between client families. Invalid registration must degrade
-- to an unavailable feature, never abort addon load.
function API.IsEventValid(event)
    if type(event) ~= "string" or event == "" then return false end
    local eventUtils = _G.C_EventUtils
    local fn = type(eventUtils) == "table" and eventUtils.IsEventValid
    if type(fn) ~= "function" then return true end
    local ok, valid = pcall(fn, event)
    return ok and valid == true
end

function API.RegisterEvent(frame, event)
    if not frame or type(frame.RegisterEvent) ~= "function" or not API.IsEventValid(event) then return false end
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

function API.RegisterUnitEvent(frame, event, unit1, unit2)
    if not frame or not API.IsEventValid(event) then return false end
    if type(frame.RegisterUnitEvent) == "function" and unit1 then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        if ok then return true end
    end
    return API.RegisterEvent(frame, event)
end

-- =============================================================================
-- PLAYER INTERACTION / SOCIAL ACTIONS
-- =============================================================================

function API.ConfirmSpiritHealer()
    local manager = _G.C_PlayerInteractionManager
    local interactionType = _G.Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.SpiritHealer
    if manager and type(manager.ConfirmationInteraction) == "function" and interactionType ~= nil then
        local ok = pcall(manager.ConfirmationInteraction, interactionType)
        if ok then return true end
    end
    if type(_G.AcceptXPLoss) == "function" then
        return pcall(_G.AcceptXPLoss)
    end
    return false
end

function API.ReleaseSpirit()
    if type(_G.RepopMe) ~= "function" then return false end
    return pcall(_G.RepopMe)
end

function API.GetBattleNetFriendInviteInfo(index)
    local modern = _G.C_BattleNet
    if modern and type(modern.GetFriendInviteInfo) == "function" then
        local ok, info = pcall(modern.GetFriendInviteInfo, index)
        if ok and type(info) == "table" then return info end
    end
    if type(_G.BNGetFriendInviteInfo) == "function" then
        local ok, inviteID, accountName, isBattleTag, message, sentTime = pcall(_G.BNGetFriendInviteInfo, index)
        if ok and inviteID then
            return {
                inviteID = inviteID, accountName = accountName,
                isBattleTag = isBattleTag, message = message,
                creationTimestamp = sentTime,
            }
        end
    end
    return nil
end

function API.InviteBattleNetFriend(gameAccountID)
    if not gameAccountID then return false end
    local modern = _G.C_BattleNet
    if modern and type(modern.InviteFriend) == "function" then
        return pcall(modern.InviteFriend, gameAccountID)
    end
    if type(_G.BNInviteFriend) == "function" then
        return pcall(_G.BNInviteFriend, gameAccountID)
    end
    return false
end

function API.CanInviteParty()
    local partyInfo = _G.C_PartyInfo
    if partyInfo and type(partyInfo.CanInvite) == "function" then
        local ok, allowed = pcall(partyInfo.CanInvite)
        if ok then return allowed == true end
    end
    if not UnitExists("party1") then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function API.InviteUnit(name)
    if not name then return false end
    local partyInfo = _G.C_PartyInfo
    if partyInfo and type(partyInfo.InviteUnit) == "function" then
        return pcall(partyInfo.InviteUnit, name)
    end
    if type(_G.InviteUnit) == "function" then
        return pcall(_G.InviteUnit, name)
    end
    return false
end

function API.ForEachChatFrame(callback)
    if type(callback) ~= "function" then return end
    local util = _G.ChatFrameUtil
    if util and type(util.ForEachChatFrame) == "function" then
        local ok = pcall(util.ForEachChatFrame, callback)
        if ok then return end
    end
    for i = 1, 50 do
        local frame = _G["ChatFrame" .. i]
        if frame then callback(frame) end
    end
end

-- =============================================================================
-- ADDONS  (retail 10.x moved to C_AddOns; enable-state arg order differs)
-- =============================================================================

API.GetAddOnMetadata = pick(GetAddOnMetadata, C_AddOns and C_AddOns.GetAddOnMetadata and function(name, field)
    return C_AddOns.GetAddOnMetadata(name, field)
end)

API.GetAddOnInfo = pick(GetAddOnInfo, C_AddOns and C_AddOns.GetAddOnInfo and function(name)
    return C_AddOns.GetAddOnInfo(name)
end)

API.DisableAddOn = pick(DisableAddOn, C_AddOns and C_AddOns.DisableAddOn and function(name, character)
    return C_AddOns.DisableAddOn(name, character)
end)

-- IsAddOnLoaded may return (loadedOrLoading, loaded). UI consumers need the
-- completed state; the one-result form remains safe on older Era builds.
local IsAddOnLoadedAPI = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
function API.IsAddOnLoaded(name)
    if not IsAddOnLoadedAPI then return false end
    local loadedOrLoading, loaded = IsAddOnLoadedAPI(name)
    if loaded ~= nil then return loaded == true end
    return loadedOrLoading == true
end

-- Normalized: API.GetAddOnEnableState(addonName) -> 0 disabled / 1 some / 2 all
API.GetAddOnEnableState = (C_AddOns and C_AddOns.GetAddOnEnableState and function(name)
    return C_AddOns.GetAddOnEnableState(name)
end) or (GetAddOnEnableState and function(name)
    return GetAddOnEnableState(nil, name)  -- legacy arg order: (character, name)
end) or function() return 0 end

-- =============================================================================
-- ITEMS  (retail 10.x moved to C_Item)
-- =============================================================================

API.GetItemInfo = pick(GetItemInfo, C_Item and C_Item.GetItemInfo and function(item)
    return C_Item.GetItemInfo(item)
end)

API.GetItemIcon = pick(GetItemIcon, C_Item and C_Item.GetItemIconByID and function(item)
    return C_Item.GetItemIconByID(item)
end)

API.GetItemInfoInstant = pick(GetItemInfoInstant, C_Item and C_Item.GetItemInfoInstant and function(item)
    return C_Item.GetItemInfoInstant(item)
end)

API.GetItemCount = pick(GetItemCount, C_Item and C_Item.GetItemCount and function(item, includeBank, includeUses, includeReagentBank)
    return C_Item.GetItemCount(item, includeBank, includeUses, includeReagentBank)
end)

-- =============================================================================
-- MERCHANTS  (Forever/Mainline exposes authoritative structured item metadata)
-- =============================================================================

API.GetMerchantNumItems = pick(GetMerchantNumItems)
API.GetMerchantItemLink = pick(GetMerchantItemLink)
API.GetMerchantItemID = pick(GetMerchantItemID)
API.GetMerchantItemMaxStack = pick(GetMerchantItemMaxStack)
API.GetMerchantItemCostInfo = pick(GetMerchantItemCostInfo)
API.BuyMerchantItem = pick(BuyMerchantItem)

local modernMerchantInfo = C_MerchantFrame and C_MerchantFrame.GetItemInfo
if type(modernMerchantInfo) == "function" then
    API.MerchantInfoKind = "C_MerchantFrame"
    API.GetMerchantItemInfo = function(index)
        local ok, info = pcall(modernMerchantInfo, index)
        if not ok then return nil end
        if not API.CanAccessValue(info) or type(info) ~= "table" then return nil end
        local name, texture, price, stackCount, numAvailable = info.name, info.texture,
            info.price, info.stackCount, info.numAvailable
        local isPurchasable, isUsable, hasExtendedCost = info.isPurchasable,
            info.isUsable, info.hasExtendedCost
        local currencyID, spellID, isQuestStartItem = info.currencyID,
            info.spellID, info.isQuestStartItem
        if not ResultsAreAccessible(name, texture, price, stackCount, numAvailable,
            isPurchasable, isUsable, hasExtendedCost, currencyID, spellID,
            isQuestStartItem) then return nil end
        -- Preserve the established global signature for feature code.
        return name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, hasExtendedCost, currencyID, spellID, isQuestStartItem
    end
elseif type(GetMerchantItemInfo) == "function" then
    API.MerchantInfoKind = "legacy-global"
    API.GetMerchantItemInfo = function(...)
        local ok, name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, hasExtendedCost, currencyID, spellID, isQuestStartItem =
            pcall(GetMerchantItemInfo, ...)
        if not ok or not ResultsAreAccessible(name, texture, price, stackCount,
            numAvailable, isPurchasable, isUsable, hasExtendedCost, currencyID,
            spellID, isQuestStartItem) then return nil end
        return name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, hasExtendedCost, currencyID, spellID, isQuestStartItem
    end
else
    API.MerchantInfoKind = "missing"
    API.GetMerchantItemInfo = NIL_STUB
end

function API.MerchantSurfaceAvailable()
    return API.GetMerchantNumItems ~= NIL_STUB
        and API.GetMerchantItemInfo ~= NIL_STUB
        and API.BuyMerchantItem ~= NIL_STUB
end

-- =============================================================================
-- MONEY / CURRENCY
-- =============================================================================
-- Midnight/Forever's current Blizzard UI uses MoneyFormatterUtil and the
-- coin-gold / coin-silver / coin-copper atlases for money text instead of the
-- old MoneyFrame texture paths. Keep those details behind Compat so feature
-- modules do not need to know which money implementation the client shipped.
--
-- Resolve formatters dynamically rather than aliasing globals at addon load:
-- Blizzard load-on-demand UI can make FrameXML helpers appear after TurboFace.
local function PlainCoinText(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    if gold > 0 then return ("%dg %ds %dc"):format(gold, silver, copper) end
    if silver > 0 then return ("%ds %dc"):format(silver, copper) end
    return ("%dc"):format(copper)
end

local COIN_ATLASES = {
    gold = "coin-gold",
    silver = "coin-silver",
    copper = "coin-copper",
}

local LEGACY_COIN_TEXTURES = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}

-- Format an arbitrary copper value using Blizzard's current MoneyFormatter.
-- CompactWithZero gives the native money presentation while still rendering
-- 0 copper. The legacy texture-string helpers remain a compatibility fallback
-- for clients that do not expose MoneyFormatterUtil yet.
function API.FormatMoney(amount)
    local util = _G.MoneyFormatterUtil
    local presets = _G.MoneyFormatterPresets
    local config = type(presets) == "table" and presets.CompactWithZero or nil
    if type(util) == "table" and type(util.FormatMoney) == "function" and config then
        local ok, text = pcall(util.FormatMoney, amount or 0, config)
        if ok and text then return text end
    end

    local fn = _G.GetCoinTextureString
    if type(fn) == "function" then
        return fn(amount or 0)
    end
    local currency = _G.C_CurrencyInfo
    if type(currency) == "table" and type(currency.GetCoinTextureString) == "function" then
        return currency.GetCoinTextureString(amount or 0)
    end
    return PlainCoinText(amount)
end

-- Apply Blizzard's current standalone coin atlas to an existing Texture while
-- preserving the caller's chosen size. Legacy clients fall back to the former
-- MoneyFrame texture asset rather than losing the indicator entirely.
function API.SetCoinIcon(texture, denomination)
    if not texture then return false end
    denomination = type(denomination) == "string" and denomination:lower() or denomination

    local atlas = COIN_ATLASES[denomination]
    if atlas and type(texture.SetAtlas) == "function" then
        local ok = pcall(texture.SetAtlas, texture, atlas, false)
        if ok then return true end
    end

    local fallback = LEGACY_COIN_TEXTURES[denomination]
    if fallback and type(texture.SetTexture) == "function" then
        texture:SetTexture(fallback)
        return true
    end
    return false
end

function API.GetCoinTextureString(amount, fontHeight)
    local fn = _G.GetCoinTextureString
    if type(fn) == "function" then
        return fn(amount, fontHeight)
    end
    local currency = _G.C_CurrencyInfo
    if type(currency) == "table" and type(currency.GetCoinTextureString) == "function" then
        return currency.GetCoinTextureString(amount, fontHeight)
    end
    return PlainCoinText(amount)
end

function API.GetCoinText(amount, separator)
    local fn = _G.GetCoinText
    if type(fn) == "function" then
        return fn(amount, separator)
    end
    local currency = _G.C_CurrencyInfo
    if type(currency) == "table" and type(currency.GetCoinText) == "function" then
        return currency.GetCoinText(amount, separator)
    end
    return PlainCoinText(amount)
end

-- =============================================================================
-- SPELLBOOK  (retail 11.0 moved to C_SpellBook)
-- =============================================================================

API.GetNumSpellTabs = pick(GetNumSpellTabs, C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and function()
    return C_SpellBook.GetNumSpellBookSkillLines()
end)

API.GetSpellTabInfo = pick(GetSpellTabInfo, C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo and function(tab)
    local t = C_SpellBook.GetSpellBookSkillLineInfo(tab)
    if not t then return nil end
    -- classic: name, texture, offset, numSpells
    return t.name, t.iconID, t.itemIndexOffset, t.numSpellBookItems
end)

API.GetSpellBookItemName = pick(GetSpellBookItemName, C_SpellBook and C_SpellBook.GetSpellBookItemName and function(index, bookType)
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    return C_SpellBook.GetSpellBookItemName(index, bank)
end)

-- =============================================================================
-- COMBO POINTS  (retail reads them as a power type)
-- =============================================================================

API.GetComboPoints = pick(GetComboPoints, UnitPower and function(unit, target)
    local pt = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
    local value = UnitPower(unit or "player", pt)
    if not API.IsReadableNumber(value) then return nil end
    return value
end)

-- =============================================================================
-- TALENTS  (classic API; retail replaced it wholesale -- stub if missing so
-- talent-dependent features degrade to their no-talent fallbacks)
-- =============================================================================

API.GetTalentInfo = pick(GetTalentInfo)
API.GetNumTalentTabs = pick(GetNumTalentTabs)
API.GetTalentTabInfo = pick(GetTalentTabInfo)

-- =============================================================================
-- QUEST LOG  (retail moved to C_QuestLog with info tables)
-- =============================================================================

API.GetNumQuestLogEntries = pick(GetNumQuestLogEntries, C_QuestLog and C_QuestLog.GetNumQuestLogEntries and function()
    return C_QuestLog.GetNumQuestLogEntries()
end)

API.GetQuestLogTitle = pick(GetQuestLogTitle, C_QuestLog and C_QuestLog.GetInfo and function(index)
    local info = C_QuestLog.GetInfo(index)
    if not info then return nil end
    local isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) and 1 or nil
    -- classic: title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
    --          frequency, questID
    return info.title, info.level, info.suggestedGroup, info.isHeader,
           info.isCollapsed, isComplete, info.frequency, info.questID
end)

-- These legacy globals operate on quest-log indices. The similarly named
-- Retail methods operate on quest IDs, so they are not compatible fallbacks.
API.GetQuestLogSelection = pick(GetQuestLogSelection)
API.SelectQuestLogEntry = pick(SelectQuestLogEntry)

API.GetQuestLogIndexByID = pick(GetQuestLogIndexByID, C_QuestLog and C_QuestLog.GetLogIndexForQuestID and function(questID)
    return C_QuestLog.GetLogIndexForQuestID(questID)
end)

API.GetQuestLogRewardXP = pick(GetQuestLogRewardXP)
API.HaveQuestRewardData = pick(HaveQuestRewardData)
API.RequestLoadQuestByID = pick(C_QuestLog and C_QuestLog.RequestLoadQuestByID)

API.IsQuestComplete = pick(IsQuestComplete, C_QuestLog and C_QuestLog.IsComplete and function(questID)
    return C_QuestLog.IsComplete(questID)
end)

-- Forever is a modern-first hybrid and can expose a legacy-named global beside
-- C_QuestLog. These are not assumed equivalent: the current quest-ID API is
-- authoritative when present, with the old global retained for Classic.
API.QuestReadyForTurnIn =
    (C_QuestLog and C_QuestLog.ReadyForTurnIn and function(questID)
        return C_QuestLog.ReadyForTurnIn(questID)
    end)
    or (type(QuestReadyForTurnIn) == "function" and QuestReadyForTurnIn)
    or function(questID)
        return API.IsQuestComplete(questID)
    end

-- =============================================================================
-- CONTAINERS  (retail 10.x moved these to C_Container; GetContainerItemInfo
-- returns an info TABLE there vs classic multi-returns. ns.API normalizes to
-- the table form -- on 1.15 the C_Container path is used directly, zero cost.)
-- =============================================================================

do
    local CC = C_Container
    API.GetContainerNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
        or NIL_STUB
    API.GetContainerNumFreeSlots = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
        or NIL_STUB
    API.GetContainerItemID = (CC and CC.GetContainerItemID) or GetContainerItemID
        or NIL_STUB
    API.PickupContainerItem = (CC and CC.PickupContainerItem) or PickupContainerItem
        or NIL_STUB
    API.UseContainerItem = (CC and CC.UseContainerItem) or UseContainerItem
        or NIL_STUB

    if CC and CC.GetContainerItemInfo then
        API.GetContainerItemInfo = CC.GetContainerItemInfo          -- already a table
    elseif GetContainerItemInfo then
        API.GetContainerItemInfo = function(bag, slot)              -- adapt multi-returns
            local _, count, locked, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
            if count == nil then return nil end
            return { stackCount = count, quality = quality, hasNoValue = noValue,
                     isLocked = locked or false, itemID = id, hyperlink = link }
        end
    else
        API.GetContainerItemInfo = NIL_STUB
    end
end

-- =============================================================================
-- ACTION BARS / MACROS / CVARS
-- 1.15.9 moved several action/macro entry points behind C_* namespaces. Quick
-- Setup is deliberately written only against this normalized surface.
-- =============================================================================

-- These use the same 1.15.9-preferred C_* ordering proven by the maintained
-- Lvl1QuickSetup build, with the older globals kept as the fallback dialect.
API.GetActionInfo = pick(C_ActionBar and C_ActionBar.GetActionInfo, GetActionInfo)
API.GetActionText = pick(C_ActionBar and C_ActionBar.GetActionText, GetActionText)
-- Modern/Forever action slots can resolve a spell even when the slot itself is
-- a macro.  Keep that semantic at the compatibility boundary so consumers do
-- not need to parse secure macro conditionals merely to discover the spell the
-- button currently represents (for example Warrior stance macros).
API.GetActionSpell = pick(C_ActionBar and C_ActionBar.GetSpell)
if C_ActionBar and type(C_ActionBar.HasAction) == "function" then
    API.HasAction = C_ActionBar.HasAction
elseif type(HasAction) == "function" then
    API.HasAction = HasAction
else
    API.HasAction = function(actionSlot)
        local actionType = API.GetActionInfo(actionSlot)
        return actionType ~= nil
    end
end
API.PlaceAction = pick(C_ActionBar and C_ActionBar.PlaceAction, PlaceAction)
API.PickupAction = pick(C_ActionBar and C_ActionBar.PickupAction, PickupAction)
API.PickupSpell = pick(C_Spell and C_Spell.PickupSpell, PickupSpell)
API.PickupItem = pick(C_Item and C_Item.PickupItem, PickupItem)
API.RequestLoadItemDataByID = pick(C_Item and C_Item.RequestLoadItemDataByID)
API.PickupMacro = pick(C_Macro and C_Macro.PickupMacro, PickupMacro)
API.GetMacroIndexByName = pick(C_Macro and C_Macro.GetMacroIndexByName, GetMacroIndexByName)
API.EditMacro = pick(C_Macro and C_Macro.EditMacro, EditMacro)
API.DeleteMacro = pick(C_Macro and C_Macro.DeleteMacro, DeleteMacro)
API.GetCVar = pick(C_CVar and C_CVar.GetCVar, GetCVar)
API.SetCVar = pick(C_CVar and C_CVar.SetCVar, SetCVar)
API.GetActionBarToggles = pick(GetActionBarToggles)
API.SetActionBarToggles = pick(SetActionBarToggles)

-- Retail-derived clients publish macro capacities through Constants.MacroConsts;
-- older Classic clients exported the same values as globals. Keep the namespace
-- difference at the compatibility boundary so profile scans never silently stop
-- at the historical 18-character-macro limit on a 30-slot client.
function API.GetMacroLimits()
    local macroConsts = type(_G.Constants) == "table" and _G.Constants.MacroConsts
    local account = type(macroConsts) == "table" and tonumber(macroConsts.MAX_ACCOUNT_MACROS)
        or tonumber(_G.MAX_ACCOUNT_MACROS)
    local character = type(macroConsts) == "table" and tonumber(macroConsts.MAX_CHARACTER_MACROS)
        or tonumber(_G.MAX_CHARACTER_MACROS)
    return account or 120, character or 30
end

API.GetMacroSpell = pick(GetMacroSpell)
API.GetMacroBody = pick(GetMacroBody)
API.GetWeaponEnchantInfo = pick(GetWeaponEnchantInfo)

-- =============================================================================
-- MINIMAP / TRACKING
-- Forever inherits the modern structured C_Minimap tracking API while older
-- Classic clients expose the legacy globals (or only GetTrackingTexture). Keep
-- that client dialect entirely behind this facade.
-- =============================================================================

local function ReadTrackingInfo(getInfo, index)
    if type(getInfo) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(getInfo, index)
    if not ok then return nil end
    if type(a) == "table" then
        return {
            name = a.name,
            texture = a.texture,
            active = a.active == true or a.active == 1,
            category = a.category or a.type,
            nested = a.nested or a.subType,
            spellID = a.spellID,
            raw = a,
        }
    end
    if a ~= nil then
        return {
            name = a, texture = b, active = c == true or c == 1,
            category = d, nested = e,
        }
    end
    return nil
end

function API.GetActiveTrackingInfo()
    local modern = _G.C_Minimap
    local getCount = modern and modern.GetNumTrackingTypes
    local getInfo = modern and modern.GetTrackingInfo
    if type(getCount) == "function" and type(getInfo) == "function" then
        local ok, count = pcall(getCount)
        if ok and type(count) == "number" then
            for index = 1, count do
                local info = ReadTrackingInfo(getInfo, index)
                if info and info.active then return info end
            end
            return nil
        end
    end

    if type(_G.GetNumTrackingTypes) == "function" and type(_G.GetTrackingInfo) == "function" then
        local ok, count = pcall(_G.GetNumTrackingTypes)
        if ok and type(count) == "number" then
            for index = 1, count do
                local info = ReadTrackingInfo(_G.GetTrackingInfo, index)
                if info and info.active then return info end
            end
            return nil
        end
    end

    if type(_G.GetTrackingTexture) == "function" then
        local ok, texture = pcall(_G.GetTrackingTexture)
        if ok and texture then return { texture = texture, active = true } end
    end
    return nil
end

function API.GetTrackingTexture()
    local info = API.GetActiveTrackingInfo()
    return info and info.texture or nil
end

-- Resolve stock minimap children at call time. Mainline/Forever moved most
-- children under Minimap/MinimapCluster while Era still exposes globals.
function API.GetMinimapParts()
    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    local indicator = cluster and cluster.IndicatorFrame
    local tracking = cluster and cluster.Tracking
    local zoneButton = (cluster and cluster.ZoneTextButton) or _G.MinimapZoneTextButton
    local backdrop = _G.MinimapBackdrop or (minimap and minimap.MinimapBackdrop)
    local gameTime = _G.GameTimeFrame
        or (cluster and (cluster.GameTimeFrame or cluster.GameTime))
    local gameTimeTexture = _G.GameTimeTexture
        or (gameTime and (gameTime.GameTimeTexture or gameTime.DayNightTexture))
    local modernCompass = _G.MinimapCompassTexture
        or (backdrop and (backdrop.MinimapCompassTexture or backdrop.CompassTexture))
    local compass = modernCompass or _G.MinimapBorder
    return {
        minimap = minimap,
        cluster = cluster,
        zoomIn = (minimap and minimap.ZoomIn) or _G.MinimapZoomIn,
        zoomOut = (minimap and minimap.ZoomOut) or _G.MinimapZoomOut,
        zoneButton = zoneButton,
        zoneText = _G.MinimapZoneText or (zoneButton and (zoneButton.ZoneText or zoneButton.Text)),
        trackingButton = (tracking and (tracking.Button or tracking)) or _G.MiniMapTracking or _G.MiniMapTrackingFrame,
        mailFrame = (indicator and indicator.MailFrame) or _G.MiniMapMailFrame,
        battlefieldFrame = (indicator and indicator.BattlefieldFrame) or _G.MiniMapBattlefieldFrame,
        -- Mainline/Forever use the ui-hud-minimap-frame atlas on
        -- MinimapCompassTexture instead of the old MinimapBorder texture.
        border = compass,
        compassTexture = modernCompass,
        borderTop = cluster and cluster.BorderTop or nil,
        northTag = _G.MinimapNorthTag,
        backdrop = backdrop or cluster,
        gameTimeFrame = gameTime,
        gameTimeTexture = gameTimeTexture,
        toggleButton = (cluster and cluster.MinimapToggleButton) or _G.MinimapToggleButton,
        clockButton = _G.TimeManagerClockButton,
        lfgButton = _G.QueueStatusMinimapButton or _G.LFGMinimapFrame or _G.MiniMapLFGFrame,
    }
end

-- Current Mainline/Forever minimap art is atlas-backed. Keep the actual atlas
-- knowledge at the compatibility boundary so InterfaceTweaks never has to know
-- whether this client owns MinimapCompassTexture or the old MinimapBorder.
function API.SetNativeMinimapBorderShown(shown)
    local parts = API.GetMinimapParts()
    local border = parts.compassTexture or parts.border
    if not border then return false end

    if shown and parts.compassTexture and type(border.SetAtlas) == "function" then
        -- Blizzard_Minimap/Mainline/Minimap.xml uses this exact atlas. Reassert it
        -- when returning from TurboFace's square mode because SetTexture/atlas
        -- ownership can be changed by UI reload/layout code on hybrid clients.
        pcall(border.SetAtlas, border, "ui-hud-minimap-frame")
    end
    if type(border.SetShown) == "function" then
        border:SetShown(shown == true)
    elseif shown and type(border.Show) == "function" then
        border:Show()
    elseif not shown and type(border.Hide) == "function" then
        border:Hide()
    end

    local north = parts.northTag
    if north then
        if type(north.SetShown) == "function" then north:SetShown(shown == true)
        elseif shown and north.Show then north:Show()
        elseif not shown and north.Hide then north:Hide() end
    end
    return true
end

-- Resolve Compact Raid Manager children across Mainline/Forever and older
-- Classic layouts. Mainline keeps the manager but exposes useful children via
-- parentKey fields instead of requiring callers to depend on generated globals.
function API.GetCompactRaidManagerParts()
    local manager = _G.CompactRaidFrameManager
    local display = manager and manager.displayFrame or _G.CompactRaidFrameManagerDisplayFrame
    return {
        manager = manager,
        container = _G.CompactRaidFrameContainer or (manager and manager.container),
        displayFrame = display,
        hiddenModeToggle = (display and display.hiddenModeToggle)
            or _G.CompactRaidFrameManagerDisplayFrameHiddenModeToggle,
    }
end

API.UnitGetTotalAbsorbs = pick(UnitGetTotalAbsorbs, nil) -- stub returns nil; callers use `or 0`
API.UnitGroupRolesAssigned = pick(UnitGroupRolesAssigned, function() return "NONE" end)

function API.ReadUnitTotalAbsorbs(unit)
    return ReadableNumberCall(API.UnitGetTotalAbsorbs, unit)
end

-- =============================================================================
-- EVENTS / FRAMEXML
-- =============================================================================

-- Registering an unknown event is a hard Lua error, so renamed events must be
-- resolved to whichever name this client accepts before RegisterEvent.
local function EventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    local probe = CreateFrame("Frame")
    local ok = pcall(probe.RegisterEvent, probe, event)
    if ok then probe:UnregisterEvent(event) end
    return ok
end

-- LEARNED_SPELL_IN_TAB (spellID, tabIndex) was renamed to
-- LEARNED_SPELL_IN_SKILL_LINE (spellID, skillLineIndex, isGuildPerkSpell).
-- TurboFace handlers only use the event as a "spellbook changed" nudge and
-- ignore the payload, so the two are interchangeable.
API.LEARNED_SPELL_EVENT = EventValid("LEARNED_SPELL_IN_TAB")
    and "LEARNED_SPELL_IN_TAB" or "LEARNED_SPELL_IN_SKILL_LINE"

-- 1.15.9's retail nameplate-driver import renamed the unit-token field on
-- nameplate base frames (namePlateUnitToken -> unitToken). Single accessor so
-- plate code can't silently read a nil field across the rename. NOTE: the
-- OnNamePlateRemoved stale-token guard depends on this returning the live
-- token — a nil here turns every spurious REMOVED into a full plate teardown.
function API.GetPlateUnitToken(nameplate)
    return nameplate.namePlateUnitToken or nameplate.unitToken
end

-- Forever/Mainline's combined bag is a dedicated ContainerFrame rather than
-- one of the numbered ContainerFrame1..N windows.  Keep its generated global
-- behind the compatibility boundary so QoL code can fail closed on clients
-- that do not provide combined-bag mode.
function API.GetCombinedBagFrame()
    return _G.ContainerFrameCombinedBags
end

-- Blizzard ports FrameXML globals to frame mixin methods over time (e.g.
-- TargetFrame_CheckClassification -> TargetFrame:CheckClassification). Hook
-- whichever form this client has; the handler receives the frame as its first
-- argument either way. Returns true when a hook landed.
function API.HookGlobalOrMethod(globalName, frame, methodName, handler)
    if type(_G[globalName]) == "function" then
        hooksecurefunc(globalName, handler)
        return true
    end
    if frame and type(frame[methodName]) == "function" then
        hooksecurefunc(frame, methodName, handler)
        return true
    end
    return false
end

-- Run fn now if the named Blizzard addon is already loaded, otherwise when it
-- loads. Blizzard splits parts of the UI into load-on-demand addons whose
-- frames simply do not exist at PLAYER_LOGIN, so a feature touching them has
-- to defer rather than nil-check once and give up. Second consumer (Plus/
-- MapTweaks.lua) is why this moved out of Plus/InterfaceTweaks.lua.
function API.OnAddonReady(addon, fn)
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded(addon, fn)
        return
    end
    if API.IsAddOnLoaded(addon) then fn() return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == addon then
            self:UnregisterAllEvents()
            fn()
        end
    end)
end

-- =============================================================================
-- CAPABILITY FLAGS  (ns.caps) — gate whole features on these, evaluated once
-- at load. If Classic Plus adds arenas / a real absorb API / role assignment,
-- the dependent features light up with no code changes beyond their gates.
-- =============================================================================

ns.caps = {
    -- Absorb API exists (Era: exists but returns 0; nanShield keeps its own model)
    absorbs        = type(UnitGetTotalAbsorbs) == "function",
    -- Incoming-heal prediction API
    healPrediction = type(UnitGetIncomingHeals) == "function",
    -- Group role assignment (Era: exists but always "NONE" outside LFG-style content)
    roles          = type(UnitGroupRolesAssigned) == "function",
    -- Focus frame/unit support (TBC+)
    focus          = type(FocusUnit) == "function",
    -- Arena opponent APIs (TBC+; drives any future arena features)
    arenas         = type(GetNumArenaOpponents) == "function",
    -- Season of Discovery rune engraving
    sodRunes       = type(C_Engraving) == "table",
    -- Classic-style talent API (nanShield talent scaling depends on it)
    classicTalents = type(GetTalentInfo) == "function",
}

-- =============================================================================
-- BASELINE AUDIT  (/tf debug compat)
-- Classifies every ns.API function against the LIVE client: NATIVE (the
-- baseline exposes the classic-signature global directly), ADAPTER (served
-- through a normalized C_*/renamed form), or MISSING (nil-stub -- the
-- dependent feature silently degrades). Run after every Blizzard patch;
-- entries that newly become ADAPTER or MISSING are drift from the 1.15.9 /
-- 2.5.6-like baseline and should be fixed in this file.
-- =============================================================================

local COMPAT_HELPERS = {
    -- TurboFace-authored helpers, not wrapped Blizzard APIs; skip in report.
    HookGlobalOrMethod = true,
    GetPlateUnitToken = true,
    OnAddonReady = true,
    IsAvailable = true,
}

function ns.CompatReport()
    local native, adapter, missing = {}, {}, {}
    for k, v in pairs(API) do
        if type(v) == "function" and not COMPAT_HELPERS[k] then
            if v == NIL_STUB then
                missing[#missing + 1] = k
            elseif _G[k] == v then
                native[#native + 1] = k
            else
                adapter[#adapter + 1] = k
            end
        end
    end
    table.sort(native); table.sort(adapter); table.sort(missing)
    ns:Chat("Compat", ("baseline audit: %d native | %d adapter | %d missing"):format(
        #native, #adapter, #missing))
    if #adapter > 0 then
        ns:Chat("Compat", "adapters: " .. table.concat(adapter, " "))
    end
    if #missing > 0 then
        ns:Chat("Compat", "|cffff5555MISSING (stubbed):|r " .. table.concat(missing, " "))
    end
    ns:Chat("Compat", "LEARNED_SPELL event: " .. tostring(API.LEARNED_SPELL_EVENT))
    local capsList = {}
    for k, v in pairs(ns.caps) do capsList[#capsList + 1] = k .. "=" .. tostring(v) end
    table.sort(capsList)
    ns:Chat("Compat", "caps: " .. table.concat(capsList, "  "))
end
