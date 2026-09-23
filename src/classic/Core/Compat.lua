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

-- Shared combat/action consumers use the modernized name on every client.
-- Classic Era still exposes the legacy global, so this is a zero-semantics
-- alias rather than a client-specific implementation branch at each call site.
API.IsCurrentSpell = pick(IsCurrentSpell, C_Spell and C_Spell.IsCurrentSpell and function(spell)
    return C_Spell.IsCurrentSpell(spell)
end)

API.IsSpellKnown = pick(IsSpellKnown)
API.IsPlayerSpell = pick(IsPlayerSpell)

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

API.UnitBuff = pick(UnitBuff, C_UnitAuras and C_UnitAuras.GetBuffDataByIndex and function(unit, i, filter)
    return AuraDataToClassic(C_UnitAuras.GetBuffDataByIndex(unit, i, filter))
end)

API.UnitDebuff = pick(UnitDebuff, C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex and function(unit, i, filter)
    return AuraDataToClassic(C_UnitAuras.GetDebuffDataByIndex(unit, i, filter))
end)

-- Native incoming-heal prediction. Classic Era 1.15.9 exposes the classic
-- signature UnitGetIncomingHeals(unit [, casterUnit]). Keep it behind Compat so
-- future API movement has one repair point.
API.UnitGetIncomingHeals = pick(UnitGetIncomingHeals)

-- Shared feature code consumes secret-safe ReadUnit* names. On Classic Era
-- these map directly to the readable legacy APIs, preserving the historical
-- return contracts while allowing the same feature files to run on Forever,
-- where Compat applies accessibility checks before returning values.
API.ReadUnitHealth = pick(UnitHealth)
API.ReadUnitHealthMax = pick(UnitHealthMax)
API.ReadUnitIncomingHeals = API.UnitGetIncomingHeals
API.ReadUnitThreatSituation = pick(UnitThreatSituation)
API.ReadUnitDetailedThreatSituation = pick(UnitDetailedThreatSituation)
API.ReadUnitGUID = pick(UnitGUID)
API.ReadUnitClass = pick(UnitClass)
API.ReadUnitIsUnit = pick(UnitIsUnit)
API.ReadUnitIsFriend = pick(UnitIsFriend)
API.ReadUnitExists = pick(UnitExists)
API.ReadUnitIsPlayer = pick(UnitIsPlayer)
API.ReadUnitPlayerControlled = pick(UnitPlayerControlled)
API.ReadUnitCanAttack = pick(UnitCanAttack)
API.ReadUnitPower = pick(UnitPower)
API.ReadUnitPowerMax = pick(UnitPowerMax)
API.ReadUnitIsDead = pick(UnitIsDead)
API.ReadUnitName = pick(UnitName)
API.ReadUnitTotalAbsorbs = pick(UnitGetTotalAbsorbs)

-- Classic Era has no secret-value domain.  Shared runtime modules still use
-- the same accessibility vocabulary as Forever so the feature code can remain
-- byte-identical without sprinkling client checks around numeric/string reads.
function API.IsSecretValue(_)
    return false
end

function API.CanAccessValue(_)
    return true
end

function API.IsReadableNumber(value)
    return type(value) == "number"
end

-- Shared diagnostics must never stringify a value through a client-specific
-- path.  Classic values are readable, but keep the same guarded contract used
-- on Forever so callers can remain byte-identical.
function API.SafeToString(value, fallback)
    local ok, text = pcall(tostring, value)
    return ok and text or (fallback or "<unreadable>")
end

-- Classic Era does not expose the modern secret-domain restrictions used by
-- Forever. Keep the shared aura consumer contract explicit rather than making
-- individual feature files probe client globals.
function API.ShouldAurasBeSecret()
    return false
end

-- Shared native-aura stylers consume table-form AuraData through the same
-- fail-closed contract as Forever. Era values are not secret, so prefer the
-- modern table API when present and otherwise normalize the legacy tuple.
local function ClassicAuraTupleToData(unit, index, filter)
    local getter = filter == "HARMFUL" and _G.UnitDebuff or _G.UnitBuff
    if type(getter) ~= "function" then return nil end
    local name, icon, count, debuffType, duration, expirationTime, source,
        isStealable, showPersonal, spellId, canApply, bossAura, castByPlayer,
        showAll, timeMod = getter(unit, index)
    if not name then return nil end
    return {
        name = name, icon = icon, applications = count, dispelName = debuffType,
        duration = duration, expirationTime = expirationTime, sourceUnit = source,
        isStealable = isStealable, nameplateShowPersonal = showPersonal,
        spellId = spellId, canApplyAura = canApply, isBossAura = bossAura,
        isFromPlayerOrPlayerPet = castByPlayer, nameplateShowAll = showAll,
        timeMod = timeMod,
    }
