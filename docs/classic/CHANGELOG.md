# TurboFace Classic Changelog

## 0.18.0 — first unified multi-client release

- Published Classic and Forever from one layered source repository with separate installable packages.
- Preserved Classic Era behavior while adopting shared compatibility hardening, provider boundaries, and regression coverage.
- Added verified GitHub Actions packaging and separate CurseForge delivery for each supported client.
- Portable SavedVariables remain at schema version 79.

## Unified multi-client baseline

- Phase 33: repository-hardening baseline; restored regression tests, hardened destructive build output handling, removed stale packaged docs/manifests, eliminated the redundant shared Trainer client-identity check, and strengthened verification for documentation/ownership freshness.
- Phase 32: completed the end-state architecture audit; no runtime module was force-merged. Verification now freezes the exact client-overlay divergence allowlist and prevents accidental re-duplication of converged modules.
- Phase 31: converged Trainer/UI_Profession.lua and Trainer/UI_Spellbook.lua through the existing trainerUI provider boundary; InterfaceTweaks remains intentionally client-owned.

## 0.17.87 — unified Phase 30 source maintenance

- Promoted `Core/Debug.lua` into the common multi-client source layer.
- Classic now shares the capability-guarded diagnostic superset without changing gameplay/runtime ownership.
- No SavedVariables schema change.

## Phase 28 — RegenTicks convergence

- Promoted `Power/RegenTicks.lua` into the physical common layer.
- Classic continues to use readable Era resource values; the shared guards are inert for ordinary numbers.
- PlayerFrame bar discovery falls back to the established Era health/mana globals.

## Phase 27 — Quick Setup convergence

- Promoted `QuickSetup.lua` into the physical common layer while preserving Classic's historical reload-bound save/apply workflow through client policy.
- Forever-specific immediate apply, save-helper persistence, modern macro scope, and unsupported-action handling remain policy-gated and do not alter Classic behavior.

# TurboFace Changelog

This document records how TurboFace reached its current design: release history,
migrations, regressions, and the reasons behind consequential changes. For the live
runtime contract, ownership boundaries, and current source structure, see
[`ARCHITECTURE.md`](ARCHITECTURE.md).

The changelog is intentionally organized newest-first. Saved-variable migration numbers
refer to `TurboFaceDB.dbVersion`, not addon releases.

- **Multi-client PowerCost convergence (development):** promoted `Power/PowerCost.lua` into common source. Detached overlay ownership, normalized action lookup, native macro resolution capability detection, and secret-resource curve sinks now form one compatibility-superset implementation; Classic retains readable resource arithmetic and legacy macro fallback. No saved-variable migration is required.

- **Multi-client Core convergence (development):** promoted root `Core.lua` into common source. Startup and native-nameplate lifecycle differences are now explicit `Core/Client.lua` policy instead of duplicated client files; Classic retains its immediate Era path while Forever retains detached/protected-frame staging. No saved-variable migration is required.

- **Multi-client ExperienceBar convergence (development):** promoted `ExperienceBar.lua` into common source. Legacy quest reward scanning remains selection-safe while modern asynchronous reward data is capability-gated and never replaces a complete snapshot with partial data. No saved-variable migration is required.

- **Multi-client UnitFrame provider extraction (development):** added shared
  `UnitFrames/Provider.lua` and promoted `DruidPowerBar.lua`, `Predictions.lua`, and `nanShield.lua`
  into the common Classic/Forever source layer. Classic registers the low-priority
  `classic-readable` provider, so its historical readable UnitFrame prediction overlays, NanShield
  reconstruction, and Druid auxiliary power bar remain active. Forever's higher-priority provider
  can disable those renderers without introducing client branches into the shared files. No
  saved-variable migration is required.

- **Multi-client Nameplate provider extraction (development):** added the shared
  `Nameplates/Provider.lua` substrate contract and promoted the reconciled Aura, BubbleNameplates,
  NameplateUnits, NameplateVisuals, NativeNameStyle, and Stacking implementations into the common
  Classic/Forever source layer. Classic registers the low-priority `classic-native` provider, so
  its readable-value behavior, legacy TurboFace aura rows, and immediate Era update semantics are
  unchanged. `Core/Compat.lua` now exposes the same `ReadUnit*` and guarded event-registration
  vocabulary consumed by that shared code. No saved-variable migration is required.

