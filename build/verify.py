#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PHASE4_SHARED = {
    "Core/Providers.lua",
    "Combat/DPSBadge.lua",
    "Movers/Movers.lua",
    "Movers/Systems.lua",
}

PHASE5_SHARED = {
    "Core/Schema.lua",
    "Core/Defaults.lua",
    "Core/Migrations.lua",
    "Core/Profiles.lua",
}

PHASE6_SHARED = {
    "Nameplates/Provider.lua",
    "Nameplates/Auras.lua",
    "Nameplates/BubbleNameplates.lua",
    "Nameplates/NameplateUnits.lua",
    "Nameplates/NameplateVisuals.lua",
    "Nameplates/NativeNameStyle.lua",
    "Nameplates/Stacking.lua",
}

PHASE7_SHARED = {
    "UnitFrames/Provider.lua",
    "UnitFrames/DruidPowerBar.lua",
    "UnitFrames/Predictions.lua",
    "UnitFrames/nanShield.lua",
}

PHASE8_SHARED = {
    "UnitFrames/UnitFrames.lua",
}

PHASE9_SHARED = {
    "Plus/Provider.lua",
    "Plus/MapTweaks.lua",
    "MinimapTracker.lua",
}

PHASE10_SHARED = {
    "Trainer/Provider.lua",
    "Trainer/UI_Core.lua",
    "Trainer/UI_ClassData.lua",
    "Trainer/UI_ClassList.lua",
    "Trainer/UI_Skills.lua",
}

PHASE11_SHARED = {
    "Trainer/Init.lua",
    "Trainer/TrainerCapture.lua",
    "Trainer/PetMerchantCapture.lua",
}

PHASE12_SHARED = {
    "Trainer/Events.lua",
    "Trainer/TrainerListUI.lua",
    "Trainer/TrainingQueue.lua",
}

PHASE13_SHARED = {
    "Trainer/SkillData.lua",
}

PHASE14_SHARED = {
    "Plus/ChatTweaks.lua",
    "Plus/Social.lua",
    "Plus/FlightBar.lua",
}

PHASE15_SHARED = {
    "Plus/Automation.lua",
    "Plus/SystemTweaks.lua",
}

PHASE16_SHARED = {
    "Combat/Provider.lua",
    "Combat/ClassFeatures.lua",
    "Combat/ClassBuffs.lua",
    "Combat/QueueDiagnostics.lua",
}

PHASE17_SHARED = {
    "Combat/SwingTimerProvider.lua",
    "Combat/SwingTimers.lua",
}

PHASE18_SHARED = {
    "Inventory/InventoryManager.lua",
    "Inventory/Bank.lua",
    "Inventory/NetWorth.lua",
}

PHASE19_SHARED = {
    "Inventory/Grocery.lua",
}

PHASE20_SHARED = {
    "PartyPetAuras.lua",
}

PHASE21_SHARED = {
    "Core/SharedMedia.lua",
}

PHASE22_SHARED = {
    "Options/OptionsGUI.lua",
}

PHASE23_SHARED = {
    "Core/Config.lua",
}

PHASE24_SHARED = {
    "ExperienceBar.lua",
}

PHASE25_SHARED = {
    "AuraStyle.lua",
}

PHASE26_SHARED = {
    "Core.lua",
}

PHASE27_SHARED = {
    "QuickSetup.lua",
}

PHASE28_SHARED = {
    "Power/RegenTicks.lua",
}

PHASE29_SHARED = {
    "Power/PowerCost.lua",
}

PHASE30_SHARED = {
    "Core/Debug.lua",
}

PHASE31_SHARED = {
    "Trainer/UI_Profession.lua",
    "Trainer/UI_Spellbook.lua",
}

# Phase 32 freezes the intentional end-state overlap between client overlays.
# Any new same-path client file must be explicitly classified rather than silently
# becoming a second implementation of a shared subsystem.
END_STATE_CLIENT_OVERLAP = {
    "Core/Compat.lua",
    "Plus/InterfaceTweaks.lua",
    "TurboFace.toc",
    "Libs/LibClassicDurations/core.lua",
    "THIRD_PARTY_NOTICES.md",
}

END_STATE_FIRST_PARTY_DIVERGENCES = {
    "Core/Compat.lua",
    "Plus/InterfaceTweaks.lua",
    "TurboFace.toc",
}


