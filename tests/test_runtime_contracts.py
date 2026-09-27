from __future__ import annotations

import random
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RuntimeContractTests(unittest.TestCase):
    def test_forever_target_aura_movers_use_native_secret_container(self) -> None:
        shared = (ROOT / "src" / "common" / "Movers" / "Auras.lua").read_text()
        adapter = (ROOT / "src" / "forever" / "Movers" / "ForeverAuraAdapter.lua").read_text()
        toc = (ROOT / "src" / "forever" / "TurboFace.toc").read_text()

        self.assertIn("ns.MoverAuraProvider", shared)
        self.assertNotIn("IS_TARGET_FOREVER_BUILD", shared)
        self.assertIn('CreateFrame, "AuraContainer"', adapter)
        self.assertIn('"CustomAuraContainerTemplate"', adapter)
        self.assertIn('return "targettarget", false, 4', adapter)
        self.assertIn("function Provider:InvalidateUnit(unit)", adapter)
        self.assertIn("and UnitPresent(unit)", adapter)
        self.assertIn("function SuppressNativeTargetAuras()", adapter)
        self.assertIn("SetMouseMotionEnabled", adapter)
        self.assertIn("SetMouseClickEnabled", adapter)
        self.assertLess(toc.index("Movers\\Auras.lua"), toc.index("Movers\\ForeverAuraAdapter.lua"))
        self.assertLess(toc.index("Movers\\ForeverAuraAdapter.lua"), toc.index("Movers\\Systems.lua"))

    def test_trainer_spellbook_rank_fallback_and_recipe_scrub(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the trainer learned-state contract")
        harness = r'''
function wipe(t) for key in pairs(t) do t[key] = nil end end
BOOKTYPE_SPELL = "spell"

local spellbook = { { "Rend", "Rank 2" }, { "Battle Shout", "" } }
local ns = {
    Trainer = {},
    API = {
        GetSpellInfo = function(id)
            if id == 772 or id == 6546 or id == 6547 then return "Rend" end
            if id == 6673 then return "Battle Shout" end
        end,
        GetNumSpellTabs = function() return 1 end,
        GetSpellTabInfo = function() return "Warrior", nil, 0, #spellbook end,
        GetSpellBookItemName = function(index) return unpack(spellbook[index]) end,
        IsKnownSpellID = function() return false end,
    },
}
function ns:EnsureProfessionRecipeDatabase()
    return {
        GetProfessions = function() return { 185 } end,
        GetRecipes = function(_, professionID)
            assert(professionID == 185)
            return { [4094] = { name = "Barbecued Buzzard Wing" } }
        end,
    }
end

TurboFaceTrainerDB = {
    data = {
        WARRIOR = {
            [0] = { [4094] = { cost = 500 } },
            [4] = { [772] = { cost = 100, rank = 1, status = "available" } },
        },
    },
}

assert(loadfile("src/common/Trainer/SkillData.lua"))("TurboFace", ns)
local trainer = ns.Trainer
assert(trainer:IsClassSpellKnown(772, "Rend", 1, true))
assert(trainer:IsClassSpellKnown(6546, "Rend", 2, true))
assert(not trainer:IsClassSpellKnown(6547, "Rend", 3, true))
assert(trainer:IsClassSpellKnown(6673, "Battle Shout", 1, false))

trainer:ScrubProfessionRecipesFromClassData()
trainer:ScrubClassTrainerTransientStatus()
assert(TurboFaceTrainerDB.data.WARRIOR[0][4094] == nil)
assert(TurboFaceTrainerDB.data.WARRIOR[4][772] ~= nil)
assert(TurboFaceTrainerDB.data.WARRIOR[4][772].status == nil)
assert(TurboFaceTrainerDB.professionCaptureIsolationV1 == true)

spellbook = { { "Rend", "Rank 3" } }
trainer:InvalidateKnownSpellbookRanks()
assert(trainer:IsClassSpellKnown(6547, "Rend", 3, true))
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_quest_automation_defers_and_serializes_npc_actions(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the quest automation contract")
        harness = r'''
local settings = {
    automateGossip = true,
    autoQuestAccept = true,
    autoQuestTurnIn = true,
    automateSpiritHealer = false,
}
local ns = {
    PlusSettings = function() return settings end,
    API = {},
    Chat = function() end,
}

local frames = {}
function CreateFrame()
    local frame = { events = {} }
    function frame:SetScript(kind, callback) self[kind] = callback end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:RegisterEvent(event) self.events[event] = true end
    frames[#frames + 1] = frame
    return frame
end
function ns.API.RegisterEvent(frame, event) frame:RegisterEvent(event) return true end
function ns.API.QuestReadyForTurnIn() return false end

local timers = {}
C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}
local function RunDelay(delay)
    for index, timer in ipairs(timers) do
        if timer.delay == delay then
            table.remove(timers, index)
            timer.callback()
            return true
        end
    end
    return false
end
local function CountDelay(delay)
    local count = 0
    for _, timer in ipairs(timers) do
        if timer.delay == delay then count = count + 1 end
    end
    return count
end

function IsShiftKeyDown() return false end
function UnitIsGhost() return false end
function UnitGUID(unit) if unit == "npc" then return "Creature-test" end end

local questDataVisible = true
local questSelected, gossipSelected = 0, 0
C_GossipInfo = {
    GetNumAvailableQuests = function() return questDataVisible and 1 or 0 end,
    GetNumActiveQuests = function() return 0 end,
    GetAvailableQuests = function()
        return questDataVisible and {{ questID = 42, title = "Test Quest" }} or {}
    end,
    GetActiveQuests = function() return {} end,
    GetOptions = function() return {{ gossipOptionID = 7, orderIndex = 1 }} end,
    SelectAvailableQuest = function(id)
        assert(id == 42)
        questSelected = questSelected + 1
        questDataVisible = false
    end,
    SelectOption = function() gossipSelected = gossipSelected + 1 end,
}

local accepted, completed, rewarded = 0, 0, 0
function AcceptQuest() accepted = accepted + 1 end
function IsQuestCompletable() return true end
function CompleteQuest() completed = completed + 1 end
function GetNumQuestChoices() return 0 end
function GetQuestReward(index) assert(index == 0) rewarded = rewarded + 1 end

assert(loadfile("src/common/Plus/Automation.lua"))("TurboFace", ns)
ns.PlusAutomation:Init()

local gossipFrame, questFrame
for _, frame in ipairs(frames) do
    if frame.events.GOSSIP_SHOW and frame.events.GOSSIP_CLOSED and frame.events.QUEST_DETAIL then
        questFrame = frame
    elseif frame.events.GOSSIP_SHOW and frame.events.GOSSIP_CLOSED then
        gossipFrame = frame
    end
end
assert(gossipFrame and questFrame, "automation event frames were not registered")

-- Neither listener may act from inside GOSSIP_SHOW.
gossipFrame.OnEvent(gossipFrame, "GOSSIP_SHOW")
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(questSelected == 0 and gossipSelected == 0)

-- The quest pump wins before delayed single-option gossip. Closing/advancing
-- gossip invalidates the latter even if the quest arrays have gone stale.
assert(RunDelay(0.10))
assert(questSelected == 1 and gossipSelected == 0)
gossipFrame.OnEvent(gossipFrame, "GOSSIP_CLOSED")
questFrame.OnEvent(questFrame, "GOSSIP_CLOSED", true)
assert(RunDelay(0.20))
assert(gossipSelected == 0, "single-option gossip raced the quest selector")

-- QUEST_DETAIL observes selector success, but acceptance itself waits until
-- the event callback has returned. No speculative gossip pump is started.
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
assert(accepted == 0)
assert(RunDelay(0))
assert(accepted == 1)
assert(CountDelay(0.10) == 0, "quest detail started a pre-confirmation rescan")

questFrame.OnEvent(questFrame, "QUEST_ACCEPTED", 42)
assert(CountDelay(0.10) == 1, "accepted quest did not schedule the next scan")

questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
assert(completed == 0)
assert(RunDelay(0))
assert(completed == 1)

questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(rewarded == 0)
assert(RunDelay(0))
assert(rewarded == 1)
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_loot_frame_accepts_either_documented_player_field(self) -> None:
        source = (ROOT / "src" / "common" / "LootFrame.lua").read_text()

        self.assertIn("local function OwnLootMessage(msg, playerName, playerName2)", source)
        self.assertIn("StripRealm(playerName) == ownName", source)
        self.assertIn("StripRealm(playerName2) == ownName", source)
        self.assertIn("OwnLootMessage(msg, playerName, playerName2)", source)
        self.assertNotIn("OwnLootMessage(msg, receiver)", source)

    def test_forever_development_restrictions_and_bypass(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the client-policy contract")
        harness = r'''
local ns = { Compat = { IS_TARGET_FOREVER_BUILD = true } }
TurboFaceCompatDB = {}
WOW_PROJECT_ID = 1
function GetBuildInfo() return "1.60.1", "test", "", 16001 end

assert(loadfile("src/common/Core/Client.lua"))("TurboFace", ns)
local client = ns.Client
assert(client:IsSettingDevelopmentRestricted("dotPredictionEnabled"))
assert(client:IsSettingDevelopmentRestricted("healPredictionEnabled"))
assert(client:IsSettingDevelopmentRestricted("bubbleNameplates.friendlyNPCNameTitleOnly"))
assert(client:IsSettingDevelopmentRestricted("bubbleNameplates.friendlyPlayerDamagedOnly"))
assert(client:IsSettingDevelopmentRestricted("bubbleNameplates.friendlyNPCDamagedOnly"))
assert(client:IsGateDevelopmentRestricted("unitframes"))
assert(client:IsGateDevelopmentRestricted("castBars"))
assert(client:IsGateDevelopmentRestricted("class"))
assert(not client:IsDevBypassActive())

assert(client:SetDevBypass(true))
assert(TurboFaceCompatDB.devFeatureBypass == true)
assert(not client:IsSettingDevelopmentRestricted("dotPredictionEnabled"))
assert(not client:IsGateDevelopmentRestricted("unitframes"))
assert(not client:IsGateDevelopmentRestricted("castBars"))
assert(not client:IsGateDevelopmentRestricted("class"))

assert(not client:SetDevBypass(false))
assert(TurboFaceCompatDB.devFeatureBypass == nil)
assert(client:IsSettingDevelopmentRestricted("dotPredictionEnabled"))
assert(client:IsGateDevelopmentRestricted("castBars"))
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_forever_target_swing_combat_estimator(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the target estimator contract")
        harness = r'''
local active
local ns = {
    Compat = { IS_TARGET_FOREVER_BUILD = true },
    API = {
        IsSecretValue = function(value) return value == "SECRET" end,
        CanAccessValue = function(value) return value ~= "SECRET" end,
    },
    Providers = {
        Register = function(_, family, _, provider)
            if family == "swingTimers" then active = provider end
        end,
    },
}

local targetExists, targetTargetExists = true, true
local canAttack, targetsPlayer = true, true
local guid = "Creature-0-0-0-0-1"
function UnitExists(unit)
    if unit == "target" then return targetExists end
    if unit == "targettarget" then return targetTargetExists end
    return false
end
function UnitCanAttack() return canAttack end
function UnitIsUnit() return targetsPlayer end
function UnitGUID() return guid end

assert(loadfile("src/forever/Combat/ForeverSwingTimerAdapter.lua"))("TurboFace", ns)
assert(active and active:UsesTargetCombatEstimator())

local duration, observedGuid = active:ObserveTargetCombat("player", "WOUND", 10)
assert(duration == 2 and observedGuid == guid)
duration = active:ObserveTargetCombat("player", "PARRY", 12.4)
assert(math.abs(duration - 2.4) < 0.0001)

-- Implausibly close results resync the bar without poisoning the learned cadence.
duration = active:ObserveTargetCombat("player", "MISS", 12.5)
assert(math.abs(duration - 2.4) < 0.0001)
assert(active:ObserveTargetCombat("player", "HEAL", 14) == nil)

targetsPlayer = false
assert(active:ObserveTargetCombat("player", "WOUND", 15) == nil)
targetsPlayer = "SECRET"
canAttack = "SECRET"
duration = active:ObserveTargetCombat("player", "WOUND", 16)
assert(math.abs(duration - 3.5) < 0.0001)

guid = "Creature-0-0-0-0-2"
canAttack, targetsPlayer = true, true
duration = active:ObserveTargetCombat("player", "WOUND", 20)
assert(duration == 2)
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        shared = (ROOT / "src" / "common" / "Combat" / "SwingTimers.lua").read_text()
        self.assertIn("function SwingTimers:RecordNameplateSwing(guid, duration, now)", shared)
        self.assertIn("SwingTimers:RecordNameplateSwing(guid, duration, now)", shared)
        self.assertIn("swingEventHandlers.UNIT_COMBAT = OnProviderTargetCombat", shared)
        self.assertIn('ns.RegisterUnitEvent(nameplateRuntimeFrame, "UNIT_COMBAT", "player")', shared)
        self.assertIn("and not nameplateRuntimeActivated", shared)
        self.assertIn("if exists == false or attackable == false then return false end", shared)

        forever_nameplates = (
            ROOT / "src" / "forever" / "Nameplates" / "ForeverNativeAdapter.lua"
        ).read_text()
        self.assertIn("if attackable == false then StopSwing(st); return end", forever_nameplates)
        self.assertIn("if currentGUID and currentGUID ~= st.guid", forever_nameplates)
        self.assertIn('widthGuide:SetPoint("LEFT", st.root, "LEFT", 0, 0)', forever_nameplates)
        self.assertIn('widthGuide:SetPoint("RIGHT", st.root, "RIGHT", 0, 0)', forever_nameplates)
        self.assertIn("host._tfSwingWidth = width", forever_nameplates)
        self.assertIn('rootCenterGuide:SetPoint("CENTER", host, "CENTER", 0, 0)', forever_nameplates)
        self.assertIn('hpBottomGuide:SetPoint("CENTER", hp, "BOTTOM", 0, 0)', forever_nameplates)
        self.assertIn("host._tfSwingCenterAnchor = host", forever_nameplates)
        self.assertIn("host._tfSwingYOffset = bottomY - rootY", forever_nameplates)
        self.assertIn("host._tfSwingYOffset = WHOLE_PLATE_HP_BOTTOM_Y", forever_nameplates)
        self.assertIn("local SWING_Y_NUDGE = -3", forever_nameplates)
        self.assertIn("f.leftGlow:SetVertexColor(1.0, 0.10, 0.06, 0.82)", forever_nameplates)
        self.assertIn("f.leftCore:SetVertexColor(1.0, 0.06, 0.03, 0.96)", forever_nameplates)
        self.assertIn("local f = BNP:_EnsureSwing(host)", forever_nameplates)
        self.assertIn('f:SetFrameStrata("TOOLTIP")', forever_nameplates)
        self.assertIn("f:SetFrameLevel(10000)", forever_nameplates)
        self.assertIn("if f:GetParent() ~= UIParent then f:SetParent(UIParent) end", forever_nameplates)
        self.assertIn('f.ready:SetDrawLayer("OVERLAY", 7)', forever_nameplates)
        self.assertIn("BNP:_AnchorSwingFrame(f, host)", forever_nameplates)
        self.assertIn("if st.hiddenByNative or not host:IsShown()", forever_nameplates)
        self.assertIn("BNP:_ShowSwingProgress(f, progress)", forever_nameplates)
        self.assertIn("BNP:_SetSwingReady(f, true)", forever_nameplates)
        self.assertNotIn('f.progress = CreateFrame("StatusBar", nil, f)', forever_nameplates)

        common_nameplates = (
            ROOT / "src" / "common" / "Nameplates" / "BubbleNameplates.lua"
        ).read_text()
        self.assertIn(
            "local anchor = plate._tfSwingAnchor or healthBarsContainer or hp",
            common_nameplates,
        )
        self.assertIn(
            'frame:SetPoint("TOP", detachedCenter, "CENTER", 0, detachedYOffset - 1)',
            common_nameplates,
        )

    def test_forever_defaults_match_promoted_live_configuration(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the Forever preset contract")
        harness = r'''
local ns = { Client = { flavor = "forever" }, DB_VERSION = 79 }
function ns.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[ns.DeepCopy(key, seen)] = ns.DeepCopy(child, seen)
    end
    return out
end

WOW_PROJECT_ID = 1
function GetBuildInfo() return "1.60.1", "", "", 16001 end

assert(loadfile("src/common/Core/Schema.lua"))("TurboFace", ns)
assert(loadfile("src/forever/Core/ForeverSchema.lua"))("TurboFace", ns)
assert(loadfile("src/common/Core/Defaults.lua"))("TurboFace", ns)
assert(loadfile("src/common/Core/Profiles.lua"))("TurboFace", ns)
assert(loadfile("src/forever/Core/ForeverDefaults.lua"))("TurboFace", ns)

local data = ns.defaults
local modules = data.modules
assert(modules.unitframes.enabled == false)
assert(modules.nameplates.enabled == true)
assert(modules.hotbarPower.enabled == true)
assert(modules.playerTicks.enabled == true)
assert(modules.swingTimers.enabled == false)
assert(modules.auras.enabled == false)
assert(modules.castBars.enabled == false)
assert(modules.class.enabled == false)
assert(modules.plus.minimap == false and modules.plus.social == false)

assert(data.quickSetup.enabled == true)
assert(data.hearthTextStyle == "SHADOW")
assert(data.netWorthFontSize == 11)
assert(data.lootFrame.width == 220)
assert(data.plus.weatherLevel == 1)
for _, key in ipairs({
    "hideHitIndicators", "hideKeybindText", "hideMiniClock",
    "hideMiniDayNight", "hideMiniLFG", "hideMiniZoneText",
    "hideMiniZoomBtns", "hideRaidGroupLabels", "hideZoneText",
    "keepAudioSynced", "minimapZoneBanner", "noBagAutomation",
    "noCombatLogTab", "noConfirmLoot", "noRestedEmotes",
    "noScreenEffects", "noScreenGlow", "setWeatherDensity",
    "showRaidToggle",
}) do
    assert(data.plus[key] == false, key .. " did not preserve the live setting")
end

assert(data.combinedBag.point == "RIGHT")
assert(data.combinedBag.relativePoint == "RIGHT")
assert(data.combinedBag.x == -22.22224235534668)
assert(data.combinedBag.y == -173.5000305175781)
assert(data.movers.activeElement == "GroceryButton")
local expectedPositions = {
    BagSlots = { 400, -510 },
    ExperienceBar = { -875, -220 },
    FPSCounter = { -400, -510 },
    GroceryButton = { 555, -580 },
    Hearthstone = { -400, -525 },
    NetWorth = { 400, -525 },
    SpeedrunSplits = { -930, 495 },
}
for name, expected in pairs(expectedPositions) do
    local mover = data.movers.elements[name]
    assert(mover.x == expected[1] and mover.y == expected[2], name .. " position drifted")
end
for _, name in ipairs({
    "BlizzardLootFrame", "GameTooltip", "LatencyBar", "MinimapClock",
    "MinimapLFG", "MinimapMail", "QuestTracker", "TargetBuffs",
    "TargetDebuffs", "TargetFrameToT", "ToTDebuffs",
}) do
    assert(data.movers.elements[name].enabled == false, name .. " should start disabled")
end
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cadence_isolates_and_evicts_failing_clients(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the cadence runtime contract")
        harness = r'''
_G.time_now = 0
function GetTime() return _G.time_now end

_G.pending_timers = {}
C_Timer = {
    NewTimer = function(delay, fn)
        local timer = { at = _G.time_now + delay, fn = fn, cancelled = false }
        timer.Cancel = function(self)
            self.cancelled = true
            for index, queued in ipairs(_G.pending_timers) do
                if queued == self then table.remove(_G.pending_timers, index) break end
            end
        end
        table.insert(_G.pending_timers, timer)
        return timer
    end,
    After = function() end,
}

_G.errors = {}
function geterrorhandler()
    return function(err) table.insert(_G.errors, tostring(err)) end
end

local noop = function() end
for _, name in ipairs({
    "UnitClass", "UnitGUID", "UnitExists", "GetSpellInfo", "SetCVar",
    "GetCVar", "InCombatLockdown", "UnitIsUnit", "GetLocale", "IsSpellKnown",
    "CombatLogGetCurrentEventInfo", "hooksecurefunc", "UnitAffectingCombat",
    "GetTimePreciseSec", "securecall", "UIParent", "PixelUtil", "LibStub",
}) do
    if _G[name] == nil then _G[name] = noop end
end
CreateFrame = function()
    local frame = {}
    setmetatable(frame, { __index = function() return function() end end })
    return frame
end

TurboFaceDB = {}
TurboFaceCacheDB = {}

local function AdvanceTo(target)
    local guard = 0
    while _G.time_now < target do
        guard = guard + 1
        if guard > 100000 then error("timer storm") end
        _G.time_now = math.min(target, _G.time_now + 0.005)
        while true do
            local due
            for index, timer in ipairs(_G.pending_timers) do
                if not timer.cancelled and timer.at <= _G.time_now then due = index break end
            end
            if not due then break end
            local timer = table.remove(_G.pending_timers, due)
            timer.fn()
        end
    end
end

local ns = {}
ns.API = setmetatable({ GetAddOnMetadata = function() return "test" end }, {
    __index = function() return function() end end,
})
assert(loadfile("src/common/Core/Config.lua"))("TurboFace", ns)

_G.good_runs = 0
ns.Cadence:Add("TurboFaceGood", 0.1, function() _G.good_runs = _G.good_runs + 1 end)
AdvanceTo(0.5)
assert(_G.good_runs > 0, "healthy cadence client did not fire")

_G.errors = {}
_G.bad_runs = 0
ns.Cadence:Add("TurboFaceBad", 0.1, function()
    _G.bad_runs = _G.bad_runs + 1
    error("simulated client failure")
end)
local good_before = _G.good_runs
AdvanceTo(1.5)
assert(_G.good_runs > good_before, "healthy cadence client stopped after peer failure")
assert(#_G.errors == 2, "failing cadence client did not use bounded reporting")
assert(_G.bad_runs == 3, "failing cadence client did not use the three-run budget")
assert(not ns.Cadence:IsActive("TurboFaceBad"), "failing cadence client was not evicted")

_G.retry_runs = 0
ns.Cadence:Add("TurboFaceBad", 0.1, function() _G.retry_runs = _G.retry_runs + 1 end)
AdvanceTo(_G.time_now + 1.0)
assert(_G.retry_runs > 0, "cadence re-registration did not receive a fresh budget")

ns.Cadence:Remove("TurboFaceGood")
ns.Cadence:Remove("TurboFaceBad")
assert(ns.Cadence:Count() == 0, "cadence scheduler did not park when empty")
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_classbuff_snapshot_preserves_first_matching_aura(self) -> None:
        source = (ROOT / "src" / "common" / "Combat" / "ClassBuffs.lua").read_text()
        for marker in (
            "local function RefreshBuffSnapshot()",
            "if buffIndexByName[name] == nil then",
            "index < bestIndex",
        ):
            self.assertIn(marker, source)

        def direct_scan(buffs: list[tuple[str, float]], wanted: set[str]) -> tuple[bool, float | None]:
            for name, expiration in buffs[:40]:
                if name in wanted:
                    return True, expiration - 1000 if expiration > 0 else None
            return False, None

        def indexed_scan(buffs: list[tuple[str, float]], wanted: set[str]) -> tuple[bool, float | None]:
            first: dict[str, tuple[int, float]] = {}
            for index, (name, expiration) in enumerate(buffs[:40], 1):
                first.setdefault(name, (index, expiration))
            matches = [first[name] for name in wanted if name in first]
            if not matches:
                return False, None
            _, expiration = min(matches, key=lambda item: item[0])
            return True, expiration - 1000 if expiration > 0 else None

        names = [
            "MarkOfTheWild", "GiftOfTheWild", "Thorns", "IceArmor", "MageArmor",
            "FrostArmor", "BattleShout", "Clearcasting", "LightningShield", "Unrelated",
        ]
        rng = random.Random(20260828)
        for case in range(4000):
            buffs = [
                (rng.choice(names), rng.choice([0, 0, 1005.5, 1010.0, 1000.25]))
                for _ in range(rng.randint(0, 12))
            ]
            wanted = set(rng.sample(names, rng.randint(1, 4)))
            self.assertEqual(direct_scan(buffs, wanted), indexed_scan(buffs, wanted), f"case {case}")

    def test_all_aura_renderers_use_shared_presentation_policy(self) -> None:
        config = (ROOT / "src" / "common" / "Core" / "Config.lua").read_text()
        for marker in (
            "ns.AuraPresentation = AuraPresentation",
            'SetPoint("BOTTOM", relativeTo, "BOTTOM", 0, 1)',
            'SetPoint("TOPRIGHT", relativeTo, "TOPRIGHT", -2, -2)',
            'TurboFaceDB.auraTimerSize',
        ):
            self.assertIn(marker, config)

        for relative in (
            "src/common/AuraStyle.lua",
            "src/common/PartyPetAuras.lua",
            "src/common/Nameplates/Auras.lua",
            "src/forever/Nameplates/ForeverAuras.lua",
            "src/forever/Movers/ForeverAuraAdapter.lua",
        ):
            source = (ROOT / relative).read_text()
            self.assertIn("ns.AuraPresentation", source, relative)

        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()
        self.assertIn('"Timer & Stack Font Size", "auraTimerSize"', options)
        self.assertNotIn('"Debuff Text Size",  "auras.debuffFontSize"', options)
        self.assertNotIn('"Buff Text Size",    "auras.buffFontSize"', options)

    def test_forever_player_aura_style_survives_secret_combat_transition(self) -> None:
        client = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text()
        aura_style = (ROOT / "src" / "common" / "AuraStyle.lua").read_text()
        compatibility = (ROOT / "src" / "forever" / "Core" / "Compatibility.lua").read_text()

        self.assertIn("nativePlayerAuraPresentation = isForever", client)
        self.assertIn("local function StyleNativePlayerPresentation", aura_style)
        self.assertIn("if UseNativePlayerAuraPresentation() then return end", aura_style)
        self.assertIn("StyleNativePlayerPresentation(btn, GetCooldown(btn), false)", aura_style)
        self.assertIn("local function GetTextFrame(button, cd)", aura_style)
        self.assertIn("duration:SetParent(textFrame)", aura_style)
        self.assertIn("StyleNativePlayerPresentation(btn, GetCooldown(btn), nil)", aura_style)
        self.assertIn("ns.AuraPresentation:AnchorTimer(duration, IconRegion(button))", aura_style)
        self.assertIn('hooksecurefunc(mixin, "OnUpdate"', aura_style)
        self.assertIn('hooksecurefunc(duration, "SetPoint"', aura_style)
        self.assertIn("InstallNativeDurationAnchorGuard(button, duration)", aura_style)
        self.assertIn("button._tfNativeDuration", aura_style)
        self.assertIn("and not btn.isAuraAnchor", aura_style)
        self.assertIn("ns.AuraStyle:Refresh()", compatibility)
        self.assertNotIn("ns.AuraStyle:ApplySettings()", compatibility)

        config = (ROOT / "src" / "common" / "Core" / "Config.lua").read_text()
        self.assertIn('type(fontString.SetFont) ~= "function"', config)

    def test_forever_centered_nameplate_auras_use_whole_plate_anchor(self) -> None:
        source = (ROOT / "src" / "forever" / "Nameplates" / "ForeverAuras.lua").read_text()
        self.assertIn("local centerAnchor = st and (st.overlay or st.root) or hp", source)
        self.assertIn('SetPoint("BOTTOM", centerAnchor, "CENTER", x, y)', source)
        self.assertIn('SetPoint(point, hp, relativePoint, x, y)', source)


if __name__ == "__main__":
    unittest.main()