- **Canonical Aggro Audio cues restored (addon 0.17.87):** replaced the temporary procedural `GainAggro.mp3` and `LoseAggro.mp3` tones with the project-owner-supplied canonical cues. Runtime paths and threat-transition behavior are unchanged. The binary provenance manifest now records the restored 48 kHz / 256 kbps assets and their release hashes. No saved-variable migration is required.
- **Independent nameplate DoT surface (addon 0.17.87):** Global -> DoT Prediction -> Show on nameplates no longer inherits the optional Nameplates enhancement-family master. With every other feature disabled, the prediction engine now maintains a minimal `NAME_PLATE_UNIT_ADDED/REMOVED` GUID bridge and binds its existing additive textures directly to Blizzard's native health StatusBar. It creates no replacement plate, aura row, quest/threat/resource feature, or enhancement polling. The full Nameplates lifecycle remains authoritative whenever that family is enabled; the dot-only binding exists solely when it is off and releases its textures/render-order amendment on removal. `/tf debug dots` reports `mode=dot-only` or `mode=enhanced`. No saved-variable migration is required.
- **Hotbar counter color opacity (addon 0.17.87):** fixed the Counter Color and shared Power color-picker adapter reading Classic Era's legacy opacity control through the retail-derived alpha path. Classic's opacity slider stores transparency (`0` means fully opaque), so selecting full opacity could be persisted as `a=0` and the counter immediately returned to transparent. TurboFace now treats the legacy Classic slider as authoritative, inverts it exactly once, and uses `GetColorAlpha` only as a modern-client fallback. Overlay and tick-marker color pickers share the corrected adapter. No saved-variable migration is required; reopening an affected color and selecting the intended opacity replaces the previously misread value.
- **Cold-login and pooled-nameplate DoT recovery (addon 0.17.87):** moved the visible-nameplate recovery scan from a fixed delay after `PLAYER_LOGIN` to `PLAYER_ENTERING_WORLD`. A fresh client login can remain behind the loading screen long enough for the old callback to run before Blizzard has created any plates, while `/reload` masks the problem because the world is already live. TurboFace now performs an immediate world-entry reconciliation plus two bounded identity-validated settle passes at 0.5 and 1.5 seconds. Live diagnostics then isolated a second recycled-plate failure with correct projection, GUID, geometry, layers, and saved opacity but a shown DoT texture whose effective and vertex alpha had become zero. The root cause was the friendly identity-only presentation walking the live native health subtree: when a pooled plate already contained TurboFace additive textures, the native alpha-suppression hook could attach to the DoT region and continue forcing it to zero after that plate was recycled to a hostile unit. Suppression now admits only objects captured in the immutable pre-augmentation Blizzard baseline and releases any older non-baseline suppression state during restoration. The renderer additionally validates live RGBA/base alpha and clears its caches on rebind/removal. Superseded world callbacks remain generation-gated and no permanent polling was added. No saved-variable migration is required.
- **Rumblecrush preset re-audit (addon 0.17.87):** re-parsed the supplied 2026-09-15 schema-79 `TF1:` export with TurboFace's strict data-only parser and compared the fully default-merged result path-by-path. Updated the sparse preset for 1.30 target buff/debuff scale, 30% overlapping nameplate power height, hidden Grocery queue, visible Combat Meter, and below-bars ToT name. Redundant values matching current factory defaults remain omitted. The permanent runtime regression now covers each corrected field, and the normalized preset has zero mismatches against the supplied export. No saved-variable migration is required.
- **Static profession Training catalog (addon 0.17.87):** profession Training no longer starts empty after the provenance cache reset or requires visiting trainers to build its recipe list. Trainer-only Classic Era recipes now come directly from the embedded MIT-licensed LibProfessionDB catalog, while Blizzard trainer scans remain a live overlay for prices, availability, and trainer-specific requirements. LibProfessionDB intentionally leaves some Vanilla learn requirements absent when its same-era sources cannot verify them; TurboFace displays those as `Skill ?` under Not Yet Available instead of guessing from the unrelated crafting-difficulty threshold. Auto-taught recipes are excluded, and Fishing/Herbalism/Skinning now explain that their profession ranks live in Skills instead of reporting an apparent collection failure. Mixed trainer/external source rows remain in Recipes because the Era community trainer flags are known to over-classify; this keeps the two views separated without restoring the removed TrainerSpells data. Added source and runtime regressions for the static baseline, crafted-item icon, unknown-requirement handling, live overlay, mixed-source exclusion, and auto-taught exclusion. No saved-variable migration is required.
- **Profession Recipes crafted-item icons (development):** Recipes rows now use LibProfessionDB's `craftedItemId` with TurboFace's cache-independent item-icon compatibility APIs, so each craft displays the icon of the item it produces rather than the crafting-spell texture. Enchants and other effects with no produced item fall back to the live recipe/spell icon. Also fixed that fallback's `GetSpellInfo` call previously running through a Lua logical expression that discarded its third icon return. Added runtime and source regressions for crafted-item priority and fallback preservation. No saved-variable migration is required.
- **Non-trainer Classic Era Recipes catalog (development):** restored the offline profession-recipe browser with the Classic Era subset of MIT-licensed LibProfessionDB 1.7.0. Training remains the persistent trainer-discovery/queue view. Recipes admits entries with a confirmed vendor, quest, container, or drop path, filters client-classified profession-rank books, and removes real trainer duplicates using TurboFace's observed Training spell IDs/names instead of LibProfessionDB's over-inclusive community trainer flags. Auto-taught, unknown-source, and never-implemented rows remain excluded. Remaining recipes are grouped as missing, ignored, and already known; live known state comes from the open Classic TradeSkill book, while skill requirements and external acquisition sources come from the static catalog. Search covers names, effects, and sources. The approximately 800 KB vendored subset excludes other game versions, standalone Ace3/version-check code, synthetic-scroll/prefix metadata, and non-English tables; localized clients resolve recipe names from their own spell data. Its generated tables are deferred until Recipes is first opened. Added the upstream license, release hash, and provenance notice. No saved-variable migration is required; legacy `recipeData` remains tolerated but has no presentation owner.
- **Critical-first / missing-source DoT recovery (development):** fixed two remaining empirical-prediction gaps that could leave a valid nameplate DoT with no drawable damage. Critical periodic hits now enter a separate conservative half-value fallback ring when no ordinary sample exists; they never contaminate the normal-tick median, and the first non-critical tick immediately supersedes the fallback. When Classic briefly omits an owned aura's `sourceUnit`, the aura scan now recovers the actual player-or-pet caster from active destination combat-log state even if the ownership flag is also absent; broader caster-wide recovery remains ownership-gated. Added a Lua runtime regression combining both conditions. No saved-variable migration is required.
- **Stacked NPC quest automation (development):** Auto Quest Accept / Turn-in now continues through multiple ready turn-ins and available quests on one NPC, including a new quest unlocked by the preceding reward while unrelated quests remain in progress. A bounded delayed post-action pump handles Classic NPCs that do not emit another fresh `GOSSIP_SHOW`; per-NPC processed quest IDs prevent stale client lists from reopening the same entry. Ready turn-ins remain higher priority than accepts, in-progress quests remain untouched, ambiguous reward choices remain manual, and Shift still cancels the chain.
- **Quest automation row cleanup (development):** shortened the two Automation labels to `Auto Quest Accept` and `Auto Quest Turn-in`, and moved their shared `Shift to bypass` guidance into the open third grid column on the same row. Runtime bypass behavior is unchanged.
- **Player swing completion across combat boundaries (development):** leaving combat no longer zeros and hides an in-progress player MH/OH swing. The existing countdown remains visible until the weapon reaches ready, then releases its standalone or embedded row and parks the cadence driver. Entering another combat before completion carries the exact remaining time forward instead of replacing it with a fabricated ready state. Target swing teardown and idle behavior remain combat-bound. No saved-variable change.
- **Two-phase Rage decay marker (development):** added a Warrior/Bear power-bar marker that begins a right-to-left pre-decay sweep on `PLAYER_REGEN_ENABLED`, switches to a repeating right-to-left two-second sweep on the first observed natural-sized Rage loss, and re-anchors to later decay events. The learned decay phase survives between pulls so the next pre-decay sweep targets the upcoming server boundary instead of reusing a variable first-loss duration. Combat re-entry, zero Rage, and leaving Bear form park the marker. Added independent marker/border toggles and Rage-specific colors under Unit Frames -> Player Bar Tick Markers. No saved-variable migration is required; schema remains 79.
- **Development-only asset manifest packaging (addon 0.17.86):** moved `ASSET_PROVENANCE.md` from the shippable addon directory to the repository root. The binary hash inventory remains part of the provenance audit and validation suite, but is now a development artifact alongside Architecture, Changelog, and the provenance handoff rather than a CurseForge package document. The release continues to ship the legally relevant `THIRD_PARTY_NOTICES.md` and referenced license texts. Package-boundary validation now requires the asset manifest at repository level and rejects it inside `TurboFace/`. No runtime or saved-variable change.
- **Rumblecrush preset refresh (addon 0.17.85):** updated the built-in Rumblecrush preset from the supplied schema-79 `TF1:` export and advanced its date to 2026-09-13. The differential now enables the current Experience Bar, FPS Counter, Grocery, Hearthstone, Skill Tracker, UnstuckSkips, baked combat timers, health/power tick amounts, overlapping nameplate power bar, threat number, both quest automations, Quick Setup, and the complete set of enabled Blizzard/aura movers represented by the export; it also adopts Combat Meter as the active mover, 100% non-selected nameplate alpha, the 10px shield font, ToT name-above-bars, and the current minimap-button angle. Redundant values equal to factory defaults and shared Aura styling remain inherited rather than duplicated. A safe-parser/full-overlay audit reports zero mismatches against the supplied export, and a permanent runtime contract covers the refreshed differential. No saved-variable migration is required; schema remains 79.
- **Mixed-NPC Auto Quest Turn-in fix (addon 0.17.84):** fixed a completed quest not being selected when the same NPC also had an in-progress active quest. Classic can provide an incomplete/stale gossip `isComplete` field or an active-quest table whose reliable extent is the explicit `GetNumActiveQuests()` count. TurboFace now iterates that count and reconciles every active gossip quest ID against `C_QuestLog.IsComplete` (plus the legacy completion API) before falling through to available pickups. Extended the runtime regression with an incomplete first entry and a completed second entry whose gossip flag is deliberately stale. No saved-variable migration is required; schema remains 79.
- **Independent Auto Quest Accept / Turn-in (addon 0.17.83):** added two default-off toggles under QoL -> Automation. TurboFace now enters completed quests before available quests at modern or legacy Classic gossip/quest-greeting NPCs, accepts quest details, advances completable progress dialogs, and claims rewards automatically only when there are zero or one selectable choices. Two or more reward choices remain manual, holding Shift bypasses every automated quest action, and disabling both settings unregisters the entire quest listener. The implementation is expressed directly against Blizzard quest/gossip APIs without an NPC or quest database. Added static and Lua runtime coverage for option independence, section gating, selection priority, accept/progress behavior, reward safety, Shift bypass, and listener teardown. No saved-variable migration is required; schema remains 79.
- **Heroic Strike queue diagnostic and target-state fix (addon 0.17.82):** removed TurboFace's unconditional queued-spell visual clear on `PLAYER_TARGET_CHANGED`; target and form changes now re-read the client's authoritative `IsCurrentSpell` state, preventing the Swing Timer from falsely appearing dequeued when Classic retained Heroic Strike/Cleave/Maul/Raptor Strike. Added an opt-in, observation-only `/tfqueue` session recorder. It announces client queue transitions and retains the surrounding action-slot/macro, cancellation API/caller stack, target, form, rage, combat, spellcast, UI-error, and player melee combat-log events so an intermittent real cancellation can be attributed after reproduction with `/tfqueue dump`. The tracer is inert until enabled and never casts or cancels a spell. Added load-order, ownership, observation-surface, and bounded-history contracts. No saved-variable migration is required; schema remains 79.
- **Baked combat-timer mover ownership fix (addon 0.17.81):** fixed Player and Target cast bars (and the shared standalone swing-timer path) being pulled back to saved mover coordinates after switching UnitFrames combat timers to baked-in mode. Registered mover `isAvailable` predicates now suspend geometry as well as overlay ownership, the permanent `SetPoint` reapply hook ignores unavailable surfaces, and mover-owned alpha/mouse state is released to the embedded owner. Standalone coordinates remain saved and are reapplied if the timer returns to standalone mode. Added runtime and source contracts for ownership release/reacquisition. No saved-variable migration is required; schema remains 79.
- **Classic single-gossip automation fix (addon 0.17.80):** fixed QoL -> Automation doing nothing for ordinary one-choice gossip entries because Classic does not reliably populate the retail-derived `selectOptionWhenOnlyOption` field. Automation now uses a strict data-independent policy—exactly one gossip option and zero available or active quests—and selects through the modern option ID, modern order index, or legacy Classic title/type API as available. Spirit-healer automation shares the same corrected selector. Updated the option label to state the real quest-exclusion boundary and added runtime coverage for flagless modern entries, ID/index selection, quest and multiple-option rejection, and the legacy fallback. No saved-variable migration is required; schema remains 79.
- **QoL naming and raid-interface reliability (schema 79 / addon 0.17.79):** renamed the visible Options `Plus` tab to `QoL` while retaining the internal `plus` namespace for profile compatibility. Reworked Hide Raid Group Labels to cover the PlayerFrame raid indicator, legacy raid pullouts, and all eight compact-raid group titles through their separate Blizzard load-on-demand owners, with an immediate sweep that does not require a live raid transition. Show Raid Frame Toggle Button now waits for `Blizzard_CompactRaidFrames`, reparents and explicitly shows the hidden-mode toggle, and reapplies its placement after Blizzard rebuilds the manager. Removed the mail, quest, and book text-resize checkboxes, sliders, defaults, section mappings, runtime FontObject mutations, and factory-profile residue. Schema 79 and a current-import guard prune all six retired saved keys.
- **Hybrid seeded/learned Flight Bar (addon 0.17.78):** added the 808 directional Classic flight durations from Flight Timer Classic `Data.lua` revision `5c9982c28af97da25baa3e7df39db62911a45840` under its declared CC BY 2.0 license, with creator/source/license/change attribution in the shipped notice set. The baseline supplies immediate timers and taxi-node estimates on first use; TurboFace still records each completed trip under its more specific faction + continent + full multi-hop coordinate key, and that observed bounded mean takes priority from the next trip onward. The seed value is retained as comparison metadata but is not blended into the live mean. Routes outside the 63-node baseline now show a visible count-up `Learning` bar instead of silently hiding, and the bar watches `UnitOnTaxi` for a true-to-false landing fallback in addition to `PLAYER_CONTROL_GAINED`. Early landing clears the pending sample so shortened routes cannot corrupt full-route timing. Added hybrid precedence, first-flight seed, observation replacement, unknown-learning, landing fallback, attribution, and load-order contracts. No saved-variable migration is required; schema remains 78.
- **Opaque custom Spellbook pages (addon 0.17.77):** fixed the Class Trainer and Skills tabs rendering over the still-visible Blizzard spell page after the provenance pass removed the unknown-origin `Trainer/inset.blp`. Decoding the removed file confirmed that its visual structure was a dark mottled interior with a thin inset border—not Character or Reputation tab artwork. Both custom Spellbook views now use Blizzard's reusable client-native `InsetFrameTemplate`, which supplies the tiled `UI-Background-Marble` interior and native NineSlice inset border across the complete replacement panel. The parent frame owns mouse input so gaps cannot click Blizzard spell buttons underneath. The parallel Training/Recipes profession view uses the same provenance-clean native inset instead of retaining a dead reference to the removed asset. Added a release contract that requires the runtime inset template, full anchors, click isolation, and zero remaining `Trainer/inset` references. No saved-variable migration is required; schema remains 78.
- **Provenance completion and learned Flight Bar capture fix (addon 0.17.76):** completed the distributable third-party notice set for EasyFrames, What's Training?, TurboPlates, LibClassicDurations, LibSharedMedia-3.0, CallbackHandler-1.0, and LibStub; added a hash-based manifest covering every shipped binary asset; removed the unknown-origin `Trainer/inset.blp` and unused TurboPlates gradient texture; and replaced the two ambiguous aggro samples with TurboFace procedural two-tone notifications. Fixed first-flight learning by snapshotting route identity while `TAXIMAP_OPENED` still owns valid taxi APIs. The protected `TakeTaxiNode` post-hook can run after Blizzard begins closing the map, so the prior live lookup could lose its continent/key and silently discard the completed measurement. The hook now consumes the stable snapshot, with live lookup only as fallback. A Lua runtime regression reproduces post-hook API invalidation, verifies first-trip storage, and verifies the learned tooltip/countdown on the next trip. No saved-variable migration is required; schema remains 78.
- **Provenance cleanup phase 5 — Training / TrainerSpells split (addon 0.17.75):** removed the 17 TrainerSpells-only static profession/recipe seed files from the distributable and converted profession metadata to TurboFace-owned live discovery through Blizzard trainer APIs. Existing mixed profession/recipe caches are reset once via `TurboFaceTrainerDB.provenanceProfessionResetV1`; subsequent profession trainer visits repopulate both the Training snapshot and the Recipes snapshot, while profession proficiency ranks remain owned by `Trainer/SkillData.lua`. The 11 bundled Classic Era class/pet seed catalogs remain under the permissive What’s Training? MIT lineage and now ship with explicit source headers plus `Licenses/WhatsTraining-MIT.txt` / `THIRD_PARTY_NOTICES.md`. Trainer runtime/UI/queue/capture code uses TurboFace `Trainer` naming rather than the historical `TrainerSpells` local alias, and the old port/D4Lib/upstream commentary is removed. No `TurboFaceDB` schema bump is required.
- **Provenance cleanup phase 4 — Shield Bars / nanShield data rebuild (addon 0.17.74):** removed the WeakAura-derived flat absorb database, palette, Season-of-Discovery rune branch, and copied NPC/test/expansion shield catalog from `UnitFrames/nanShield.lua`. Added `UnitFrames/ShieldData.lua` as a TurboFace-owned Classic Era model with named fields and only player-accessible shield families needed by the live feature: Priest Power Word: Shield, Mage Mana/Fire/Frost Wards and Ice Barrier, Warlock Sacrifice/Spellstone/Shadow Ward, and Classic protection-effect ranks. The existing TurboFace Player/Party renderer, CLEU remainder tracking, Party direct-cast PW:S ownership, and `UnitGetTotalAbsorbs` reconciliation remain. The school palette is new; talent modifiers now prefer learned passive spell ranks with Classic talent-index fallbacks; the obsolete Advanced Warding SoD rune path is removed; and Ice Barrier now correctly sources its 10% coefficient from Frost spell damage instead of healing power. Historic `nanShield*` saved keys / internal method names remain solely for profile/API compatibility. No saved-variable migration is required.
- **Provenance cleanup phase 3 — Plus/Leatrix reimplementation (addon 0.17.73):** replaced the remaining Leatrix-derived Plus implementations with TurboFace-owned modules expressed directly against Blizzard Classic Era APIs. Automation no longer ships the large NPC-ID gossip catalog: quest-free single-option gossip now follows Blizzard's `selectOptionWhenOnlyOption` metadata, with Alt as the explicit override. Social, System, Chat, and Interface helpers were independently restructured around TurboFace section gating/event ownership; shared-quest filtering also fixes the old `UnitIsPlayer(name)` misuse by testing the `questnpc` unit token. Removed both bundled faction flight-time data files and rebuilt Flight Bar around account-learned taxi measurements stored in `TurboFaceCacheDB.flightTimes`; the first trip learns a route, later trips provide the countdown/tooltip, and learned measurements survive client-build cache resets. Replaced the prior externally inspired minimap zone-banner crop with a simple TurboFace tooltip-backdrop banner. `MapTweaks.lua` remains the existing TurboFace-owned Blizzard-default-map workaround, with stale comparison/provenance commentary removed. No `TurboFaceDB` schema migration is required.
- **Druid/Rogue nameplate combo cadence hotfix (addon 0.17.72):** fixed a latent split-module initialization bug where `NameplateVisuals.lua` captured `ns.NP.MAX_CP` even though the shared Nameplates substrate never published that constant. Rogues could hit it when target combo dots first rendered; Druids commonly exposed it on entering Cat Form, where the nil arithmetic repeated until Cadence correctly evicted the failing combo client. Nameplates now publishes the Classic Era five-slot capacity centrally and the visual module keeps a defensive local fallback of 5, preventing the combo renderer from taking down its cadence client if that shared constant is ever lost during a future refactor. No saved-variable migration or intended presentation change.
- **Provenance cleanup phase 2 — TurboDebuffs catalog (addon 0.17.71):** removed the imported BigDebuffs/Ascension rank-by-rank spell database and rebuilt TurboDebuffs around a TurboFace-owned Classic Era important-aura catalog. The new classifier stores only one canonical Blizzard spell/effect identity per selected aura family and resolves localized names at runtime, collapsing all ranks without copied parent/alias structures. Removed Death Knight, TBC/Wrath, Ascension/private-server and other expansion-only baggage; retained the existing TurboFace renderer, timer, blacklist, category toggles and user priority policy. Permanent forms/stances and ordinary low-information buffs are intentionally not catalogued. The legacy `interrupts` profile category is preserved but remains inactive in the aura-only scanner because Classic school lockouts are not reliable UnitDebuff auras. No saved-variable migration is required.
- **SwingTimer closure upvalue hotfix (addon 0.17.70):** fixed the `LUA_WARNING` that `SwingTimerOnEvent` exceeded Classic Lua's 60-upvalue warning threshold after provenance cleanup phase 1. The cleanup spell-family behavior now remains behind one `SwingTimerSpellData` interface-table capture instead of several individually captured helper functions. This reduces the event dispatcher's closure footprint below the pre-cleanup 0.17.68 shape without changing swing/reset/queue behavior or saved variables.
- **Provenance cleanup phase 1 — swing/leash/reminder data (addon 0.17.69):** independently reconstructed the small third-party-reference hotspots in `Combat/SwingTimerSpellData.lua`, `Combat/SwingTimers.lua`, `Combat/LeashTimer.lua`, and the class-agnostic talent reminder in `Combat/ClassBuffs.lua`. Swing interactions now use TurboFace-owned canonical Blizzard spell-family identities resolved by localized name instead of rank-by-rank imported tables; queued Heroic Strike/Cleave/Raptor Strike/Maul state is read through that family layer. Removed the inherited healing-potion reset IDs because the renderer only consumes item resets from `SPELL_DAMAGE`/`SPELL_MISSED` (so those heal IDs were unreachable), removed the non-Era/dead channel entries, and retained only Oil of Immolation's damage effect in the item-reset path. Leash loss-of-control suppression is now organized independently by chase-invalidating control behavior, and the unspent-talent reminder is a direct `UnitCharacterPoints()` helper. No saved-variable migration or intended presentation change.
- **Factory-default profile refresh (addon 0.17.68):** re-audited the shipped baseline against the newly supplied schema-78 `TF1:` export. The adopted differences are 160px standalone Swing/Cast widths, Blizzard Raid Bar attack/cast textures, Loot Frame width 220 / duration 7s / spacing 0, and the Loot Frame as the selected mover at CENTER (0, 290). Database-version bookkeeping, the empty legacy `map` container, and redundant named RGB aliases already duplicated by the positional DPS color remain intentionally outside the defaults schema. No saved-variable migration is required.
- **Deterministic nameplate DoT layering (addon 0.17.67):** fixed a renderer-only failure exposed by `/tf debug dots` reporting a valid mapped plate, exact health basis, non-zero remaining damage, and `overlay=true` while no prediction was visible. The old renderer placed Blizzard's native health fill, TurboFace's opaque black normalization underlay, and the coloured DoT texture in the same `ARTWORK:0` bucket and relied on creation order, which WoW does not define for overlapping textures sharing one layer/sublevel. While a prediction is drawable, the nameplate stack is now explicitly **native fill -2 / black underlay -1 / coloured prediction 0 / untouched Blizzard border 1**. TurboFace snapshots and restores the native fill's original draw layer when the prediction ends, the plate recycles, or the feature is released; plates without an active prediction remain fully native. `/tf debug dots` now also reports rendered texture dimensions/effective alpha, current native-health-bar identity, bottom power inset, vertex colour, and the fill/underlay/prediction draw layers so any remaining visual-only failure can be classified immediately. No saved-variable migration is required.
- **Darker rounded Loot Frame shell edge (addon 0.17.66):** changed only the finalized Blizzard Tooltip shell border tint from the previous cool silver-gray to near-black **RGB 0.01 / 0.01 / 0.01 at full alpha**. The interior fill remains **RGB 0.03 / 0.03 / 0.03** with the existing user-controlled background alpha, so the edge now reads darker than the fill while retaining the Tooltip texture's rounded shape. Edge size, inset, shell padding, icon geometry, text anchors, stacking, mover bounds, and saved settings are unchanged. No saved-variable migration is required.
- **Nameplate DoT prediction reliability hardening (addon 0.17.65):** closed four nameplate-only repaint/lifecycle races behind the remaining intermittent missing prediction overlay. Periodic CLEU ticks now repaint the exact visible destination plate through the existing O(1) GUID -> nameplate-token map after the tick sample invalidates prediction state, so `UNIT_HEALTH` arriving first can no longer leave newly learned damage undisplayed. `UNIT_AURA` on Target/ToT is explicitly bridged to the same GUID's visible nameplate, and nameplate aura/bind events receive one deduplicated 50 ms identity-validated reconciliation so transient aura metadata or native layout ordering cannot cache an empty result indefinitely. The pooled-frame 0.5 s lifecycle guard now treats same-token GUID replacement as a full canonical nameplate rebind instead of repairing only lookup tables, keeping `myPlate.cachedGUID` and every augmentation synchronized. DoT rendering also performs up to three reconcile retries only when Blizzard's native health bar still reports placeholder geometry, and pooled removal now hides/reset DoT textures explicitly. `/tf debug dots` now reports the target's mapped nameplate unit, live/cached GUIDs, native bar width, overlay visibility, projected damage, health basis, learned tick, and cadence; the older duplicate unreachable `dots` debug branch was removed. No saved-variable migration is required.
- **Loot icon optical left alignment (addon 0.17.64):** shifted the rounded Loot Frame item/money icon 0.5px left inside the finalized shell. This corrects the slightly roomier-looking left gap created by the icon frame outset without changing the 3px shell padding, row dimensions, derived icon size, text spacing, stacking, or mover footprint.
- **Loot Frame unified row/icon sizing (schema 78 / addon 0.17.63):** removed the separate Loot Frame Icon Size slider and retired `lootFrame.iconSize`. Row Height is now the sole vertical-size control; item/money icons derive automatically as `rowHeight - 3px` using the fixed shell padding (32px row -> 29px icon). Repacked the remaining sliders into the three-column grid, and schema/current guards prune legacy icon-size values so imports cannot restore independent sizing.
- **Final rounded loot shell geometry (schema 77 / addon 0.17.62):** finalized the Loot Frame outer shell at a static **7px Tooltip edge** with **1.2px backdrop inset**, removed the temporary Border Edge Size / Border Inset tuning sliders and their saved settings, and tightened the shell padding from 4px to **3px per side** so the outer edge sits 1px closer to the rounded item icon. Configured width/row-height remain content-box dimensions; stacking and mover bounds automatically follow the resulting +6px visual footprint. Schema 77 plus the current-schema guard prune the retired tuning keys so imports cannot resurrect them.
- **Temporary loot border tuning sliders (addon 0.17.61):** added **Border Edge Size** and **Border Inset** sliders to Speedrun -> Loot Frame so the rounded Tooltip shell can be tuned live in-game before its final values are baked back into static presentation. Both controls use 0.2px steps; Edge Size spans 1-32px and Inset spans 0-10px, with the current 15px / 3px look retained as the defaults. Loot row style caching now includes both values, and the Loot-specific slider path quantizes fractional steps before saving so direct entry and dragging remain stable.
- **Rounded loot border tuning (addon 0.17.60):** increased the outer loot row Tooltip edge from 13px to 15px and changed its backdrop inset from 2px to 3px. The 4px shell padding, configured content geometry, icon border, text anchors, row stacking, and mover footprint remain unchanged.
- **Rounded loot border refinement (addon 0.17.59):** enlarged the rounded row Tooltip edge from 10px to 13px and tightened the dark-fill backdrop inset from 3px to 2px. The existing 4px shell padding, content dimensions, icon border geometry, text anchors, stacking, and mover footprint are unchanged; this pass only strengthens the outer rounded border and lets the fill sit closer beneath it.
- **Rounded loot shell spacing finish (addon 0.17.58):** increased the outer rounded loot shell padding from 2px to 4px on every side so Blizzard's Tooltip edge has visible breathing room around the quality-framed rounded icon, including its 1px border outset. Configured Width/Row Height remain the content-box dimensions; icon/text sizing is unchanged, while row stacking and Loot Frame mover bounds now use the finished +8px visual width/height. Also removed a duplicate per-row style-key assignment left in the 0.17.57 follow-up.
- **Rounded loot padding follow-up (addon 0.17.57):** expanded each rounded loot rectangle by 2px on every side around its configured content box, providing clear space between the quality-framed icon and the outer edge. Icon/text sizes and user-configured width/row-height values remain unchanged; row stacking and mover bounds now include the added 4px total width and height.
- **Rounded loot presentation (addon 0.17.56):** restyled each TurboFace loot toast as a rounded rectangle using Blizzard's scalable Tooltip edge and an inset dark background. Item/money icons now use TurboFace's rounded alpha mask and silver rounded-square frame, tinted by item quality or coin gold. Loot row dimensions, spacing, click/tooltip behavior, timers, and mover geometry are unchanged.
- **Nameplate power opt-in cleanup (addon 0.17.55):** **Overlap Power Bar** is now the complete nameplate-power presentation and runtime gate. When unchecked, TurboFace hides any stale resource visual, does not create or update the power holder, does not query `UnitPower*`, and unregisters the three nameplate power events. Checking it enables only the overlapping health-bar presentation; the development-only separate resource row and its border/geometry path are removed.
- **Pet happiness alignment (addon 0.17.54):** moved Blizzard's native Pet happiness icon 1px down and 0.5px right against the v3 artwork. Icon size, state, tooltip, portrait, bars, names, and artwork remain unchanged.
- **Pet portrait v3 artwork (addon 0.17.53):** replaced the packaged `UI-Pet-Portrait.tga` with the supplied v3 artwork. All pet portrait, bar, name, happiness-icon, frame, and texture-crop geometry remains unchanged from 0.17.52.
- **Pet portrait v2 alignment (addon 0.17.52):** replaced the packaged `UI-Pet-Portrait.tga` with the supplied v2 artwork. Pet health and power bars move down 1px to Y 8 and Y 22, and both below-bars and optional above-bars name anchors move down 1px to Y 37 and a -2px top gap respectively. Portrait geometry and the happiness icon's absolute position remain unchanged.
- **Pet name placement option (schema 76 / addon 0.17.51):** added **Name Above Bars** under Unit Frames -> Pet, matching the existing ToT presentation choice. New, factory, and upgrading profiles without an explicit placement choice put the pet name in the clear strip below its HP/power stack by default; enabling the option restores the prior above-frame anchor exactly.
- **Factory-default profile refresh (addon 0.17.50):** re-audited the complete shipped baseline against the newly supplied schema-75 `TF1:` export, including every mover position and mover enabled/hidden/click-through state. All mover coordinates and state flags already matched; the adopted differences are 6px aura horizontal spacing, 1.0 Target buff/debuff and ToT debuff scales, 8px Party/Pet/ToT name text, and disabled nameplate Threat Number and overlapping power-bar presentation. Database bookkeeping and the empty legacy `map` container remain intentionally outside factory settings.
- **ToT debuff countdown refinement (addon 0.17.49):** Target-of-Target debuff countdown text now renders exactly 1 font-size step below the shared Aura Timer Font Size while retaining the same typeface, outline/shadow style, scale counter-correction, and bottom anchor. Other aura timers and ToT stack counts remain at their configured shared size.
- **ToT debuff alignment/edge refinement (addon 0.17.48):** reduced only the Blizzard-owned ToT debuff-chain nudge from 3px to 1px; Target buffs and Target debuffs remain at 3px. The nudge snapshot now records its applied distance so a changed per-group correction is safely restored and reapplied rather than inherited as stale anchor state. The ToT-only debuff border overlay is expanded outward by 0.5px per edge, subtly thinning the rendered ring without changing icon size, spacing, timer geometry, or dispel tint.
- **Blizzard-owned aura alignment (addon 0.17.47):** when Auras are enabled but either the Movers master, aura-layout ownership, or the corresponding Target Buffs, Target Debuffs, or ToT Debuffs mover element is disabled, that Blizzard-positioned aura group receives a static 3px right nudge at the first button in its anchor chain. Because Blizzard propagates a shown Target buff root's position into debuffs without always exposing that relationship through `GetPoint()`, visible nudged buffs suppress the direct debuff correction; debuff-only targets retain it. Reversible snapshot guards prevent refresh accumulation, stale transition offsets, and the former compounded 6px result; mover-owned positioning remains untouched.
- **Narrow Target-of-Target artwork (addon 0.17.46):** replaced `UI-ToT-Portrait.tga` with the narrower v3 composition. The rendered fixed-art surface is now 98×48 instead of 119×48; its name, health, and power regions shrink from 70px to 49px while retaining their existing left and vertical anchors. The default ToT-debuff fallback moves left by the same 21px so it continues to clear the artwork.
- **Factory-default profile refresh (addon 0.17.45):** promoted the supplied schema-75 `TF1:` configuration to the shipped factory baseline, including its standalone combat-timer dimensions/styles, Clean attack/cast textures, non-embedded timer mode, enabled Plus Interface/System preferences, class reminder growth, party DoT prediction, and every explicit mover enabled/hidden/click-through state and saved position. The obsolete `experienceBar.session` default was removed so XP history remains exclusively per-character and outside settings profiles.
- **Wand-versus-physical ranged swing fix (addon 0.17.44):** split ranged attacks into explicit wand and physical kinds. Auto Shot, Shoot Bow/Gun/Crossbow, and Throw restart only the ranged clock without disturbing MH/OH; wand **Shoot** restarts the ranged clock and both melee clocks. The kind is captured from canonical/localized spell identity at SENT/START and pinned to the cast GUID through success/failure/stop so an ambiguous 1.15.9 success payload cannot change its behavior.
- **Wand Shoot melee-isolation attempt (addon 0.17.43):** hardened ranged-shot identification across the spellcast lifecycle, but incorrectly grouped wand Shoot with physical ranged attacks and therefore suppressed its required MH/OH reset.
- **Standalone attack/cast bar dimensions (addon 0.17.42):** added independent **Standalone Width** and **Standalone Height** sliders under Global -> Swing Timers and Global -> Cast Bars. Swing settings apply only to the non-baked Player MH/OH/Ranged and Target attack rows; Cast settings apply only to non-baked Player/Target cast rows. Defaults preserve the legacy 150x12 standalone geometry. Attack-bar height also drives the default standalone row stride and cast-bar offset so mixed attack/cast heights do not overlap. Embedded 121x14 UnitFrame artwork remains fixed and ignores these settings.
- **Retired Plus backpack free-slot display (addon 0.17.41):** removed **Plus -> Interface -> Show free bag slots on backpack** and its `MainMenuBarBackpackButton_UpdateFreeSlots`/tooltip hooks now that Classic Era provides a native Blizzard backpack free-slot display. The retired `plus.showFreeBagSlots` setting is pruned from live/imported config. The separate Speedrun **Free Bag Slot Counter** (`Inventory/BagSlots.lua`) is unchanged.
- **Target-of-Target power alignment follow-up (addon 0.17.40):** nudged the ToT power bar down 1px (`Y 27 -> 28`) after artwork alignment testing. Health bar, name placement, portrait, artwork, debuffs, and Target timer layering are unchanged.
- **Target timer layering (addon 0.17.39):** lowered the embedded Target attack/cast stack to one frame strata below Target-of-Target so the ToT frame and its artwork always render above the timers. Target timer positioning and internal cast-over-attack ordering are unchanged.
- **Target-of-Target name placement option (addon 0.17.38):** restored Blizzard-style ToT name placement as the default: the name now sits below the HP/power stack. Added **Name Above Bars** under Unit Frames -> Target of Target to opt back into the compact above-bars placement introduced with the revised artwork. HP/power/art/portrait geometry is unchanged.
- **Target-of-Target art alignment follow-up (addon 0.17.37):** nudged the revised ToT name down 1px (`Y 1 -> 2`) and power bar up 1px (`Y 28 -> 27`) after in-game alignment testing. Health bar, portrait, artwork, and debuff geometry are unchanged.
- **Target-of-Target artwork refresh (addon 0.17.36):** replaced the fixed ToT frame artwork with the new 128×64 source while retaining the canonical `UI-ToT-Portrait.tga` asset path. The ToT name, health bar, and power bar anchors each move down exactly 2px to fit the revised openings: name Y `-1 -> 1`, health Y `15 -> 17`, and power Y `26 -> 28`. Portrait geometry, secure Blizzard ToT visibility ownership, and the independent ToT debuff surface are unchanged.
- **Diagnostic cleanup after validation (addon 0.17.35):** removed the temporary `/tf debug taint` and `/tf debug levelup` systems now that the Quick Setup one-shot action-bar path and level-up hitch fixes have been validated in repeated play. All taint ring-buffer/event hooks, secure-variable probes, level-up MeasureCall wrappers, and their runtime callsite branches are gone. Users upgrading while the taint tracer was armed have their saved pre-debug `taintLog` value restored once and the temporary cache keys cleared. The actual fixes remain: Quick Setup releases its temporary action-bar state drivers after bootstrap, Class Buffs/Class Features no longer rebuild on every level, Skill Tracker updates caps in place, and hidden Trainer Spells defers its heavy list rebuild until shown.
- **Level-up hidden Trainer rebuild fix + trace expansion (addon 0.17.34):** the 0.17.33 capture showed only ~20 KB of allocations inside the instrumented XP/Splits/Skills/UnitFrame handlers while TurboFace-attributed memory still rose by ~6.7 MB. The missing level-up consumer was Trainer Spells: its hidden Spellbook `ClassFrame` remained subscribed to `PLAYER_LEVEL_UP` and rebuilt the complete class/skills list plus a new ScrollBox data provider even while the panel was closed. Hidden Trainer panels now only mark their list dirty (while retaining the lightweight shared skill-cache invalidation); `OnShow` performs the already-existing authoritative rebuild when the user actually opens the panel. Trainer class-list events are now included in `/tf debug levelup` allocation timing when visible, and Grocery's visible-only level refresh is instrumented as well.
- **Level-up hitch reduction + targeted profiler (addon 0.17.33):** removed two unnecessary synchronous `PLAYER_LEVEL_UP` cache rebuilds from Class Buffs and Class Features; leveling alone does not change learned spells, localized spell names/icons, or reactive-ability ownership, while talent-point changes already have their own event. Skill Tracker now updates the cached weapon/Defense `5 * level` cap in place instead of invalidating and rebuilding the shared skill-line scanner solely because the character leveled. Added opt-in `/tf debug levelup on|report|off|clear`: the next level captures a 2.25-second native `C_AddOnProfiler.MeasureCall` window for wrapped TurboFace level-up boundaries, including elapsed time, allocations/deallocations, and addon/Lua-memory deltas. The existing taint tracer and Speedrun Splits storage/display behavior are unchanged.
- **Quick Setup one-shot runtime ownership (addon 0.17.32):** tightened the 0.17.31 no-reload action-bar experiment so Quick Setup does not remain an action-bar visibility owner after bootstrap. `RegisterStateDriver()` is now used only while the staged restore/retry is active; finalization explicitly calls `UnregisterStateDriver()` for every temporary bar driver. If finalization occurs during combat, cleanup waits only for `PLAYER_REGEN_ENABLED`. Restore-only `EDIT_MODE_LAYOUTS_UPDATED` / `PLAYER_REGEN_ENABLED` listeners are then released as soon as no staged job, deferred Edit Mode selection, or driver cleanup remains. Snapshot capture remains explicit-only through **Save Class Profile**; automatic setup reads the stored snapshot once, applies it, marks the GUID, and becomes dormant. Manual **Apply Stored Profile** also no longer installs action-bar drivers before its pending early-CVar handoff actually begins the staged restore.
- **Quick Setup no-reload secure state-driver experiment (addon 0.17.31):** the 0.17.30 reproduction showed that even `securecallfunction(Settings.SetValue, PROXY_SHOW_ACTIONBAR_*)` still contaminates Blizzard's later `ActionBarMixin:UpdateShownButtons()` path and can block individual `ActionButton:SetShown()` calls in combat. Quick Setup no longer writes the live Blizzard Settings proxies or calls `MultiActionBar_Update()` at all. Changed Bars 2-8 are persisted with `SetActionBarToggles()` for the next normal login while the current session is mirrored immediately with `RegisterStateDriver(frame, "visibility", ...)`, the secure Blizzard-supported mechanism for protected-frame visibility. Visible secondary bars use vehicle/override/possess-aware conditions; hidden bars use a constant secure hide driver. These state drivers are session-local and disappear naturally on the next login, when Blizzard's persisted native setting takes over. The taint report also gained per-incident probes for the affected action bar's `actionButtons`, `shownButtonContainers`, `numButtonsShowable`, and button `index/bar/container/_tfPowerOverlay` fields so a remaining failure can identify the poisoned value more precisely.
- **Quick Setup live action-bar restore (addon 0.17.30):** removed the normal `/reload` dependency for Blizzard Action Bars 2-8 during automatic fresh-character setup. Classic Era's own action-bar controller uses `Settings.SetValue(PROXY_SHOW_ACTIONBAR_*)` plus `MultiActionBar_Update()` for live changes; TurboFace now enters those Blizzard functions through `securecallfunction()` so addon execution taint is not propagated into protected `SetShown()` calls. Saved values are applied only out of combat, verified through the Settings proxy, and followed by a secure Blizzard `MultiActionBar_Update()`. `SetActionBarToggles()` remains only as a no-reload fallback that queues failed live changes for the next normal login. The taint debug report now also probes `securecallfunction` and `MultiActionBar_Update`. Manual **Apply Stored Profile** still uses a user `/reload` for its separate early-CVar ownership handoff.
- **Quick Setup protected reload fix (addon 0.17.29):** removed all programmatic `ReloadUI()`/`Reload()` calls from `QuickSetup.lua` after Classic Era 1.15.9 blocked the automatic action-bar handoff with `ADDON_ACTION_BLOCKED ... Reload()`. Automatic fresh-character setup now continues restoring macros, bindings, and actions in the current session while any changed Blizzard Action Bars 2-8 visibility is queued safely for the next login or user `/reload`. **Apply Stored Profile** now persists its early-CVar handoff, queues next-load bar toggles, and explicitly asks the user to type `/reload`; the post-reload startup path resumes the staged restore. No protected reload is attempted by addon code.
- **Quick Setup action-bar taint fix (addon 0.17.28):** the taint diagnostic reproduction tied the new protected action-bar failures to Quick Setup's live `Settings.SetValue(PROXY_SHOW_ACTIONBAR_*)` restore path. Quick Setup no longer reads or writes Blizzard action-bar visibility through the Settings proxy. Save/restore now uses the dedicated `GetActionBarToggles()` / `SetActionBarToggles()` API through `Core/Compat.lua`; changed bar states are queued as next-load preferences and cross a clean reload boundary before automatic/manual setup continues. The 0.17.27 taint tracer remains available for verification.
- **Action-bar taint diagnostics (addon 0.17.27):** added `/tf debug taint on|report|off|clear`. The opt-in trace enables Blizzard `taintLog=2`, listens for `ADDON_ACTION_BLOCKED/FORBIDDEN`, retains a short ring buffer of TurboFace action-bar mutation boundaries (Quick Setup action placement/cleanup and Blizzard bar-option writes, Plus action-button text hiding, and PowerCost overlay creation), and reports secure-variable probes without hooking protected Blizzard functions. This diagnostic build intentionally does not change Quick Setup restore behavior so a clean reproduction can identify the original contaminating path.
## Unreleased — Settings baseline and Unit Frame ownership