end

function API.GetReadableAuraDataByIndex(unit, index, filter)
    local auras = _G.C_UnitAuras
    local fn = type(auras) == "table" and auras.GetAuraDataByIndex
    if type(fn) == "function" then
        local ok, auraData = pcall(fn, unit, index, filter)
        if ok then return auraData end
    end
    if type(auras) == "table" then
        fn = filter == "HARMFUL" and auras.GetDebuffDataByIndex or auras.GetBuffDataByIndex
        if type(fn) == "function" then
            local ok, auraData = pcall(fn, unit, index)
            if ok then return auraData end
        end
    end
    return ClassicAuraTupleToData(unit, index, filter)
end

function API.GetReadableAuraDataByAuraInstanceID(unit, auraInstanceID)
    if auraInstanceID == nil then return nil end
    local auras = _G.C_UnitAuras
    local fn = type(auras) == "table" and auras.GetAuraDataByAuraInstanceID
    if type(fn) ~= "function" then return nil end
    local ok, auraData = pcall(fn, unit, auraInstanceID)
    return ok and auraData or nil
end

-- Resolve Blizzard minimap children at call time through the same vocabulary
-- used by modern clients. Era exposes most of these as globals; keeping the
-- object lookup here lets shared minimap consumers stay client-neutral.
function API.GetMinimapParts()
    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    return {
        minimap = minimap,
        cluster = cluster,
        zoomIn = _G.MinimapZoomIn,
        zoomOut = _G.MinimapZoomOut,
        zoneButton = _G.MinimapZoneTextButton,
        zoneText = _G.MinimapZoneText,
        trackingButton = _G.MiniMapTracking or _G.MiniMapTrackingFrame,
        mailFrame = _G.MiniMapMailFrame,
        battlefieldFrame = _G.MiniMapBattlefieldFrame,
        border = _G.MinimapBorder,
        compassTexture = _G.MinimapCompassTexture,
        borderTop = cluster and cluster.BorderTop or nil,
        northTag = _G.MinimapNorthTag,
        backdrop = _G.MinimapBackdrop or cluster,
        gameTimeFrame = _G.GameTimeFrame,
        gameTimeTexture = _G.GameTimeTexture,
        toggleButton = _G.MinimapToggleButton,
        clockButton = _G.TimeManagerClockButton,
        lfgButton = _G.QueueStatusMinimapButton or _G.LFGMinimapFrame or _G.MiniMapLFGFrame,
    }
end

-- Shared client-neutral feature files use the guarded registration vocabulary
-- that Forever needs for event drift. Classic's event names are stable, so the
-- adapter is intentionally just the native call with the same boolean result.
function API.RegisterEvent(frame, event)
    if not frame or type(frame.RegisterEvent) ~= "function" or type(event) ~= "string" then return false end
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

function API.RegisterUnitEvent(frame, event, unit1, unit2)
    if not frame then return false end
    if type(frame.RegisterUnitEvent) == "function" and unit1 then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        if ok then return true end
    end
    return API.RegisterEvent(frame, event)
end

-- Shared Automation owns player-interaction policy; Compat owns the client
-- action used to perform it. Era's spirit-healer confirmation is the legacy
-- AcceptXPLoss call, while releasing to the graveyard is RepopMe.
function API.ConfirmSpiritHealer()
    if type(_G.AcceptXPLoss) ~= "function" then return false end
    return pcall(_G.AcceptXPLoss)
end

function API.ReleaseSpirit()
    if type(_G.RepopMe) ~= "function" then return false end
    return pcall(_G.RepopMe)
end

-- Shared QoL/Social consumers use the same client-neutral helpers as Forever.
-- Era keeps the legacy globals as the authoritative path; modern namespaces
-- are accepted opportunistically so the shared feature files stay free of
-- client branches.
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
-- MERCHANTS
-- =============================================================================
-- Grocery uses one normalized merchant vocabulary on every client. Era's
-- globals already expose the established multiple-return contract, so these
-- bindings are normally zero-overhead aliases; the guarded C_MerchantFrame
-- table adapter is only used if a future Classic surface removes that global.
API.GetMerchantNumItems = pick(GetMerchantNumItems)
API.GetMerchantItemLink = pick(GetMerchantItemLink)
API.GetMerchantItemID = pick(GetMerchantItemID)
API.GetMerchantItemMaxStack = pick(GetMerchantItemMaxStack)
API.GetMerchantItemCostInfo = pick(GetMerchantItemCostInfo)
API.BuyMerchantItem = pick(BuyMerchantItem)