def inventory(root: Path) -> dict[str, str]:
    out = {}
    for path in root.rglob("*"):
        if path.is_file():
            out[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def merged_expected(flavor: str) -> dict[str, str]:
    result = inventory(ROOT / "src" / "common")
    result.update(inventory(ROOT / "src" / flavor))
    return result


def main() -> None:
    classic_toc_source = (ROOT / "src" / "classic" / "TurboFace.toc").read_text(errors="replace")
    forever_toc_source = (ROOT / "src" / "forever" / "TurboFace.toc").read_text(errors="replace")
    if "## Version: 0.18.1" not in classic_toc_source:
        raise SystemExit("Classic version contract changed unexpectedly")
    if "## Version: 0.18.1" not in forever_toc_source:
        raise SystemExit("Forever version contract changed unexpectedly")

    common = set(inventory(ROOT / "src" / "common"))
    missing = PHASE4_SHARED - common
    if missing:
        raise SystemExit(f"phase4 shared files missing from common: {sorted(missing)}")

    for rel in PHASE4_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase4 shared file still client-owned: {rel}")

    missing = PHASE5_SHARED - common
    if missing:
        raise SystemExit(f"phase5 shared files missing from common: {sorted(missing)}")
    for rel in PHASE5_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase5 shared file still client-owned: {rel}")

    missing = PHASE6_SHARED - common
    if missing:
        raise SystemExit(f"phase6 shared files missing from common: {sorted(missing)}")
    for rel in PHASE6_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase6 shared file still client-owned: {rel}")

    missing = PHASE7_SHARED - common
    if missing:
        raise SystemExit(f"phase7 shared files missing from common: {sorted(missing)}")
    for rel in PHASE7_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase7 shared file still client-owned: {rel}")

    missing = PHASE8_SHARED - common
    if missing:
        raise SystemExit(f"phase8 shared files missing from common: {sorted(missing)}")
    for rel in PHASE8_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase8 shared file still client-owned: {rel}")

    missing = PHASE9_SHARED - common
    if missing:
        raise SystemExit(f"phase9 shared files missing from common: {sorted(missing)}")
    for rel in PHASE9_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase9 shared file still client-owned: {rel}")

    missing = PHASE10_SHARED - common
    if missing:
        raise SystemExit(f"phase10 shared files missing from common: {sorted(missing)}")
    for rel in PHASE10_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase10 shared file still client-owned: {rel}")

    missing = PHASE11_SHARED - common
    if missing:
        raise SystemExit(f"phase11 shared files missing from common: {sorted(missing)}")
    for rel in PHASE11_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase11 shared file still client-owned: {rel}")

    missing = PHASE12_SHARED - common
    if missing:
        raise SystemExit(f"phase12 shared files missing from common: {sorted(missing)}")
    for rel in PHASE12_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase12 shared file still client-owned: {rel}")

    missing = PHASE13_SHARED - common
    if missing:
        raise SystemExit(f"phase13 shared files missing from common: {sorted(missing)}")
    for rel in PHASE13_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase13 shared file still client-owned: {rel}")

    missing = PHASE14_SHARED - common
    if missing:
        raise SystemExit(f"phase14 shared files missing from common: {sorted(missing)}")
    for rel in PHASE14_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase14 shared file still client-owned: {rel}")

    chat_tweaks = (ROOT / "src" / "common" / "Plus" / "ChatTweaks.lua").read_text(errors="replace")
    social = (ROOT / "src" / "common" / "Plus" / "Social.lua").read_text(errors="replace")
    flight_bar = (ROOT / "src" / "common" / "Plus" / "FlightBar.lua").read_text(errors="replace")
    if "ns.API.ForEachChatFrame" not in chat_tweaks or "ns.API.RegisterEvent" not in chat_tweaks:
        raise SystemExit("shared ChatTweaks bypasses the compatibility boundary")
    for required in (
        "ns.API.GetBattleNetFriendInviteInfo",
        "ns.API.CanInviteParty",
        "ns.API.InviteUnit",
        "ns.API.InviteBattleNetFriend",
    ):
        if required not in social:
            raise SystemExit(f"shared Social bypasses compatibility helper: {required}")
    if "registeredEvents" not in flight_bar or "ns.API.RegisterEvent" not in flight_bar:
        raise SystemExit("shared FlightBar lost guarded event diagnostics/registration")
    if 'type(hooksecurefunc) ~= "function"' not in flight_bar:
        raise SystemExit("shared FlightBar lost safe hook availability guards")
    for rel in PHASE14_SHARED:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared Phase14 QoL module contains direct Forever branch: {rel}")

    classic_compat = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text(errors="replace")
    for helper in (
        "function API.GetBattleNetFriendInviteInfo(index)",
        "function API.InviteBattleNetFriend(gameAccountID)",
        "function API.CanInviteParty()",
        "function API.InviteUnit(name)",
        "function API.ForEachChatFrame(callback)",
    ):
        if helper not in classic_compat:
            raise SystemExit(f"Classic Compat is missing Phase14 shared QoL helper: {helper}")
    if 'local frame = _G["ChatFrame" .. i]' not in classic_compat:
        raise SystemExit("Classic chat-frame adapter lost the Era ChatFrame1..50 fallback")
    if "BNGetFriendInviteInfo" not in classic_compat or "BNInviteFriend" not in classic_compat:
        raise SystemExit("Classic Battle.net adapter lost legacy invite fallbacks")

    missing = PHASE15_SHARED - common
    if missing:
        raise SystemExit(f"phase15 shared files missing from common: {sorted(missing)}")
    for rel in PHASE15_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase15 shared file still client-owned: {rel}")

    automation = (ROOT / "src" / "common" / "Plus" / "Automation.lua").read_text(errors="replace")
    system_tweaks = (ROOT / "src" / "common" / "Plus" / "SystemTweaks.lua").read_text(errors="replace")
    for required in (
        "ns.API.RegisterEvent",
        "ns.API.QuestReadyForTurnIn",
        "ns.API.ConfirmSpiritHealer",
        "ns.API.ReleaseSpirit",
        "ns.API.GetCoinText",
    ):
        if required not in automation:
            raise SystemExit(f"shared Automation bypasses compatibility helper: {required}")
    if "SelectQuestWithConfirmation" not in automation or "questPendingSerial" not in automation:
        raise SystemExit("shared Automation lost serialized quest-selection confirmation")
    if "PLAYER_DEAD" not in automation or "ns.API.ReleaseSpirit()" not in automation:
        raise SystemExit("shared Automation must use the client action adapter for PvP release")
    if "M:GetFastLootDiagnostics" not in system_tweaks or "IsMasterLoot" not in system_tweaks:
        raise SystemExit("shared SystemTweaks lost hardened fast-loot behavior/diagnostics")
    if "ns.PlusProviderSupportsVendorPriceTooltip" not in system_tweaks:
        raise SystemExit("shared SystemTweaks bypasses provider-owned vendor-tooltip policy")
    for rel in PHASE15_SHARED:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared Phase15 Plus module contains direct Forever branch: {rel}")

    for helper in (
        "function API.ConfirmSpiritHealer()",
        "function API.ReleaseSpirit()",
        "function API.GetCoinText(amount, separator)",
    ):
        if helper not in classic_compat:
            raise SystemExit(f"Classic Compat is missing Phase15 Automation helper: {helper}")

    missing = PHASE16_SHARED - common
    if missing:
        raise SystemExit(f"phase16 shared files missing from common: {sorted(missing)}")
    for rel in PHASE16_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase16 shared file still client-owned: {rel}")

    combat_provider = (ROOT / "src" / "common" / "Combat" / "Provider.lua").read_text(errors="replace")
    class_features = (ROOT / "src" / "common" / "Combat" / "ClassFeatures.lua").read_text(errors="replace")
    class_buffs = (ROOT / "src" / "common" / "Combat" / "ClassBuffs.lua").read_text(errors="replace")
    queue_diag = (ROOT / "src" / "common" / "Combat" / "QueueDiagnostics.lua").read_text(errors="replace")
    forever_combat = (ROOT / "src" / "forever" / "Combat" / "ForeverNativeAdapter.lua").read_text(errors="replace")
    forever_compatibility = (ROOT / "src" / "forever" / "Core" / "Compatibility.lua").read_text(errors="replace")

    if 'Register("combatUI", "classic-readable", Classic, 10)' not in combat_provider:
        raise SystemExit("Classic combat presentation provider registration missing")
    if 'Register("combatUI", "forever-secret-safe", Forever, 100)' not in forever_combat:
        raise SystemExit("Forever combat presentation provider registration missing")
    if "ns.CombatProviderSupportsReactiveNameplateIndicator" not in class_features:
        raise SystemExit("shared ClassFeatures bypasses combat-presentation ownership")
    if "ns.CombatProviderUsesClassBuffTalentReminder" not in class_buffs:
        raise SystemExit("shared ClassBuffs bypasses talent-reminder ownership")
    if "if USES_TALENT_REMINDER then" not in class_buffs or 'frame:RegisterEvent("CHARACTER_POINTS_CHANGED")' not in class_buffs:
        raise SystemExit("shared ClassBuffs lost capability-gated talent-point event ownership")
    for required in (
        "ns.API.SafeToString",
        'ns.API.ReadUnitPower("player", 1)',
        'ns.API.ReadUnitName("target")',
        'ns.API.ReadUnitGUID("target")',
    ):
        if required not in queue_diag:
            raise SystemExit(f"shared QueueDiagnostics bypasses secret-safe Compat path: {required}")
    for rel in PHASE16_SHARED:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared Phase16 Combat module contains direct Forever branch: {rel}")
    if "function API.SafeToString(value, fallback)" not in classic_compat:
        raise SystemExit("Classic Compat is missing Phase16 SafeToString helper")
    if 'GetName("combatUI")' not in forever_compatibility:
        raise SystemExit("Forever compatibility diagnostics omit the Phase16 combatUI provider")

    trainer_init = (ROOT / "src" / "common" / "Trainer" / "Init.lua").read_text(errors="replace")
    trainer_capture = (ROOT / "src" / "common" / "Trainer" / "TrainerCapture.lua").read_text(errors="replace")
    pet_capture = (ROOT / "src" / "common" / "Trainer" / "PetMerchantCapture.lua").read_text(errors="replace")
    if "function Trainer:GetTrainerServiceInfoCompat(index)" not in trainer_init:
        raise SystemExit("shared Trainer init is missing service-return normalization")
    if "C_TooltipInfo.GetTrainerService" not in trainer_init or "ResolveClassTrainerServiceSpellID" not in trainer_init:
        raise SystemExit("shared Trainer init is missing guarded modern spell-service resolution")
    if "Trainer:GetTrainerServiceInfoCompat(i)" not in trainer_capture:
        raise SystemExit("shared Trainer capture bypasses the service normalization boundary")
    if "TooltipDataProcessor.AddTooltipPostCall" not in pet_capture or "ns.API.ReadUnitHealth" not in pet_capture:
        raise SystemExit("shared pet merchant capture is missing modern-tooltip/readable-health fallbacks")

    trainer_events = (ROOT / "src" / "common" / "Trainer" / "Events.lua").read_text(errors="replace")
    trainer_list = (ROOT / "src" / "common" / "Trainer" / "TrainerListUI.lua").read_text(errors="replace")
    trainer_queue = (ROOT / "src" / "common" / "Trainer" / "TrainingQueue.lua").read_text(errors="replace")
    trainer_skill_data = (ROOT / "src" / "common" / "Trainer" / "SkillData.lua").read_text(errors="replace")
    if "RegisterOptionalEvent(frame, \"TRAINER_CLOSED\")" not in trainer_events:
        raise SystemExit("shared Trainer events do not capability-gate trainer-close registration")
    if "RegisterOptionalEvent(frame, \"SPELL_DATA_LOAD_RESULT\")" not in trainer_events:
        raise SystemExit("shared Trainer events do not capability-gate spell-data registration")
    if "HasLegacyTrainerListSurface" not in trainer_list or "if not trainerUpdateOverrideInstalled then return end" not in trainer_list:
        raise SystemExit("shared Trainer list renderer does not fail closed on native trainer surfaces")
    if "Trainer:GetTrainerServiceInfoCompat(i)" not in trainer_queue:
        raise SystemExit("shared TrainingQueue bypasses the trainer-service compatibility boundary")
    if "return record.spellID == serviceSpellID" not in trainer_queue:
        raise SystemExit("shared TrainingQueue lost authoritative numeric spell matching")
    if "ns.API and ns.API.IsKnownSpellID" not in trainer_queue:
        raise SystemExit("shared TrainingQueue bypasses the cross-client known-spell adapter")
    if "IS_TARGET_FOREVER_BUILD" in trainer_skill_data:
        raise SystemExit("shared SkillData regressed a direct Forever build check")
    if "TrainerProviderUsesDetailedWeaponMasterSources" not in trainer_skill_data:
        raise SystemExit("shared SkillData is missing provider-owned weapon-master source policy")
    if "TrainerProviderUsesOpenProfessionSkillFallback" not in trainer_skill_data:
        raise SystemExit("shared SkillData is missing provider-owned modern profession-rank fallback")
    if "target.requirementText = captured.requires" not in trainer_skill_data:
        raise SystemExit("shared SkillData must keep human requirement text separate from prerequisite spell IDs")

    forever_schema = ROOT / "src" / "forever" / "Core" / "ForeverSchema.lua"
    if not forever_schema.is_file():
        raise SystemExit("Forever client schema extension missing")
    if (ROOT / "src" / "classic" / "Core" / "ForeverSchema.lua").exists():
        raise SystemExit("Classic must not ship the Forever schema extension")

    retired_forever_workaround = (
        "src/forever/Core/ForeverRestoreData.lua",
        "src/forever/Core/ForeverDevPreset.lua",
        "src/forever/Save-TurboFaceForever.bat",
        "src/forever/Save-TurboFaceForever.sh",
        "src/forever/Tools/Save-ForeverVariables.ps1",
        "docs/forever/FOREVER_SAVEDVARIABLES_WORKAROUND.md",
    )
    for rel in retired_forever_workaround:
        if (ROOT / rel).exists():
            raise SystemExit(f"retired Forever SavedVariables workaround returned: {rel}")

    retired_runtime_markers = (
        "ForeverDevPreset",
        "ForeverRestoreData",
        "TurboFaceForeverRestoreMeta",
    )
    for rel in ("src/common/Core.lua", "src/common/Core/Debug.lua", "src/forever/TurboFace.toc"):
        text = (ROOT / rel).read_text(errors="replace")
        for marker in retired_runtime_markers:
            if marker in text:
                raise SystemExit(f"retired Forever restore marker remains in {rel}: {marker}")

    # Shared policy must not regress into direct Forever build checks. Client
    # ownership is expressed through Core/Client.lua and provider registration.
    for rel in ("Combat/CombatMeter.lua", "Combat/DPSBadge.lua", "Movers/Movers.lua", "Movers/Systems.lua"):
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared provider consumer contains direct Forever branch: {rel}")

    missing = PHASE17_SHARED - common
    if missing:
        raise SystemExit(f"phase17 shared files missing from common: {sorted(missing)}")
    for rel in PHASE17_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase17 shared file still client-owned: {rel}")

    missing = PHASE18_SHARED - common
    if missing:
        raise SystemExit(f"phase18 shared files missing from common: {sorted(missing)}")
    for rel in PHASE18_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase18 shared file still client-owned: {rel}")

    missing = PHASE19_SHARED - common
    if missing:
        raise SystemExit(f"phase19 shared files missing from common: {sorted(missing)}")
    for rel in PHASE19_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase19 shared file still client-owned: {rel}")

    missing = PHASE20_SHARED - common
    if missing:
        raise SystemExit(f"phase20 shared files missing from common: {sorted(missing)}")
    for rel in PHASE20_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase20 shared file still client-owned: {rel}")

    missing = PHASE21_SHARED - common
    if missing:
        raise SystemExit(f"phase21 shared files missing from common: {sorted(missing)}")
    for rel in PHASE21_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase21 shared file still client-owned: {rel}")

    missing = PHASE22_SHARED - common
    if missing:
        raise SystemExit(f"phase22 shared files missing from common: {sorted(missing)}")
    for rel in PHASE22_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase22 shared file still client-owned: {rel}")

    missing = PHASE23_SHARED - common
    if missing:
        raise SystemExit(f"phase23 shared files missing from common: {sorted(missing)}")
    for rel in PHASE23_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase23 shared file still client-owned: {rel}")

    missing = PHASE24_SHARED - common
    if missing:
        raise SystemExit(f"phase24 shared files missing from common: {sorted(missing)}")
    for rel in PHASE24_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase24 shared file still client-owned: {rel}")

    missing = PHASE25_SHARED - common
    if missing:
        raise SystemExit(f"phase25 shared files missing from common: {sorted(missing)}")
    for rel in PHASE25_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase25 shared file still client-owned: {rel}")

    missing = PHASE26_SHARED - common
    if missing:
        raise SystemExit(f"phase26 shared files missing from common: {sorted(missing)}")
    for rel in PHASE26_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase26 shared file still client-owned: {rel}")
    core_source = (ROOT / "src" / "common" / "Core.lua").read_text(errors="replace")
    if "IS_TARGET_FOREVER_BUILD" in core_source:
        raise SystemExit("phase26 shared Core.lua contains a direct Forever identity branch")
    if 'CorePolicy("detachedNameplateAdapter")' not in core_source:
        raise SystemExit("phase26 shared Core.lua missing client-owned nameplate lifecycle policy")

    missing = PHASE27_SHARED - common
    if missing:
        raise SystemExit(f"phase27 shared files missing from common: {sorted(missing)}")
    for rel in PHASE27_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase27 shared file still client-owned: {rel}")
    quicksetup_source = (ROOT / "src" / "common" / "QuickSetup.lua").read_text(errors="replace")
    if "IS_TARGET_FOREVER_BUILD" in quicksetup_source or ":IsForever()" in quicksetup_source:
        raise SystemExit("phase27 shared QuickSetup.lua contains a direct Forever identity branch")
    for required in ('QuickPolicy("externalPersistence")', 'QuickPolicy("macroScopeBySnapshot")', 'QuickPolicy("preserveUnsupportedActions")'):
        if required not in quicksetup_source:
            raise SystemExit(f"phase27 shared QuickSetup missing client policy contract: {required}")

    missing = PHASE28_SHARED - common
    if missing:
        raise SystemExit(f"phase28 shared files missing from common: {sorted(missing)}")
    for rel in PHASE28_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase28 shared file still client-owned: {rel}")
    regen_source = (ROOT / "src" / "common" / "Power" / "RegenTicks.lua").read_text(errors="replace")
    for required in ("AccessibleNumber", "ObserveSecretHealthEvent", "rageSecretFallbackActive", "MarkerGeometry"):
        if required not in regen_source:
            raise SystemExit(f"phase28 shared RegenTicks missing secret-resource compatibility contract: {required}")
    if "IS_TARGET_FOREVER_BUILD" in regen_source or ":IsForever()" in regen_source:
        raise SystemExit("phase28 shared RegenTicks contains a direct Forever identity branch")

    missing = PHASE29_SHARED - common
    if missing:
        raise SystemExit(f"phase29 shared files missing from common: {sorted(missing)}")
    for rel in PHASE29_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase29 shared file still client-owned: {rel}")
    powercost_source = (ROOT / "src" / "common" / "Power" / "PowerCost.lua").read_text(errors="replace")
    for required in ("overlayByButton", "GetActionSpell", "RenderSecretPower", "GetUnitPowerPercentOpaque", "ReadUnitPower"):
        if required not in powercost_source:
            raise SystemExit(f"phase29 shared PowerCost missing normalized action/secret-resource contract: {required}")
    if "IS_TARGET_FOREVER_BUILD" in powercost_source or ":IsForever()" in powercost_source:
        raise SystemExit("phase29 shared PowerCost contains a direct Forever identity branch")

    missing = PHASE30_SHARED - common
    if missing:
        raise SystemExit(f"phase30 shared files missing from common: {sorted(missing)}")
    for rel in PHASE30_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase30 shared file still client-owned: {rel}")
    debug_source = (ROOT / "src" / "common" / "Core" / "Debug.lua").read_text(errors="replace")
    for required in ("TrainerStyleProbe", "ProfessionProbe", "NameplateAPIProbe", "GetFastLootDiagnostics", "GetDebugState"):
        if required not in debug_source:
            raise SystemExit(f"phase30 shared Debug missing cross-client diagnostic contract: {required}")

    missing = PHASE31_SHARED - common
    if missing:
        raise SystemExit(f"phase31 shared files missing from common: {sorted(missing)}")
    for rel in PHASE31_SHARED:
        for flavor in ("classic", "forever"):
            if (ROOT / "src" / flavor / rel).exists():
                raise SystemExit(f"{flavor}: phase31 shared Trainer host still client-owned: {rel}")

    # Phase 32 end-state guard: the two client overlays may overlap only at the
    # deliberately classified architectural boundaries. This catches future
    # copy/paste forks even when build output would otherwise look valid.
    classic_overlay = inventory(ROOT / "src" / "classic")
    forever_overlay = inventory(ROOT / "src" / "forever")
    client_overlap = set(classic_overlay) & set(forever_overlay)
    if client_overlap != END_STATE_CLIENT_OVERLAP:
        added = sorted(client_overlap - END_STATE_CLIENT_OVERLAP)
        missing_overlap = sorted(END_STATE_CLIENT_OVERLAP - client_overlap)
        raise SystemExit(
            f"client overlay ownership drift: unexpected={added}, missing={missing_overlap}"
        )
    divergent_overlap = {rel for rel in client_overlap if classic_overlay[rel] != forever_overlay[rel]}
    if divergent_overlap != END_STATE_CLIENT_OVERLAP:
        raise SystemExit(
            f"client overlap unexpectedly became identical or changed classification: {sorted(divergent_overlap)}"
        )
    first_party_divergences = {
        rel for rel in divergent_overlap
        if not rel.startswith("Libs/") and rel != "THIRD_PARTY_NOTICES.md"
    }
    # Repository-hardening contracts. Direct client identity is allowed only in
    # the small policy/provider/diagnostic boundary that already owns flavor selection.
    identity_allowlist = {
        "Core/Client.lua",
        "Core/Debug.lua",
        "Nameplates/Provider.lua",
        "UnitFrames/Provider.lua",
        "Plus/Provider.lua",
        "Combat/Provider.lua",
        "Combat/SwingTimerProvider.lua",
        "Trainer/Provider.lua",
    }
    identity_patterns = ("IS_TARGET_FOREVER_BUILD", "ClientIsForever", ":IsForever()")
    identity_users = set()
    for path in (ROOT / "src" / "common").rglob("*.lua"):
        text = path.read_text(errors="replace")
        if any(pattern in text for pattern in identity_patterns):
            identity_users.add(path.relative_to(ROOT / "src" / "common").as_posix())
    unexpected_identity = identity_users - identity_allowlist
    if unexpected_identity:
        raise SystemExit(f"direct client-identity branch escaped policy/provider boundary: {sorted(unexpected_identity)}")
    if identity_users != identity_allowlist:
        raise SystemExit(f"client-identity allowlist drifted; review boundary explicitly: {sorted(identity_users)}")

    # Canonical docs live under docs/. Historical packaged copies/manifests were removed in
    # Phase 33 so they cannot silently drift from the repository source of truth.
    forbidden_forever_duplicates = {
        "ARCHITECTURE.md", "CHANGELOG.md", "FOREVER_SAVEDVARIABLES_WORKAROUND.md",
        "MULTICLIENT_STRATEGY.md", "PORT_STATUS.md",
    }
    present_duplicates = sorted(name for name in forbidden_forever_duplicates if (ROOT / "src" / "forever" / name).exists())
    if present_duplicates or (ROOT / "src" / "forever" / "build").exists():
        raise SystemExit(f"stale packaged documentation/manifest state returned: {present_duplicates}")

    phase_reports = sorted(path.name for path in ROOT.glob("PHASE*_REPORT.md"))
    if phase_reports:
        raise SystemExit(f"internal phase reports returned to the public repository root: {phase_reports}")
    if (ROOT / "docs" / "forever" / "PORT_STATUS.md").exists():
        raise SystemExit("retired Forever port-status diary returned to canonical documentation")
    readme = (ROOT / "README.md").read_text(errors="replace")
    if "PHASE33_REPORT.md" in readme or "Phase 33)" in readme:
        raise SystemExit("README regressed to an internal phase-report landing page")
    release_workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(errors="replace")
    if not re.search(r'^\s+-\s+["\x27]v\*["\x27]\s*$', release_workflow, re.MULTILINE):
        raise SystemExit("release workflow must trigger on v* tags")

    source_map = (ROOT / "docs" / "SOURCE_MAP.md").read_text(errors="replace")
    strategy = (ROOT / "docs" / "MULTICLIENT_STRATEGY.md").read_text(errors="replace")
    for marker in (
        "**Forever:** 0.18.1 / Interface 16001",
        "| Byte-identical same-path files | 176 |",
        "| Same-path but different contents | 5 |",
        "| Forever-only paths | 13 |",
        "The union is 195 relative paths.",
        "| Byte-identical | 107 |",
    ):
        if marker not in source_map:
            raise SystemExit(f"SOURCE_MAP current-state marker missing: {marker}")
    if "Legacy snapshot manifests were removed" not in strategy:
        raise SystemExit("MULTICLIENT_STRATEGY still relies on stale legacy manifest state")
    forever_architecture = (ROOT / "docs" / "forever" / "ARCHITECTURE.md").read_text(errors="replace")
    for stale_manifest in ("build/common.list", "build/adapted.list", "build/compare_clients.py"):
        if stale_manifest in forever_architecture:
            raise SystemExit(f"Forever architecture still references removed manifest tooling: {stale_manifest}")

    # Local Markdown links in the public README and canonical docs must resolve.
    public_docs = [ROOT / "README.md", *(ROOT / "docs").rglob("*.md")]
    for doc in public_docs:
        text = doc.read_text(errors="replace")
        for match in re.finditer(r"\[[^]]+\]\(([^)]+)\)", text):
            target = match.group(1).split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            if not (doc.parent / target).resolve().exists():
                raise SystemExit(f"broken canonical Markdown link: {doc.relative_to(ROOT)} -> {target}")

    # Freeze the package-level end state independently of documentation prose.
    classic_package = merged_expected("classic")
    forever_package = merged_expected("forever")
    same_package_paths = set(classic_package) & set(forever_package)
    identical_package_paths = {rel for rel in same_package_paths if classic_package[rel] == forever_package[rel]}
    if (len(classic_package), len(forever_package), len(same_package_paths), len(identical_package_paths)) != (182, 194, 181, 176):
        raise SystemExit(
            "package inventory contract drifted: "
            f"classic={len(classic_package)} forever={len(forever_package)} "
            f"same={len(same_package_paths)} identical={len(identical_package_paths)}"
        )
    if first_party_divergences != END_STATE_FIRST_PARTY_DIVERGENCES:
        raise SystemExit(
            f"first-party divergence contract drifted: {sorted(first_party_divergences)}"
        )

    interface_classic = (ROOT / "src" / "classic" / "Plus" / "InterfaceTweaks.lua").read_text(errors="replace")
    interface_forever = (ROOT / "src" / "forever" / "Plus" / "InterfaceTweaks.lua").read_text(errors="replace")
    if "Quest list level/difficulty prefix" not in interface_classic:
        raise SystemExit("Classic InterfaceTweaks lost legacy quest-level ownership marker")
    for marker in ("Movable Blizzard combined bag", "ModernDifficultySuffix", "InstallCombinedBagDrag"):
        if marker not in interface_forever:
            raise SystemExit(f"Forever InterfaceTweaks lost native-UI ownership marker: {marker}")

    aura_style = (ROOT / "src" / "common" / "AuraStyle.lua").read_text(errors="replace")
    for required in ("AuraDataReadable", "SuspendButtonOverlay", "GetReadableAuraDataByIndex", "GetReadableAuraDataByAuraInstanceID"):
        if required not in aura_style:
            raise SystemExit(f"shared AuraStyle missing protected-aura contract: {required}")
    if "IS_TARGET_FOREVER_BUILD" in aura_style or ":IsForever()" in aura_style:
        raise SystemExit("shared AuraStyle contains a direct Forever build branch")
    for flavor in ("classic", "forever"):
        compat = (ROOT / "src" / flavor / "Core" / "Compat.lua").read_text(errors="replace")
        for required in ("ShouldAurasBeSecret", "GetReadableAuraDataByIndex", "GetReadableAuraDataByAuraInstanceID"):
            if required not in compat:
                raise SystemExit(f"{flavor}: Compat missing shared AuraStyle contract: {required}")

    experience = (ROOT / "src" / "common" / "ExperienceBar.lua").read_text(errors="replace")
    for required in ("modernQuestRewardAPI", "HaveQuestRewardData", "EnsureQuestLogHideHooks", "QUEST_DATA_LOAD_RESULT"):
        if required not in experience:
            raise SystemExit(f"shared ExperienceBar missing quest-reward compatibility contract: {required}")
    if "IS_TARGET_FOREVER_BUILD" in experience or ":IsForever()" in experience:
        raise SystemExit("shared ExperienceBar contains a direct Forever build branch")

    client_policy = (ROOT / "src" / "common" / "Core" / "Client.lua").read_text(errors="replace")
    config = (ROOT / "src" / "common" / "Core" / "Config.lua").read_text(errors="replace")
    for required in ("ApplyCVarBaseline", "ns.CLEU.Available", "FeatureAvailable", "requireDetachedNameplateAdapter"):
        if required not in config and required != "requireDetachedNameplateAdapter":
            raise SystemExit(f"shared Config missing hardened contract: {required}")
    if "requireDetachedNameplateAdapter" not in config or "requireDetachedNameplateAdapter" not in client_policy:
        raise SystemExit("shared Config/client policy missing detached-nameplate safety policy")
    if "IS_TARGET_FOREVER_BUILD" in config or ":IsForever()" in config:
        raise SystemExit("shared Config contains a direct Forever build branch")
    options_gui = (ROOT / "src" / "common" / "Options" / "OptionsGUI.lua").read_text(errors="replace")
    if "ClientFeatureAvailable" not in options_gui or "ClientOptionPolicy" not in options_gui:
        raise SystemExit("shared OptionsGUI bypasses client feature/options policy")
    if "IS_TARGET_FOREVER_BUILD" in options_gui or "ClientIsForever" in options_gui:
        raise SystemExit("shared OptionsGUI contains a direct Forever build branch")
    for policy in ("hud.spendTalentPoint", "plus.questLevels", "plus.combinedBagMovable", "plus.vendorPrice"):
        if policy not in options_gui or policy not in client_policy:
            raise SystemExit(f"OptionsGUI/client policy missing capability: {policy}")

    shared_media = (ROOT / "src" / "common" / "Core" / "SharedMedia.lua").read_text(errors="replace")
    if 'GetAsset("bankIconTexture"' not in shared_media:
        raise SystemExit("shared SharedMedia bypasses client asset policy")
    if "IS_TARGET_FOREVER_BUILD" in shared_media or "IsForever" in shared_media:
        raise SystemExit("shared SharedMedia contains a direct Forever build branch")
    for asset in ("BankIcon.tga", "Tracking\\\\Banker"):
        if asset not in client_policy:
            raise SystemExit(f"client asset policy missing banker artwork: {asset}")

    party_pet_auras = (ROOT / "src" / "common" / "PartyPetAuras.lua").read_text(errors="replace")
    if "ShouldAurasBeSecret" not in party_pet_auras or "AuraDataReadable" not in party_pet_auras:
        raise SystemExit("shared PartyPetAuras lost secret-aura fail-closed boundary")
    if 'ns.RegisterEvent(EnsureDeferredAuraFrame(), "PLAYER_REGEN_ENABLED")' not in party_pet_auras:
        raise SystemExit("shared PartyPetAuras bypasses guarded event registration")
    if "RestorePartyNativeAuraAlpha" not in party_pet_auras:
        raise SystemExit("shared PartyPetAuras lost native-aura restoration path")
    if "IS_TARGET_FOREVER_BUILD" in party_pet_auras or "IsForever" in party_pet_auras:
        raise SystemExit("shared PartyPetAuras contains a direct Forever build branch")

    grocery = (ROOT / "src" / "common" / "Inventory" / "Grocery.lua").read_text(errors="replace")
    for required in (
        "ns.API.GetMerchantNumItems",
        "ns.API.GetMerchantItemInfo",
        "ns.API.GetMerchantItemLink",
        "ns.API.GetMerchantItemID",
        "ns.API.GetMerchantItemMaxStack",
        "ns.API.GetMerchantItemCostInfo",
        "ns.API.BuyMerchantItem",
        "ns.API.GetItemCount",
        "ns.API.GetCoinTextureString",
        "ns.API.MerchantSurfaceAvailable",
    ):
        if required not in grocery:
            raise SystemExit(f"shared Grocery bypasses compatibility helper: {required}")
    if 'CreateFrame("Button", name, parent)' not in grocery or '"ItemButtonTemplate"' in grocery:
        raise SystemExit("shared Grocery must use the owned template-free item cell")
    if "merchantSessionOpen" not in grocery or "reason == \"notpurchasable\"" not in grocery:
        raise SystemExit("shared Grocery lost hardened merchant-session/purchasability handling")
    if "IS_TARGET_FOREVER_BUILD" in grocery:
        raise SystemExit("shared Grocery contains a direct Forever build branch")

    for helper in (
        "API.GetItemCount =",
        "API.GetMerchantNumItems =",
        "API.GetMerchantItemInfo =",
        "function API.MerchantSurfaceAvailable()",
        "function API.GetCoinTextureString(amount, fontHeight)",
    ):
        if helper not in classic_compat:
            raise SystemExit(f"Classic Compat is missing Phase19 Grocery helper: {helper}")

    inventory_manager = (ROOT / "src" / "common" / "Inventory" / "InventoryManager.lua").read_text(errors="replace")
    bank = (ROOT / "src" / "common" / "Inventory" / "Bank.lua").read_text(errors="replace")
    net_worth = (ROOT / "src" / "common" / "Inventory" / "NetWorth.lua").read_text(errors="replace")
    if "ns.API.SetCoinIcon" not in inventory_manager or "ns.API.FormatMoney" not in inventory_manager:
        raise SystemExit("shared InventoryManager bypasses the inventory money/icon compatibility boundary")
    if "ContainerFrameItemButtonMixin" not in inventory_manager or "ContainerFrameCombinedBags" not in inventory_manager:
        raise SystemExit("shared InventoryManager lost guarded modern pooled-container support")
    for classic_fallback in (
        'local name = frame:GetName()',
        '_G[name .. "Item" .. i]',
        'hooksecurefunc("ContainerFrame_Update"',
    ):
        if classic_fallback not in inventory_manager:
            raise SystemExit(f"shared InventoryManager lost Classic container fallback: {classic_fallback}")
    if "ForEachModernCharacterBankSlot" not in bank or "BankPanelItemButtonMixin" not in bank:
        raise SystemExit("shared Bank lost guarded modern character-bank support")
    for classic_fallback in (
        "GetContainerNumSlots(BANK_CONTAINER)",
        "FIRST_BANK_BAG, FIRST_BANK_BAG + NUM_BANK_BAGS - 1",
        '_G["BankFrameItem" .. i]',
    ):
        if classic_fallback not in bank:
            raise SystemExit(f"shared Bank lost Classic bank fallback: {classic_fallback}")
    if "ns.API.SetCoinIcon" not in net_worth:
        raise SystemExit("shared NetWorth bypasses the coin-icon compatibility boundary")
    for rel in PHASE18_SHARED:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared Phase18 inventory module contains direct Forever branch: {rel}")

    classic_compat = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text(errors="replace")
    if "function API.SetCoinIcon(texture, denomination)" not in classic_compat:
        raise SystemExit("Classic Compat is missing the shared inventory coin-icon helper")
    for texture in (
        "Interface\\\\MoneyFrame\\\\UI-GoldIcon",
        "Interface\\\\MoneyFrame\\\\UI-SilverIcon",
        "Interface\\\\MoneyFrame\\\\UI-CopperIcon",
    ):
        if texture not in classic_compat:
            raise SystemExit(f"Classic Compat lost legacy coin texture fallback: {texture}")

    swing_provider = (ROOT / "src" / "common" / "Combat" / "SwingTimerProvider.lua").read_text(errors="replace")
    swing_timers = (ROOT / "src" / "common" / "Combat" / "SwingTimers.lua").read_text(errors="replace")
    forever_swing = (ROOT / "src" / "forever" / "Combat" / "ForeverSwingTimerAdapter.lua").read_text(errors="replace")
    if 'Providers:Register("swingTimers", "classic-cleu", Classic, 10)' not in swing_provider:
        raise SystemExit("Classic Swing Timer provider registration missing")
    if 'ns.Providers:Register("swingTimers", "forever-player-swing", Forever, 100)' not in forever_swing:
        raise SystemExit("Forever Swing Timer provider registration missing")
    for contract in (
        "function ns.SwingTimerProviderUsesPlayerSwingEvent",
        "function ns.SwingTimerProviderCanReadTargetAttackSpeed",
        "function ns.SwingTimerProviderCanReadNameplateAttackSpeed",
        "function ns.SwingTimerProviderUsesThreatSituationEngagement",
        "function ns.SwingTimerProviderUsesCharacterDamageCapture",
    ):
        if contract not in swing_provider:
            raise SystemExit(f"shared Swing Timer capability contract missing: {contract}")
    if "IS_TARGET_FOREVER_BUILD" in swing_timers or "IS_FOREVER" in swing_timers:
        raise SystemExit("shared SwingTimers regressed direct client-build branching")
    for required in (
        "ns.SwingTimerProviderUsesPlayerSwingEvent()",
        "ns.SwingTimerProviderCanReadTargetAttackSpeed()",
        "ns.SwingTimerProviderCanReadNameplateAttackSpeed()",
        "ns.SwingTimerProviderUsesThreatSituationEngagement()",
        "ns.SwingTimerProviderInstallCharacterDamageCapture(ST, eventFrame)",
        "swingEventHandlers.PLAYER_SWING",
    ):
        if required not in swing_timers:
            raise SystemExit(f"shared SwingTimers lost Phase17 runtime seam: {required}")
    for required in (
        "function Forever:Attach(ST)",
        "function ST:CapturePaperDollDamageText",
        "function ST:ScanCharacterStatsDamage",
        "function ST:ScanCharacterFrameDamage",
        "function Forever:InstallCharacterDamageCapture",
    ):
        if required not in forever_swing:
            raise SystemExit(f"Forever Swing Timer adapter lost Character damage capture: {required}")
    if "function API.IsSecretValue(_)" not in classic_compat:
        raise SystemExit("Classic Compat missing readable secret-value stub for shared SwingTimers")
    if "function API.CanAccessValue(_)" not in classic_compat or "function API.IsReadableNumber(value)" not in classic_compat:
        raise SystemExit("Classic Compat missing shared SwingTimers value-access helpers")

    for rel in PHASE6_SHARED - {"Nameplates/Provider.lua"}:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text or "ForeverNameplates" in text:
            raise SystemExit(f"shared nameplate consumer contains direct Forever branch: {rel}")

    for rel in PHASE7_SHARED - {"UnitFrames/Provider.lua"}:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared UnitFrame consumer contains direct Forever branch: {rel}")

    unitframes_core = (ROOT / "src" / "common" / "UnitFrames" / "UnitFrames.lua").read_text(errors="replace")
    if "IS_TARGET_FOREVER_BUILD" in unitframes_core or "ResolveModernUnitFrameObjects" in unitframes_core:
        raise SystemExit("shared UnitFrames core regressed client-specific modern-frame logic")

    map_tweaks = (ROOT / "src" / "common" / "Plus" / "MapTweaks.lua").read_text(errors="replace")
    if "IS_TARGET_FOREVER_BUILD" in map_tweaks or "FOREVER_NATIVE_MAPCANVAS" in map_tweaks:
        raise SystemExit("shared MapTweaks regressed direct Forever ownership checks")
    minimap_tracker = (ROOT / "src" / "common" / "MinimapTracker.lua").read_text(errors="replace")
    if "IS_TARGET_FOREVER_BUILD" in minimap_tracker:
        raise SystemExit("shared MinimapTracker regressed direct Forever ownership checks")

    for rel in PHASE10_SHARED - {"Trainer/Provider.lua"}:
        text = (ROOT / "src" / "common" / rel).read_text(errors="replace")
        if "IS_TARGET_FOREVER_BUILD" in text:
            raise SystemExit(f"shared Trainer UI consumer contains direct Forever branch: {rel}")

    for flavor in ("classic", "forever"):
        overlap = common & set(inventory(ROOT / "src" / flavor))
        if overlap:
            raise SystemExit(f"{flavor}: common/client overlap: {sorted(overlap)[:5]}")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "addon"
            subprocess.run([
                "python3", str(ROOT / "build" / "build_client.py"), flavor, "--out", str(out)
            ], check=True)
            if inventory(out) != merged_expected(flavor):
                raise SystemExit(f"{flavor}: generated tree does not match source overlays")

            toc = (out / "TurboFace.toc").read_text(errors="replace")
            client_pos = toc.find("Core\\Client.lua")
            providers_pos = toc.find("Core\\Providers.lua")
            schema_pos = toc.find("Core\\Schema.lua")
            config_pos = toc.find("Core\\Config.lua")
            defaults_pos = toc.find("Core\\Defaults.lua")
            migrations_pos = toc.find("Core\\Migrations.lua")
            profiles_pos = toc.find("Core\\Profiles.lua")
            if min(client_pos, providers_pos, schema_pos, config_pos, defaults_pos, migrations_pos, profiles_pos) < 0:
                raise SystemExit(f"{flavor}: shared core schema files missing from TOC")
            if not (client_pos < providers_pos < schema_pos < config_pos < defaults_pos < migrations_pos < profiles_pos):
                raise SystemExit(f"{flavor}: core order must be Client -> Providers -> Schema -> Config -> Defaults -> Migrations -> Profiles")
            if flavor == "forever":
                forever_schema_pos = toc.find("Core\\ForeverSchema.lua")
                if forever_schema_pos < 0 or not (config_pos < forever_schema_pos < defaults_pos):
                    raise SystemExit("forever: ForeverSchema must load after Config and before Defaults")

            nameplate_provider_pos = toc.find("Nameplates\\Provider.lua")
            nameplate_auras_pos = toc.find("Nameplates\\Auras.lua")
            if min(nameplate_provider_pos, nameplate_auras_pos) < 0 or not (providers_pos < nameplate_provider_pos < nameplate_auras_pos):
                raise SystemExit(f"{flavor}: Nameplate provider must load after Core/Providers and before Nameplate consumers")
            if flavor == "forever":
                forever_np_pos = toc.find("Nameplates\\ForeverNativeAdapter.lua")
                if forever_np_pos < 0 or not (nameplate_auras_pos < forever_np_pos):
                    raise SystemExit("forever: detached Nameplate provider must load after shared Nameplate consumers")

            combat_provider_pos = toc.find("Combat\\Provider.lua")
            class_features_pos = toc.find("Combat\\ClassFeatures.lua")
            class_buffs_pos = toc.find("Combat\\ClassBuffs.lua")
            queue_diag_pos = toc.find("Combat\\QueueDiagnostics.lua")
            if min(combat_provider_pos, class_features_pos, class_buffs_pos, queue_diag_pos) < 0:
                raise SystemExit(f"{flavor}: Combat provider/shared consumers missing from TOC")
            if not (providers_pos < combat_provider_pos < class_features_pos < class_buffs_pos < queue_diag_pos):
                raise SystemExit(f"{flavor}: Combat presentation provider must load before shared combat consumers")
            if flavor == "forever":
                forever_combat_pos = toc.find("Combat\\ForeverNativeAdapter.lua")
                if forever_combat_pos < 0 or not (combat_provider_pos < forever_combat_pos < class_features_pos):
                    raise SystemExit("forever: combat presentation adapter must load after shared provider and before combat consumers")

            swing_spell_data_pos = toc.find("Combat\\SwingTimerSpellData.lua")
            swing_provider_pos = toc.find("Combat\\SwingTimerProvider.lua")
            swing_timers_pos = toc.find("Combat\\SwingTimers.lua")
            castbars_pos = toc.find("Combat\\Castbars.lua")
            if min(swing_spell_data_pos, swing_provider_pos, swing_timers_pos, castbars_pos) < 0:
                raise SystemExit(f"{flavor}: Swing Timer provider/shared runtime missing from TOC")
            if not (swing_spell_data_pos < swing_provider_pos < swing_timers_pos < castbars_pos):
                raise SystemExit(f"{flavor}: Swing Timer provider must load after spell data and before SwingTimers/Castbars")
            if flavor == "forever":
                forever_swing_pos = toc.find("Combat\\ForeverSwingTimerAdapter.lua")
                if forever_swing_pos < 0 or not (swing_provider_pos < forever_swing_pos < swing_timers_pos):
                    raise SystemExit("forever: Swing Timer adapter must load after shared provider and before SwingTimers")

            unitframe_provider_pos = toc.find("UnitFrames\\Provider.lua")
            druid_power_pos = toc.find("UnitFrames\\DruidPowerBar.lua")
            unitframes_pos = toc.find("UnitFrames\\UnitFrames.lua")
            predictions_pos = toc.find("UnitFrames\\Predictions.lua")
            if min(unitframe_provider_pos, druid_power_pos, unitframes_pos, predictions_pos) < 0:
                raise SystemExit(f"{flavor}: UnitFrame provider/shared consumers missing from TOC")
            if not (providers_pos < unitframe_provider_pos < druid_power_pos < unitframes_pos < predictions_pos):
                raise SystemExit(f"{flavor}: UnitFrame provider must load before UnitFrame consumers")
            if flavor == "forever":
                forever_uf_pos = toc.find("UnitFrames\\ForeverNativeAdapter.lua")
                if forever_uf_pos < 0 or not (unitframes_pos < forever_uf_pos < predictions_pos):
                    raise SystemExit("forever: native-safe UnitFrame provider must load after UnitFrames core and before optional consumers")

            plus_provider_pos = toc.find("Plus\\Provider.lua")
            plus_automation_pos = toc.find("Plus\\Automation.lua")
            plus_map_pos = toc.find("Plus\\MapTweaks.lua")
            plus_system_pos = toc.find("Plus\\SystemTweaks.lua")
            if min(plus_provider_pos, plus_automation_pos, plus_map_pos, plus_system_pos) < 0:
                raise SystemExit(f"{flavor}: Plus provider/shared runtime files missing from TOC")
            if not (providers_pos < plus_provider_pos < plus_automation_pos < plus_map_pos < plus_system_pos):
                raise SystemExit(f"{flavor}: Plus UI provider must load before Automation/Map/System consumers")
            if flavor == "forever":
                forever_plus_pos = toc.find("Plus\\ForeverNativeAdapter.lua")
                if forever_plus_pos < 0 or not (plus_provider_pos < forever_plus_pos < plus_map_pos):
                    raise SystemExit("forever: native Plus UI provider must load after shared provider and before MapTweaks")

            trainer_core_pos = toc.find("Trainer\\Trainer.lua")
            trainer_provider_pos = toc.find("Trainer\\Provider.lua")
            trainer_init_pos = toc.find("Trainer\\Init.lua")
            trainer_ui_pos = toc.find("Trainer\\UI_Core.lua")
            if min(trainer_core_pos, trainer_provider_pos, trainer_init_pos, trainer_ui_pos) < 0:
                raise SystemExit(f"{flavor}: Trainer provider/shared UI files missing from TOC")
            if not (trainer_core_pos < trainer_provider_pos < trainer_init_pos < trainer_ui_pos):
                raise SystemExit(f"{flavor}: Trainer provider must load after Trainer core and before Trainer runtime/UI consumers")
            if flavor == "forever":
                forever_trainer_pos = toc.find("Trainer\\ForeverNativeAdapter.lua")
                if forever_trainer_pos < 0 or not (trainer_provider_pos < forever_trainer_pos < trainer_init_pos):
                    raise SystemExit("forever: detached Trainer UI provider must load after shared provider and before Trainer runtime/UI consumers")

    providers = (ROOT / "src" / "common" / "Core" / "Providers.lua").read_text(errors="replace")
    meter = (ROOT / "src" / "common" / "Combat" / "CombatMeter.lua").read_text(errors="replace")
    bridge = (ROOT / "src" / "forever" / "Combat" / "BlizzardDamageMeterBridge.lua").read_text(errors="replace")
    if 'Register("combatMeter", "turboface-local", CM, 10)' not in meter:
        raise SystemExit("Classic/local combat-meter provider registration missing")
    if 'Register("combatMeter", "blizzard-damage-meter", Bridge, 100)' not in bridge:
        raise SystemExit("Forever Blizzard combat-meter provider registration missing")
    if "function Providers:Get(group)" not in providers:
        raise SystemExit("provider selection contract missing")

    nameplate_provider = (ROOT / "src" / "common" / "Nameplates" / "Provider.lua").read_text(errors="replace")
    forever_nameplates = (ROOT / "src" / "forever" / "Nameplates" / "ForeverNativeAdapter.lua").read_text(errors="replace")
    if 'Providers:Register("nameplates", "classic-native", Classic, 10)' not in nameplate_provider:
        raise SystemExit("Classic nameplate provider registration missing")
    if 'ns.Providers:Register("nameplates", "forever-detached", FNP, 100)' not in forever_nameplates:
        raise SystemExit("Forever detached nameplate provider registration missing")
    if "function ns.NameplateProviderAfterNativeUpdate" not in nameplate_provider:
        raise SystemExit("shared nameplate defer contract missing")

    unitframe_provider = (ROOT / "src" / "common" / "UnitFrames" / "Provider.lua").read_text(errors="replace")
    forever_unitframes = (ROOT / "src" / "forever" / "UnitFrames" / "ForeverNativeAdapter.lua").read_text(errors="replace")
    if 'Providers:Register("unitframes", "classic-readable", Classic, 10)' not in unitframe_provider:
        raise SystemExit("Classic UnitFrame provider registration missing")
    if 'ns.Providers:Register("unitframes", "forever-native-safe", FOREVER, 100)' not in forever_unitframes:
        raise SystemExit("Forever native-safe UnitFrame provider registration missing")
    for contract in (
        "function ns.UnitFrameProviderAllowsCustomPredictions",
        "function ns.UnitFrameProviderAllowsNanShield",
        "function ns.UnitFrameProviderAllowsDruidPowerBar",
    ):
        if contract not in unitframe_provider:
            raise SystemExit(f"shared UnitFrame capability contract missing: {contract}")
    for contract in (
        "function UF.GetPlayerHealthBar",
        "function UF.GetTargetHealthBar",
        "function UF.GetToTHealthBar",
        "function UF:GetPlayerArtLayout",
        "function UF:GetPlayerReserveGeometry",
        "function UF:GetTargetReserveGeometry",
    ):
        if contract not in forever_unitframes:
            raise SystemExit(f"Forever UnitFrame adapter helper missing: {contract}")

    plus_provider = (ROOT / "src" / "common" / "Plus" / "Provider.lua").read_text(errors="replace")
    forever_plus = (ROOT / "src" / "forever" / "Plus" / "ForeverNativeAdapter.lua").read_text(errors="replace")
    classic_compat = (ROOT / "src" / "classic" / "Core" / "Compat.lua").read_text(errors="replace")
    if 'Providers:Register("plusUI", "classic-ui", Classic, 10)' not in plus_provider:
        raise SystemExit("Classic Plus UI provider registration missing")
    if 'ns.Providers:Register("plusUI", "forever-native-ui", Forever, 100)' not in forever_plus:
        raise SystemExit("Forever Plus UI provider registration missing")
    if "function ns.PlusProviderOwnsNativeMapCanvas" not in plus_provider:
        raise SystemExit("shared Plus native-MapCanvas ownership contract missing")
    if "function ns.PlusProviderSupportsVendorPriceTooltip" not in plus_provider:
        raise SystemExit("shared Plus vendor-tooltip ownership contract missing")
    if "function Classic:SupportsVendorPriceTooltip()" not in plus_provider:
        raise SystemExit("Classic Plus provider must own vendor-price tooltip augmentation")
    if "function Forever:SupportsVendorPriceTooltip()" not in forever_plus:
        raise SystemExit("Forever Plus provider must explicitly yield vendor-price tooltip augmentation")
    if "function API.GetMinimapParts()" not in classic_compat:
        raise SystemExit("Classic minimap compatibility resolver missing")

    trainer_provider = (ROOT / "src" / "common" / "Trainer" / "Provider.lua").read_text(errors="replace")
    forever_trainer = (ROOT / "src" / "forever" / "Trainer" / "ForeverNativeAdapter.lua").read_text(errors="replace")
    if 'Providers:Register("trainerUI", "classic-embedded", Classic, 10)' not in trainer_provider:
        raise SystemExit("Classic Trainer UI provider registration missing")
    if 'ns.Providers:Register("trainerUI", "forever-detached", FOREVER, 100)' not in forever_trainer:
        raise SystemExit("Forever detached Trainer UI provider registration missing")
    for contract in (
        "function ns.TrainerProviderUsesNativeTrainerCards",
        "function ns.TrainerProviderUsesSpellbookGrid",
        "function ns.TrainerProviderSpellbookListSizeBump",
        "function ns.TrainerProviderOwnsEmbeddedSpellbookHost",
        "function ns.TrainerProviderOwnsDetachedProfessionHost",
        "function ns.TrainerProviderUsesDetailedWeaponMasterSources",
        "function ns.TrainerProviderUsesOpenProfessionSkillFallback",
    ):
        if contract not in trainer_provider:
            raise SystemExit(f"shared Trainer UI capability contract missing: {contract}")
    if "API.GetSpellSubtext" not in classic_compat:
        raise SystemExit("Classic spell-subtext compatibility adapter missing for shared Trainer UI")

    schema = (ROOT / "src" / "common" / "Core" / "Schema.lua").read_text(errors="replace")
    migrations = (ROOT / "src" / "common" / "Core" / "Migrations.lua").read_text(errors="replace")
    profiles = (ROOT / "src" / "common" / "Core" / "Profiles.lua").read_text(errors="replace")
    forever_schema_text = forever_schema.read_text(errors="replace")
    if "Schema.PORTABLE_VERSION = 79" not in schema:
        raise SystemExit("portable schema version contract missing")
    if "LEGACY_FOREVER_DB_MAX = 81" not in schema:
        raise SystemExit("legacy Forever 80/81 adoption contract missing")
    if "Schema:RegisterClient(\"forever\", 2" not in forever_schema_text:
        raise SystemExit("Forever revision-2 registration missing")
    if "Schema:RunClientMigrations(TurboFaceDB)" not in migrations:
        raise SystemExit("shared migration chain does not invoke client revisions")
    if "__clientRevisions = true" not in profiles:
        raise SystemExit("client revision metadata must be excluded from profiles")
    print("TurboFace unified source verification passed")


if __name__ == "__main__":
    main()