- **Loot Frame three-column slider layout (addon 0.17.26):** reorganized the Speedrun → Loot Frame sliders into the shared three-column control grid. Width/Row Height/Icon Size, Spacing/Scale/Font Size, and Background Alpha/Visible Duration/Max Visible Items now each share a row; behavior and ranges are unchanged.

- **Speedrun tab category order (addon 0.17.25):** reorganized the Speedrun tab as **Lvl1 Quick Setup, Speedrun Splits, Loot Frame, Net Worth, Junk & Inventory, Free Bag Slot Counter, Grocery List, Trainer Spells, Luxthos-like XP Bar, Hearthstone Tracker, Hearthstone Batching, FPS Counter, UnstuckSkips Notifier, Skill Tracker, Enemy Leash Timer**. This is a presentation-only reorder; feature gates, dependencies, storage paths, and runtime ownership are unchanged.

- **Lvl1 Quick Setup Speedrun UI cleanup (addon 0.17.24):** moved **Lvl1 Quick Setup** to the top of the Speedrun tab, removed its standalone description paragraph, and moved the concise feature summary into the section tooltip.

- **Lvl1 Quick Setup control separation (addon 0.17.23):** removed the category-header gate from **Lvl1 Quick Setup**. **Auto-skip Level 1 cinematic** is now the first independent option, followed by **Enable Automatic Lvl1 Quick Setup**, which alone controls fresh-character profile restoration. Cinematic skipping no longer depends on the automatic-restore toggle.