local modernMerchantInfo = C_MerchantFrame and C_MerchantFrame.GetItemInfo
if type(GetMerchantItemInfo) == "function" then
    API.MerchantInfoKind = "legacy-global"
    API.GetMerchantItemInfo = GetMerchantItemInfo
elseif type(modernMerchantInfo) == "function" then
    API.MerchantInfoKind = "C_MerchantFrame"
    API.GetMerchantItemInfo = function(index)
        local ok, info = pcall(modernMerchantInfo, index)
        if not ok or type(info) ~= "table" then return nil end
        return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
            info.isPurchasable, info.isUsable, info.hasExtendedCost, info.currencyID,
            info.spellID, info.isQuestStartItem
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

-- Shared money presentation boundary. Keep Classic's exact historical
-- GetCoinTextureString(..., 12) behavior while Forever can route the same call
-- through its native MoneyFormatter adapter.
function API.FormatMoney(amount)
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(amount or 0, 12)
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    if gold > 0 then return ("%dg %ds %dc"):format(gold, silver, copper) end
    if silver > 0 then return ("%ds %dc"):format(silver, copper) end
    return ("%dc"):format(copper)
end

function API.GetCoinTextureString(amount, fontHeight)
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(amount or 0, fontHeight)
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    if gold > 0 then return ("%dg %ds %dc"):format(gold, silver, copper) end
    if silver > 0 then return ("%ds %dc"):format(silver, copper) end
    return ("%dc"):format(copper)
end

-- Shared inventory presentation helper. Forever prefers the modern coin
-- atlases when available; Era keeps the historical MoneyFrame textures.
-- Keeping this behind Compat lets InventoryManager/NetWorth share one source
-- without teaching either module which client owns the icon asset.
local LEGACY_COIN_TEXTURES = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}

function API.SetCoinIcon(texture, denomination)
    if not texture or type(texture.SetTexture) ~= "function" then return false end
    denomination = type(denomination) == "string" and denomination:lower() or denomination
    local path = LEGACY_COIN_TEXTURES[denomination]
    if not path then return false end
    texture:SetTexture(path)
    return true
end

function API.GetCoinText(amount, separator)
    if type(GetCoinText) == "function" then
        return GetCoinText(amount or 0, separator)
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    local sep = separator or " "
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " Gold" end
    if silver > 0 then parts[#parts + 1] = silver .. " Silver" end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. " Copper" end
    return table.concat(parts, sep)
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
    return UnitPower(unit or "player", pt) or 0
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

API.GetQuestLogSelection = pick(GetQuestLogSelection, C_QuestLog and C_QuestLog.GetSelectedQuest and function()
    return C_QuestLog.GetSelectedQuest()
end)

API.SelectQuestLogEntry = pick(SelectQuestLogEntry, C_QuestLog and C_QuestLog.SetSelectedQuest and function(index)
    return C_QuestLog.SetSelectedQuest(index)
end)

API.GetQuestLogIndexByID = pick(GetQuestLogIndexByID, C_QuestLog and C_QuestLog.GetLogIndexForQuestID and function(questID)
    return C_QuestLog.GetLogIndexForQuestID(questID)
end)

API.GetQuestLogRewardXP = pick(GetQuestLogRewardXP)

API.IsQuestComplete = pick(IsQuestComplete, C_QuestLog and C_QuestLog.IsComplete and function(questID)
    return C_QuestLog.IsComplete(questID)
end)

-- 1.15.9 baseline audit: neither the QuestReadyForTurnIn global nor
-- C_QuestLog.ReadyForTurnIn exists on the 2.5.6-like surface — the era-correct
-- form is IsQuestComplete (close enough for the XP-overlay "turn-in ready"
-- highlight; it goes true when objectives are done, same as the old behavior).
API.QuestReadyForTurnIn = pick(QuestReadyForTurnIn,
    (C_QuestLog and C_QuestLog.ReadyForTurnIn and function(questID)
        return C_QuestLog.ReadyForTurnIn(questID)
    end)
    or function(questID)
        return API.IsQuestComplete(questID)
    end)

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

API.GetMacroSpell = pick(GetMacroSpell)
API.GetMacroBody = pick(GetMacroBody)
API.GetWeaponEnchantInfo = pick(GetWeaponEnchantInfo)
-- Classic-only global (retail replaced it with C_Minimap.GetTrackingInfo,
-- which has no single "current texture" equivalent). Stub returns nil, so the
-- tracker module simply shows its inactive state if this ever goes away.
API.GetTrackingTexture = pick(GetTrackingTexture)
API.UnitGetTotalAbsorbs = pick(UnitGetTotalAbsorbs, nil) -- stub returns nil; callers use `or 0`
API.UnitGroupRolesAssigned = pick(UnitGroupRolesAssigned, function() return "NONE" end)

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
