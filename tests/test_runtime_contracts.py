from __future__ import annotations

import random
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RuntimeContractTests(unittest.TestCase):
    def test_nameplate_combo_points_use_layered_blizzard_style_pips(self) -> None:
        classic = (ROOT / "src" / "common" / "Nameplates" / "NameplateVisuals.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Nameplates" / "ForeverNativeAdapter.lua").read_text()
        defaults = (ROOT / "src" / "common" / "Core" / "Defaults.lua").read_text()
        cache = (ROOT / "src" / "common" / "Nameplates" / "Nameplates.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()

        for source in (classic, forever):
            self.assertIn('CreateTexture(nil, "BACKGROUND")', source)
            self.assertIn('CreateTexture(nil, "ARTWORK")', source)
            self.assertIn('CreateTexture(nil, "OVERLAY")', source)
            self.assertIn('.background:SetPoint("CENTER")', source)
            self.assertIn('.fill:SetPoint("CENTER")', source)
            self.assertIn('.fill:SetShown(filled)', source)
            self.assertIn('.highlight:SetSize(3, 3)', source)
            self.assertIn('.highlight:SetPoint("CENTER", d.fill, "CENTER", 1.5, 1.5)', source)
            self.assertIn('.highlight:SetShown(filled)', source)

        self.assertIn("local TF_CP_SIZE       = 11", classic)
        self.assertIn("local TF_CP_INNER_SIZE = 9", classic)
        self.assertIn("local TF_CP_FILL_SIZE  = 7", classic)
        self.assertIn("local COMBO_SIZE = 11", forever)
        self.assertIn("local COMBO_INNER_SIZE = 9", forever)
        self.assertIn("local COMBO_FILL_SIZE = 7", forever)
        self.assertIn("comboPointYOffset = 3", defaults)
        self.assertIn("ns.c_comboPointYOffset = comboPointYOffset", cache)
        self.assertIn('"comboPointYOffset", -50, 3, 1, false', options)
        self.assertIn('(ns.c_comboPointYOffset or 3)', classic)
        self.assertIn('ns.c_comboPointYOffset or 3)', forever)

    def test_nameplate_combo_snapshots_survive_target_changes(self) -> None:
        classic = (ROOT / "src" / "common" / "Nameplates" / "NameplateVisuals.lua").read_text()
        core = (ROOT / "src" / "common" / "Core.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Nameplates" / "ForeverNativeAdapter.lua").read_text()
        forever_auras = (ROOT / "src" / "forever" / "Nameplates" / "ForeverAuras.lua").read_text()

        self.assertIn("cp = math.max(0, math.min(MAX_CP", classic)
        self.assertIn("plate._tfComboPoints = cp", classic)
        self.assertIn('type(plate._tfComboPoints) == "number" and plate._tfComboPoints > 0', classic)
        self.assertIn("local function RenderComboSnapshot(plate)", classic)
        self.assertIn("local function ClearOtherComboPoints(ownerPlate)", classic)
        self.assertIn("if cp > 0 and comboOwnerPlate ~= plate then", classic)
        self.assertIn("plate._tfComboPoints = 0", classic)
        self.assertIn("function ns.ClearNameplateComboSnapshot(plate, skipReflow)", classic)
        self.assertIn("ns.ClearNameplateComboSnapshot(nameplate.myPlate, true)", core)
        units = (ROOT / "src" / "common" / "Nameplates" / "NameplateUnits.lua").read_text()
        self.assertIn('ns.RegisterEvent(eventFrame, "UPDATE_SHAPESHIFT_FORM")', units)
        self.assertNotIn("old.tfCombo:Hide()", classic)

        self.assertIn("if ComboIsCurrentTarget(st) then", forever)
        self.assertIn("local function ClearOtherComboPoints(ownerState)", forever)
        self.assertIn("if cp > 0 and FNP.comboOwner ~= st then", forever)
        self.assertIn("st.comboPoints = 0", forever)
        self.assertIn("cp = min(MAX_CP", forever)
        self.assertIn("st.comboPoints = cp", forever)
        self.assertIn("local cp = st.comboPoints", forever)
        self.assertIn('if type(cp) ~= "number" or cp <= 0 then', forever)
        self.assertIn("local function HideComboRow(st, hp)", forever)
        self.assertIn("st.comboPoints = nil", forever)
        self.assertIn("function FA:Reposition(st, hp)", forever_auras)
        self.assertIn("PositionAnchorGuide(controller, st, hp)", forever_auras)

    def test_forever_package_identity_survives_client_version_drift(self) -> None:
        compatibility = (ROOT / "src" / "forever" / "Core" / "Compatibility.lua").read_text()
        client = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text()
        core = (ROOT / "src" / "common" / "Core.lua").read_text()

        self.assertIn("local IS_TARGET_FOREVER_BUILD = true", compatibility)
        self.assertNotIn('tostring(v) == "1.60.1"', compatibility)
        self.assertNotIn("tonumber(toc) == 16001", compatibility)
        self.assertNotIn("WOW_PROJECT_ID == 1", compatibility)
        self.assertIn("staticFriendlyIdentityRestore = isForever", client)
        self.assertIn('if not wasEnabled and CorePolicy("staticFriendlyIdentityRestore") then return true end', core)
        self.assertIn('if not CorePolicy("staticFriendlyIdentityRestore")', core)

    def test_quick_setup_saves_mouseover_cast_checkbox_and_modifier(self) -> None:
        quick_setup = (ROOT / "src" / "common" / "QuickSetup.lua").read_text()
        self.assertIn('GetCVarCompat, "enableMouseoverCast"', quick_setup)
        self.assertIn('GetModifiedClickCompat, "MOUSEOVERCAST"', quick_setup)
        self.assertIn('SetCVarCompat, "enableMouseoverCast"', quick_setup)
        self.assertIn('SetModifiedClickCompat, "MOUSEOVERCAST"', quick_setup)
        self.assertIn('storedProfile.blizzard.mouseoverCast = mouseoverCast', quick_setup)
        for modifier in ("NONE", "ALT", "CTRL", "SHIFT"):
            self.assertRegex(quick_setup, rf"\b{modifier}\s*=\s*true")

        for flavor in ("classic", "forever"):
            compatibility = (ROOT / "src" / flavor / "Core" / "Compat.lua").read_text()
            self.assertIn("API.IsMouseoverCastSupported = pick(IsMouseoverCastSupported)", compatibility)
            self.assertIn("API.GetModifiedClick = pick(GetModifiedClick)", compatibility)
            self.assertIn("API.SetModifiedClick = pick(SetModifiedClick)", compatibility)

    def test_quick_setup_saves_map_and_quest_log_filters(self) -> None:
        quick_setup = (ROOT / "src" / "common" / "QuickSetup.lua").read_text()
        expected_cvars = {
            "questObjectives": "questPOI",
            "questLevels": "showQuestLevel",
            "questDifficultyColor": "showQuestDifficultyColor",
            "instanceEntrances": "showDungeonEntrancesOnMap",
            "trackedItems": "contentTrackingFilter",
        }
        for field, cvar in expected_cvars.items():
            self.assertIn(f'field = "{field}", cvar = "{cvar}"', quick_setup)
        self.assertIn("filters.TrivialQuests", quick_setup)
        self.assertIn("return not filteredOut", quick_setup)
        self.assertIn("storedProfile.blizzard.mapQuestLog = mapQuestLog", quick_setup)
        self.assertIn("SetMinimapTrackingCompat, filterIndex, desired", quick_setup)
        self.assertIn("worldMap.WorldMapTrackingOptionsButton", quick_setup)
        self.assertIn('SetWorldMapFilter(entry.cvar, desired)', quick_setup)
        self.assertIn('SetWorldMapFilter("trivialQuests", desired)', quick_setup)
        self.assertIn("minimapUtil.SetTrackingFilterByFilterID", quick_setup)
        self.assertIn("ReadMapQuestLogCVar(entry) == desired", quick_setup)
        self.assertIn("ReadLowLevelQuestFilter() == desired", quick_setup)
        self.assertIn("ArmWorldMapFilterReconciliation(profileToken)", quick_setup)
        self.assertIn('event == "ADDON_LOADED"', quick_setup)
        self.assertIn('arg1 == "Blizzard_WorldMap"', quick_setup)
        self.assertIn('hooksecurefunc(button, "OnShow"', quick_setup)
        self.assertIn("reconcile synchronously while that authorization is still present", quick_setup)
        self.assertIn("CharRoot().mapQuestLogFingerprint", quick_setup)
        self.assertIn("pcall(securecallfunction, filter.Set, filter, desired)", quick_setup)
        self.assertIn("local ok = pcall(filter.Set, filter, desired)", quick_setup)
        self.assertIn("pcall(securecallfunction, SetCVarCompat, entry.cvar, rawValue)", quick_setup)
        self.assertIn("changed ~= false", quick_setup)
        self.assertIn("pcall(ConsoleExec, entry.cvar", quick_setup)
        self.assertIn("MAX_MAP_FILTER_RETRIES = 3", quick_setup)
        self.assertIn('pcall(C_CVar.GetCVarInfo, "showQuestLevel")', quick_setup)
        self.assertIn("Map Filter restore is still blocked for:", quick_setup)
        self.assertIn('CreateFrame("Frame", nil, UIParent, "BackdropTemplate")', quick_setup)
        self.assertIn('apply:SetScript("OnClick"', quick_setup)
        self.assertIn("SetWorldMapFilter(entry.cvar, desired)", quick_setup)
        self.assertIn("ReconcileMapFiltersAfterWorldMapLoad()", quick_setup)
        self.assertIn("function QuickSetup:MapFilterProbe(selector)", quick_setup)
        self.assertIn('selector == "objectives" and "questObjectives" or "questLevels"', quick_setup)
        self.assertIn('"ToggleWorldMap", "ToggleQuestLog", "OpenWorldMap", "OpenQuestLog"', quick_setup)
        self.assertIn('Attempt("secure native filter"', quick_setup)
        self.assertIn('Attempt("ordinary native filter"', quick_setup)
        self.assertIn('Attempt("secure C_CVar"', quick_setup)
        self.assertIn('Attempt("ordinary C_CVar"', quick_setup)
        self.assertIn('Attempt("ConsoleExec"', quick_setup)
        core = (ROOT / "src" / "common" / "Core.lua").read_text()
        self.assertIn('cmd == "mapfilterprobe"', core)
        self.assertIn("ns.QuickSetup:MapFilterProbe(args)", core)

        for flavor in ("classic", "forever"):
            compatibility = (ROOT / "src" / flavor / "Core" / "Compat.lua").read_text()
            self.assertIn("API.GetNumMinimapTrackingTypes", compatibility)
            self.assertIn("API.GetMinimapTrackingFilter", compatibility)
            self.assertIn("API.SetMinimapTracking", compatibility)
            self.assertIn("API.IsMinimapTrackingFilteredOut", compatibility)

    def test_leash_timer_uses_secret_safe_midnight_event_fallbacks(self) -> None:
        source = (ROOT / "src" / "common" / "Combat" / "LeashTimer.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Core" / "Compat.lua").read_text()
        classic = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text()
        client = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()

        self.assertIn('ns.FeatureAvailable("combat.leashTimer", true) == false', source)
        self.assertIn("local UnitGUID = API.ReadUnitGUID", source)
        self.assertIn("local UnitAffectingCombat = API.ReadUnitAffectingCombat", source)
        self.assertIn("local GetUnitSpeed = API.ReadUnitSpeed", source)
        self.assertIn('event == "UNIT_SPELLCAST_SUCCEEDED"', source)
        self.assertIn('event == "UNIT_COMBAT"', source)
        self.assertIn('event == "PLAYER_TARGET_DIED"', source)
        self.assertIn('API.RegisterUnitEvent(eventFrame, "UNIT_COMBAT", "player")', source)
        self.assertIn('API.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")', source)
        self.assertIn("API.IsSpellHarmful(arg3) == true", source)
        self.assertIn("UnitAffectingCombat(unit) == false", source)
        self.assertNotIn("not UnitAffectingCombat(unit)", source)
        self.assertNotIn("local UnitGUID = UnitGUID", source)
        self.assertNotIn("local GetUnitSpeed = GetUnitSpeed", source)

        self.assertIn('["combat.leashTimer"] = Row("shared", true', client)
        self.assertIn('Override("combat.leashTimer", "blocked", false', client)
        self.assertIn('ClientFeatureAvailable("combat.leashTimer", true)', options)
        self.assertIn('or "Unavailable on Forever: the new API does not expose reliable per-enemy combat attribution."', options)
        self.assertIn('if sec.available == false then', options)
        self.assertIn('local gateOn = sec.available ~= false and GateEnabled', options)
        self.assertIn('table.insert(turboFaceMovers, 7, { "Leash Timer", "LeashTimer" })', options)

        for compat in (forever, classic):
            self.assertIn("API.IsSpellHarmful", compat)
            self.assertIn("ReadUnitAffectingCombat", compat)
            self.assertIn("ReadUnitClassification", compat)
            self.assertIn("ReadRaidTargetIndex", compat)
            self.assertIn("ReadUnitSpeed", compat)

    def test_skill_tracker_uses_modern_skillinfo_compatibility_boundary(self) -> None:
        shared = (ROOT / "src" / "common" / "Skills.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Core" / "Compat.lua").read_text()
        classic = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text()

        self.assertIn("local GetNumSkillLines   = ns.API.GetNumSkillLines", shared)
        self.assertIn("local GetSkillLineInfo   = ns.API.GetSkillLineInfo", shared)
        self.assertIn("local ExpandSkillHeader  = ns.API.ExpandSkillHeader", shared)
        self.assertIn("local function SkillLineCount()", shared)
        self.assertIn("AddNames(GetNumSpellTabs, GetSpellTabInfo)", shared)
        self.assertNotIn("local GetNumSkillLines   = GetNumSkillLines", shared)

        for source in (forever, classic):
            self.assertIn("API.GetNumSkillLines = pick(", source)
            self.assertIn("API.GetSkillLineInfo = pick(", source)
            self.assertIn("GetNumSkillLines", source)
            self.assertIn("GetSkillLineInfo", source)
            self.assertIn("not info.isCollapsed", source)
            self.assertIn("API.ExpandSkillHeader = pick(", source)
            self.assertIn("API.CollapseSkillHeader = pick(", source)

    def test_skill_tracker_scan_restores_headers_and_filters_class_lines(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the skill tracker contract")
        harness = r'''
local collapsed = true
local function Lines()
    if collapsed then
        return {
            { "Weapon Skills", true, false },
            { "Class Skills", true, false },
        }
    end
    return {
        { "Weapon Skills", true, true },
        { "Swords", false, nil, 31, 0, 0, 50 },
        { "Class Skills", true, true },
        { "Arms", false, nil, 50, 0, 0, 50 },
        { "Professions", true, true },
        { "Mining", false, nil, 40, 0, 0, 75 },
        { "Mining", false, nil, 42, 0, 0, 75 },
    }
end

local ns = {
    API = {
        GetNumSkillLines = function() return #Lines() end,
        GetSkillLineInfo = function(index) return unpack(Lines()[index]) end,
        ExpandSkillHeader = function(index) assert(index == 0); collapsed = false end,
        CollapseSkillHeader = function() collapsed = true end,
        GetNumTalentTabs = function() return nil end,
        GetTalentTabInfo = function() return nil end,
        GetNumSpellTabs = function() return 1 end,
        GetSpellTabInfo = function() return "Arms" end,
    },
    DB = function() return {} end,
    ProfessionData = {
        GetKey = function(_, name) if name == "Mining" then return "mining" end end,
        IsSecondary = function() return false end,
        GetIcon = function() return 123 end,
    },
    RegisterCPUProfileTarget = function() end,
}
function UnitLevel() return 10 end

assert(loadfile("src/common/Skills.lua"))("TurboFace", ns)
local result = ns.Skills:Scan()
assert(collapsed == true)
assert(#result.weapon == 1 and result.weapon[1].name == "Swords")
assert(result.byName.Arms == nil)
assert(#result.profession == 1 and result.profession[1].name == "Mining")
assert(result.profession[1].rank == 42 and result.profession[1].maxRank == 75)
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_nameplate_buff_icon_size_is_square_and_rebuilds_forever_geometry(self) -> None:
        defaults = (ROOT / "src" / "common" / "Core" / "Defaults.lua").read_text()
        shared = (ROOT / "src" / "common" / "Nameplates" / "Auras.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Nameplates" / "ForeverAuras.lua").read_text()

        self.assertIn("buffIconWidth        = 26", defaults)
        self.assertIn("buffIconHeight       = 26", defaults)
        self.assertIn("ns.c_buffIconHeight = ns.c_buffIconWidth", shared)
        self.assertIn("local function ControllerSignature(kind)", forever)
        self.assertIn("local signature = ControllerSignature(kind)", forever)
        self.assertIn("styleSignature = signature or ControllerSignature(kind)", forever)
        self.assertIn("ns.c_buffIconHeight", forever)

    def test_castbars_never_cache_or_compare_secret_cast_guids(self) -> None:
        source = (ROOT / "src" / "common" / "Combat" / "Castbars.lua").read_text()

        self.assertIn("local function ReadableCastGUID(value)", source)
        self.assertIn("not ns.API.CanAccessValue(value)", source)
        self.assertIn("castGUIDShown = ReadableCastGUID(castGUID)", source)
        self.assertIn("pCastGUID = ReadableCastGUID(castGUID)", source)
        self.assertIn("local incomingGUID = ReadableCastGUID(castGUID)", source)
        self.assertNotIn("castGUIDShown = castGUID", source)
        self.assertNotIn("castGUIDShown == castGUID", source)
        self.assertNotIn("pCastGUID = castGUID", source)
        self.assertNotIn("pCastGUID == castGUID", source)

    def test_target_castbar_never_divides_by_opaque_timing(self) -> None:
        source = (ROOT / "src" / "common" / "Combat" / "Castbars.lua").read_text()

        self.assertIn("local targetTimingReadable = false", source)
        self.assertIn("local function CaptureTargetTiming(start, finish)", source)
        self.assertIn("ns.API.IsReadableNumber", source)
        self.assertIn("if not startReadable or not finishReadable or finish <= start then", source)
        self.assertIn("elseif active and targetTimingReadable then", source)
        self.assertIn("local targetNeedsTick = holdTime > 0 or (active and targetTimingReadable)", source)
        self.assertIn('castbar.timerText:SetText(channel and (CHANNELING or "Channeling")', source)
        self.assertNotIn("duration  = math.max((finish - start) / 1000, 0.001)", source)

    def test_junk_marks_desaturate_default_bag_item_art(self) -> None:
        source = (ROOT / "src" / "common" / "Inventory" / "InventoryManager.lua").read_text()

        self.assertIn("local function SetJunkIconDimmed(button, dimmed)", source)
        self.assertIn("SetItemButtonDesaturated(button, true)", source)
        self.assertIn("SetItemButtonDesaturated(button, false)", source)
        self.assertIn("button._tfJunkDimmed = true", source)
        self.assertIn("SetJunkIconDimmed(button, showJunk == true)", source)
        self.assertIn("SetJunkIconDimmed(button, false)", source)

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

    def test_forever_target_debuff_border_matches_nameplate_geometry(self) -> None:
        target = (ROOT / "src" / "forever" / "Movers" / "ForeverAuraAdapter.lua").read_text()
        nameplate = (ROOT / "src" / "forever" / "Nameplates" / "ForeverAuras.lua").read_text()

        texture = 'local BORDER_TEXTURE = "Interface\\\\Buttons\\\\UI-Debuff-Overlays"'
        coords = "localBORDER_COORDS={0.296875,0.5703125,0,0.515625}"
        for source in (target, nameplate):
            self.assertIn(texture, source)
            self.assertIn(coords, source.replace(" ", ""))
            self.assertIn('border:SetPoint("CENTER")', source)
        self.assertIn("border:SetSize(controller.iconSize + 2, controller.iconSize + 2)", target)
        self.assertIn("button.Border = border", target)
        self.assertNotIn('border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)', target)

    def test_trainer_spellbook_rank_fallback_and_recipe_scrub(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the trainer learned-state contract")
        harness = r'''
function wipe(t) for key in pairs(t) do t[key] = nil end end
BOOKTYPE_SPELL = "spell"

local spellbook = {
    { "Rend", "Rank 2", 6546 },
    { "Battle Shout", "", 6673 },
}
local ns = {
    Trainer = {},
    API = {
        GetSpellInfo = function(id)
            if id == 772 or id == 6546 or id == 6547 then return "Rend" end
            if id == 6673 then return "Battle Shout" end
            if id == 1752 or id == 1757 or id == 1758 then return "Sinister Strike" end
        end,
        GetNumSpellTabs = function() return 1 end,
        GetSpellTabInfo = function() return "Warrior", nil, 0, #spellbook end,
        GetSpellBookItemName = function(index) return unpack(spellbook[index]) end,
        GetSpellBookItemSpellID = function(index) return spellbook[index][3] end,
        -- Forever can report the entire learned rank family as known. Exact-ID
        -- truth must not override the spellbook's Rank 2 ceiling for Rank 3.
        IsKnownSpellID = function(spellID) return spellID == 6546 or spellID == 6547 end,
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

-- Forever can expose misleading family rank text for a built-in starter
-- ability. The exact spellbook ID is Rank 1 because the trainer catalog starts
-- at Rank 2; Sinister Strike Rank 2 must remain visible while Rank 3 does too.
spellbook = { { "Sinister Strike", "Rank 2", 1752 } }
trainer:PrimeClassSpellRankCatalog({
    [6] = { [1757] = { rank = 2 } },
    [14] = { [1758] = { rank = 3 } },
})
assert(trainer:IsClassSpellKnown(1752, "Sinister Strike", 1, true))
assert(not trainer:IsClassSpellKnown(1757, "Sinister Strike", 2, true))
assert(not trainer:IsClassSpellKnown(1758, "Sinister Strike", 3, true))

-- Once the exact Rank 2 ID occupies the slot, catalog identity wins even if
-- the subtext has not loaded yet.
spellbook = { { "Sinister Strike", "", 1757 } }
trainer:InvalidateKnownSpellbookRanks()
assert(trainer:IsClassSpellKnown(1757, "Sinister Strike", 2, true))
assert(not trainer:IsClassSpellKnown(1758, "Sinister Strike", 3, true))

trainer:ScrubProfessionRecipesFromClassData()
trainer:ScrubClassTrainerTransientStatus()
assert(TurboFaceTrainerDB.data.WARRIOR[0][4094] == nil)
assert(TurboFaceTrainerDB.data.WARRIOR[4][772] ~= nil)
assert(TurboFaceTrainerDB.data.WARRIOR[4][772].status == nil)
assert(TurboFaceTrainerDB.professionCaptureIsolationV1 == true)

spellbook = { { "Rend", "Rank 1", 772 } }
trainer:InvalidateKnownSpellbookRanks()
assert(trainer:IsClassSpellKnown(772, "Rend", 1, true))
assert(not trainer:IsClassSpellKnown(6546, "Rend", 2, true))

spellbook = { { "Rend", "Rank 3", 6547 } }
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

    def test_quest_automation_keeps_repeatables_and_vendor_npcs_manual(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the quest automation contract")
        harness = r'''
local settings = {
    automateGossip = false,
    autoQuestAccept = true,
    autoQuestTurnIn = true,
    automateSpiritHealer = false,
}
local currentQuestID = 9001
local currentDaily = false
local currentWeekly = false
local moneyRequired = 0
local currenciesRequired = 0
local autoAccepted = false
local ns = {
    PlusSettings = function() return settings end,
    API = {
        QuestReadyForTurnIn = function() return false end,
        IsRepeatableQuest = function(questID) return questID == 9001 end,
        GetCurrentQuestID = function() return currentQuestID end,
        IsCurrentQuestDaily = function() return currentDaily end,
        IsCurrentQuestWeekly = function() return currentWeekly end,
        GetQuestMoneyRequired = function() return moneyRequired end,
        GetNumQuestRequiredCurrencies = function() return currenciesRequired end,
        QuestGetAutoAccept = function() return autoAccepted end,
        CanAccessValue = function(value) return value ~= "SECRET" end,
    },
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
Enum = { QuestFrequency = { Default = 0, Daily = 1, Weekly = 2 } }

local vendorVisible = true
local available = {{ questID = 42, title = "Ordinary quest" }}
local active = {}
local selected = 0
C_GossipInfo = {
    GetNumAvailableQuests = function() return #available end,
    GetNumActiveQuests = function() return #active end,
    GetAvailableQuests = function() return available end,
    GetActiveQuests = function() return active end,
    GetOptions = function()
        return vendorVisible and {{ icon = 132060 }} or {}
    end,
    SelectAvailableQuest = function() selected = selected + 1 end,
    SelectActiveQuest = function() selected = selected + 1 end,
}

local accepted, completed, rewarded, closed = 0, 0, 0, 0
function AcceptQuest() accepted = accepted + 1 end
function CloseQuest() closed = closed + 1 end
function IsQuestCompletable() return true end
function CompleteQuest() completed = completed + 1 end
function GetNumQuestChoices() return 0 end
function GetQuestReward() rewarded = rewarded + 1 end

assert(loadfile("src/common/Plus/Automation.lua"))("TurboFace", ns)
ns.PlusAutomation:Init()

local questFrame
for _, frame in ipairs(frames) do
    if frame.events.GOSSIP_SHOW and frame.events.QUEST_DETAIL then questFrame = frame end
end
assert(questFrame, "quest automation event frame was not registered")

-- A vendor-capable NPC must be left at its service menu even when it also
-- exposes a normal quest that the automation could otherwise select.
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(RunDelay(0.10))
assert(selected == 0, "vendor gossip selected a quest before the player could sell")
questFrame.OnEvent(questFrame, "GOSSIP_CLOSED")

-- The direct gossip flag handles available repeatables. The quest-ID adapter
-- catches active repeatables whose legacy-shaped row has no repeatable field.
vendorVisible = false
available = {{ questID = 9001, title = "Blood Shards", repeatable = true }}
active = {}
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(RunDelay(0.10))
assert(selected == 0, "repeatable quest was auto-accepted")
questFrame.OnEvent(questFrame, "GOSSIP_CLOSED")

available = {}
active = {{ questID = 9001, title = "Blood Shards", isComplete = true }}
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(RunDelay(0.10))
assert(selected == 0, "repeatable quest was auto-selected for turn-in")

-- Even a player-opened repeatable detail/progress/reward panel remains manual.
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(CountDelay(0) == 0)
assert(accepted == 0 and completed == 0 and rewarded == 0,
    "repeatable quest panel received an automated action")

-- Daily and weekly rows stay at the gossip list, and their open panels are a
-- second safety boundary when client payloads omit frequency metadata.
questFrame.OnEvent(questFrame, "GOSSIP_CLOSED")
currentQuestID = 42
available = {{ questID = 42, title = "Daily", frequency = 1 }}
active = {}
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(RunDelay(0.10))
assert(selected == 0, "daily quest was auto-selected")
questFrame.OnEvent(questFrame, "GOSSIP_CLOSED")

available = {{ questID = 43, title = "Weekly", frequency = 2 }}
questFrame.OnEvent(questFrame, "GOSSIP_SHOW")
assert(RunDelay(0.10))
assert(selected == 0, "weekly quest was auto-selected")

currentDaily = true
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(CountDelay(0) == 0, "daily quest panel received an automated action")
currentDaily = false
currentWeekly = true
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(CountDelay(0) == 0, "weekly quest panel received an automated action")

-- One-time quests that spend gold or currency remain manual even though they
-- are not repeatable. Ordinary cost-free quests still use both independent
-- accept and turn-in paths.
currentWeekly = false
moneyRequired = 1
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(CountDelay(0) == 0, "gold-cost quest received an automated action")
moneyRequired = 0
currenciesRequired = 1
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(CountDelay(0) == 0, "currency-cost quest received an automated action")

currenciesRequired = 0
autoAccepted = true
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
assert(RunDelay(0))
assert(accepted == 0, "Blizzard auto-accepted quest was accepted twice")
assert(closed == 1, "Blizzard auto-accepted quest panel was left open")
autoAccepted = false
questFrame.OnEvent(questFrame, "QUEST_DETAIL")
assert(RunDelay(0))
questFrame.OnEvent(questFrame, "QUEST_PROGRESS")
assert(RunDelay(0))
questFrame.OnEvent(questFrame, "QUEST_COMPLETE")
assert(RunDelay(0))
assert(accepted == 1 and completed == 1 and rewarded == 1,
    "ordinary one-time quest did not use the split accept and turn-in actions")
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        source = (ROOT / "src" / "common" / "Plus" / "Automation.lua").read_text()
        self.assertIn("local function ReadNPCGUID()", source)
        self.assertNotIn('UnitGUID and UnitGUID("npc") or nil', source)
        self.assertNotIn('"QUEST_AUTOCOMPLETE"', source)

        for flavor in ("classic", "forever"):
            compat = (ROOT / "src" / flavor / "Core" / "Compat.lua").read_text()
            self.assertIn("API.IsCurrentQuestDaily = pick(QuestIsDaily)", compat)
            self.assertIn("API.IsCurrentQuestWeekly = pick(QuestIsWeekly)", compat)
            self.assertIn("API.QuestGetAutoAccept = pick(QuestGetAutoAccept)", compat)
            self.assertIn("API.GetQuestMoneyRequired = pick(GetQuestMoneyToGet)", compat)
            self.assertIn("API.GetNumQuestRequiredCurrencies = pick(GetNumQuestCurrencies)", compat)

    def test_trainer_rank_labels_fall_back_to_catalog_metadata(self) -> None:
        source = (ROOT / "src" / "common" / "Trainer" / "UI_Core.lua").read_text()

        self.assertIn("local function GetEntryRankText(entry)", source)
        self.assertIn('local pattern = type(_G.RANK) == "string" and _G.RANK or "Rank %d"', source)
        self.assertIn('return "Rank " .. rankNum', source)
        self.assertEqual(source.count("local rankSubtext = GetEntryRankText(entry)"), 2)
        self.assertIn('rankFS:SetPoint("BOTTOMLEFT", nameFS, "BOTTOMRIGHT", 4, 1)', source)
        self.assertIn('rankFS:SetPoint("LEFT", nameFS, "RIGHT", -1, 2)', source)

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
assert(not client:IsGateDevelopmentRestricted("class"))
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
assert(not client:IsGateDevelopmentRestricted("class"))
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
assert(modules.class.enabled == true)
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

    def test_rumblecrush_preset_matches_2026_09_29_export(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the preset contract")
        harness = r'''
local ns = { Client = { flavor = "classic" }, DB_VERSION = 79 }
function ns.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[ns.DeepCopy(key, seen)] = ns.DeepCopy(child, seen) end
    return out
end
WOW_PROJECT_ID = 1
function GetBuildInfo() return "1.15.9", "", "", 11509 end
assert(loadfile("src/common/Core/Schema.lua"))("TurboFace", ns)
assert(loadfile("src/common/Core/Defaults.lua"))("TurboFace", ns)
assert(loadfile("src/common/Core/Profiles.lua"))("TurboFace", ns)
local preset = assert(ns.Profiles:GetPreset("Rumblecrush's Preset"))
local data = ns.DeepCopy(ns.defaults)
local function overlay(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then overlay(target[key], value)
        else target[key] = ns.DeepCopy(value) end
    end
end
overlay(data, preset.data)
assert(preset.desc == "2026-09-29")
assert(data.groceryButtonSize == 48)
assert(data.auraTargetBuffScale == 1.3500000238418579)
assert(data.auraTargetDebuffScale == 1.3500000238418579)
assert(data.modules.unitframes.enabled == false)
assert(data.modules.castBars.enabled == false)
assert(data.modules.plus.minimap == true and data.modules.plus.social == false)
assert(data.plus.unclampMinimap == true and data.plus.minimapShape == "round")
assert(data.movers.activeElement == "GroceryButton")
assert(data.movers.gridSize == 20)
assert(data.movers.elements.AlertToasts.x == 0 and data.movers.elements.AlertToasts.y == 220)
assert(data.movers.elements.GroceryButton.x == 555 and data.movers.elements.GroceryButton.y == -573)
assert(data.movers.elements.TargetBuffs.x == 365 and data.movers.elements.TargetBuffs.y == -302)
assert(data.movers.elements.TargetDebuffs.x == 125 and data.movers.elements.TargetDebuffs.y == -260)
assert(data.combinedBag.x == -21.111124038696289 and data.combinedBag.y == -127.38897705078131)
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
            "local buffSnapshotReady = false",
            "return buffSnapshotReady",
            "local playerCastPresent = {}",
            "RecordPlayerBuffCast(spellID)",
            "if present == nil then return false end",
        ):
            self.assertIn(marker, source)

        secret_guard = source.index("if ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret() then")
        snapshot_wipe = source.index("wipe(buffIndexByName)", secret_guard)
        self.assertLess(secret_guard, snapshot_wipe, "secret aura pass must not erase the readable snapshot")

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

    def test_reactive_class_reminders_use_modern_spell_usability(self) -> None:
        class_buffs = (ROOT / "src" / "common" / "Combat" / "ClassBuffs.lua").read_text()
        classic = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text()
        forever = (ROOT / "src" / "forever" / "Core" / "Compat.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()

        for marker in (
            "local IsUsableSpell      = ns.API.IsSpellUsable",
            "local IsSpellOnCooldown  = ns.API.IsSpellOnCooldown",
            "if usable == true or insufficientPower == true then return true end",
            'key = "overpower", label = "Overpower", dbKey = "warriorOverpowerIndicator"',
            "reducedNameplateFallback = true",
            "ns.CombatProviderSupportsReactiveNameplateIndicator() ~= true",
            'key = "counterattack", label = "Counterattack", dbKey = "hunterCounterattackIndicator"',
            "local ReadWeaponEnchantInfo = ns.API.ReadWeaponEnchantInfo",
            "if HAS_WEAPON_ENCHANT then RefreshWeaponSnapshot() end",
        ):
            self.assertIn(marker, class_buffs)
        self.assertNotIn("local IsUsableSpell      = IsUsableSpell", class_buffs)
        self.assertIn("API.IsSpellUsable = pick(IsUsableSpell", classic)
        self.assertIn("function API.IsSpellOnCooldown(spell)", classic)
        self.assertIn("function API.IsSpellUsable(spell)", forever)
        self.assertIn("spells.IsSpellUsable", forever)
        self.assertIn("local active, onGCD = info.isActive, info.isOnGCD", forever)
        self.assertIn("function API.ReadWeaponEnchantInfo()", forever)
        self.assertIn("items.GetWeaponEnchantInfo", forever)
        self.assertNotIn("info.startTime", forever)
        self.assertNotIn("info.duration", forever)
        self.assertIn('"Show Overpower Window", "warriorOverpowerIndicator"', options)
        self.assertIn("local nameplateReactiveIndicator =", options)
        self.assertNotIn('Header(c, y, "Class Text")', options)
        self.assertNotIn('Header(c, y, "Buff Reminders")', options)
        self.assertNotIn('Header(c, y, "Overpower Reminder")', options)
        self.assertNotIn('"Enable missing-buff reminders", "classBuffEnabled"', options)
        self.assertNotIn('ns.Opt("classBuffEnabled"', class_buffs)
        self.assertLess(
            options.index('"Show Overpower Window", "warriorOverpowerIndicator"'),
            options.index('"Show Revenge Window", "classBuffRevenge"'),
        )
        self.assertLess(
            options.index('"Warn Before Expiry (sec)"'),
            options.index('"Show Overpower Window", "warriorOverpowerIndicator"'),
        )
        self.assertLess(
            options.index('"Show Counterattack Window", "hunterCounterattackIndicator"'),
            options.index('"Show Mongoose Bite Window", "classBuffMongooseBite"'),
        )

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
        self.assertIn("local function ComboReservation(st)", source)
        self.assertIn("return math.max(0, COMBO_ROW_HEIGHT + y)", source)
        self.assertIn("local function PositionAnchorGuide(controller, st, hp)", source)
        self.assertIn('guide = CreateFrame("Frame", nil, st.overlay or UIParent)', source)
        self.assertIn('guide:SetPoint("CENTER", centerAnchor, "CENTER", x, y)', source)
        self.assertIn('guide:SetPoint(point, hp, relativePoint, x, y)', source)
        self.assertIn('controller.frame:SetPoint("BOTTOM", guide, "CENTER", 0, 0)', source)
        self.assertIn('controller.frame:SetPoint(point, guide, point, 0, 0)', source)
        self.assertIn("PositionAnchorGuide(controller, st, hp)", source)
        self.assertIn("if controller.anchorGuide then controller.anchorGuide:Hide() end", source)
        self.assertNotIn('controller.frame:SetPoint("BOTTOM", centerAnchor', source)

    def test_forever_minimap_can_reach_the_screen_edge_in_edit_mode(self) -> None:
        defaults = (ROOT / "src" / "common" / "Core" / "Defaults.lua").read_text()
        config = (ROOT / "src" / "common" / "Core" / "Config.lua").read_text()
        client = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()
        interface = (ROOT / "src" / "forever" / "Plus" / "InterfaceTweaks.lua").read_text()

        self.assertIn("unclampMinimap       = false", defaults)
        self.assertIn('unclampMinimap = "minimap"', config)
        self.assertIn('["plus.minimapEdgePlacement"]', client)
        self.assertIn('Override("plus.minimapEdgePlacement", "adapted", true', client)
        self.assertIn('ClientFeatureAvailable("plus.minimapEdgePlacement", false)', options)
        self.assertIn('"Allow minimap art to reach the screen edge"', options)
        self.assertIn("local function ApplyMinimapEdgePlacement()", interface)
        self.assertIn("cluster:SetClampedToScreen(false)", interface)
        self.assertIn('hooksecurefunc, cluster, "AnchorSelectionFrame"', interface)
        self.assertIn('OnAddonReady("Blizzard_EditMode", ApplyMinimapEdgePlacement)', interface)

    def test_minimap_button_drag_matches_libdbicon_coordinate_math(self) -> None:
        source = (ROOT / "src" / "common" / "MinimapButton.lua").read_text()
        self.assertIn("local math_atan2  = math.atan2", source)
        self.assertIn("local scale  = Minimap:GetEffectiveScale()", source)
        self.assertIn("px, py = px / scale, py / scale", source)
        self.assertIn("math_deg(math_atan2(py - my, px - mx)) % 360", source)
        self.assertNotIn("DRAG_SENSITIVITY", source)
        self.assertNotIn("local atan2       = atan2", source)

    def test_forever_recipe_toast_mover_owns_only_the_alert_base_anchor(self) -> None:
        defaults = (ROOT / "src" / "common" / "Core" / "Defaults.lua").read_text()
        client = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text()
        movers = (ROOT / "src" / "common" / "Movers" / "Systems.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()

        self.assertIn("AlertToasts       = { enabled = true", defaults)
        self.assertIn('["movers.alertToasts"]', client)
        self.assertIn('Override("movers.alertToasts", "adapted", true', client)
        self.assertIn('local frame = _G.AlertFrame', movers)
        self.assertIn('self:RegisterElement("AlertToasts", frame', movers)
        self.assertIn('label = "Recipe / Alert Toasts"', movers)
        self.assertNotIn("NewRecipeLearnedAlertSystem.alertFramePool:Acquire", movers)
        self.assertIn('ClientFeatureAvailable("movers.alertToasts", false)', options)
        self.assertIn('{ "Recipe / Alert Toasts", "AlertToasts" }', options)

    def test_grocery_launcher_size_updates_button_border_and_mover(self) -> None:
        defaults = (ROOT / "src" / "common" / "Core" / "Defaults.lua").read_text()
        grocery = (ROOT / "src" / "common" / "Inventory" / "Grocery.lua").read_text()
        options = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text()

        self.assertIn("groceryButtonSize  = 32", defaults)
        self.assertIn('"Grocery Button Icon Size", "groceryButtonSize", 16, 64, 1', options)
        self.assertIn('ns.Opt("groceryButtonSize", 32)', grocery)
        self.assertIn("launcher:SetSize(size, size)", grocery)
        self.assertIn("launcher.border:SetSize(size * (58 / 32), size * (58 / 32))", grocery)
        self.assertIn("overlayWidth = size", grocery)
        self.assertIn("overlayHeight = size", grocery)


if __name__ == "__main__":
    unittest.main()