- **Rumblecrush preset module-gate fix (addon 0.17.22):** restored the `modules` branch that was accidentally omitted from the 2026-09-09 sparse preset snapshot. The preset now preserves the checked parent gates for Map, Flight Bar, Automation, Social, Interface, Chat, System, and Minimap, plus Hotbar Power and the other enabled top-level module families. Child Plus settings were already present; this fixes the parent/child mismatch without a schema change.

- **Lvl1 Quick Setup integration (schema 75 / addon 0.17.21):** integrated the maintained
  Lvl1QuickSetup 1.0.4.9 restore engine as the native root `ns.QuickSetup` subsystem under Speedrun.
  Automatic fresh-character setup remains off by default and preserves the Level-1/0-XP gate, GUID
  recreation detection, three-attempt bootstrap safety, staged multi-frame restore, place-before-clear
  action safety, slots 1-180, character bindings, macro scope synchronization, Blizzard Action Bars
  2-8, Edit Mode resolution, and delayed missing spell/item retries. Class setup data now lives in
  `TurboFaceProfilesDB.quickSetup.classes`, character bootstrap state in `TurboFaceCharDB.quickSetup`,
  and ordinary TurboFace settings only store the Quick Setup enable/options table.
- **Portable Quick Setup profiles:** added **Export Lvl1QuickSetup** / **Import Lvl1QuickSetup** beneath
  the existing Settings and XP Split transfer rows. `TFL1QS1:` exports select among stored class
  profiles; imports detect and validate the embedded class token and replace only that class profile
  without touching the active character or requiring a reload. The validator allowlists profile
  fields, Classic class tokens, action slots/types, Blizzard bar/Edit Mode data, and Quick Setup CVars.
- **Quick Setup CVar/cinematic ownership:** class saves capture a defined persistent CVar allowlist
  instead of shipping standalone `ConsoleVariables.lua`. Eligible automatic restores and manual applies
  apply that baseline immediately after DB load, before Plus/System can acquire temporary CVar owners;
  the staged restore never rewrites CVars later. Level-1 automatic cinematic skip now belongs solely to
  Quick Setup, and the former Plus `fasterMovieSkip` implementation/key is retired. Guidelime/RXP and
  the standalone WeakAuras/Scrap/Peddler/ActionbarPlus baggage were deliberately not integrated.
- **Compatibility boundary:** action-bar, macro, item-pickup, and CVar API drift used by Quick Setup now
  routes through `Core/Compat.lua` / `ns.API` instead of maintaining a second local compatibility layer.

- **Flight Bar simplification (schema 74):** made the category-enabled Flight Bar automatic on
  known taxi routes, with background, destination text, and fill-forward progress now fixed parts
  of its presentation. Removed their individual toggles and completely removed the remaining-time
  TTS setting and runtime. Width and scale are now the only Flight Bar settings. Migration and
  current-schema guards remove all five retired saved keys from existing profiles and imports.
- **Plus category order:** reorganized the Plus tab as **Map, Flight Bar, Automation, Social,
  Interface, Chat, System, Minimap, Minimap Tracking Icon**. The change affects presentation order
  only; all section gates, storage paths, reload requirements, and live refresh owners are preserved.
- **XP mover ownership:** removed the obsolete `XPBar` mover for Blizzard's native XP/status bar,
  whose placement now belongs to HUD Edit Mode. The remaining `ExperienceBar` mover is TurboFace's
  custom bar and is now labeled **Luxthos-like XP** in both Options and the mover overlay. Schema 73
  removes stale `movers.elements.XPBar` data and clears it as the active mover when necessary.
- **Movers organization:** replaced Unit Frame Movers, Aura Movers, Combat Timer Movers, and System
  Bar Movers with two ownership-oriented lists beneath Mover Mode. **Blizzard Movers** contains
  Target of Target, Quest Tracker, Minimap Clock/Icon/LFG, Loot Roll Frames, Latency Bar, Tooltip,
  Blizzard Loot Window, and Target/ToT aura elements; every remaining element now appears under
  **TurboFace Movers**. Aside from the separately retired Blizzard `XPBar` mover, saved mover keys
  and runtime behavior are unchanged. Also fixed the Druid Power Bar option's class lookup so it is
  reliably included for Druids.
- **XP session profiles:** moved XP run/session history from account-wide
  `TurboFaceDB.experienceBar.session` to per-character `TurboFaceCharDB.experienceBarSession`.
  Ordinary named profiles, presets, and `TF1:` settings exports now exclude XP history, including
  legacy embedded sessions. Added dedicated **Export XP Splits** / **Import XP Splits** buttons
  directly beneath the Settings buttons in **Profile -> Import / Export**, backed by a strict
  `TFXP1:` data-only format. Importing replaces only the current character's session, applies live,
  and does not reload or modify settings. Schema 72 migrates the current legacy session without
  overwriting an existing per-character session.
- **Factory defaults:** adopted the audited schema-71 user configuration as the new shipped baseline.
  Prediction defaults now enable DoT and Heal overlays; Hotbar Power, FPS, Hearth, Unstuck, Grocery,
  Tracking, Experience Bar, and unused Plus sections start disabled; Net Worth and the two Map tools
  start enabled. Unit Frame value formats, font sizes, NanShield per-school text, Player Tick amount
  presentation, Loot Frame dimensions, Inventory marking shortcut, Nameplate friendly presentation,
  mover availability, power-bar height, overlap, and non-selected alpha now match the supplied profile.
  XP session history, editor selection state, and resolution-specific mover coordinates were excluded.

- **Shared Aura Styling baseline:** promoted Rumblecrush's Aura presentation to the canonical
  factory defaults. Player/Target styling and ToT styling now default enabled; timer and aura text
  use the preset's 11px Outline presentation; Target buff/debuff and ToT scales default to 1.3;
  nameplate buff/debuff dimensions, debuff Y offset, and Party class reminders match the audited
  preset values. Removed the duplicate Aura keys from Rumblecrush's dated preset so Factory
  Defaults, that preset, and future differential presets inherit one source of truth. Existing
  saved user choices remain intact until the user resets or applies a preset.
- **Unit Frame options:** removed the combined `Health & Power Text` category and placed each
  Health/Power Text format under its owning Player, Target, Target-of-Target, Pet, or Party section.
  Player now owns its static Health Color control, while Target owns Tagged Mob Grey. Bar Border
  Color and the Class Color, HP%-based, Friendly Health, and Enemy Health policies remain General
  because runtime applies them across multiple non-player frame types. The post-master category
  order is now General, Shield Bars, Player, Target, Target of Target, Pet, Party.
- **NanShield text:** enabled remaining-absorb text by default and exposed Show Absorb Text plus
  Per-School Amounts in the Shield Bars section. NanShield now owns dedicated Text Font, Text Style,
  and Text Size settings shared by its Player and Priest Party presentations instead of borrowing
  general Unit Frame bar typography. The renderer explicitly establishes opaque white glyph color,
  and the visibility toggle now consistently gates combined, per-school, and Party values. Schema
  69 initializes the new typography from each existing profile's former Bar settings and enables the
  previously inaccessible number.
- **Player Tick Marker options:** added the missing Health marker border toggle and independent
  Health Border color; the renderer no longer hardcodes Health's border on or borrows Mana's border
  color. Reordered the section so all marker gates, geometry, and marker/border colors come first,
  followed by the HP/Power `+X` gates and their complete font, style, size, and offset group. Schema
  70 initializes the new Health border settings without changing the prior visible appearance.
- **Nameplates options:** removed the Nameplates, Job Icon, Nameplate Swing Timer, and Threat Number
  subsection headers. Every setting now lives directly beneath the TurboFace Nameplate Enhancements
  master in a single master-gated surface. Checkbox rows explicitly fill the shared three-column grid,
  and sliders retain the standard left-to-right three-column flow. Overlap Power Bar, Show Threat
  Number, and Mute Aggro Sounds now each own a dedicated row with their related height, font-size,
  and volume sliders immediately beside the controlling checkbox. Renamed Stacked Plate Spacing to
  Overlap Vertical and moved the nameplate CVar controls above the checkbox grid. Added live Overlap
  Horizontal, Selected Scale, Selected Alpha, and Not Selected Alpha sliders; all five settings use
  the module's reversible CVar ownership and restore the user's captured values when disabled.
- Added regression contracts for both the shared Aura default/preset boundary and Unit Frame option
  ownership, plus NanShield text visibility and typography.

## 0.17.20 — Deterministic nameplate DoT refresh and menu-safe DPS badge

- **Nameplate DoT prediction:** registered the nameplate renderer as an explicit prediction consumer.
  `UNIT_AURA` invalidation now repaints the current mapped plate immediately instead of waiting for an
  incidental health event, fixing the intermittent case where a known DoT prediction existed but its
  nameplate overlay did not appear. The callback resolves the pooled plate at notification time and
  verifies its cached GUID before rendering.
- **Player DPS/HPS badge layering:** moved the independent UIParent badge from `HIGH` to `MEDIUM`
  strata while retaining frame level 100. It remains above PlayerFrame glow/art and TurboFace baked
  swing/cast rows, but Blizzard's higher menu strata now cover it normally.

## 0.17.19 — Feature-local Blizzard typography

- **Release baseline / branding:** TurboFace now uses Blizzard FileID **237572** as the canonical addon identity. The minimap button references the FileID directly and `TurboFace.toc` declares `## IconTexture: 237572` for Blizzard's AddOns list.
- **Presets/defaults:** re-audited the schema-68 Factory Defaults and Rumblecrush differential. The shipped built-in preset list is intentionally only Factory Defaults + Rumblecrush's Preset - 2026-09-09.
- **Player tick amount typography:** removed the last legacy `STANDARD_TEXT_FONT + OUTLINE` initialization from pooled `+X` regen text. `power.tickFont`, `power.tickTextStyle`, and `power.tickAmountSize` are now the sole owners and existing pooled FontStrings restyle immediately on refresh.
- **Badge presentation:** Player/Target Level badges and the independent DPS/HPS badge now settle on **50%** black backing opacity; Level-badge refreshes preserve that value instead of restoring full opacity. DPS/HPS badge text uses TurboFace's native FontObject Shadow styling at black `2,-2`.
- **Known issue under investigation:** live testing has reported an intermittent miss where Nameplate DoT prediction occasionally fails to render. No speculative fix is recorded here yet; the nameplate consumer/recycle/dirty-refresh path remains under investigation.

- Player/Target Level badges and the independent DPS/HPS badge now share one explicit 50% black background opacity. Badge darkness is controlled only through Texture:SetAlpha; the old Level-badge refresh path that hard-pinned object alpha back to 1.0 is removed, fixing the long-standing case where Level badge transparency changes appeared to have no effect.
- Druid Power Bar now owns Text Font, Text Style, Text Size, and Text Format settings; added Percent Current (Blizzard) dual text (percent left, current right).
- Unit Frames: split typography into independent Name and Bar families. Player/Target/ToT/Pet/Party names use Name Font / Name Text Style, while HP/Power/NanShield/value text uses Bar Font / Bar Text Style. Public defaults are Blizzard Default + Shadow for names and Blizzard Narrow + Outline for values. Party, Pet, and ToT now each own dedicated Name Text Size and Bar Text Size sliders; Player/Target retain the shared base size pair. Party NanShield text follows Party Bar Text Size, and the stale Party-only forced-shadow override is removed so all unit names honor the shared Name Text Style.

- Druid Power Bar presentation is now Class-owned and automatically dual-mode. With the TurboFace Player Unit Frame enabled it keeps the existing baked-in reserved-art slot and follows that frame's power-bar texture. With the Player Unit Frame disabled it becomes a 12px standalone bar beneath Blizzard's player power bar, uses the shared Blizzard Tooltip border plus its Class `Standalone Bar Texture`, and exposes its own standalone-only `DruidPowerBar` mover. Untouched standalone player swing rows stack beneath the Druid bar while it is visible so the two default placements cannot overlap; explicit swing mover positions still win.
- Release cleanup: removed stale unused third-party dependency metadata and a dead nameplate-specific conflict branch. `OptionalDeps` now lists only the two addons with intentional runtime integrations: Baganator and UnstuckSkips. The temporary `/tf debug fontshadow` A-G visual probe used to reverse-engineer Classic's FontObject shadow behavior is also removed now that the production path is proven.
- Options dependency layout: subordinate checkboxes now sit directly beneath their parent toggle in the same three-column grid column with a 16px indent and are dimmed/disabled while the parent is off. Independent controls continue to fill separate columns. Applied to Hotbar Power custom colors, nameplate full-width health centering, regen marker borders, Druid status text, Skill Tracker equipped-weapon filtering, Plus automation dependencies, whisper-invite friend filtering, and quest difficulty tags.
- Options layout: converted the standard control grid from two columns to three across the full 504px scroll-child width (164px columns at x=0/170/340). Sliders and dropdowns now fill left → middle → right before wrapping, Hotbar Power Overlay uses all three columns for its top toggles, and Movers repacks its element lists into the same three-column grid. Deliberately wide 300px Plus controls remain full-row.
- Options sliders: every cyan slider value is now a direct-entry EditBox as well as a live readout. Clicking the value selects it for typing; Enter or focus loss validates and applies numeric input within the slider's existing range, snaps it to the configured step, and keeps the slider synchronized. Escape and non-numeric input restore the previous valid value. Numeric input above/below the range clamps to the configured maximum/minimum, and the editable value field is layered above the slider so clicks anywhere inside the box cannot move the slider. Percentage-style sliders accept the displayed units (for example `75` or `75%` for an underlying `0.75`).
- Nameplates: the Name Text Shadow setting replaces the duplicate-glyph workaround with the proven native FontObject route. TurboFace clones Blizzard's live nameplate face/size/flags (including `SLUG`) into a private FontObject and applies a black `2,-2` shadow; `/tf debug shadow` reports the active mode and verifies no duplicate underlay exists.
- Shadow cleanup: Threat Number, FPS Counter, and Free Bag Slots now use a single FontString with the same native FontObject-owned black `2,-2` shadow. Their old duplicate black glyphs are removed; stale hidden compatibility shadow children in Skill Tracker and Net Worth are removed as dead code.
- Speedrun: FPS Counter is now a standalone feature with `fpsCounterEnabled` in the Speedrun tab. It retains a fallback position when Movers is disabled; the `FPSCounter` mover only owns optional placement/hide/click-through. Hearthstone Batching now formally requires FPS Counter: enabling batching also enables the counter, while disabling the counter disables batching. Runtime batching is inert without the dependency.
- Options typography: category headers, collapse glyphs, and the TurboFace Config title now route their intentional `OUTLINE` presentation through the same cached FontObject renderer instead of mutating individual FontStrings with `SetFont(..., "OUTLINE")`. Ordinary option labels continue to inherit Blizzard `GameFont*` FontObjects and their stock native shadows.

- Typography: Classic Era shadow probing confirmed Blizzard's `PlayerName -> GameFontNormalSmall -> SystemFont_Shadow_Small` FontObject inheritance chain. TurboFace now mirrors that native ownership model: `Shadow` is a cached runtime FontObject using Blizzard's native shadow mechanism with TurboFace's stronger black 2,-2 offset (stock `SystemFont_Shadow_Small` is 1,-1), assigned through `SetFontObject()` rather than direct FontString `SetShadow*()` calls. Outline/None use the same complete FontObject path so live style changes cannot retain stale inherited shadow state.

Replaced the old addon-wide Font/Text Style inheritance model with explicit feature-local
typography ownership. TurboFace now exposes only four portable Blizzard-owned font choices --
**Blizzard Default**, **Blizzard Narrow**, **Blizzard Quest**, and **Blizzard Combat** -- and
ships no font assets. The aliases resolve through Blizzard FontObjects at runtime for locale-safe
client fonts. Typography no longer queries LibSharedMedia; unknown/external font names normalize
to Blizzard Default, so the public typography baseline is fully self-contained.

Removed the Global Font/Text Style options and all user-facing `INHERIT` semantics. Added local
Font/Text Style controls to Unit Frames, Auras, Hotbar Power, Player tick amounts, Combat Meter,
Swing Timers, Cast Bars, Class text, Speedrun Splits, Skill Tracker, Enemy Leash Timer, Net Worth,
Hearthstone Tracker, UnstuckSkips, Luxthos-like XP Bar, and Loot Frame. Fixed Player/Target aura
timers ignoring the dedicated aura face, Hearthstone/Unstuck inheriting UnitFrame typography,
regen tick amounts forcing a second shadow after the selected style, Druid Power Bar status text
incorrectly following Unit Frame typography, and Combat Meter header selectors not restyling live. Skill Tracker and Net Worth retire their visible duplicate-shadow
rendering in favor of the shared FontString-native style path. TurboDebuffs now uses an explicit
local presentation instead of the stale ignored `SetFontSafe(..., "OUTLINE")` argument.

DB schema 64 retires the former `globalFont`, root `textStyle`, and `auraTimerFont` keys. Because
this boundary is still pre-public-release, development-era typography profiles are not guaranteed
to preserve their old appearance; current feature-local defaults are the clean baseline. Schema 65
adds the standalone `fpsCounterEnabled` gate while preserving the previous visible-by-default behavior.
Schema 66 splits UnitFrame Name typography from Bar/value typography. Schema 67 gives Party, Pet,
and ToT independent Name Text Size and Bar Text Size settings while keeping the shared font/style
families. Schema 68 gives the Druid Power Bar dedicated font/style/size/format ownership. Rumblecrush's
2026-09-09 preset is authored directly against schema 68, with Blizzard
Default + Shadow names and Blizzard Narrow + Outline bar/value text.

## 0.17.18 — Release configuration and preset audit

Completed the pre-public-release configuration pass. Rebuilt **Rumblecrush's Preset -
2026-09-09** from the current schema-62 live export as a clean schema-63 differential
preset, preserving current feature choices and mover layout while dropping runtime/session
state and retired settings from older TurboFace generations. Factory Defaults now declares
the live schema directly instead of replaying the entire historical migration chain.

The canonical defaults table now owns the addon-wide font/text-style defaults and the
Grocery Button mover entry. No user-facing factory behavior was changed in this audit:
destructive/experimental features remain opt-in, while existing core visual defaults stay
as shipped. DB schema 63 prunes dead Leatrix Maps/quest-automation fields, retired Class/
Druid/Net Worth/Grocery/TurboDebuffs keys, stale combat-timer mover containers, and the
old Power compatibility flags/fields. The former Power self-migrations are now versioned
once in `Core/Migrations.lua`, so current exports no longer need migration guard state.

Normalized the minimap-button drag angle to one 0-359 degree turn, preventing historical
multi-turn values from bloating profiles while preserving the exact position. Also removed
the now-fixed nameplate debuff stack-anchor setting from persisted defaults.

Finished the release options-panel sweep: the Class tab no longer carries description
blocks; Minimap Tracking Icon now lives under Plus; Speedrun sections use concise category
tooltips plus only the requested warnings; Hearthstone Tracker and Luxthos-like XP Bar use
their final names; and the Hearthstone Batching-to-XP section spacing no longer overlaps.
Speedrun Splits keeps its footer anchored to the rendered last row with a half-row visual gap
before `Total`.

## 0.17.17 — Speedrun Splits footer anchoring

Anchored the Speedrun Splits `Total` footer directly to the rendered bottom of the split-label column
instead of estimating the table height from row count and configured font size. This removes the
font/style/UI-scale-dependent blank gap that could appear after the final visible level row.

## 0.17.16 — Classified target-art pixel correction

Corrected the Elite, Rare, and Rare Elite TGA sheets themselves by shifting their pixels 1px left
inside the unchanged 256×128 canvas. The earlier runtime anchor adjustments could not affect the
reported gap because target health and power bars are anchored to that same texture and moved with it.
All target sheets now share the normal runtime anchor, while an asset-level regression check verifies
that both active bar openings occupy the normal sheet's border coordinates.

## 0.17.15 — Classified target-art second alignment pass

Moved the Elite, Rare, and Rare Elite target artwork one additional pixel left (two pixels total
relative to the normal target sheet) after in-game inspection showed the first compensation was still
one pixel short. Because the bars share that texture as their anchor, this did not change the relative
gap and was superseded by the asset-level correction in 0.17.16.

## 0.17.14 — Blizzard rarity-icon position

Added an opt-in Nameplates setting that moves Blizzard 1.15.9's existing Elite, Rare, and Rare Elite
classification texture from the left side to the right edge of the native nameplate. Blizzard still
owns the Rarity Icon information setting, classification/atlas choice, scale, visibility, raid-target
suppression, and PvP indicators. TurboFace moves only the texture—not its parent classification frame,
which Blizzard also uses as an aura-layout anchor—and restores the exact native texture anchor when the
setting is disabled or a pooled plate is recycled.

## 0.17.13 — Classified target-art alignment

Pixel inspection confirmed that all three new classification sheets place their health/power
openings one pixel to the right of the normal target sheet. Elite, Rare, and Rare Elite artwork now
uses a 1px-left texture-anchor compensation, eliminating the right-edge bar gap while leaving the
shared bar geometry and normal target art unchanged.

## 0.17.12 — Target classification artwork

Added dedicated 256x128 TurboFace target-frame sheets for Elite, Rare, and Rare Elite targets.
`UnitClassification("target")` now selects the sheet in the existing guarded target-art reassertion
path; World Bosses share Elite artwork and all other classifications retain the normal target sheet.
Target changes explicitly refresh the selection, while the Blizzard classification post-hook keeps
the chosen art authoritative during native target-frame updates.

## 0.17.11 — Unit Frames blank scroll-tail fix

Removed the 2000px placeholder height used when registering options scroll children. Classic could
retain that initial rectangle after the lazy builder shortened the Unit Frames tab, creating a large
blank scroll range below Party. Section layout now explicitly refreshes the scroll-child rectangle
and clamps stale vertical offsets whenever the measured content height changes.

## 0.17.10 — Unit Frames option-panel cleanup

Shortened the Unit Frames master description to the fixed Classic-style artwork summary. Removed
the permanent descriptions from its later categories. Shield Bars retains the sole post-master
feature summary as a category tooltip: `TurboFace-native NanShield replacement`.

## 0.17.9 — Player Bar Tick Markers tooltip

Extended independent section headers to support the shared wrapped, cursor-anchored tooltip framework.
Player Bar Tick Markers now has a concise placeholder summary covering mana, energy, health-regeneration,
and five-second-rule timing markers.

## 0.17.8 — Wrapped cursor-anchored category tooltips

Category-header descriptions now open at the cursor and use a wrapped 320px width cap. This keeps
long feature summaries readable across multiple lines instead of stretching the tooltip across the
screen. The behavior is centralized in the shared category header framework.

## 0.17.7 — Nameplates option-panel cleanup

Renamed the Nameplates parent control to `Enable TurboFace Nameplate Enhancements`. Removed the
tab's permanent description blocks. Threat Number now owns the tab's sole feature-description
tooltip, with concise placeholder copy explaining its below-100, aggro-at-100, and above-100 threat
display.

## 0.17.6 — Global category tooltip cleanup

Moved the DoT Prediction, Heal Prediction, Combat Meter, Player DPS/HPS Badge, Auras, Swing
Timers, and Cast Bars descriptions into their category-header hover tooltips. Removed their
permanent description blocks to make the Global panel substantially more compact.

## 0.17.5 — Classic-safe category tooltips

Changed category-header descriptions to the cross-version-safe one-argument
`GameTooltip:SetText(text)` form. Classic Era 1.15.9 rejects the legacy five-argument color/wrap
overload that was initially used, causing a Lua error when the Hotbar Power Overlay header was
hovered.

## 0.17.4 — Category-header description tooltips

Added reusable hover descriptions to collapsible options category headers. Hotbar Power Overlay is
the first converted section: hovering its header shows `TurboFace-native MissingPower features`, and
the former multi-line description block at the bottom of the category has been removed to reduce
vertical space.

## 0.17.3 — Movers option-panel cleanup

Replaced the redundant description under `Enable TurboFace Movers` with the practical `/tf move`,
drag, nudge, Hide, and Click-through instructions that previously appeared again lower in Mover Mode.
The lower duplicate was removed. Normalized the space between the last Aura Movers row and Combat
Timer Movers to match the other mover categories.

## 0.17.2 — Options organization

Moved Movers to the first position in the TurboFace options tab bar. The six target aura-layout
controls (icons per row, horizontal/vertical spacing, Target buff/debuff growth, and ToT debuff
growth) now live in Global -> Auras instead of Movers -> Aura Movers. Their existing
`movers.aura` saved keys and live refresh behavior are unchanged; Aura Movers now contains only the
three actual mover elements.

## 0.17.1 — Loot Frame vendor values

Added a `Show vendor value` toggle to the Speedrun tab's Loot Frame settings. Item rows now show
their total vendor sell value right-aligned inside the frame, including combined stack quantity;
money rows and unsellable items leave the column empty. Delayed item-info completion refreshes active
rows so uncached item prices do not remain missing. Schema 61 enables the new column by default.

## 0.17.0 — UnstuckSkips notifier visual hook

Added an optional TurboFace visual for the separately maintained UnstuckSkips addon without copying
its routing data or target-selection logic. TurboFace delegates target refresh to the loaded addon's
notifier and presents the result as a Hearthstone-style row: green `Ready` or an `H:MM:SS` timer,
`UnstuckSkip: <target>`, and a checkbox. Checking the box starts a four-hour estimate stored as an
absolute per-character server timestamp, so time spent logged out counts; unchecking clears it.

The TurboFace visual suppresses only UnstuckSkips' original notifier while active and restores it when
disabled if the source addon permits it. The row is mover-owned, uses shared fonts and cadence, and
remains absent when UnstuckSkips is not loaded. Schema 60 adds the feature and its interactive mover.

## 0.16.8 — Font-safe split timer separator

Replaced the Unicode right arrow in the Speedrun Splits total-timer line with an ASCII hyphen. WoW
fonts that do not contain the arrow glyph no longer render a missing-character rectangle between the
next checkpoint label and its segment timer.

## 0.16.7 — Seed missing Race/Class PB checkpoints

Restored the original SpeedrunSplits baseline behavior: completing a checkpoint now automatically
fills that Race/Class PB entry when no prior value exists. TurboFace applies this to partial checkpoints
as well as whole levels, allowing a future character of the same Race/Class to compare against every
recorded tenth. Each active run still holds a frozen PB reference, so newly seeded values do not create
self-comparisons. Manual Save and the configured automatic PB save level retain their overwrite behavior.

## 0.16.6 — Hide the synthetic Level 1 split

Removed the visible `Level 1  0:00` row from both whole-level and partial-level views. Level 1 remains
stored internally as the zero-time anchor used for split calculations, while the partial display now
begins at 1.1 and the whole-level display begins at Level 2.

## 0.16.5 — Fresh-character partial splits survive level-up

Fixed level 1 partial checkpoints being cleared when a fresh character reached level 2. Classic can
deliver `PLAYER_LEVEL_UP` with the new level in the event argument while `UnitLevel("player")` still
briefly reports the previous level. The same-character recreation safeguard no longer runs during
that transient event window; it is restricted to `PLAYER_ENTERING_WORLD`, where the unit level is
stable. A runtime regression test covers 1.1 through 1.9 followed by this exact delayed level update.

## 0.16.4 — Multi-hop flight segment resolution

Fixed chained flight-map tooltips still missing after the destination-type correction. Route keys are
now built from Classic's ordered source and destination coordinates for every flight segment, so a
route such as Thunder Bluff -> Crossroads -> Ratchet includes the intermediate stop during hover.
The older node-slot reconstruction remains as a compatibility fallback when segment APIs are absent.
A runtime regression test now exercises that exact Horde route and requires `Flight Time: 3:30`.

## 0.16.3 — Chained flight tooltip lookup

Fixed known chained flights such as Thunder Bluff -> Crossroads -> Ratchet missing their tooltip
duration. Classic can report a valid multi-hop destination as `DISTANT`, so tooltip lookup no longer
rejects a node solely because it is not classified as a direct `REACHABLE` flight. The existing
multi-hop route resolver and route database remain authoritative: if the complete route resolves, the
tooltip is shown. The label is now the shorter `Flight Time: M:SS`.

## 0.16.2 — Flight-path hover estimates

Flight-map destination tooltips now show `Estimated flight time: M:SS` for reachable routes known
to TurboFace. Tooltip estimates and the active Flight Bar share the same faction, continent, and
multi-hop coordinate-key resolver, preventing the two surfaces from drifting or duplicating route
logic. Unknown and unreachable nodes leave Blizzard's tooltip unchanged. The normal Classic taxi
hover handler is used when available, with an event-driven taxi-map fallback for lazily created
buttons; no polling or additional timing data was added.

## 0.16.1 — In-widget partial-level toggle

Added a button directly beneath the Speedrun Splits total timer. It reads `Hide Partial Levels` when
partial rows are visible and `Show Partial Levels` in whole-level mode, switching the view immediately
without changing the underlying partial checkpoints being recorded. The Speedrun Splits mover now owns
the button as an interactive child and defaults click-through off; schema 59 corrects that default for
profiles that initialized the 0.16.0 mover.

## 0.16.0 — Native Speedrun Splits with partial levels

Added a clean TurboFace-native Speedrun Splits module based on the behavior of the user-supplied
SpeedrunSplits 2.4 reference addon. The supplied archive contains author metadata but no license, so
TurboFace does not copy or execute its implementation. Instead, the new module uses TurboFace's own
module lifecycle, shared cadence, font system, Movers, options, CPU profiler, and saved-data boundaries.

Splits now track both full levels and every 10% XP checkpoint (`12.1` through `12.9`). Current-run
checkpoints and a frozen PB reference are stored per character, while race/class PBs and best segment
times are stored in a dedicated account-wide database outside profile exports. Timing anchors one
authoritative `/played` response to the monotonic client clock; XP and level events record checkpoints,
and the shared 1 Hz cadence runs only while the display is visible. This replaces the reference addon's
permanent private `OnUpdate`, repeated string/layout setup, global function surface, and standalone
settings panel.

The Speedrun tab now includes live settings for partial rows, next split, deltas, colors, long-duration
formatting, row count, auto-save level, font size, and scale, plus Save, Reset, and legacy Import actions.
The `SpeedrunSplits` mover controls placement and visibility. `/tfsplits save|reset|print|import` exposes
the same run controls from chat. Legacy import is intentionally data-only and is available when the
original addon is loaded alongside TurboFace.

## 0.15.106 — Party leader icon alignment finalization

Moved the fixed-art party leader icon another two pixels to the right. Its size, vertical position,
visibility rules, and event behavior remain unchanged.

## 0.15.105 — Party leader icon alignment follow-up

Moved the fixed-art party leader icon another six pixels to the right. Its size, vertical position,
visibility rules, and event behavior remain unchanged.

## 0.15.104 — Party leader icon final alignment

Moved the fixed-art party leader icon another six pixels to the right. Its anchor is now ten pixels
right of the original 0.15.102 position; all visibility and event behavior is unchanged.

## 0.15.103 — Party leader icon alignment

Moved the fixed-art party leader icon four pixels to the right for better alignment with the party
portrait artwork. Its size, vertical position, visibility rules, and event handling are unchanged.

## 0.15.102 — Party leader indicator

Restored the leader icon when another party member is group leader. TurboFace's fixed party artwork
suppresses Blizzard's legacy frame chrome, which also hid the native leader texture. Each styled
party frame now owns a foreground copy of the standard Classic group-leader icon, resolves leadership
from the pooled frame's assigned unit, and refreshes immediately on `PARTY_LEADER_CHANGED`. The icon
does not depend on party-name visibility and remains visible while NanShield occupies the name row.

## 0.15.101 — Party name acquisition recovery

Fixed TurboFace-owned party names sometimes remaining blank when first joining a group. Classic can
acquire a pooled PartyMemberFrame during `GROUP_ROSTER_UPDATE` before the corresponding unit name is
available, so the initial styling pass could store an empty string with no later recovery. Party names
now use the pooled frame's assigned unit when available, the post-`UpdateMember` hook styles that exact
frame, and `UNIT_NAME_UPDATE` refreshes the owned text when the name cache becomes ready. The refresh
only changes the string; existing Show Names and active NanShield visibility remain authoritative.

## 0.15.100 — Skull-level UnitFrame badge

Fixed the Target UnitFrame's decorative Totem Border disappearing for skull-level mobs. Blizzard
hides the normal target level FontString for `UnitLevel == -1` and presents a separate high-level
skull texture, while TurboFace had keyed the badge only to the FontString's visibility. The badge now
uses Blizzard's skull texture as its anchor in that state. Blizzard retains ownership of the native
level text and skull artwork.

## 0.15.99 — Threat Number NPC eligibility

Fixed Threat Number appearing on hostile player nameplates after a threat-event refresh. Full
nameplate setup already excluded player plates, but the independent threat batch called the update
path directly and its presentation flag only checked whether Threat Number was enabled. Threat Number
now requires a hostile non-player, non-player-controlled unit. Enemy-player swing handling and the
independently gated Aggro Audio path remain unchanged.

## 0.15.98 — Per-enemy Leash Timer reset cleanup

Fixed a reset mob's leash row sometimes surviving until the player's entire combat ended when a
second mob was still engaged. The stale path occurred when the resetting mob lost its nameplate token:
the GUID state correctly survived token recycling, but it then had no observation surface from which to
finish individual disengagement cleanup.

An outgoing `EVADE` miss now removes that mob's GUID state immediately. A disengagement timestamp
observed just before nameplate removal is also preserved long enough to finish the existing 0.60-second
debounce. If a GUID has no remaining nameplate, target, or focus token when its nominal countdown ends,
it is retired rather than entering unbounded overtime; overtime remains available for observable mobs.
This keeps multi-mob combat isolated without treating ordinary nameplate loss as an immediate reset.

## 0.15.97 — Leash Timer overtime display

Changed Enemy Leash Timer behavior at the nominal leash boundary. Reaching 0.0 seconds no longer
removes the GUID state or allows a late reset-like signal to jump the row back to a fresh 11-15 second
countdown. Instead the row enters an overtime observation mode and counts upward as `+0.1s`, `+0.2s`,
etc. until the mob actually disengages/resets, dies, is suppressed by tracked CC, or player combat ends.

This is intentionally useful while the exact Classic leash formula is still being characterized: the
level-derived duration remains the baseline estimate, while any real-world excess becomes directly
visible instead of being hidden by another nominal reset. Estimated body-pull states remain sticky
before zero; after crossing zero they become eligible for the existing debounced disengagement cleanup
so a real reset can remove the overtime row without one transient API sample causing flicker.

## 0.15.96 — Leash Timer false-positive admission tightening

Fixed Enemy Leash Timer occasionally admitting hostile NPCs that were not actually part of the
player's combat. The remaining source was the 0.15.94 synchronized-combat fallback: a nearby NPC
that happened to enter combat with somebody else during the player's combat-entry window could be
interpreted as a body-pull candidate.

Threat-table membership, `unit.."target" == player`, and direct player CLEU interactions remain
authoritative admission signals. The combat-flag transition path is now strictly a last-resort rescue:
it only considers NPCs whose combat flag was observed changing within 0.35 seconds of the player's
combat transition, only runs when no leash state is already active, and admits the fallback only when
there is exactly one plausible unconfirmed hostile. If multiple candidates exist, TurboFace refuses to
guess and waits for threat/victim/CLEU evidence. A nameplate first seen already in combat is now only
a baseline observation and can no longer manufacture a combat-transition candidate.

This keeps the mounted no-hit body-pull escape hatch for the common single-mob case while preventing
the fallback from adding unrelated nearby fights or extra mobs to an already-established pull.

## 0.15.95 — Leash Timer body-pull flicker fix

Fixed Enemy Leash Timer rows oscillating between a valid countdown and `No tracked enemies` during
pure body/proximity pulls before either side lands a hit. The cause was cleanup still treating transient
Classic threat, victim-target, or `UnitAffectingCombat` disagreement as permission to revoke a state
that the acquisition system had just validly admitted.

Estimated body-pull states are now sticky until their natural expiration, NPC death, tracked CC, or
player combat exit. Those pre-hit states deliberately ignore temporary threat/victim/combat-flag loss;
the countdown itself is the cleanup clock. Once a direct CLEU interaction confirms the relationship,
the state becomes confirmed and may end early on explicit disengagement, but that cleanup now requires
0.60 seconds of stable disengagement before removal so one bad API sample cannot cause row flicker.

## 0.15.94 — Leash Timer body-pull acquisition hardening

The 0.15.93 threat-status change was still insufficient for pure proximity pulls. In Classic, a mob
can aggro and chase the player while mounted with neither side landing a hit, yet the player's
`UnitThreatSituation` entry can remain nil long enough that the one-time combat-entry scan misses the
relationship entirely.

Enemy Leash Timer admission now uses three independent signals instead of threat alone: any non-nil
player threat status, the hostile NPC's live `unit.."target"` resolving to the player, or (as a narrow
fallback) a visible hostile NPC's `UnitAffectingCombat` flag transitioning at the same time the player
enters combat. A nameplate that first becomes visible already in combat during that same short entry
window is accepted as the equivalent first observation, because there was no earlier plate sample.
TurboFace already uses the NPC-victim relationship in its native nameplate threat system; Leash Timer
now follows that proven pattern.

`UNIT_TARGET` and `UNIT_FLAGS` now participate in event-driven admission. Combat entry arms a short
1.5-second 10 Hz acquisition pass over only the already-visible nameplate map, and an in-combat
`NAME_PLATE_UNIT_ADDED` gets a 0.75-second window. These windows exist only to bridge Blizzard event
ordering and park immediately afterward; there is still no permanent nameplate poll or private
`OnUpdate`. Direct player CLEU interactions are now authoritative by themselves and no longer require
threat-table confirmation before starting/resetting a visible GUID timer. Existing live timers are
also preserved across temporarily unknown threat/victim data and removed only on explicit
observations of disengagement, death, CC suppression, expiration, or combat end.

## 0.15.93 — Leash Timer body-pull acquisition

Fixed Enemy Leash Timer acquisition for proximity/social pulls where the player enters combat and
the NPC begins chasing without landing a hit. The tracker no longer requires Blizzard to report the
player as the mob's current primary threat target (`isTanking == true`). Instead, a hostile NPC is
admitted as soon as `UnitThreatSituation("player", unit)` reports any non-nil status, including
status 0. Classic can use status 0 for freshly body-pulled/socially pulled mobs even while they are
engaged with the player.

This keeps acquisition selective: nearby NPCs merely fighting someone else are not added unless the
player is actually present on their threat table. Existing GUID-authoritative timers, CLEU resets,
CC suppression, and demand-driven cadence behavior are unchanged.

## 0.15.92 — Leash Timer raid marker icons

Fixed Enemy Leash Timer raid markers rendering as literal `{rt#}` text. The tracker now uses the Blizzard raid-target icon textures directly, which renders skull/cross/moon/etc. correctly inside its FontString.

## 0.15.91 — Restore 11-second low-level leash estimate

Further in-client testing showed level 1-8 NPCs are not consistently a 10-second leash; observed
behavior can vary between roughly 10 and 11 seconds. Removed the special 1-8 band and restored the
conservative reference estimate of 11 seconds for all NPCs below level 30. Higher level bands are
unchanged.

## 0.15.90 — Low-level leash timing correction

Corrected the Enemy Leash Timer's lowest level band from the reference estimate after in-client
validation: level 1-8 NPCs use a 10-second leash timer, while level 9-29 NPCs use 11 seconds.
The higher bands remain unchanged: 12 seconds at 30-39, 13 at 40-44, 14 at 45-49, and 15 at
level 50+/skull.

## 0.15.89 — Enemy Leash Timer

Added a native TurboFace Enemy Leash Timer under the Speedrun tab, based on the stronger state
logic of the newer reference WeakAura and the compact list presentation of the widely used helper.
The feature is opt-in and mover-dependent; it has a dedicated `LeashTimer` mover and font-size
control.

The implementation does not port WeakAura polling machinery. It uses TurboFace's filtered shared
`ns.CLEU` dispatcher, event-driven threat/nameplate identity, and `ns.Cadence` only while live
countdowns exist. Timers are keyed by NPC GUID rather than recyclable nameplate unit tokens, so a
valid timer survives a plate leaving view and naturally expires instead of disappearing because the
visual substrate was recycled. Target/focus provide fallback unit metadata without creating a
Nameplates module dependency.

Level-based estimates are 11 seconds below level 30, 12 at 30-39, 13 at 40-44, 14 at 45-49, and
15 at level 50+/skull. Player direct damage, cast-success interactions, and immune misses provide
authoritative reset timestamps; hidden CLEU observations are held pending until level/threat metadata
exists rather than guessing a duration. Periodic damage does not extend the timer. A narrow
stationary incoming-swing rule is retained from the newer reference for stand-leash behavior.

Tracked hard-CC/root effects temporarily suppress leash state using localized spell names resolved
from a static Classic spell-ID catalog. Death/destruction clears immediately, combat exit wipes the
whole fight state, and a hidden Leash Timer mover parks its CLEU/events/cadence because the feature
has no headless consumer. Display rows are urgency-sorted with raid markers, warning color below
7 seconds, and danger color below 3 seconds.

This is an additive-default release only; SavedVariables schema remains 57.

## 0.15.88 — Bank item state and all-stack withdrawal

Junk & Inventory now has a third per-character item state: Bank. Bank is mutually exclusive
with Junk and explicit Useful protection. The supplied gold-bank artwork is stored as
`Textures/BankIcon.tga` and shared with the friendly-NPC banker Job Icon. The existing mark keybinding and its optional modified-right-click
shortcut cycle all three states; no separate Bank marking control is required.

Opening a live character bank automatically deposits every carried stack whose item ID is
marked Bank. Physical container slots—not rendered button order—drive batched transfers, which
makes the same implementation work with default Blizzard bags/bank and Baganator. After every
carried stack of an item ID deposits successfully, its Bank state changes to Useful so banked
items and future copies are neutral/protected. A partial or blocked deposit retains the Bank mark
for the next visit.

An enabled-by-default option gives live bank items a fixed Ctrl+Right Click action: withdraw all
stacks with the clicked item ID into player bags. It scans the main bank plus purchased bank bags,
is inactive in Baganator offline views, and yields to available bag space and Blizzard slot locks.

Schema 57 adds the Bank state and all-stack withdrawal preference. The per-character
`discardPile` needs no destructive migration: its existing boolean Junk/Useful values remain valid
and the string `"bank"` extends the representation.

## 0.15.87 follow-up

### Threat Number event regression

The Blizzard-native nameplate sweep removed the old threat-role/color engine and its
dispatcher. Threat Number and Aggro Audio were meant to remain independent additive
features, but Threat Number was then refreshed only when a plate appeared or the target
changed. At those moments the client frequently had not populated threat yet, so the
number could remain absent.

Threat refresh is now demand-driven by `UNIT_THREAT_LIST_UPDATE` and
`UNIT_THREAT_SITUATION_UPDATE`. Events enter a deduplicated 50 ms batch, normalize target
tokens to their nameplate unit where possible, and conservatively dirty all visible plates
when Blizzard reports the actor rather than the affected target. The subscriptions exist
only while Threat Number or unmuted group Aggro Audio needs them. `GROUP_ROSTER_UPDATE` is
owned only by the audio consumer.

The same follow-up sweep also:

- routes unavoidable native FrameXML mixin calls through `securecall`;
- removes restricted native string-height measurement from aura layout;
- removes the obsolete deferred nameplate-position queue;
- avoids allocating aura containers while nameplate auras are disabled;
- skips the TurboDebuff spell-name database when TurboDebuffs are disabled;
- aligns stale option text, comments, cache names, and documentation with native ownership.

## 0.15.87 — Blizzard-native nameplate consolidation

The final pre-native nameplate renderer was removed instead of being retained as an
unreachable fallback. Blizzard's Classic Era 1.15.9 nameplate is now the sole baseline
renderer and TurboFace supplies only additive information or narrowly scoped native
presentation amendments.

Removed source modules:

- `Nameplates/Castbars.lua` — replacement/fallback castbar;
- `Nameplates/NameplateAdapter.lua` — passive substrate adapter;
- `Nameplates/NameplateThreat.lua` — tank/DPS health-color threat engine.

Also removed:

- the synthetic lite/name-only and fallback baseline renderers;
- target arrows and glow;
- custom classification and raid-marker rendering;
- mouseover/intersect-alpha ownership;
- aura-driven health recoloring;
- retired Bubble health, cast, classification, and target-arrow media;
- the unused `Textures/EliteIcons/` tree;
- serialized geometry, skin, cast, classification, target-effect, threat-color, and
  raid-marker settings that no longer controlled runtime behavior.

Blizzard now owns plate identity, health and cast presentation, raid markers,
classification art, targeting/hover effects, scale, placement, and stacking. TurboFace
fails open when the expected native health substrate is absent: it parks its augmentation
host and never constructs a replacement plate.

The persisted `bubbleNameplates` table remains for profile compatibility. Its name is
historical; its contents are live additive features such as health-text centering, native
name shadow, Job Icon, friendly presentation modes, Threat Number/Aggro Audio, swing timer,
NPC power, and stacking-spacing ownership.

Saved-variable schema 56 prunes the retired nameplate surface from existing databases and
imports. This was a removal migration, not merely a defaults change: invisible old keys
must not continue to travel through profiles.

## 0.15.86 — Native name-shadow scope

The native-name shadow workaround was expanded from enemy NPC names to Blizzard-owned
player names. The setting was renamed from the NPC-specific key to
`bubbleNameplates.nameTextShadow`; migration 55 preserves the prior enabled state and
removes the old key.

The shadow glyph remains below the native name in frame strata/level so it cannot obscure
Blizzard's real text. This continues the name-underlay correction first established in
0.15.13.

## 0.15.76 — Trainer tab spacing

The custom Spellbook trainer tabs received additional vertical separation to keep their
click regions and presentation distinct after the tab layout changes.

## 0.15.73 and 0.15.71 — Priest Party NanShield

Party Power Word: Shield visualization was hardened around actual local-Priest ownership.
Absorb state is never inferred from another caster and is not reconstructed after reload.
Replacement by another Priest invalidates local ownership immediately. Party recycling,
group leave, Unit Frames combinations, and first application during combat are explicit
regression cases because protected geometry may not be created or mutated opportunistically
in lockdown.

## 0.15.62–0.15.63 — Quantitative threat presentation

The legacy ThreatBubble shell/fill was retired in favor of a text-only Threat Number beside
the live native health bar. Migration 50 preserved the old visibility choice while removing
Bubble geometry. Migration 51 moved the font-size setting beside the feature and removed
the old global offsets. Aggro Audio remained a separate runtime consumer even though its
controls are grouped with Threat Number in Options.

## 0.15.60 — Independent nameplate swing timing

Enemy nameplate swing timing became an explicit Nameplates feature rather than fixed-on
behavior or a child of threat presentation. Migration 49 seeded it enabled for existing
profiles. It does not depend on the Global player/target Swing Timers module.

## 0.15.53–0.15.55 — Aura ownership split

Party and Pet aura presentation moved from Unit Frames to the Auras family, followed by an
independent Target-of-Target Aura child. Migrations copied presentation settings and seeded
new gates from the old effective state so users retained what they had actually been seeing.
These surfaces are valid on Blizzard unit frames and therefore do not inherit TurboFace Unit
Frame gates.

## 0.15.37 — Documentation separation decision

Release chronology was designated as separate from the architecture contract. The intended
history file did not survive in the supplied tree, so the architecture document gradually
accumulated dated fixes again. This `CHANGELOG.md` completes that separation: architecture
describes what exists; this file records when and why it changed.

## 0.15.30 — Plus Chat text outline

Optional outline-only chat styling was corrected to preserve Blizzard's existing shadow
state. Styling ownership must not silently erase a separate native property when the option
only claims the outline.

## 0.15.29 — Flight Bar ownership cleanup

Obsolete helper listeners were removed. Taxi state ownership now belongs only to Flight Bar,
eliminating duplicate event work and ambiguous teardown.

## 0.15.28 — Independent DPS/HPS badge

The player DPS/HPS badge was made independent from TurboFace Unit Frames and from visibility
of the movable Combat Meter window. Combat accounting remains active in headless mode only
when this badge consumes it. The persisted key remains under `unitframes` solely for profile
compatibility.

## 0.15.26 — Regen delivery-jitter hardening

Mana/Energy/Health tick learning was made tolerant of event-delivery jitter without allowing
false phase resets. Authoritative phase acceptance still requires the subsystem's validated
resource-delta and confidence rules.

## 0.15.20 — Mover recursion fix

The `/tf move` path could recurse through mover-state refresh until Lua exhausted the C stack.
Mover activation and refresh ownership were separated so state synchronization no longer
re-entered its own command path.

## 0.15.17 — External nameplate ownership release

TurboFace stopped locking nameplate visibility and stopped owning Questie's nameplate offset.
Upgrade cleanup restores any captured client/Questie snapshot exactly once, then releases the
debt. Ownership records are preserved across client-build cache wipes because they are values
TurboFace owes back to the user, not disposable discovery cache.

## 0.15.8 — Investigation probes removed

Temporary native wrappers and work-volume counters from the post-kill CPU investigation were
removed after the A/B tests completed. Production retained only low-frequency flush/cleanup
boundaries, short kill/post-combat windows, event markers, and native threshold deltas. Deep
cadence/timer attribution remains available through the opt-in profiler.

## 0.15.4–0.15.7 — Post-kill CPU investigation

Profiling coverage was expanded to aura, nameplate, combat-meter, swing, party-aura, and regen
flush boundaries. The investigation established that instrumentation must wrap the coalesced
flush—not the cheap event that only sets a dirty flag—or the real cost is attributed to the
wrong subsystem. It also established native `C_AddOnProfiler` baseline/delta measurement as the
normal low-overhead diagnostic and `scriptProfile` as opt-in deep attribution because profiling
overhead can exceed normal addon CPU.

## 0.15.3 — Static dependency checks

Mover-gate validation was expanded to catch direct construction, event registration, and
indirect activation shapes. This protects the contract that mover-dependent widgets remain
dormant while Movers is disabled without erasing the user's stored preference.

## 0.15.2 — Combat-path hardening

A broad runtime audit established the current hot-path model:

- `ns.CLEU` dispatches by subevent instead of broadcasting every combat-log event to every
  consumer;
- regen markers have no CLEU dependency;
- PowerCost avoids duplicate frequent-unit events;
- DoT prediction uses event invalidation and a safety TTL rather than repeatedly scanning a
  changing 40-aura surface;
- Combat Meter accounting exists only while its window or the independent badge needs it;
- nameplate combo polling belongs to Nameplates and is demand-driven;
- prediction engines require a presentation consumer, not an unrelated Unit Frames gate;
- Trainer live-disable detaches events and predicate-gates irreversible hooks;
- periodic work moved from per-frame throttles to the shared native cadence scheduler;
- active cast/spend/swing visuals use shared active sets;
- one-second widgets no longer enter Lua once per rendered frame;
- combat exit rebuilds only caches whose work was actually deferred;
- bag invalidation does not force a second Baganator item-widget pass;
- loot bursts coalesce rendering and use cancellable expiry timers;
- Net Worth caches carried-junk valuation and rescans only on inventory/junk invalidation.

## 0.14.3 — Target-of-Target taint incident

A direct call into Blizzard FrameXML tainted state later consumed by secure code. The durable
rule is to hook FrameXML with `hooksecurefunc`, or use `securecall` only when invocation is
unavoidable. Protection is checked on the exact frame involved; it is not inferred from the
parent. Target-of-Target therefore uses alpha-only presentation where protected visibility is
unsafe.

## 0.14.x — Startup and modularity hardening

TurboFace adopted the “disabled means dormant” contract. Optional systems moved behind the
post-`LoadVariables()` login boundary, module gates were centralized, event/CLEU/timer ownership
became demand-driven, and initialization gained `ns.SafeCall` isolation so one subsystem cannot
prevent later modules from starting.

## Saved-variable schema history

The authoritative executable history is the ordered migration table in
`Core/Migrations.lua`. The major transitions are summarized here:

- **76:** add user-selectable Pet name placement and initialize profiles without an explicit choice to below the bars.
- **68:** give the Druid Power Bar dedicated font, text style, text size, and text-format ownership, including `Percent Current (Blizzard)`.
- **67:** give Party, Pet, and Target-of-Target independent Name Text Size and Bar Text Size settings.
- **66:** split UnitFrame Name typography from Bar/value typography.
- **65:** add the standalone Speedrun `fpsCounterEnabled` feature gate; preserve the former visible-by-default FPS behavior.
- **64:** retire addon-wide Font/Text Style ownership in favor of feature-local Blizzard typography.
- **63:** prune retired pre-release configuration and normalize the Rumblecrush release preset baseline.
- **57:** add Bank-state marking and live-bank all-stack withdrawal preferences.
- **56:** prune the retired TurboFace-owned nameplate renderer settings.
- **55:** generalize the native name-shadow setting to NPC and player names.
- **54:** retire the friendly-name-only Blizzard-hover-color option.
- **53:** make friendly NPC Job Icon an independent Nameplates feature.
- **52:** add Grocery's Ammo category without hiding it for existing profiles.
- **51:** move Threat Number font size into its owning namespace.
- **50:** replace ThreatBubble shell/fill with text-only Threat Number.
- **49:** make enemy nameplate swing timing independently configurable.
- **48:** split Target-of-Target debuffs into an independent Aura child.
- **47:** move Party/Pet aura ownership from Unit Frames to Auras.
- **46:** retire the Plus Dismount helper family and its settings.
- **45:** retire the Pet happiness Unit Frames timer setting.
- **44:** adopt native nameplate health text and release visibility/Questie controls.
- **43:** adopt native nameplate sizing, target scaling, and castbars.
- **42:** split Hearthstone timer and auto-bind helper preferences.
- **36–41:** introduce and tune lethal DoT prediction colors and badge defaults while
  preserving user-picked colors.
- **34–35:** replace the minimap shape boolean, then retire the short-lived torn shape.
- **30–33 and 37–38:** migrate successive DPS badge default colors without overwriting
  customized values.
- **29:** disable the restricted-region Lua nameplate stacking engine in favor of Blizzard's
  native anti-overlap CVar.
- **28:** remove the GUI-only Party gate mirror and retain the canonical module gate.
- **27:** make the minimap button always present and remove its orphaned enable key.
- **26:** retire Potato PC Mode; cadence is tuned per subsystem instead.
- **25:** retire the Plus sound-muting suite.
- **24:** introduce module-family master gates and split power features.
- **22–23:** give Target-of-Target independent formats and adjust fitted fonts.
- **20–21:** adopt fixed native-scale Party and Target-of-Target artwork.
- **19:** move timer/status ownership toward compact and Blizzard-native presentation.
- **17–18:** add, then retire, the old white-name presentation.
- **16:** adopt fixed Classic PlayerFrame artwork/ownership.
- **15:** split friendly NPC and player presentation controls.
- **14:** split Bubble value controls into independent settings.
- **13:** retire Bubble's compact aura presentation and restore native ownership.
- **12:** establish the former locked Bubble nameplate model.
- **11:** hand HUD placement to Blizzard's imported Edit Mode.
- **7–10:** evolve Party buff/reminder presentation and timer styling.
- **2–6:** remove early retired features and split shared unit-frame formats into
  surface-specific settings.

Migrations are append-only and ordered. A later default change must not rewrite an older
migration in place because users who already crossed that schema boundary will never execute
the edited step again.

## Regression anchors

These remain high-value live-client checks even though their originating releases are now
historical:

- Chat outline changes preserve Blizzard shadow state.
- The DPS/HPS badge works with TurboFace Unit Frames disabled and with the movable meter hidden.
- Native name-shadow FontObjects remain stable across target, hover, and pooled-unit reuse without duplicate underlays.
- Regen markers tolerate delivery jitter without accepting invalid phases.
- NanShield handles local apply, absorb depletion, expiry, external replacement, group recycle,
  mixed Unit Frames gates, and first combat application without protected mutation.
- Threat Number appears after threat is established, updates through target changes and group
  transitions, and remains independent from Aggro Audio mute/state choices.

- Unit Frames: added `Percent Current (Blizzard)` to every Health/Power text-format dropdown; it renders percent inside-left and current value inside-right using TurboFace-owned bar text.

- Unit Frames: corrected `Percent Current (Blizzard)` ordering to match Blizzard presentation: percent inside-left, current value inside-right.
