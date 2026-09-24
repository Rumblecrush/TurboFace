# TurboFace Forever Changelog

## 0.18.1 — CurseForge packaging correction

- Removed `Save-TurboFaceForever.bat` from public release ZIPs after CurseForge rejected the 0.18.0 Forever archive for containing a batch file.
- Retained the launcher in the source repository and retained the underlying PowerShell and Linux snapshot tools in the installable Forever package.
- Updated Windows workaround instructions to invoke the PowerShell tool directly.
- Reorganized the public repository around a player-facing README, dedicated maintainer guides, clear support links, issue forms, and a root third-party notice index.
- No gameplay or SavedVariables schema change.

## 0.18.0 — first unified multi-client release

- Published Forever alongside Classic from the unified layered source repository.
- Retained Forever's protected-frame, secret-value, native Nameplate, Unit Frame, Trainer, Combat, and SavedVariables compatibility boundaries.
- Replaced the internal Prep version in public package metadata with the shared TurboFace 0.18.0 product version.
- Added verified GitHub Actions packaging and Forever-specific CurseForge delivery.
- Portable SavedVariables remain at schema version 79; Forever-only evolution remains separately revisioned.

## 0.17.87-ForeverPrep156-Forever69977

- Phase 33 repository hardening: restored regression tests, hardened destructive build output handling, removed stale packaged docs/manifests, eliminated the redundant shared Trainer client-identity check, and strengthened verification for documentation/ownership freshness. No gameplay feature change.

- Phase 32 / Prep155: completed the end-state architecture audit; no runtime module was force-merged. Verification now freezes the exact client-overlay divergence allowlist and prevents accidental re-duplication of converged modules.
- Phase 31: converged Trainer/UI_Profession.lua and Trainer/UI_Spellbook.lua through the existing trainerUI provider boundary; InterfaceTweaks remains intentionally client-owned.

## 0.17.87-ForeverPrep154-Forever69977

- Phase 30: promoted `Core/Debug.lua` into the physical common layer.
- Retained Forever's extended probes as guarded, read-only capability diagnostics; Classic safely no-ops unavailable modern surfaces.
- Source audit: **174** byte-identical same-path package files, **105** identical first-party source paths, **7** same-path divergences, and **5** remaining first-party divergences.
- No portable SavedVariables schema change (`dbVersion=79`).

## 0.17.87-ForeverPrep152-Forever69977

- Phase 29: promoted `Power/PowerCost.lua` into the physical common layer.
- Preserved detached protected-action-button overlay ownership, native macro spell resolution, and secret-resource curve rendering as capability-gated shared behavior.
- Classic consumes the same implementation with readable resource arithmetic and legacy macro fallback.
- Source audit: **173** byte-identical same-path package files, **104** identical first-party source paths, **8** same-path divergences, and **6** remaining first-party divergences.
- Portable SavedVariables schema remains `dbVersion=79`.

## 0.17.87-ForeverPrep151-Forever69977

- Phase 28: promoted `Power/RegenTicks.lua` into the physical common layer.
- Preserved secret Rage/Health safety through accessibility-guarded reads and event-timed fallback markers.
- Preserved modern PlayerFrame bar discovery with Era-global fallback, without a direct Forever branch in shared RegenTicks.
- Portable SavedVariables schema remains `dbVersion=79`.

## 0.17.87-ForeverPrep150-Forever69977

- Phase 27: promoted `QuickSetup.lua` into the physical common layer.
- Added client-owned Quick Setup policy for legacy reload persistence vs Forever immediate/save-helper persistence, modern macro limits/scope resolution, Edit Mode indexing, CVar baseline ownership, and unsupported-action preservation.
- Shared Quick Setup contains no direct Forever/build identity branch; portable profile schema remains `dbVersion=79`.

# TurboFace Forever Changelog

## 0.17.87-ForeverPrep149-Forever69977

- Phase 26: promoted root `Core.lua` into the physical common layer.
- Moved detached-nameplate startup, deferred native callbacks, restricted-frame-safe identity restoration, native castbar presentation, driver-hook validity, startup ordering, and extended diagnostics into `Core/Client.lua` `corePolicy`.
- Shared Core uses secret-safe Compat unit reads and guarded event registration with no direct Forever/build identity branch.
- Source audit: **170** byte-identical same-path package files, **101** identical first-party source paths, **11** same-path divergences, and **9** remaining first-party divergences.
- Advanced the Forever preparation marker to Prep149; portable profile schema remains `dbVersion=79`.

## 0.17.87-ForeverPrep148-Forever69977

- Phase 25: promoted `AuraStyle.lua` into the physical common layer.
- Shared player/target/ToT aura styling now consumes Compat readable-aura helpers and fails closed while aura values are protected.
- Classic Compat supplies the same table-form readable-aura contract without introducing a secret-value domain; Forever retains native Blizzard duration rendering while protected.
- Advanced the Forever preparation marker to Prep148; portable profile schema remains unchanged.

## 0.17.87-ForeverPrep147-Forever69977

- Phase 24: promoted `ExperienceBar.lua` into the physical common layer.
- Unified Classic selection-based quest reward lookup and Forever asynchronous reward-data loading behind API capability detection.
- Forever now retains the last complete quest-XP snapshot while reward data is pending and reconciles on quest data completion/removal events.
- Advanced the Forever preparation marker to Prep147; portable profile schema remains unchanged.

## 0.17.87-ForeverPrep146-Forever69977

- Phase 23: promoted `Core/Config.lua` into the physical common layer.
- Shared guarded cadence reporting, reload-free CVar baseline application, capability-gated CLEU registration, and client feature policy.
- Moved detached-nameplate adapter ownership into `Core/Client.lua` policy rather than a direct Forever branch in Config.
- Advanced the Forever preparation marker to Prep146; portable profile schema remains unchanged.

## 0.17.87-ForeverPrep145-Forever69977

- Phase 22: promoted `Options/OptionsGUI.lua` into the physical common layer.
- Moved client-specific option visibility and apply-lifecycle decisions into `Core/Client.lua` feature/option policy instead of branching on Forever identity inside the GUI.
- Classic retains quest-level/vendor-price controls and the ClassBuffs unspent-talent icon; Forever retains the standalone Spend Talent Point HUD, combined-bag mover, detached nameplate refresh ownership, and Blizzard-owned feature exclusions.
- Advanced the Forever preparation marker to Prep145; portable profile schema remains unchanged.

## 0.17.87-ForeverPrep144-Forever69977

- Phase 21: promoted `Core/SharedMedia.lua` into the physical common layer.
- Moved the client-specific Banker/Bank-mark artwork choice into `Core/Client.lua` asset policy: Classic retains TurboFace's bundled `Textures/BankIcon.tga`; Forever retains Blizzard's native Banker tracking artwork.
- Shared media consumers now resolve the banker texture through `Client:GetAsset()` with no direct Forever branch in `Core/SharedMedia.lua`.
- Advanced the Forever preparation marker to Prep144; portable profile schema remains unchanged.

### Multi-client reorganization phase 20 — Party/Pet aura convergence
- Promoted `PartyPetAuras.lua` into the physical common source layer. The shared implementation is
  the hardened Forever superset and contains no direct client-build branch.
- Aura ownership now fails closed through `ns.API.ShouldAurasBeSecret()`: when aura data enters a
  secret domain, TurboFace suspends its owned Party/Pet aura containers instead of attempting to
  inspect protected values. Classic's Compat stub remains readable, preserving Era behavior.
- Native Blizzard Party/Pet aura suppression is now reversible. TurboFace restores native aura
  alpha whenever the custom surface is disabled or aura data becomes unreadable, while retaining
  one-time hooks that re-pin alpha only while TurboFace owns the surface.
- Deferred and world/roster event registration now uses the shared guarded event boundary rather
  than direct `RegisterEvent` calls.
- Source audit: **164** byte-identical same-path package files, **95** identical addon-owned source
  paths, **17** same-path divergences, and **15** remaining first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep142-Forever69977

### Multi-client reorganization phase 19 — Grocery / merchant UI convergence
- Promoted `Inventory/Grocery.lua` into the physical common source layer. Inventory now has zero
  same-path client divergences.
- Classic `Core/Compat.lua` now exposes the same merchant vocabulary used by Forever:
  `GetMerchantNumItems`, `GetMerchantItemInfo`, `GetMerchantItemLink`, optional merchant item ID,
  stack/cost queries, `BuyMerchantItem`, `GetItemCount`, `MerchantSurfaceAvailable`, and
  `GetCoinTextureString`. Era globals remain the preferred zero-overhead path.
- The common Grocery UI uses TurboFace-owned template-free item cells with Blizzard quick-slot
  textures instead of inheriting `ItemButtonTemplate`. This avoids a hard missing-template failure
  on Forever while preserving the same icon/count/quality-border presentation contract on Classic.
- Shared auto-buy now fails closed when the merchant surface is unavailable, tracks merchant-session
  lifetime explicitly, rejects extended-currency and explicitly non-purchasable rows, and retains
  the existing inventory auto-sell barrier before purchases begin.
- Source audit: **163** byte-identical same-path package files, **94** identical addon-owned source
  paths, **18** same-path divergences, and zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep141-Forever69977

### Multi-client reorganization phase 18 — Inventory storage/value convergence
- Promoted `Inventory/InventoryManager.lua`, `Inventory/Bank.lua`, and `Inventory/NetWorth.lua`
  into the physical common source layer. The shared implementations are the hardened compatibility
  supersets already used by Forever, with Classic fallbacks preserved in the same files.
- Classic `Core/Compat.lua` now exposes `API.SetCoinIcon()`, mapping gold/silver/copper to the
  historical MoneyFrame textures so common Inventory/NetWorth presentation keeps Era's existing
  visual assets while Forever can continue using modern coin atlases.
- Shared InventoryManager retains the Classic `ContainerFrame_Update` / `ContainerFrameNItemM`
  path and additionally capability-discovers Forever's pooled `ContainerFrameItemButtonMixin` and
  combined-bag surfaces. No client build check is required in the common module.
- Shared Bank retains `BANK_CONTAINER` + purchased-bank-bag scanning on Classic and additionally
  capability-discovers Forever's tab-backed character bank / `BankPanelItemButtonMixin` surface.
- `Inventory/Grocery.lua` is intentionally left client-owned because its remaining diff combines
  merchant API normalization with a visible item-cell host change; that will be handled as a
  dedicated merchant/UI convergence pass.
- Source audit: **162** byte-identical same-path package files, **93** identical addon-owned source
  paths, **19** same-path divergences, and zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep140-Forever69977

### Multi-client reorganization phase 17 — SwingTimers runtime decomposition
- Added shared `Combat/SwingTimerProvider.lua`. Classic registers `swingTimers=classic-cleu`;
  Forever's client-owned `Combat/ForeverSwingTimerAdapter.lua` registers
  `swingTimers=forever-player-swing` at higher priority.
- Promoted `Combat/SwingTimers.lua` into the physical common source layer. The shared engine owns
  timer state, player/target/ranged rendering, queued-swing coloring, cast interactions, target
  phase caching, standalone/embedded presentation, and the optional `PLAYER_SWING` handler.
- Forever-only Character/PaperDoll damage-row discovery moved out of the shared engine and into the
  Forever adapter. The adapter also declares unreadable target/nameplate attack-speed surfaces and
  disables the Classic threat-as-engagement fallback.
- Classic Compat now exposes readable `API.IsSecretValue`, `API.CanAccessValue`, and
  `API.IsReadableNumber` contracts so the shared engine can use one value-access vocabulary on both
  clients without client branches.
- Classic keeps CLEU/spellcast reconstruction because its provider does not register
  `PLAYER_SWING`. Forever registers `PLAYER_SWING` and suppresses duplicate player CLEU resets while
  retaining observational CLEU target/nameplate tracking.
- `/tf compat plan` and diagnostic exports now report the selected `swingTimers` provider.
- The Combat family now has zero same-path divergences. Source audit: **159** byte-identical
  same-path package files, **90** identical addon-owned source paths, **22** same-path divergences,
  and zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep139-Forever69977

### Multi-client reorganization phase 16 — shared class-combat compatibility
- Added shared `Combat/Provider.lua`. Classic registers `combatUI=classic-readable`; Forever's new
  `Combat/ForeverNativeAdapter.lua` registers `combatUI=forever-secret-safe` at higher priority.
- Promoted `Combat/ClassFeatures.lua` and `Combat/ClassBuffs.lua` into the physical common source
  layer. The provider now owns the two real presentation differences: Classic may use the direct Era
  reactive-nameplate indicator and the historical ClassBuffs talent-point icon, while Forever keeps
  both dormant because those concerns are owned by detached/native nameplates and the standalone
  Speedrun talent reminder.
- Promoted `Combat/QueueDiagnostics.lua` into common source. Classic Compat now exposes
  `API.SafeToString()` so diagnostics use the same secret-safe string/unit-read vocabulary on both
  clients instead of binding raw `UnitPower`, `UnitName`, or `UnitGUID` in shared code.
- `/tf compat plan` and compatibility exports now report the selected `combatUI` provider alongside
  the existing meter/nameplate/unitframe/Plus/Trainer providers.
- `Combat/SwingTimers.lua` is now the only remaining same-path Combat divergence.
- Source audit: **157** byte-identical same-path package files, **88** identical addon-owned source
  paths, **23** same-path divergences, and zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep138-Forever69977

### Multi-client reorganization phase 15 — shared Automation / System ownership
- Promoted `Plus/Automation.lua` and `Plus/SystemTweaks.lua` into the physical common source layer.
  `Plus/InterfaceTweaks.lua` is now the only same-path `Plus/*` divergence.
- Classic `Core/Compat.lua` now exposes `API.ConfirmSpiritHealer()`, `API.ReleaseSpirit()`, and
  `API.GetCoinText()`, preserving the Era `AcceptXPLoss`, `RepopMe`, and native money-string paths
  while allowing the shared Automation controller to remain client-neutral.
- Shared Automation keeps the hardened serialized quest-selection confirmation/retry flow, guarded
  quest lifecycle events, `PLAYER_DEAD` battleground release through `API.ReleaseSpirit()`, and
  client-neutral repair summaries. Unsupported companion events fail closed through Compat.
- Shared System Tweaks adopts the hardened fast-loot path on both clients: guarded loot APIs,
  modern/legacy loot-method normalization, master-loot threshold preservation, locked-slot skips,
  and fast-loot diagnostics.
- Added `plusUI` capability `SupportsVendorPriceTooltip()`. Classic owns TurboFace's vendor-price
  tooltip augmentation; Forever explicitly yields that presentation to Blizzard, so stale/imported
  `showVendorPrice=true` data cannot re-enable the removed Forever behavior.
- Source audit is now 153 byte-identical same-path package files / 84 identical addon-owned source
  paths / 26 same-path divergences / zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep137-Forever69977

### Multi-client reorganization phase 14 — shared Chat / Social / Flight QoL
- Promoted `Plus/ChatTweaks.lua`, `Plus/Social.lua`, and `Plus/FlightBar.lua` into the physical
  common source layer. Their previous client differences were API-shape hardening rather than
  different user-facing ownership, so both flavors now use the same implementations.
- Classic `Core/Compat.lua` now exposes the same guarded QoL vocabulary used by Forever for chat
  enumeration, Battle.net friend-invite identity/actions, party invite eligibility/action, and
  chat event registration. Era still uses `ChatFrame1..50`, legacy `BN*`, and legacy party globals
  when those are the authoritative APIs.
- Shared Flight Bar adopts the guarded hook/event diagnostics from the Forever implementation:
  `hooksecurefunc` availability is checked before taxi hooks, actual event-registration success is
  recorded, and either the legacy taxi tooltip handler or button-level `OnEnter` hooks may supply
  route estimates. The seeded/learned timing model is unchanged.
- `Plus/Automation.lua`, `Plus/SystemTweaks.lua`, and `Plus/InterfaceTweaks.lua` remain client-owned;
  their current differences are behavioral/ownership differences and are not hidden behind this
  compatibility-only convergence pass.
- Source audit: **151** byte-identical same-path package files, **82** byte-identical addon-owned
  source paths, **28** same-path divergences, and zero >=99%-similar first-party divergences.
- No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep136-Forever69977

### Multi-client reorganization phase 13 — Trainer SkillData convergence
- Promoted `Trainer/SkillData.lua` into the physical common source layer. Classic and Forever now
  use one weapon-skill/profession-starter/proficiency-rank catalog and one captured-skill migration
  path.
- Extended the existing `trainerUI` provider with two narrow data capabilities. Classic preserves
  the historical generic `Weapon Master` source and uses `ns.Skills` for profession-rank checks;
  Forever retains detailed trainer/city weapon sources and the guarded
  `C_TradeSkillUI.GetBaseProfessionInfo()` fallback when the matching profession page is open.
- Shared SkillData now keeps human requirement text in `requirementText` while reserving `requires`
  for prerequisite spell-ID tables, matching the shared Trainer row contract.
- A two-flavor harness verifies Classic still renders `Weapon Master` and ignores the modern rank
  fallback, while Forever resolves `Ansekhwa - Thunder Bluff` for Horde Staves and accepts a
  matching open-profession skill rank.
- Source convergence rises to 148 byte-identical same-path package files / 79 identical first-party
  source paths, with 31 same-path divergences remaining and zero >=99%-similar first-party
  divergences. Only `UI_Profession.lua` and `UI_Spellbook.lua` remain same-path Trainer
  divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep135-Forever69977

### Multi-client reorganization phase 12 — Trainer events / queue / legacy-list convergence
- Promoted `Trainer/Events.lua`, `Trainer/TrainerListUI.lua`, and `Trainer/TrainingQueue.lua` into
  the physical common source layer. Classic and Forever now use the same trainer event lifecycle,
  legacy-list ownership guard, queue matcher, purchase flow, and read-only trainer diagnostics.
- Trainer event registration now treats `TRAINER_CLOSED` and `SPELL_DATA_LOAD_RESULT` as optional
  capabilities. Modern spell-data retry remains available where `C_Spell.RequestLoadSpellData`
  exists, while clients without that API do not depend on the event.
- The legacy ClassTrainer list override now fails closed unless every Era XML object/function it
  needs is present. Classic retains the ignored-rank filter; Forever's native trainer remains
  untouched and does not advertise the extra filter.
- Training Queue now uses the shared trainer-service normalizer and `ns.API.IsKnownSpellID()` on both
  clients. Numeric spell identity is authoritative whenever both sides have an ID; a numeric mismatch
  no longer falls through to same-name matching, preventing a later unavailable rank from stealing
  the queued exact-rank service when rank text is absent.
- The shared queue keeps guarded load-on-demand spell warming, visit-close invalidation, stop-reason
  tracing, and `/tf debug trainer` output. Those modern paths are inert where their APIs are absent.
- Source convergence rises to 147 byte-identical same-path package files / 78 identical first-party
  source paths, with 32 same-path divergences remaining and zero >=99%-similar first-party
  divergences. Only `SkillData.lua`, `UI_Profession.lua`, and `UI_Spellbook.lua` remain same-path
  Trainer divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep134-Forever69977

### Multi-client reorganization phase 11 — Trainer service/capture convergence
- Promoted `Trainer/Init.lua`, `Trainer/TrainerCapture.lua`, and `Trainer/PetMerchantCapture.lua`
  into the physical common source layer. Classic and Forever now use the same trainer-service
  normalization, spell-identity resolution, trainer capture, and pet-merchant tooltip bridge.
- The shared service normalizer preserves Era's ordinary category-in-return-#3 contract as the
  direct Classic path while also accepting the known retail-derived/structured layouts behind one
  fail-closed boundary.
- The shared spell resolver keeps Classic's trainer-tooltip numeric spell ID path, then adds guarded
  `C_TooltipInfo`, seeded class-catalog, load-on-demand `C_Spell`, and legacy name-lookup fallbacks
  needed by Forever's unlearned trainer spells.
- Profession trainer capture now preserves explicit `skillReq`/`skillName` entry metadata on both
  clients. This is additive trainer-cache metadata and does not change the portable profile schema.
- Pet merchant capture now shares the modern `TooltipDataProcessor` post-call path with an Era
  `OnTooltipSetItem` fallback and reads pet existence/health through `ns.API`.
- A Classic service harness verifies Era rows normalize as `category-third` and that the tooltip
  spell ID remains preferred. Generated source audit rises to 144 byte-identical same-path package
  files / 75 identical first-party source paths, with 35 same-path divergences remaining and zero
  >=99%-similar first-party divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep133-Forever69977

### Multi-client reorganization phase 10 — Trainer UI provider extraction
- Added shared `Trainer/Provider.lua`. Classic registers `classic-embedded` at priority 10; Forever
  registers `forever-detached` at priority 100 through `Trainer/ForeverNativeAdapter.lua`.
- Promoted `Trainer/UI_Core.lua`, `Trainer/UI_ClassData.lua`, `Trainer/UI_ClassList.lua`, and
  `Trainer/UI_Skills.lua` to the physical common source layer. These files no longer inspect the
  Forever build directly.
- Shared Trainer UI policy now asks the active provider whether the client uses native Trainer
  cards, the Spellbook grid, the Forever list-size bump, an embedded Spellbook host, or a detached
  profession host. Classic keeps its existing one-column Era presentation; Forever keeps its
  native-card 2/4-column presentation through the same shared row/list code.
- Added Classic `ns.API.GetSpellSubtext` normalization so the shared profession-rank classifier no
  longer depends on a Forever-only spell API path.
- Forever's profession and Spellbook host controllers now consult the Trainer UI provider for host
  ownership rather than branching directly on `IS_TARGET_FOREVER_BUILD`. They remain client-owned
  because the detached modern hosts are materially different from Classic's embedded UI.
- `/tf compat plan` now reports `trainerUI=forever-detached` alongside the existing runtime
  providers.
- Source convergence rises to 141 byte-identical same-path package files / 72 identical first-party
  source paths, with 38 same-path divergences remaining and zero >=99%-similar first-party
  divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep132-Forever69977

### Multi-client reorganization phase 9 — Map / native-interface ownership
- Added shared `Plus/Provider.lua`. Classic registers `classic-ui` at priority 10; Forever registers
  `forever-native-ui` at priority 100 through the new `Plus/ForeverNativeAdapter.lua`.
- Promoted `Plus/MapTweaks.lua` to the common source layer. The shared implementation keeps Classic's
  movable map, cursor-centred enhanced zoom, extra zoom ladder, and remember-pan/zoom behavior, but
  asks the active Plus UI provider whether Blizzard owns native MapCanvas state before installing
  any zoom/pan/mouse-wheel/provider-related hooks.
- Forever's provider reports native MapCanvas ownership, so the shared controller retains only the
  safe top-level movable-map amendment and refuses all protected ScrollContainer zoom/pan work.
- Promoted `MinimapTracker.lua` to the common layer. Classic `Core/Compat.lua` now exposes
  `API.GetMinimapParts()` so the shared tracker resolves legacy Era minimap globals through the same
  object vocabulary used by Forever's modern MinimapCluster hierarchy.
- `Plus/InterfaceTweaks.lua` intentionally remains client-owned because its differences are semantic:
  Classic still owns legacy quest-level presentation and minimap geometry, while Forever preserves
  native numeric quest levels, adds difficulty tags only, and targets modern Frame/NineSlice parts.
- `/tf compat plan` now reports `plusUI=forever-native-ui` alongside the existing Combat Meter,
  Nameplate, and UnitFrame providers.
- Source convergence rises to 136 byte-identical same-path package files / 67 identical first-party
  source paths, leaving 42 same-path divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep131-Forever69977

### Multi-client reorganization phase 8 — primary UnitFrame convergence
- Promoted `UnitFrames/UnitFrames.lua` into the physical common layer. Classic and Forever now ship
  the same 3,600-line primary UnitFrame source body; the removed 4,041-line Forever duplicate is no
  longer maintained independently.
- Moved the remaining Forever-only helper ownership into `UnitFrames/ForeverNativeAdapter.lua`:
  modern Player/Target/ToT health/power object resolution, the Forever-aligned Player art geometry,
  reserve-row geometry used by Swing Timers, and the target-tag name amendment.
- Forever's adapter continues to register `forever-native-safe` at priority 100 and replaces
  `UF:Init()` / `UF:Refresh()` before `Core.lua` initializes UnitFrames. The shared Era renderer is
  therefore present as common source but is not activated as the Forever runtime renderer.
- Added Phase-8 verification that the shared UnitFrame core contains no Forever build check or
  modern object resolver and that the Forever adapter publishes the modern getter/geometry helpers
  required by shared consumers.
- Source convergence rises to 133 byte-identical same-path package files / 64 identical first-party
  source paths, leaving 44 same-path divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep130-Forever69977

### Multi-client reorganization phase 7 — UnitFrame capability providers
- Added shared `UnitFrames/Provider.lua`. Classic registers `classic-readable` at priority 10;
  Forever's native-safe adapter registers `forever-native-safe` at priority 100 through the shared
  provider registry.
- Reconciled and physically shared `UnitFrames/DruidPowerBar.lua`, `UnitFrames/Predictions.lua`, and
  `UnitFrames/nanShield.lua`. Those files no longer branch directly on the Forever client.
- The UnitFrame provider now owns whether custom prediction textures, NanShield reconstruction, and
  the Classic Druid auxiliary power StatusBar are valid, plus provider-safe Player health/power bar
  resolution for shared consumers. Classic preserves all three readable renderers; Forever keeps
  them dormant and leaves Blizzard's protected/secret-safe native layers authoritative.
- The primary `UnitFrames/UnitFrames.lua` implementation intentionally remains client-divergent.
  Prep130 does not force its modern protected-frame geometry/text/hook differences into the Classic
  renderer merely to reduce file count.
- `/tf compat plan` now reports the selected UnitFrame provider in addition to Combat Meter and
  Nameplates. Expected on Forever: `unitframes=forever-native-safe`.
- Source convergence rises to 132 byte-identical same-path package files / 63 identical first-party
  source paths, leaving 45 same-path divergences. No SavedVariables schema/client-revision change.

## 0.17.87-ForeverPrep129-Forever69977

### Multi-client reorganization phase 6 — Nameplate substrate providers
- Added shared `Nameplates/Provider.lua`. Classic registers the native Era substrate as
  `classic-native` at priority 10; Forever's detached adapter registers `forever-detached` at
  priority 100 through the existing `Core/Providers.lua` selector.
- Reconciled and physically shared `Nameplates/Auras.lua`, `BubbleNameplates.lua`,
  `NameplateUnits.lua`, `NameplateVisuals.lua`, `NativeNameStyle.lua`, and `Stacking.lua`.
  Shared Nameplate code no longer branches on `IS_TARGET_FOREVER_BUILD` for pooled-frame timing.
- The provider contract preserves each client's existing behavior: Classic keeps immediate Era
  target/faction/heal/power handling and the legacy TurboFace aura row; Forever keeps next-frame
  power/heal/native-refresh staging and routes auras to detached Blizzard `AuraContainer`s.
- Expanded Classic `Core/Compat.lua` with the secret-safe `ReadUnit*` vocabulary and guarded event
  registration used by the shared Nameplate code. On Classic these adapters are direct readable
  legacy calls; no Classic gameplay value becomes opaque.
- `/tf compat plan` now reports both selected providers (`combatMeter` and `nameplates`) so live
  validation can confirm `nameplates=forever-detached` on the Forever client.
- Source convergence rises to 128 byte-identical same-path package files / 59 identical first-party
  source paths, leaving 48 same-path divergences. No SavedVariables schema change.

## 0.17.87-ForeverPrep128-Forever69977

### Multi-client reorganization phase 5 — portable schema ownership
- Unified `Core/Defaults.lua`, `Core/Migrations.lua`, and `Core/Profiles.lua`; the last >=99%-similar
  first-party divergences are now physically shared between Classic and Forever.
- Added shared `Core/Schema.lua`. `TurboFaceDB.dbVersion` / `ns.DB_VERSION` now describe only the
  portable cross-client settings schema and remain **79** on both flavors. Client-only settings
  evolution uses internal per-flavor revisions that are excluded from named profiles and `TF1:`
  exports.
- Added `Core/ForeverSchema.lua` at Forever revision 2. Revision 1 contains the former v79 -> v80
  standalone talent-reminder migration/default changes; revision 2 contains the former v80 -> v81
  movable combined-bag migration/default. Forever-only preset pruning and current-schema cleanup live
  behind the same client schema adapter.
- Added transition handling for Prep127-and-earlier Forever saves and TF1 exports that carry
  `dbVersion=80/81`. Existing live saves adopt the corresponding internal Forever revision before
  returning `dbVersion` to portable schema 79, so completed client migrations are not lost. Legacy
  imports remain accepted during this transition.
- The unified source audit now reports 121 byte-identical same-path package files, 52 identical
  addon-owned source paths, and 54 same-path divergences. No >=99%-similar first-party divergence
  remains.
- No gameplay renderer/provider semantics changed. The Forever restore placeholder remains inert and
  the beta restore/Dev Preset workflow remains client-owned.

## 0.17.87-ForeverPrep127-Forever69977

### Multi-client reorganization phase 4 — provider extraction
- Added shared `Core/Providers.lua`, a deterministic priority/capability registry for runtime
  implementations. Shared consumers can now request an active provider without knowing the client or
  concrete backend.
- Converted Combat Meter ownership to the first provider surface. `Combat/CombatMeter.lua` registers
  the TurboFace CLEU/local-accounting provider at priority 10; Forever's
  `Combat/BlizzardDamageMeterBridge.lua` registers the public `C_DamageMeter` provider at priority
  100 when supported. Core init/slash handling, Options refresh, Movers dependent refresh, and the
  PlayerFrame DPS/HPS badge now consume the selected provider rather than branch on Forever.
- Unified `Combat/DPSBadge.lua`. Both clients now use one provider-neutral badge implementation.
  Classic's provider formats readable DPS/HPS locally; Forever's provider continues to pass the
  opaque Blizzard rate directly to the verified `SetFormattedText` sink without Lua arithmetic.
- Unified `Movers/Movers.lua` and `Movers/Systems.lua`. Objective Tracker mover ownership now comes
  from the shared `movers.questTracker` capability: Classic keeps the existing mover, while Forever
  registers no tracker events/hooks and hides the mover row because Blizzard Edit Mode owns it.
- Added provider/source ownership assertions to the unified build verifier. The common package set is
  now 117 paths / 48 first-party source files; 57 same-path package divergences remain.
- No saved-variable schema change. The Forever restore placeholder remains inert; active restore data
  is not part of this source-convergence change.

## 0.17.87-ForeverPrep126-Forever69977

- Multi-client organization phase 3: performed the first physical source convergence against the actual Classic 0.17.87 tree. Classic now loads the shared `Core/Client.lua` capability registry and its `Core/Compat.lua` exposes behavior-preserving aliases for the secret-safe/shared call-site vocabulary (`ReadUnitHealth*`, threat/GUID/class/friend reads, `IsCurrentSpell`, `ShouldAurasBeSecret=false`, and shared money formatting).
- Promoted twelve previously >=99%-similar first-party files to byte-identical shared source: Combat Meter, DoT Prediction, Heal Prediction, Leash Timer, PvP Health Estimate, SwingTimer spell data, Loot Frame, Nameplates substrate, TurboDebuffs, Skills, Trainer Ignore, and Trainer core. The Forever copies were already the compatibility-routed forms; Classic now consumes those same files without changing Classic semantics.
- The audited common set rises from 100 to 113 packaged paths and from 31 to 44 first-party source files; divergent same-path files fall from 72 to 60. Schema owners (`Defaults`, `Migrations`, `Profiles`) and the protected Objective Tracker mover pair remain client-specific for now.
- Added the executable unified-source overlay model: byte-identical paths live once in `src/common`, divergent/exclusive paths remain under `src/classic` / `src/forever`, and `build/build_client.py` reconstructs either addon without rewriting its TOC order.
- No Forever gameplay implementation changed in this Prep; this is source/build ownership work plus documentation/version metadata.

This document records how the Forever client port reached its current design: API migrations,
secret/protected-value discoveries, live regressions, ownership changes, validation probes, and the
reasons behind consequential client-specific decisions. For the **current** runtime contract and
source/ownership model and current validation requirements, see [`ARCHITECTURE.md`](ARCHITECTURE.md).

The changelog is intentionally newest-first. `ForeverPrepN` is the Forever port/build sequence,
not the `TurboFaceDB` saved-variable schema. The Forever build derives from the Classic Era 0.17.87
product line while targeting Forever 1.60.1 / Interface 16001.

## Current architecture milestones

- **Prep117-123 — Hotbar Power:** restored the Classic user-facing cast-count/missing-resource
  feature through a detached, secret-safe Forever implementation. Blizzard action buttons are
  anchors only; macro/stance resolution is native through `C_ActionBar.GetSpell`; current secret
  power is never inspected by Lua; `UnitPowerPercent(..., curve)` evaluates affordability curves
  inside Blizzard code; and the color fill now means only “cannot afford the first cast.”
- **Prep108-116 — Nameplates:** moved from unsafe pooled-frame mutation to external side tables and
  `UIParent`-owned overlays, added Blizzard-owned AuraContainers for secret aura state, detached
  health text, and stable-alias threat percentages. Native Blizzard nameplate objects remain
  substrate/anchor objects rather than TurboFace state/parent containers.
- **Prep97-107 — Professions/Training:** established modern profession identity and evidence capture,
  detached the TurboFace Training view from Blizzard's retail-derived Professions frame, and began
  rebuilding Forever-specific training data from verified live trainer evidence rather than assuming
  the Classic catalog is authoritative.
- **Prep83-100 — modern Blizzard UI boundaries:** rebuilt detached Spellbook/Training/Skills pages,
  reconstructed native trainer-card presentation, and yielded protected World Map canvas/provider/
  pin internals to Blizzard after a live taint failure.
- **Prep56-70 — combat/action/SavedVariables adaptation:** adopted Forever's `PLAYER_SWING` clock,
  modern current-spell/action-slot APIs, and the beta restore/Dev Preset workflow while retaining
  ordinary Options as the runtime activation model.
- **Prep36-55 — broad client ownership conversion:** bridged the independent DPS/HPS badge to public
  `C_DamageMeter`, introduced detached UnitFrame/Nameplate baselines, and modernized QoL/Trainer/
  Minimap/tooltip boundaries.

### Documentation consolidation — 2026-09-23

- Rebuilt `ARCHITECTURE.md` as a present-tense architecture manual modeled after the Classic document
  instead of continuing to prepend Prep-by-Prep notes. Historical Prep rationale remains here and
  live campaign state remains in `PORT_STATUS.md`.
- Documented the recommended long-term multi-client strategy: one repository/product architecture,
  separate Classic and Forever build flavors, shared feature policy/data where ownership is truly
  common, and explicit client adapters/manifests for divergent Blizzard UI.
- Documented the current architectural debt that status/capability information is duplicated across
  prose, Options checks, `PORT_STATUS.md`, and historical compatibility diagnostics. Prep124 begins
  resolving that debt with the first declarative client feature registry.
- Documentation-only consolidation; no runtime behavior or saved-variable schema change.

## 0.17.87-ForeverPrep125-Forever69977

### Multi-client reorganization phase 2 — actual Classic source audit
- Audited the supplied TurboFace Classic 0.17.87 package directly against Forever Prep124 instead of
  inferring shared ownership from documentation. Classic contains 173 packaged files and Forever 194;
  172 relative paths exist in both, with 100 byte-identical and 72 same-path divergences. Classic has
  one package-only path and Forever has 22.
- Among first-party source files, 31 are already byte-identical, 17 more are >=99% line-similar,
  26 are 95-99%, 15 are 80-95%, and only 12 are below 80%. This confirms the long-term direction of
  one repository with separate Classic/Forever builds rather than two independently maintained addons.
- Replaced the phase-1 guessed build lists with audited `common.list`, `adapted.list`, `classic.list`,
  and `forever.list`; added `build/SOURCE_MAP.md` and a reproducible offline
  `build/compare_clients.py`. The manifests remain non-operative and do not change TOC load order or
  runtime behavior.
- Formalized `Core/Client.lua` validation states as `classic-baseline`, `prepared`, `live-partial`,
  `live-validated`, and `blocked`. The previous ad-hoc `baseline-prepared` UnitFrame label is now the
  canonical `prepared`; this is diagnostic vocabulary only and does not change feature activation.
- Identified the first safe convergence wave: byte-identical source can move to a common physical
  source root without code edits; >=99% files should be reconciled next through API/capability
  boundaries. Schema-bearing Defaults/Migrations/Profiles are explicitly excluded from blind merging
  despite high textual similarity because Forever is schema 81 while Classic remains schema 79.
- No saved-variable schema change and no intended gameplay/UI behavior change.

## 0.17.87-ForeverPrep124-Forever69977

### Multi-client reorganization phase 1 — client registry + source manifests
- Added `Core/Client.lua`, loaded after Forever identity diagnostics and before Config. It is the
  machine-readable client-policy registry for implementation class (`shared`, `adapted`, `reduced`,
  `blizzard-owned`, `blocked`), effective availability, ownership, and coarse validation state. It
  creates no SavedVariables and does not replace normal `TurboFaceDB` user preferences.
- `ns.ModuleEnabled()` now honors group-level client availability while preserving unsupported saved
  preferences unchanged for profile portability. The existing Forever Nameplate fail-closed adapter
  check remains in place, so this is an ownership cleanup rather than a broader activation change.
- Removed the stale hand-maintained `Compat.PORT_MATRIX`. `/tf compat plan` and compatibility exports
  now read the same `Core/Client.lua` registry, eliminating a status table that had fallen behind the
  live Nameplate/UnitFrame/Training/Hotbar ports.
- Began moving Options availability to the registry without changing current behavior: the Forever
  native name-shadow omission, protected MapCanvas zoom/remember controls, and legacy Combat Meter
  window now query client feature entries instead of embedding their own Forever availability rule.
  Client-specific refresh ownership remains explicit where the actual renderer differs.
- Added `build/common.list`, `build/forever.list`, `build/classic.list`, and `build/README.md` as
  **classification-only** manifests. Prep124 still ships/loads from `TurboFace.toc`; the manifests do
  not alter load order or package contents yet. `classic.list` is deliberately empty until the actual
  current Classic source tree is merged—no Classic paths are guessed from documentation.
- Adopted the consolidated present-tense `ARCHITECTURE.md` and updated `PORT_STATUS.md` to make the
  registry the machine-readable classification source while the status file remains the live test
  journal. No saved-variable schema change.

## 0.17.87-ForeverPrep123-Forever69977

### Hotbar Power — hide fill once the action is affordable
- Fixed the Forever secret-power fill visibility curve to use the normalized `cost / maxPower` point expected by `UnitPowerPercent`, rather than the raw spell cost. The previous raw-cost point sat outside the curve's `[0,1]` input domain, so the color tint could remain visible after the player already had enough resource to cast.
- The color overlay now means only **missing power for the first cast**: it disappears immediately at `currentPower >= cost`, while the independent cast counter may continue showing `1.x`, `2.x`, and higher affordability values.
- No secret player-power value is inspected or manipulated in Lua; only readable spell cost/max-power values are used to build the normalized curve.

## 0.17.87-ForeverPrep122-Forever69977

- Hotbar Power now resolves macro action slots with Forever's native `C_ActionBar.GetSpell(actionSlot)` before falling back to TurboFace's legacy macro-body parser. This lets stance-conditioned Warrior macros expose the spell Blizzard currently considers active, so their rage cost can drive the same missing-power fill and cast counter as a directly slotted spell.
- Added `ns.API.GetActionSpell` to the compatibility boundary; no protected action-button internals are hooked or mutated, and TurboFace does not need to parse secure macro conditionals on Forever.
- Extended `/tf powerprobe` action samples with a resolution source (`macro-native`, `macro-fallback`, or the original action type), aggregate macro-resolution counts, and action-spell API availability, making stance/macro validation explicit without touching secret power values.

## 0.17.87-ForeverPrep121-Forever69977

- Fixed the live Prep120 Hotbar Power failure identified by `/tf powerprobe`: raw secret rage reached the detached StatusBar (`value=true`), but all three direct `CurveObject:Evaluate(secretPower)` calls failed before their UI sinks.
- Removed direct curve evaluation of opaque player power. Secret Hotbar curves now use `UnitPowerPercent(unit, powerType, false, curve)`, keeping restricted current-power evaluation inside Blizzard code.
- Curve x-coordinates are normalized from readable spell cost and readable player `UnitPowerMax`; no arithmetic, comparison, formatting, or logging touches the current secret power value or curve results.
- Added a `maxPower` boolean to the render probe and reset every render-stage probe flag at the start of each attempt so diagnostics cannot report stale success.

## 0.17.87-ForeverPrep120-Forever69977

- Fixed Prep119's all-or-nothing secret Hotbar render failure. A rejected counter sink can no longer hide a working missing-power StatusBar, and a fill failure no longer suppresses the counter.
- Routed secret visibility through explicit native color aspects: missing-power alpha goes directly to `StatusBar:SetStatusBarColor`, while counter alpha goes directly to `FontString:SetTextColor`. The containing addon frames keep ordinary alpha values.
- The curve-produced cast count now goes directly to `FontString:SetFormattedText("%s", value)` instead of `SetText(value)`, leaving secret conversion inside the UI setter rather than addon Lua.
- Made the detached secret StatusBar vertical so its fill matches TurboFace's legacy bottom-up resource-progress presentation.
- Extended `/tf powerprobe` with ordinary boolean render-stage diagnostics (`value`, fill curve/sink, count/text sink, counter curve/sink). No opaque power or curve result is inspected or logged.

## 0.17.87-ForeverPrep119-Forever69977

- Rebuilt Hotbar Power's Forever render path around the live probe evidence: player rage is secret, but addon-owned StatusBars and numeric curves may consume it.
- Missing-power fills now pass opaque power directly into a detached StatusBar. Blizzard step curves calculate the visible fill state and cast-count steps, and secret results are passed directly to alpha/text setters without addon-side arithmetic or inspection.
- Retained the original arithmetic/formatting path for readable Classic/Era values. Forever secret counters use whole or one-decimal steps to keep curve size bounded.

## 0.17.87-ForeverPrep118-Forever69977

- Fixed Hotbar Power resolving zero actions on Forever: `PowerCost.lua` now consumes `C_ActionBar.GetActionInfo` and `C_ActionBar.HasAction` through the central compatibility boundary instead of binding removed legacy globals at file load.
- Added `/tf powerprobe`, a bounded read-only report of module state, button discovery, action/cost resolution, readable power values, and detached overlay allocation.

## 0.17.87-ForeverPrep117-Forever69977

- Re-enabled the Hotbar Power design for Forever using the build-16001 spell-cost and readable player-power path verified against MissingPower.
- Detached cast-counter and missing-power artwork from protected Blizzard action buttons. Overlay frames are owned by `UIParent`, button identity lives in a weak side table, and TurboFace no longer writes `_tfPowerOverlay` or parents addon frames to native buttons.
- Made the Forever Hotbar Power module gate apply immediately without prompting for `/reload`, avoiding the beta SavedVariables loader defect while testing or tuning the feature.

## 0.17.87-ForeverPrep116-Forever69977

- Restored readable nameplate threat percentages using the stable-unit-alias strategy observed in Details Tiny Threat for Forever. Direct `nameplateN` calls remain forbidden/secret; TurboFace maps detached plate state to `target`, `focus`, `mouseover`, `pettarget`, and party/raid member target aliases before querying threat.
- Added `Compat.ReadUnitThreatPercent`, which validates tanking state, status, and scaled percentage independently. A secret unused raw-percentage or absolute-threat return no longer discards a readable scaled percentage, while a secret scaled value still fails closed to the coarse status fallback.
- Kept TurboFace's existing percentage display and color thresholds rather than adopting signed absolute-threat differences. A demand-driven 0.20-second cadence updates only while nameplate threat numbers or aggro audio are enabled and active plate state exists.
- Retained TurboFace's detached `UIParent` overlay ownership. No Tiny Threat plate parenting, native frame-level reads, aura scans, or raw-secret `SetFormattedText` fallback was copied. `/tf debug modules` now reports readable aliases, mapped plates, and visible threat numbers.

## 0.17.87-ForeverPrep115-Forever69977

- Corrected the vertical position of whole-nameplate health text. The Blizzard nameplate root includes the name row above the health chassis, so its geometric center placed the text too high; whole-plate mode now retains that root's horizontal center with a six-unit downward health-row alignment.
- Fill-only mode remains at the native health bar's unmodified center.

## 0.17.87-ForeverPrep114-Forever69977

- Fixed **Center Across Entire Nameplate** having no visible effect on Forever. The native `HealthBarsContainer` shares the health fill's center on this build, so both choices previously resolved to the same point.
- Whole-nameplate centering now uses the TurboFace overlay's center, which is already anchored center-to-center on the Blizzard nameplate root. Fill-only centering continues to use the native health bar as a write-only anchor; no Blizzard geometry is measured or mutated.

## 0.17.87-ForeverPrep113-Forever69977

- Replaced the deferred/broken Blizzard nameplate-health centering path on Forever with a TurboFace-owned detached FontString. It anchors to either the full native `HealthBarsContainer` or the health fill according to the existing option, without parenting to, measuring, re-anchoring, hiding, or storing state on a Blizzard nameplate region.
- Added a secret-safe health-text compatibility boundary. Opaque `UnitHealth` is passed directly through Blizzard's `AbbreviateNumbers` and into the addon-owned FontString; TurboFace performs no comparison, arithmetic, concatenation, percentage calculation, or Lua formatting on secret health.
- The display refreshes on guarded `UNIT_HEALTH`/`UNIT_MAXHEALTH` events and fails closed if the client rejects the opaque text write. Forever's option is now honestly labeled **Center Health Text**; Era retains **Center Blizzard Health Text** and its existing native-anchor implementation.

## 0.17.87-ForeverPrep112-Forever69977

- Retired TurboFace's detached name-shadow workaround on Forever. Blizzard now renders a native name shadow, so drawing a second copy visibly duplicated NPC names. The Forever adapter never creates the duplicate and hides any object left from an earlier live session.
- Hid **Name Text Shadow** from the Forever Nameplates options while preserving the setting and native FontObject implementation on Era clients. `/tf debug modules` reports `shadow=blizzard-native`.

## 0.17.87-ForeverPrep111-Forever69977

- Fixed the first live detached-aura failure: Blizzard marks generated `CustomAuraButton` objects forbidden once secret aura state is attached. TurboFace now performs button size/font/art setup only inside the initial creation callback and never restyles an existing button.
- Bound AuraContainers are now immutable during general nameplate refreshes. TurboFace no longer reapplies groups/layout, forces `UpdateAllAuras`, or redundantly shows/enables a bound container; Blizzard owns ongoing secret aura updates. Explicit plate release still uses the template's supported disable/hide lifecycle.
- Replaced the raw numeric duration formatter—which displayed thousandths of a second—with native bound formatting rules matching TurboFace's prior presentation: whole seconds below 90 seconds, compact minutes from 90 seconds, and compact hours from 60 minutes. TurboFace still never reads or compares the secret remaining duration.

## 0.17.87-ForeverPrep110-Forever69977

- Forever's detached **Nameplates** and **Auras** module gates now activate/deactivate through their complete live refresh paths instead of showing the generic reload-required popup. This avoids the beta SavedVariables loader restoring an older snapshot and undoing the user's newly selected test state during `/reload`.
- Other module gates retain the existing reload boundary; the exception is limited to the two Forever adapters that own reversible event, pooled-frame, and CVar lifecycles.

## 0.17.87-ForeverPrep109-Forever69977

- Restored option-gated Forever nameplate aura rows through Blizzard's modern `CustomAuraContainerTemplate`. The two TurboFace containers and every icon are direct `UIParent` descendants; Blizzard's health bar is used only as a write-only anchor target, and no addon field or child is attached to a native plate.
- Aura enumeration, secret duration handling, cooldown binding, sorting, and `UNIT_AURA` updates remain inside Blizzard's `AuraContainer`. TurboFace never calls secret aura index/data APIs and registers no independent aura event. Existing debuff/buff limits, dimensions, spacing, growth, duration filters, blacklist, whitelist, and buff-filter mode are translated into native container groups/candidate filters.
- Friendly/unknown classification fails closed: detached rows bind only when `ReadUnitCanAttack("player", unit)` is explicitly true. Pooled roots disable and hide their containers on removal, and Options refreshes reconfigure existing containers without touching Blizzard-owned frames.
- `/tf debug modules` now reports AuraContainer support, active detached aura rows, and the last aura-container error separately from the core nameplate adapter.

## 0.17.87-ForeverPrep108-Forever69977

- Added `/tf nameplateapiprobe`, a bounded read-only inventory of the native Forever nameplate capabilities relevant to the next Blizzard-owned implementation. It reports native manager/setter availability without invoking setters, texture loading-group tags, secret-safe color curves, modern aura-duration/template support, and a numbered object-presence view of currently visible plates.
- `/tf nameplateapiprobe plate N` safely reports one plate's ordinary/forbidden lookup identity, known Blizzard region objects, readable unit identity, and detached TurboFace state. It never reads native health/text/cooldown values, measures Blizzard geometry, installs hooks, registers events, or retains native objects.

## 0.17.87-ForeverPrep107-Forever69977

- Fixed pooled native trainer cards occasionally retaining a gray or tinted icon presentation after rebinding. Every row now clears desaturation and restores an opaque white vertex color both during pool reset and after assigning the current entry texture, so `Available Now` icons consistently render with their authored color.

## 0.17.87-ForeverPrep106-Forever69977

- Fixed Forever profession Training putting learned recipes back under `Available Now`. The detached page now reads the active character's `C_TradeSkillUI.GetRecipeInfo(recipeID).learned` state and matches by stable recipe ID as well as localized name; the removed legacy trade-skill list remains only as the non-Forever fallback.
- Fixed the final profession-skill gate consulting Classic's unavailable skill-line scanner after the page had already obtained the correct modern rank. Forever now validates `skillReq` against the matching active profession's `GetBaseProfessionInfo().skillLevel`, so Blacksmithing 41 recipes through skill 40 are available while skill 45+ recipes remain unavailable.
- Training queries only its deduplicated candidate recipe IDs rather than rescanning the full 512-recipe profession catalog on every search/collapse refresh. The Recipes view still scans the complete native catalog because it must classify every recipe there.

## 0.17.87-ForeverPrep105-Forever69977

- Fixed profession Training cards displaying a skill bucket as `Requires: Level 20`. Older trainer captures stored the gate only as the outer `professionData[skillReq]` bucket, while the native card renderer treated any shown `entry.level` as a character-level fallback.
- Profession observations now persist both `skillReq` and the localized `skillName`. Existing bucket-only SavedVariables are normalized through a shallow in-memory view, so no migration or recapture is required.
- Native and fallback cards now render named profession gates in parenthesized form, such as `Requires: Blacksmithing (20)`. Explicit character-level requirements remain independently supported and class trainer rows retain `Requires: Level N`.

## 0.17.87-ForeverPrep104-Forever69977

- Extracted the completed Blacksmithing snapshot: 512 live recipes versus 315 Classic records, with 203 live-only crafts and six Classic-only records. The dataset confirms large Forever-specific armor/weapon families and profession objects rather than a small rank reshuffle.
- Added the first evidence-backed Forever profession training seeds: Glowing Copper Boots (`1252231`) and Strange Copper Boots (`1252230`), both taught at Blacksmithing 35 for 95 copper. They now appear without depending on a prior per-character trainer observation; live capture still overrides seeded metadata by spell ID.
- Fixed bulk-capture client metadata losing build/interface values. `GetBuildInfo()` is now assigned directly so Lua preserves all returns instead of collapsing them through a boolean expression. The already-extracted recipe and trainer payload was unaffected, and its authoritative compatibility login record identifies build 69977.

## 0.17.87-ForeverPrep103-Forever69977

- Added `/tf professiondataprobe capture recipes`. It enumerates the active profession's full modern recipe catalog in batches of 20 per frame and saves complete readable `GetRecipeInfo`, requirements, schematic/reagent structure, source, item link, cooldown, trade-skill-line mapping, and quality-item results under `TurboFaceCompatDB.professionDataProbe`.
- Added `/tf professiondataprobe capture trainer`, which saves every currently open trainer service with name, rank, status, spell ID, required profession skill, required character level, cost, skill line, and icon into the same per-profession snapshot.
- Capture recursively removes secret and unserializable values, bounds recursion/table size, records completion metadata, and uses the already-declared account-wide compatibility SavedVariables file. This eliminates manual copying of 86 Blacksmithing recipe pages: after the completion message, log out to character selection so the client writes the snapshot for external extraction.

## 0.17.87-ForeverPrep102-Forever69977

- Updated the live Forever target after the beta advanced from build 69913 to 69977. The prior exact-build comparison silently made `IS_TARGET_FOREVER_BUILD` false, disabling detached profession/spellbook adapters, native-frame taint boundaries, swing compatibility, and the SavedVariables fallback on the new hotfix.
- Forever identity now uses the stable full tuple `version=1.60.1`, `interface=16001`, and `project=1`; the numeric hotfix build is recorded for diagnostics rather than used as an activation boundary. This does not match ordinary Retail and prevents the next same-version hotfix from reopening unsafe Blizzard ownership paths.
- The Prep101 profession-data result is valid: every `R[N] id=####` value is directly accepted by `/tf professiondataprobe recipe ####` (for example, Copper Chain Pants is `2662`).

## 0.17.87-ForeverPrep101-Forever69913

- Added `/tf professiondataprobe`, a bounded read-only discovery tool for rebuilding the changed Forever profession catalog. Its summary reports the active profession, readiness, deduplicated recipe count, and which modern recipe enumeration surfaces actually returned data.
- Added paged `recipes N`, `categories N`, `trainer N`, and `apis N` modes. Recipe pages expose stable IDs and core `GetRecipeInfo` fields; trainer pages expose the teaching name/rank/status, resolved spell ID, required profession skill, required character level, price, and reported skill line. Six rows per page avoid Blizzard chat truncation.
- Added `recipe ID` detail mode for structured requirements, schematic/reagent shape, item link, description, source text, cooldown, output count/quality IDs, and recipe-to-skill-line mapping. The probe installs no hooks, retains no native objects/tables, and never selects, learns, trains, or crafts.

## 0.17.87-ForeverPrep100-Forever69913

- Fixed the World Map `ADDON_ACTION_BLOCKED` failure at protected `Button:SetPassThroughButtons()`. TurboFace's enhanced-zoom implementation post-hooked Blizzard's native `ScrollContainer:CreateZoomLevels`, replaced its `baseScale`/`zoomLevels`, and hooked its mouse-wheel script; Forever later reused that tainted MapCanvas execution while acquiring protected quest-pin buttons.
- Forever now gives Blizzard exclusive ownership of `WorldMapFrame.ScrollContainer`, MapCanvas methods, data providers, pin pools, and pin buttons. Enhanced cursor zoom, the custom zoom ceiling, and remembered pan/zoom are dormant on build 69913, and `PlusMap:Refresh()` cannot invoke native canvas methods there.
- The top-level windowed-map drag remains available. Its position restores through a deferred `OnShow` callback without post-hooking `SynchronizeDisplayState`; non-Forever clients retain the existing zoom and remember behavior.

## 0.17.87-ForeverPrep99-Forever69913

- Rebuilt the detached profession book launcher from the live Forever tab probe. Its 55×55 chassis now uses Blizzard's `common-sidetab` atlas, the book icon is clipped by `common-sidetab-mask` and centered at the native `-4` horizontal offset, and the open/hover states use `common-sidetab-selected` and `common-sidetab-hover` respectively.
- Removed the legacy spellbook-side-tab border and glow textures that made the book appear as a separate square icon beneath the native profession rail. Functionality, detached ownership, selected-profession detection, and per-profession queues are unchanged.

## 0.17.87-ForeverPrep98-Forever69913

- Added a detached profession Training page for Forever's Retail-derived `ProfessionsFrame`. A single addon-owned 55×55 book tab appears beneath the last visible native profession tab and follows the profession selected by Blizzard through `C_TradeSkillUI.GetBaseProfessionInfo()`.
- Clicking the book hides only Blizzard's `CraftingPage` after capturing its visibility, then displays TurboFace's existing trainer-teaching and queue data in a two-column grid using the reconstructed native trainer cards and parchment. Clicking it again restores the exact native state; closing the window, disabling Trainer Spells, or selecting the native Overview page also cleans up safely.
- TurboFace does not parent its launcher/content into `ProfessionsFrame`, register with a native tab system, change native tab state, or replace Blizzard's recipe provider. Native profession switching is observed through existing trade-skill data events and refreshes the open TurboFace page on the next callback.
- Profession collapse keys now include the canonical profession owner, and modern profession entries use their queue owner for ignore actions. Blacksmithing, Cooking, and other profession queues and view state therefore remain isolated.

## 0.17.87-ForeverPrep97-Forever69913

- Added `/tf professionprobe`, a bounded read-only inspector for Forever's Retail-derived Professions window. Its summary reports the current `C_TradeSkillUI` and legacy profession identity results, visible profession roots, relevant state fields, and ranked native button/tab candidates.
- Added `/tf professionprobe button N`, `root N`, `crafting`, and `tabs` detail modes for exact anchors, parentage, text, and native textures. This supplies the evidence needed to place an addon-owned book launcher in the profession header and make its detached Training page follow Blizzard's selected profession without joining or mutating the native tab system.
- The probe installs no hooks, retains no native objects, and changes no selection or visibility state. Profession queues remain separated by their existing `scope="profession"` and canonical owner keys.

## 0.17.87-ForeverPrep96-Forever69913

- Corrected the compact Horde Staves source to `Ansekhwa - Thunder Bluff`. What's Training lists several valid Horde weapon masters for Staves; the previous generic first-entry rule selected Hanashi in Orgrimmar.
- Added a per-faction/per-weapon primary-master override layer while retaining the complete adapted source catalog, so presentation choices no longer depend solely on declaration order.

## 0.17.87-ForeverPrep95-Forever69913

- Replaced weapon-skill card requirement text such as `Requires: Skill 50` with `Source: NPC Name - Capital City`.
- Adapted What's Training?'s MIT-licensed Classic weapon-master catalog for the eight Alliance/Horde capital trainers and their taught weapon spell IDs. Cards choose the first deterministic faction-appropriate master for a compact source line; capital names use `C_Map.GetAreaInfo` when available for client localization.
- Live trainer capture may still update price/icon metadata, but its generic `Weapon Master` source marker no longer overwrites the more specific static NPC/city source. Profession and class-spell requirement rendering is unchanged, and the third-party notice now explicitly covers the weapon-master catalog.

## 0.17.87-ForeverPrep94-Forever69913

- Fixed the Skills tab warning at `Trainer/UI_Core.lua:474`. Class spell entries use `requires` as a table of prerequisite spell IDs, while profession rank rows and captured trainer metadata could use the same field for text such as `Mining 65`; the native-card renderer passed that string to `ipairs`.
- Split the schemas cleanly: `requires` is now table-only at the shared entry boundary, while human-readable profession requirements use `requirementText`. Existing persisted/captured string values are migrated in memory and ignored safely by both prerequisite rendering and talent classification.
- Added a regression contract covering generated profession ranks, captured metadata, legacy string values, the renderer, and the talent classifier.

## 0.17.87-ForeverPrep93-Forever69913

- Corrected the remaining trainer page/card interior mismatch. Blizzard's normal `404984` service-row sprite is translucent: its orange parchment interior comes from the large trainer-frame background at the top of the same texture sheet, not from the generic dark `UI-Background-Marble` texture (`374154`) used by `InsetFrameTemplate`.
- The detached page now renders the exact trainer-frame crop (`0.00195313,0.58593750,0.00195313,0.65429688`) beneath the card grid and suppresses the generic dark inset fill. Minimized mode uses one parchment panel; expanded mode uses a panel for each half of the two-page book so the native texture is not distorted across the full spread.
- The corrected Prep92 service-row borders, highlights, prices, responsive two/four-column grid, and native Spellbook ownership boundary are unchanged.

## 0.17.87-ForeverPrep92-Forever69913

- Reconstructed the native trainer service-card sprites from the corrected eight-corner probe. Texture `404984` now uses exact normal (`0.0020,0.5742,0.6582,0.7500`), highlight (`0.0020,0.5742,0.7539,0.8457`), and selected (`0.0020,0.5742,0.8496,0.9414`) legacy bounds, so the baked rounded rectangle spans the complete card and encloses the top-right price.
- Replaced the generic Spellbook inset fill with the live trainer inset parchment, FileDataID `374154`, using Blizzard's measured tiled coordinates. TurboFace retains the inset template's native frame treatment while the Training and Skills cards keep the responsive two-column/one-page and four-column/two-page layout.
- Confirmed from the probe that the service-card border is baked into the ordinary, non-tiled `404984` sprite; no guessed NineSlice or custom border is introduced.

## 0.17.87-ForeverPrep91-Forever69913

- Corrected the trainer-style probe's texture-coordinate reporting. Forever returns four transformed corners (`ulX,ulY,llX,llY,urX,urY,lrX,lrY`); Prep85 incorrectly labeled only the first four values as legacy left/right/top/bottom coordinates. The resulting Prep88 crop copied vertical sprite-sheet positions into the horizontal axis, causing visible card art to end before its price.
- Texture reports now print all eight coordinates at four-decimal precision plus slice margins, slice mode, and horizontal/vertical tiling. This will distinguish an ordinary cropped sprite from Blizzard's rounded-border sliced texture before the final card reconstruction.

## 0.17.87-ForeverPrep90-Forever69913

- Extended `/tf trainerstyleprobe` with `root N` selection so the live trainer's top-level background, inset, money background, and other named visual regions can be inspected directly rather than only through service-row candidates.
- The new root detail path reports a texture/font root directly or a frame's geometry, backdrop, regions, and immediate children. This targets the remaining Prep89 visual mismatch: the native service card's rounded frame is baked into texture `404984`, while TurboFace's price currently occupies the texture's transparent reservation instead of a framed area.

## 0.17.87-ForeverPrep89-Forever69913

- Made the Forever Spellbook Training and Skills card layout responsive to Blizzard's book form: the minimized one-page book displays two cards per row, while the expanded two-page book displays four cards per row.
- Category headers remain full-width and cards never flow across a category boundary. Each visual row retains the probe-derived 47px height and uses a compact two-pixel gutter, keeping the same card width per column in both book forms.
- A deferred secure post-hook observes `SpellBookFrame:SetMinimized`; when the TurboFace page is open, it reanchors the detached content and rebuilds only its addon-owned data provider after Blizzard finishes changing book geometry. No native tab pool or layout state is touched.

## 0.17.87-ForeverPrep88-Forever69913

- **Superseded by Prep91:** the visual measurements remain valid, but the four-value UV interpretation below was incorrect; final coordinates must come from the corrected eight-corner probe.
- Rebuilt the Forever Spellbook Training/Skills entry presentation from the live Blizzard trainer probe. Entry cards now use Blizzard texture `404984` with the probed normal (`0,.7,0,.8`), hover (`0,.8,0,.8`), and selected (`0,.8,0,.9`) UV treatments, stretched only horizontally to the wider Spellbook page.
- Matched the native 47-pixel card rhythm, zero inter-card gap, 36×36 icon at a six-pixel inset, 12px gold service name, 10px rank and requirement line, and top-right price placement. Prices use TurboFace's shared Blizzard-native money formatter and current coin atlases.
- Requirement lines now follow Blizzard's `Requires:` form and can show colored level, profession-skill, and prerequisite-spell/rank requirements. Met requirements are white and unmet requirements are red.
- Hover uses Blizzard's additive highlight slice. TurboFace's queued state uses the additive selected slice, preserving the existing left-click queue behavior rather than introducing a second selection model. Header grouping, collapse controls, tooltips, ignore actions, classifications, and Classic/Era/profession layouts remain unchanged.

## 0.17.87-ForeverPrep87-Forever69913

- Fixed `/tf trainerstyleprobe` root discovery indexing global functions such as `GetTrainerServiceTypeFilter` as though they were frames. Candidate globals are now type-checked as tables/userdata before any method lookup.

## 0.17.87-ForeverPrep86-Forever69913

- Fixed `/tf trainerstyleprobe [row]` routing. Prep85 registered the handler only inside the `/tf debug ...` dispatcher, so the documented top-level command fell through and opened TurboFace Options. Both `/tf trainerstyleprobe` and the shorter `/tf trainerstyle` now route directly to the read-only probe.

## 0.17.87-ForeverPrep85-Forever69913

- Added `/tf trainerstyleprobe`, a read-only inspector for the live Forever Blizzard trainer window. Run it with the trainer open to discover likely service-card rows; then run `/tf trainerstyleprobe N` for a selected candidate's exact dimensions, anchors, parent/child hierarchy, backdrop files/colors, button textures, texture atlases and coordinates, fonts, text colors, alignment, and visible regions.
- The probe performs a bounded one-shot traversal only when invoked. It installs no hooks, OnUpdate handlers, or persistent frame references and does not mutate the native trainer.
- This supplies the measurements needed to redesign TurboFace's Spellbook Training page around Blizzard's native trainer-card visual language rather than either the old or current What's Training presentation.

## 0.17.87-ForeverPrep84-Forever69913

- Fixed the Prep83 Spellbook launcher initialization error in `TabSystemTemplates.lua:UpdateTabWidth`. `SpellBookCategoryTabTemplate:Init()` calls through its parent while calculating square-mode width, so the detached launcher must be parented to the real `CategoryTabSystem`, exactly as What's Training does.
- The launchers remain outside `CategoryTabSystem.tabs`, its pools, and its layout; no `AddNamedTab`, `layoutIndex`, `MarkDirty`, or native selection mutation was introduced. The TurboFace content page remains detached on `UIParent`.

## 0.17.87-ForeverPrep83-Forever69913

- Restored the **Class Trainer** and **Skills** views beside Forever's Player Spells book using the proven detached-launcher pattern from What's Training. TurboFace's two unregistered `SpellBookCategoryTabTemplate` buttons are visually anchored beside Blizzard's tabs, while its content frame is owned by `UIParent`.
- The restored integration never joins `CategoryTabSystem.tabs`, calls `AddNamedTab`, creates native layout slots, marks Blizzard's layout dirty, or changes pooled native-tab selection state. This preserves the Prep79 secret-cooldown taint boundary while bringing the feature back.
- Native category navigation closes the TurboFace page through a zero-delay deferred restore, outside Blizzard's tab call stack. Opening or changing a TurboFace page is blocked during combat, and native page-widget visibility is restored exactly when leaving the page or disabling Trainer Spells.
- Added static and runtime contracts covering ownership, native-pool immutability, deferred restoration, exact visibility restoration, page switching, and combat blocking.

## 0.17.87-ForeverPrep82-Forever69913

- Fixed the standalone Spend Talent Point reminder on Forever by preferring Retail's `C_ClassTalents.HasUnspentTalentPoints()` over surviving legacy globals that can remain present but report a stale zero on the hybrid client. Readable class and specialization counts are combined; the accessible boolean result remains a fallback.
- Added modern talent refresh signals (`TRAIT_CONFIG_UPDATED`, `TRAIT_NODE_CHANGED`, `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`, and `UNIT_LEVEL`) through guarded event registration.
- Level/talent events now perform three bounded refreshes at 0, 0.25, and 1 second because Forever can publish the new point state after `PLAYER_LEVEL_UP`. No polling or OnUpdate driver was added.
- Added `/tf talentprobe`, which reports the normalized point count, selected API source, option state, mover-hidden state, frame availability, and current visibility.

## 0.17.87-ForeverPrep81-Forever69913

- Fixed Quest Greeting NPCs with multiple available quests, including the **Supervisor Fizsprocket** / **The Venture Co.** case. The Greeting branch previously marked a row processed as soon as it called `SelectAvailableQuest`; if Forever dropped that selection during the NPC refresh, the still-visible quest could not be retried.
- Quest Greeting active and available selections now use the same lifecycle-confirmed pending state and timeout retry as modern gossip. `QUEST_DETAIL` / `QUEST_PROGRESS` confirms the selection; an unconfirmed selection becomes eligible again after the existing short timeout.
- Available Greeting rows prefer `GetAvailableQuestID(index)` for stable identity when exposed, fall back to title, and finally use an interaction-local index key. `/tf questprobe` now reports each Greeting available quest's ID and processed state.

## 0.17.87-ForeverPrep80-Forever69913

- Added **Allow dragging Blizzard's combined bag** under QoL > Interface. It augments only `ContainerFrameCombinedBags`; Blizzard continues to own the bag's contents, sizing, appearance, and open/close behavior, while individual bag windows remain untouched.
- Dragging the combined bag by its native title (or empty frame background when no title container is exposed) saves one UIParent-relative anchor in `TurboFaceDB.combinedBag`. The saved anchor is reapplied one frame after each show so Blizzard can finish its normal container layout first.
- Movement and restoration fail closed during combat and retry after `PLAYER_REGEN_ENABLED`. The implementation uses no polling, no OnUpdate handler, and no TurboFace mover overlay.

## 0.17.87-ForeverPrep79-Forever69913

- Retired TurboFace's embedded Training/Skills tabs inside the native Player Spells book on Forever after a level-up/spellbook refresh reached `CooldownFrame_Set` with secret cooldown values while execution was tainted by TurboFace.
- The old integration parented TurboFace layout slots and tab-template children directly into Blizzard's pooled `CategoryTabSystem`, marked its layout dirty, and hooked native tab methods. Forever now exits before creating the loader, tabs, children, scripts, or hooks, leaving Blizzard as the sole owner of the Player Spells frame and its cooldown-button pools.
- Trainer capture, training lists, tooltip augmentation, queue behavior, and profession integration remain available. Classic/Era embedded Spellbook tabs are unchanged.

## 0.17.87-ForeverPrep78-Forever69913

- Retired TurboFace's Quest Tracker mover on Forever after a level-up taint failure in Blizzard's Objective Tracker: `ScenarioObjectiveTracker:LayoutContents` reached `ShouldShowMawBuffs`, whose secret aura query was rejected because execution was tainted by TurboFace.
- Root cause was the legacy mover attaching callbacks to the native Objective Tracker's `SetPoint` and update paths and synchronously reapplying placement while Blizzard layout was still executing. Forever now installs no Objective Tracker hooks, performs no frame mutations, and subscribes to no tracker-reapply events. Blizzard Edit Mode is the sole placement owner for this native frame.
- Classic/Era QuestTracker, WatchFrame, and Questie mover behavior is unchanged.

## 0.17.87-ForeverPrep77-Forever69913

- Live `/tf questprobe` output proved Baine uses the legacy-named Quest Greeting surface (`C_GossipInfo` active/available counts were both zero), so the preceding modern-gossip corrections could not select **Rites of the Earthmother**.
- Ported Quest Greeting turn-in detection to Forever's Mainline-derived contract. TurboFace now reads completion from return #2 of `GetActiveTitle(index)`, obtains the stable quest ID with `GetActiveQuestID(index)`, and checks `C_QuestLog.ReadyForTurnIn(questID)` through Compat. The removed/optional `IsActiveQuestComplete` global is only a fallback rather than a prerequisite for processing every active quest.
- Extended `/tf questprobe` with `greetingActive`, `greetingAvailable`, and `GA[]` / `GV[]` rows so the legacy-named QuestFrame payload is visible alongside modern gossip data.

## 0.17.87-ForeverPrep76-Forever69913

- Corrected the turn-in compatibility boundary after Prep75 did not change the live Baine result. Forever can expose the legacy-named `QuestReadyForTurnIn` global alongside the modern API; `ns.API.QuestReadyForTurnIn` now prefers `C_QuestLog.ReadyForTurnIn(questID)` rather than allowing the legacy symbol to shadow it.
- Added `/tf questprobe`. While an NPC quest list is open, it reports every active and available quest ID/title, the gossip completion flag, `C_QuestLog.IsComplete`, modern and legacy readiness results, the final Compat result, pending selection, and processed state. This provides a decisive live payload if the modern readiness correction is not sufficient.

## 0.17.87-ForeverPrep75-Forever69913

- Fixed Forever turn-ins such as **Rites of the Earthmother** being skipped while available quests at the same NPC were accepted. The gossip entry's `isComplete` flag and `C_QuestLog.IsComplete()` can both remain false for this state; quest automation now also consumes the compatibility boundary for `C_QuestLog.ReadyForTurnIn(questID)` before deciding an active quest is still in progress.
- Completed/ready active quests continue to take priority over newly available quests. Added runtime coverage for the exact Forever return shape: gossip incomplete, quest-log incomplete, but explicitly ready for turn-in.

## 0.17.87-ForeverPrep74-Forever69913

- Fixed multi-quest NPC automation stalling after one or two actions. Modern gossip quests are no longer marked processed when TurboFace merely calls `C_GossipInfo.SelectAvailableQuest` or `SelectActiveQuest`; `QUEST_DETAIL` / `QUEST_PROGRESS` must now confirm that Retail actually opened the quest.
- If Retail drops a selection while refreshing the NPC's gossip options, the pending quest becomes eligible again after a short timeout and the serialized pump retries it. `GOSSIP_OPTIONS_REFRESHED`, `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, and `QUEST_REMOVED` now drive follow-up passes through stacked accepts and turn-ins.
- Added `GOSSIP_CLOSED(interactionIsContinuing)` ownership. Transitions between an NPC's gossip and quest panels retain the current chain, while fully closing and reopening the same NPC clears stale processed state.

## 0.17.87-ForeverPrep73-Forever69913

- Routed the Inventory auto-sell completion message through `ns.API.FormatMoney`. The “sold junk for” chat line now uses Blizzard's native `coin-gold`, `coin-silver`, and `coin-copper` atlas presentation instead of the legacy coin texture string.

## 0.17.87-ForeverPrep72-Forever69913

- Fixed intermittent missing completed-quest XP in the Luxthos-like Experience Bar by following Retail's asynchronous reward-data contract. TurboFace now checks `HaveQuestRewardData(questID)`, requests unavailable records through `C_QuestLog.RequestLoadQuestByID(questID)`, and rescans on `QUEST_DATA_LOAD_RESULT`.
- A scan with any unloaded reward now preserves the last complete quest-XP snapshot instead of committing a partial total. Once all data is available, cached reward amounts are still reclassified on every scan so newly completed quests move immediately from the incomplete segment to the completed segment.
- Removed the obsolete quest-selection scan. Retail's `C_QuestLog.SetSelectedQuest` accepts a quest ID, not the legacy log index TurboFace supplied, and `GetQuestLogRewardXP(questID)` no longer requires selection. The Experience Bar can now refresh while the Quest Log is open without altering Blizzard's selection.
- Added `QUEST_REMOVED` and `QUEST_TURNED_IN` refreshes so turned-in or abandoned rewards leave the overlays immediately.

## 0.17.87-ForeverPrep71-Forever69913

- Routed Loot Frame item vendor values through the shared `ns.API.FormatMoney` compatibility boundary. Forever now uses Blizzard's native `MoneyFormatterUtil` presentation with `coin-gold`, `coin-silver`, and `coin-copper` atlases instead of the legacy coin texture string.
- Money-loot rows share the same formatter, keeping all currency presentation inside the Loot Frame consistent. Compat retains legacy texture-string and plain-text fallbacks for clients without the modern formatter.

## 0.17.87-ForeverPrep70-Forever69913

- Fixed the live Level-1 Warrior result where 40/40 macros synchronized but 30 macro action slots reported missing. Forever's modern `C_ActionBar.GetActionInfo` macro `actionID` is not the legacy absolute macro-list index, so comparing it with the account-macro limit produced false character scopes.
- Action-profile saves now derive macro scope from the already captured macro records. Duplicate macro names across account and character lists remain unscoped and are resolved by exact name at restore time.
- Macro action lookup now prefers the recorded scope but falls back to the other macro list by exact name. Existing Prep69 Warrior profiles therefore recover without a resave; the 30 false character references can find their account macros immediately.
- The separately reported unavailable spell slots remain intentionally deferred when a fresh Level-1 character has not learned those spell IDs.
- The Linux saver now resolves its physical directory and explicitly reports when a terminal is still attached to a deleted addon under Linux Trash, instead of presenting that situation as a generic missing-WTF error.

## 0.17.87-ForeverPrep69-Forever69913

- Reworked **Apply Stored Profile** to start the staged Quick Setup restore immediately. It no longer writes a per-character pending flag and asks for `/reload`, which was incompatible with the Forever SavedVariables preload workaround.
- Added `ns.ApplyCVarBaseline()`: reload-free profile applies update the saved baseline inside active TurboFace CVar-owner snapshots while leaving their temporary live overrides intact; unowned CVars apply immediately.
- Added Retail macro-capacity normalization through `ns.API.GetMacroLimits()`, preferring `Constants.MacroConsts`. Quick Setup now scans and validates all 30 character-macro slots on Retail-derived clients instead of falling back to 18.
- Corrected Edit Mode preset naming by converting the one-based full layout index to the zero-based `Enum.EditModePresetLayouts` value.
- Quick Setup now records action slots whose Retail action kind it cannot recreate. Supported actions still restore, but exact fresh-character cleanup is skipped when the snapshot is incomplete so flyouts, summoned pets, outfits, or future action kinds cannot be silently erased.
- Extended Quick Setup import validation, status reporting, diagnostics, and contract coverage for the new unsupported-action metadata and reload-free workflow.

## 0.17.87-ForeverPrep68-Forever69913

- Added `Save-TurboFaceForever.sh` for native Linux/Proton and Wine-prefix installations. It accesses the prefix as ordinary Linux files and does not require PowerShell, Wine, or execution inside Proton.
- The Linux saver infers the Forever `WTF` directory from the installed addon path and mirrors the Windows guardrails: fork/folder filename discovery, numeric realm support, newest-file selection, same-account enforcement, primary-root validation, explicit `SAVE` confirmation, timestamped backup, and atomic restore-file replacement.
- Added `--wtf-root`, `--account-file`, and `--character-file` overrides for symlinked addons, staging trees, or unusual prefix layouts. SavedVariables restoration semantics are unchanged from Prep67.

## 0.17.87-ForeverPrep67-Forever69913

- Added an inert-by-default `Core/ForeverRestoreData.lua` preload before every SavedVariables consumer. A generated snapshot can therefore restore TurboFace's six account-wide and four per-character database roots even when Forever writes them to disk but fails to load them.
- Added `Save-TurboFaceForever.bat` and `Tools/Save-ForeverVariables.ps1`. After logout to character selection, the saver finds the most recently written account and character `TurboFace.lua` files, supports numeric realm directories, verifies both files belong to the same account, validates the primary database assignments, requires an explicit `SAVE` confirmation, backs up the previous snapshot, and replaces the preload atomically.
- The hardcoded Forever Dev Preset is now fallback-only. A valid versioned restore marker preserves the preloaded `TurboFaceDB`; without one, startup behavior remains the same deterministic Prep42 baseline. `/tf debug modules` reports whether restored data or the fallback supplied the settings.
- Added `FOREVER_SAVEDVARIABLES_WORKAROUND.md` with the safe workflow and explicit-path recovery syntax. This bridges the beta bug; it does not claim to repair Blizzard's SavedVariables loader.

## 0.17.87-ForeverPrep66-Forever69913

- Swing Timers / Forever Character-sheet damage capture phase 4: Prep65 live output found no readable Damage label, but did find one readable range (`78 - 99`) inside Blizzard's dedicated `CharacterStatsPaneScrollBox` (`ranges=1`). This confirms the compact Forever sheet renders the value without an addon-readable label.
- The one-shot CharacterFrame scan now accepts that unlabeled layout only when the stats scroll-box subtree contains exactly one numeric range. It does not hard-code `child12/region2`, and it refuses to guess if a later layout exposes multiple range candidates.
- A successful capture reports `frameStatus=captured-single-stats-range`, `captureSource=character-frame-single-stats-range`, and `paperdollDamage=<range>`. Timing remains owned by `PLAYER_SWING`; no cadence or per-frame tree scan changed.

## 0.17.87-ForeverPrep65-Forever69913

- Swing Timers / Forever Character-sheet damage probe phase 3: Prep64 live output showed the active `CharacterStatsPane.statsFramePool` is readable but only exposes `Armor`, with no Damage row (`paneStatus=no-damage-row`, scanned=6). TurboFace now falls back to a bounded one-shot census of the entire visible `CharacterFrame` hierarchy when the pane-row scan does not find Damage.
- The full-frame scan inspects readable text regions, finds the localized `Damage` label, and pairs it with the nearest visible numeric range on the same visual row using frame coordinates. If found, that exact Blizzard-rendered range is cached for the standalone main-hand swing bar.
- `/tfswing paperdollprobe` now prints a focused `CharacterFrameProbe` (Damage-like labels and numeric ranges first) plus `frameStatus`, node/text counts, and matched label/range paths. The scan runs only on CharacterFrame show or explicit probe; no cadence/per-frame tree traversal was added.
- `PLAYER_SWING` timing semantics remain unchanged.

## 0.17.87-ForeverPrep64-Forever69913

- Swing Timers / Forever Character-sheet damage probe: Forever build 69913 exposes the legacy/Mainline PaperDoll damage globals but its live Character sheet did not call them (`labelCalls=0`, `damageCalls=0`). Added a safe live `CharacterStatsPane` tree scan that searches Blizzard stat-row `Label`/`Value` pairs and sibling FontStrings for the visible Damage row, then caches the already-rendered range when readable.
- Swing Timers: CharacterFrame `OnShow` now performs the scan one frame after Blizzard lays out its stats; `/tfswing` also scans while the Character panel is open. `/tfswing paperdollprobe` prints the scan status, node count and matched row path for live reverse-engineering without any per-frame traversal.
- The Prep62/63 PaperDoll hooks remain as compatibility fallbacks; `PLAYER_SWING` timing behavior is unchanged.

## 0.17.87-ForeverPrep63-Forever69913

### Character-sheet damage capture — renderer-level probe
- Prep62 live diagnostics showed `paperdollHook=true` with no captured range, so the Character-sheet hook existed but the post-render `statFrame.Value:GetText()` path did not produce a usable value.
- Added a secure post-hook on Blizzard's generic `PaperDollFrame_SetLabelAndText`. Current Mainline FrameXML routes `PaperDollFrame_SetDamage` through this renderer with the final formatted Damage range as the `text` argument, so TurboFace now captures the value at that earlier boundary.
- Retained the existing `PaperDollFrame_SetDamage` post-read as a fallback/probe instead of assuming one client layout.
- Expanded `/tfswing` with `labelHook`, `labelCalls`, `damageCalls`, `captureSource`, `reject`, `postRead`, and `textSecret` diagnostics so Forever can distinguish "renderer never fired" from "value is secret/inaccessible".
- No `PLAYER_SWING` timing semantics changed.

## 0.17.87-ForeverPrep62-Forever69913

### Character-sheet damage capture for standalone swing bar
- Added a Forever/Mainline post-hook for Blizzard's `PaperDollFrame_SetDamage(statFrame, unit)` and cache the already-rendered `statFrame.Value` damage range after Blizzard updates the Character stats pane.
- The standalone main-hand swing bar now prefers that Blizzard-rendered Character-sheet range once it has been captured for the current weapon/form identity; before the Character sheet has populated, TurboFace retains its existing secret-safe `UnitDamage` fallback.
- Weapon/form identity changes invalidate the captured Character-sheet range so an old weapon value is never carried into a new weapon/form. Normal `UNIT_DAMAGE` invalidation does not discard the last known Blizzard-rendered range, allowing it to remain useful when combat makes raw stat values secret.
- The PaperDoll hook installs lazily through `ADDON_LOADED` because `Blizzard_UIPanels_Game` may not exist at TurboFace startup. `/tfswing` now reports `paperdollDamage`, `damageSource`, and `paperdollHook` for live validation.
- No player timing semantics changed: `PLAYER_SWING` remains authoritative for Forever MH/OH/ranged clocks.

## 0.17.87-ForeverPrep61-Forever69913

### Forever item-icon compatibility / swing cadence fix
- Fixed the second live SwingTimers cadence eviction at `Combat/SwingTimers.lua:657`. The player swing renderer still called the removed legacy global `GetItemIcon(itemID)` while Forever/Mainline exposes item-ID icons through `C_Item.GetItemIconByID`.
- Routed SwingTimers weapon-icon lookup through the existing `ns.API.GetItemIcon` compatibility adapter instead of bypassing the API boundary.
- Routed SwingTimers spell-texture lookup through the existing `ns.API.GetSpellTexture` adapter at the same time, eliminating another direct legacy-global dependency from the player swing presentation path.
- `PLAYER_SWING` remains live-validated and authoritative for Forever player timing; this pass changes presentation/API compatibility only.

## 0.17.87-ForeverPrep60-Forever69913

### Forever current-spell compatibility / swing cadence fix
- Fixed the live cadence eviction at `Combat/SwingTimers.lua:1510`. Forever no longer exports the legacy global `IsCurrentSpell`, while current clients expose `C_Spell.IsCurrentSpell`; the per-frame attack-state check was therefore attempting to call nil.
- Added `ns.API.IsCurrentSpell` in `Core/Compat.lua` with `C_Spell.IsCurrentSpell` support and a legacy `_G.IsCurrentSpell` fallback, and routed SwingTimers through that adapter.
- Routed `SwingTimerSpellData` Heroic Strike/Cleave/Raptor Strike/Maul queue-state detection through the same adapter. That code previously failed closed when the legacy global was absent, so queued-swing orange state could silently stop updating on Forever even though it did not throw.
- `PLAYER_SWING` remains the authoritative Forever source for MH/OH/ranged timing; no timing semantics from Prep56-59 changed.

## 0.17.87-ForeverPrep59-Forever69913

### Forever Dev Preset: Swing Timers ON
- Enabled the `swingTimers` module in the build-69913 hardcoded `TurboFace Dev Preset` so the new `PLAYER_SWING` implementation is active after every login/reload while Blizzard SavedVariables persistence remains unreliable.
- This changes only the development preset baseline; normal profile/default behavior outside the affected Forever build is unchanged.

## 0.17.87-ForeverPrep58-Forever69913

### World Map init safety
- Fixed a live Forever login warning where `PlusMap:Init()` called `GetNormalizedHorizontalScroll()` / `GetNormalizedVerticalScroll()` before Blizzard's MapCanvas child had non-zero dimensions, causing `MapCanvas_ScrollContainerMixin` to divide by zero.
- `Remember Zoom` no longer samples map scale/pan during addon initialization. It captures only from a fully initialized canvas (`mapID`, zoom levels, non-zero frame/child geometry, valid scale) and restores one frame after Blizzard finishes `WorldMapFrame:OnShow`.
- Removed the old hide/show redraw hack after restoring a saved map view; `InstantPanAndZoom` already invalidates Blizzard's canvas correctly.
- Enhanced Zoom mouse-wheel and live zoom-ceiling refresh paths now share the same canvas-readiness gate, preventing TurboFace from entering Blizzard map math while the canvas is incomplete.
- Added map diagnostics for canvas map ID, readiness, child geometry, and zoom-level count.

## 0.17.87-ForeverPrep57-Forever69913

### SwingTimers upvalue-limit refactor
- Fixed the live `LUA_WARNING` reporting that the monolithic `SwingTimerOnEvent` closure had more than WoW Lua's 60 upvalues after the Prep56 `PLAYER_SWING` port.
- Split the event dispatcher into focused handlers for combat entry/exit, `PLAYER_SWING`, target changes, attack-speed changes, inventory changes, spellcast lifecycle, UI errors, autorepeat state, and login/world initialization.
- The public event frame now performs a tiny event-to-handler lookup, so future swing-timer features no longer increase one giant closure's captured-local count.
- Prep56 behavior is intentionally unchanged: Forever `PLAYER_SWING` remains authoritative for player MH/OH/ranged clocks; target/nameplate cadence, queue coloring, hard-cast resets, weapon swaps, and legacy fallbacks remain intact.

## 0.17.87-ForeverPrep56-Forever69913

### Forever `PLAYER_SWING` player-clock port
- Ported the player's own swing clock to Forever's public `PLAYER_SWING(swingDuration, swingType)` event. `Enum.PlayerSwingType.MainHand/OffHand/Ranged` are preferred with the live-verified numeric `0/1/2` mapping retained as fallback.
- On Forever, a successful `PLAYER_SWING` registration makes that event authoritative for ordinary player MH/OH/ranged resets. Player `SWING_DAMAGE` / `SWING_MISSED` CLEU events no longer double-reset those clocks; CLEU remains active for target/nameplate cadence, parry haste, queued-spell cleanup, and explicit special-reset effects.
- Forever ranged swings now update only the ranged clock. Wand/physical ranged spell-success handling no longer restarts MH/OH when the authoritative player-swing event is active, removing the old spell-name/weapon-type ambiguity from the Forever path.
- Preserved TurboFace's existing Heroic Strike/Cleave queue coloring, hard-cast reset behavior, weapon-swap behavior, compact/standalone presentation, target swing timer, and nameplate swing timing.
- Guarded player `UnitAttackSpeed`, `UnitRangedDamage`, and weapon/ranged damage presentation against secret values. Readable speed events may still refine a running clock, but secret unit stats are no longer required to establish a Forever player swing.
- Preserved pre-combat `PLAYER_SWING` opener timestamps through `PLAYER_REGEN_DISABLED`, and extended `/tfswing` diagnostics with event registration plus last observed type/duration/time.
- This integration uses the event contract observed in the supplied AppelSwingsForever addon as a behavioral reference; TurboFace's swing engine and implementation remain independent.

## 0.17.87-ForeverPrep55-Forever69913

### Forever quest-log ownership cleanup
- Removed TurboFace's `Show quest levels in quest log` feature and `enhanceQuestLevels` config key from the Forever branch; WoW Forever now owns quest-level presentation natively.
- Retained quest difficulty classification as the standalone `Show quest difficulty tags (D/R/+/P)` option.
- Modern quest-log decoration now preserves Blizzard's complete rendered quest title/level string and prefixes only TurboFace's compact classification token (`[D]`, `[R]`, `[+]`, `[P]`).
- Legacy quest-log fallback likewise adds classification tags only; TurboFace no longer injects numeric quest levels on any Forever code path.

## 0.17.87-ForeverPrep54-Forever69913
- Fixed **Spend Talent Point Reminder** visibility: the literal `SPEND TALENT POINT` text now remains hidden whenever the character has 0 unspent talent points, including while TurboFace mover mode is active. The mover overlay remains available for positioning without fabricating the warning text.

## 0.17.87-ForeverPrep53-Forever69913

- Hardened **Hide day/night indicator** again for Forever's hybrid minimap. TurboFace now suppresses the known `GameTimeFrame` tree and also scans the live `MinimapCluster` / backdrop / minimap descendants for detached time-of-day artwork by object name and the historical `Interface\Minimap\UI-TOD-Indicator` texture identity. Re-show hooks are installed on the actual resolved objects, and `GameTimeFrame_SetDate` triggers a targeted re-scan without polling every frame.
- Moved **Spend Talent Point Reminder** out of Class Features and into the Speedrun tab. The old ClassBuffs talent icon and `classBuffTalentPoints` setting are retired; the replacement is a standalone mover-backed text HUD that displays exactly `SPEND TALENT POINT` while unspent talent points exist.
- Added `ns.API.GetUnspentTalentPoints()` as a capability-first compatibility boundary (`GetUnspentTalentPoints` -> `UnitCharacterPoints` -> `GetNumUnspentTalents`) so the new Speedrun reminder is not tied to one client-family talent API.
- Added dedicated reminder font/style/size settings and mover token `SpendTalentPoint`. DB v80 migrates the old Class preference into the new Speedrun gate and prevents old imports from resurrecting the icon reminder.

## 0.17.87-ForeverPrep52-Forever69913

- Replaced TurboFace's bundled banker artwork with Blizzard's native Banker minimap-tracking texture, `Interface\\Minimap\\Tracking\\Banker`. The Inventory Bank-state overlay and the Banker nameplate Job Icon continue to share one banker visual, but now use Blizzard's own sacks icon.
- Removed the now-unused bundled `Textures/BankIcon.tga` from the Forever package. Prep51 minimap fixes and Prep46 trainer automation are otherwise unchanged.

## 0.17.87-ForeverPrep51-Forever69913

- Fixed the live Forever minimap crash from `InterfaceTweaks.lua:488`. Current Blizzard defines `MinimapCluster.BorderTop` as a `NineSliceCodeTemplate` Frame, not a Texture; TurboFace now resolves it as `borderTop` and hides the frame through the standard visibility helper instead of calling the invalid `:SetTexture("")`.
- Hardened **Hide day/night indicator** for Forever's hybrid GameTime implementation. TurboFace still hides `GameTimeFrame`, but it now also discovers and suppresses texture regions owned by that button when the old `_G.GameTimeTexture` global is not exported, and reasserts suppression if Blizzard shows the button again.
- Prep50's owner-scoped Minimap/World Map refresh separation and modern `MinimapCompassTexture` / `ui-hud-minimap-frame` border handling remain unchanged.

## 0.17.87-ForeverPrep50-Forever69913

- Fixed the live minimap-border Options crash reported on Forever. The minimap controls were still using the broad `RefreshPlusOptions()` callback, so changing `minimapBorderTexture` also called `Plus/MapTweaks:Refresh()`. That method manually invoked Blizzard `ScrollContainer:CreateZoomLevels()` while the canvas could have no `container.mapID`, causing Blizzard's modern MapCanvas code to reach `C_Map.GetMapArtLayers(nil)`.
- Scoped Minimap controls to `PlusInterface:Refresh()` and Map controls to `PlusMap:Refresh()` so unrelated QoL settings no longer force a World Map zoom rebuild. `PlusMap:Refresh()` is also hardened to run only while the World Map is shown and the ScrollContainer itself owns a valid numeric `mapID`; it validates `C_Map.GetMapArtLayers(mapID)` before entering the Blizzard canvas method.
- Updated native minimap-border ownership for the Forever/Mainline frame model. `ns.API.GetMinimapParts()` now distinguishes Blizzard's modern `MinimapCompassTexture` from the legacy `MinimapBorder`, and `ns.API.SetNativeMinimapBorderShown()` restores the modern border with Blizzard's current `ui-hud-minimap-frame` atlas through `Texture:SetAtlas()` while retaining old-frame fallbacks. Square mode hides the native compass art through this adapter; round mode restores it.
- Ported the `Hide day/night indicator` path across the modern GameTime split. Current Blizzard FrameXML uses `GameTimeFrame` as the calendar-date button while the legacy `GameTimeTexture` day/night artwork remains a separate texture. TurboFace now resolves both surfaces and suppresses both when the option is enabled, including re-show protection for hybrid Forever behavior.
- Minimap `:Refresh()` now reapplies the minimap element policy instead of only square-mask geometry, so enabling supported hide options can take effect immediately. Turning one-way Blizzard-owned hide options back off still remains reload-safe rather than force-showing frames Blizzard may intentionally have hidden.
- Prep49 QoL API modernization and Prep46 trainer automation are otherwise unchanged.

## 0.17.87-ForeverPrep49-Forever69913

- Started the broad Forever QoL API modernization pass identified by the Prep48 audit. The goal is capability-first compatibility: QoL modules ask `ns.API` for modern/legacy behavior instead of directly guessing whether the client is Era, Forever, or Retail.
- Modernized Minimap Tracker data access. `ns.API.GetActiveTrackingInfo()` now prefers structured `C_Minimap.GetNumTrackingTypes()` / `C_Minimap.GetTrackingInfo()` and falls back through the legacy tracking globals. The tracker also listens for `SPELLS_CHANGED` and resolves Blizzard's native tracking button dynamically.
- Added `ns.API.GetMinimapParts()` and rewired Interface minimap styling/hiding around the current `Minimap` / `MinimapCluster` ownership model: modern zoom buttons, zone button/text, Tracking button, indicator mail/battlefield frames, compass/border, clock, and LFG button are resolved at call time with Classic fallbacks. Square-minimap code no longer assumes `MinimapBorder`/`MinimapNorthTag` exist.
- Ported quest-level decoration to Forever/Mainline's pooled quest log. When `QuestLogQuests_Update` exists, TurboFace decorates active `QuestScrollFrame.titleFramePool` entries after Blizzard rebuilds them and preserves Blizzard's existing decorated title text; the old `QuestLog_Update` / `QuestLogTitle#` path is retained only as a legacy fallback.
- Ported Spirit Healer confirmation through `C_PlayerInteractionManager.ConfirmationInteraction(Enum.PlayerInteractionType.SpiritHealer)` with `AcceptXPLoss()` only as a legacy fallback. PvP auto-release now calls `RepopMe()` through `ns.API.ReleaseSpirit()` instead of clicking Blizzard's DEATH StaticPopup.
- Ported Battle.net invite paths through `C_BattleNet.GetFriendInviteInfo()` and `C_BattleNet.InviteFriend()` when available, with legacy fallbacks. Party invite capability/action now prefer `C_PartyInfo.CanInvite()` / `C_PartyInfo.InviteUnit()`.
- Modernized chat-frame iteration through `ChatFrameUtil.ForEachChatFrame()` with the legacy `ChatFrame1..50` sweep retained as fallback. Automation, Social, Chat, System, Flight Bar, and Minimap Tracker event registration now consistently use the safe `ns.API.RegisterEvent()` boundary where they register events.
- Added a Compact Raid Manager resolver. The existing group-frame generation/update contract remains present in current Mainline, but the Show Raid Toggle path now resolves the modern `displayFrame.hiddenModeToggle` parentKey first and uses the generated global only as fallback.
- Prep46's live-working Thunder Clap trainer automation, Prep47 native coin art, and Prep48 Blizzard-owned vendor-price tooltip remain unchanged. This is QoL modernization phase 1; Flight Bar taxi enumeration, chat child-button resolution, bag-auto-open suppression semantics, and lower-risk System cleanup remain follow-up work.

## 0.17.87-ForeverPrep48-Forever69913

- Removed TurboFace's legacy `Show vendor price in tooltips` feature from the Forever fork because Forever already presents vendor/sell price natively. Blizzard now exclusively owns ordinary item vendor-price tooltip presentation.
- Deleted the vendor tooltip hook and stack-count helper from `Plus/SystemTweaks.lua`, including the `SetTooltipMoney` injection path.
- Removed the `showVendorPrice` option from Forever defaults, section ownership, the Rumblecrush preset, and the Options panel. `Keep audio synced (device changes)` remains available as a standalone System option.
- Non-tooltip vendor-value consumers are intentionally unchanged: Loot Frame valuation, Grocery observed prices, Junk & Inventory classification/selling, Net Worth, and Trainer money presentation retain their existing behavior.
- Prep47 native coin-atlas work and Prep46 trainer automation remain otherwise unchanged.

## 0.17.87-ForeverPrep47-Forever69913

- Switched the requested money visuals to Blizzard's new native MoneyFormatter assets. `Core/Compat.lua` now exposes `ns.API.FormatMoney()` using `MoneyFormatterUtil.FormatMoney(..., MoneyFormatterPresets.CompactWithZero)` when available and `ns.API.SetCoinIcon()` using the native `coin-gold`, `coin-silver`, and `coin-copper` atlases, with legacy texture/formatter fallbacks for older clients.
- Net Worth keeps its existing TurboFace layout, font, mover, label, and denomination visibility rules, but its three standalone denomination textures now render the native Blizzard coin atlases instead of `Interface\\MoneyFrame\\UI-*Icon` textures.
- Trainer Spells cost and owned-gold tooltip lines now use the modern Blizzard money formatter, so the current embedded gold/silver/copper atlas art is used without reviving the old MoneyFrame tooltip path.
- Replaced the Junk & Inventory bag marker's `UI-GroupLoot-Coin-Up` texture with Blizzard's native `coin-gold` atlas for both default Blizzard bag buttons and the Baganator corner-widget integration.
- Prep46 trainer automation behavior is otherwise unchanged; this pass is intentionally limited to shared money presentation.

## 0.17.87-ForeverPrep46-Forever69913

- Fixed the live-confirmed Forever Training Queue cross-rank collision exposed by `/tf debug trainer`. A queued Warrior Thunder Clap spell `8198` correctly resolved to the available level-18 trainer row, but the matcher then fell through from later numeric spell-ID mismatches to same-name matching because Forever omits trainer rank text. That made all visible Thunder Clap ranks match the same queue key (`matched=5`), and the final unavailable rank overwrote the valid available service, producing `lastProcess=no-candidates`.
- `QueueRecordMatchesService()` now treats numeric spell IDs as authoritative whenever both the queue record and trainer row have one. A numeric mismatch returns false immediately; localized-name/rank matching is only a compatibility fallback when at least one side lacks a usable spell ID.
- Expected live signature for the reported Warrior case is now one exact Thunder Clap match (`8198`), followed by `purchase-submitted` if the character can afford the 3000-copper service. Later Thunder Clap ranks such as `8204` remain distinct even though Forever returns no rank subtext.

## 0.17.87-ForeverPrep45-Forever69913

- Continued the Forever Training Queue investigation after Prep44 did not auto-train queued Warrior Thunder Clap in live testing. The remaining failure is now instrumented at the trainer-service and purchase-execution boundaries rather than hidden behind silent returns.
- Added `Trainer:GetTrainerServiceInfoCompat()` and routed trainer capture/queue automation through it. It accepts the Classic/Era category-in-return-#3 layout, a retail-derived category-in-return-#2 layout, and an obvious structured-table shape; unknown shapes fail closed.
- Added load-on-demand `C_Spell` metadata warming for queued numeric spell IDs via `C_Spell.RequestLoadSpellData`. `SPELL_DATA_LOAD_RESULT` retries the trainer capture/match path, while per-session request deduplication prevents loops on partial data.
- Added `/tf debug trainer` live diagnostics for API availability, queue records, spell cache/known/attempted state, the last queue-processing gate, raw + normalized trainer row returns, trainer level/cost, resolved spell ID, and queue match identity. The probe is read-only and never calls `BuyTrainerService`.
- Training Queue now records explicit stop reasons (`missing-api`, `no-context`, `no-context-queue`, filter enable, no candidates, purchase submitted, purchase error), making a protected/behaviorally blocked purchase distinguishable from row-resolution failure.
- Corrected the architecture/status wording so trainer globals are treated as a required capability to verify on the live Forever build, not as a behavioral guarantee merely because the symbol exists.

## 0.17.87-ForeverPrep44-Forever69913

- Fixed Forever class-trainer auto-training identity resolution. The trainer transaction APIs themselves remain the legacy global service APIs (`GetNumTrainerServices`, `GetTrainerServiceInfo`, `BuyTrainerService`); Prep44 no longer treats a hypothetical `C_Trainer.GetTrainerServiceInfo` as an alternate capability.
- Reworked `Trainer:GetSpellIDForService()` so an unlearned service no longer depends on `C_Spell.GetSpellInfo(serviceName)`. Modern spell-name identifiers are spellbook-dependent, which made a queued unlearned spell such as Warrior **Thunder Clap Rank 1** fail to resolve to seeded spell ID `6343` even though the Training UI could display it by numeric ID.
- Added a deterministic class-trainer catalog resolver: localized trainer service name is the identity boundary, numeric rank and trainer level requirement are disambiguators, and ambiguous ties fail closed instead of risking purchase of the wrong rank. Thunder Clap Rank 1 therefore resolves from the Warrior seed catalog by name/rank/level even before it is learned.
- Added an optional modern `C_TooltipInfo.GetTrainerService()` probe ahead of the Era `GameTooltip:SetTrainerService()` path. Structured tooltip IDs are accepted only when numeric spell metadata resolves back to the exact trainer service name; the code does not assume that tooltip `id` is inherently a spell ID.
- Kept the Era trainer-tooltip scan as a capability-gated fallback and retained name-based spell lookup only as the final compatibility fallback for clients where it remains valid.
- Routed Trainer known-spell checks through `ns.API.IsKnownSpellID` and taught the compatibility facade to use Forever's `C_SpellBook.IsSpellKnown` when legacy `IsPlayerSpell` / `IsSpellKnown` globals are absent. This keeps queue pruning and Training-list learned state on the same modern spellbook boundary.
- Removed the direct `C_Spell.GetSpellInfo` call used to identify Beast Training at Trainer initialization; Trainer now consumes that metadata through `ns.API.GetSpellInfo` like the rest of the subsystem.
- Updated the Training compatibility contract, `ARCHITECTURE.md`, and `PORT_STATUS.md` for the Prep44 automation probe. Live validation remains required before Training is promoted beyond Probing.

### Prep43 hotfix — native tab chrome and retail spell APIs

- Prevented the Era `ClassTrainerFrame_Update` replacement from installing on Forever's retail-derived Trainer window. Forever retains trainer-service data APIs but omits legacy XML globals such as `ClassTrainerNameText`; trainer capture now continues independently while the incompatible ignored-spell list renderer and its custom filter checkbox remain dormant.
- Restored the build-69913 `SpellBookCategoryTabTemplate` styling after the square skill-line-border experiment proved to be the wrong direction. Background-only screenshots showed that resizing the button frame did not resize the template's fixed 32-pixel atlas pieces. The visible frames and background/active/highlight pieces are exactly 44×44 inside unchanged 46×32 layout slots; the current border-isolation probe widens only their left/right caps by six pixels without stretching the center.
- Restored the two custom icon textures after completing the background-only pass. The template center proved opaque, so icons render on `ARTWORK` at 32×32 with a calibrated `(-0.5, 0.5)` bottom-anchor offset, remaining visible while staying inset from the thicker chrome edges.
- Registered dedicated native-height layout slots with the category strip's inherited `HorizontalLayoutFrame` using consecutive `layoutIndex` values. This preserves the new horizontal arrangement and prevents later Blizzard layout passes from moving Training and Skills over categories 2 and 3.
- Expanded the Training/Skills content surface to `PagedSpellsFrame`'s bounds. The opaque Trainer page begins seven pixels below that frame's top to clear the category-tab chrome, while its other edges reach the modern spellbook's inner left, right, and bottom border.
- Hooked Forever's pooled `CategoryTabSystem.tabs` buttons and the spellbook's `SetTab` path. Selecting any Blizzard category now closes an open Training/Skills page, restores native content, and clears the custom selection state whether the change came from a click or Blizzard code.
- Opening Training or Skills now clears the underlying native category's visual-selected/disabled state without changing its stored tab ID. This makes the already-current General tab clickable; closing the custom page restores Blizzard's native visual selection.
- Increased Forever's Training/Skills list category text, spell names, ranks, level text, and icons by eight pixels. Their header and row extents grow by the same amount to prevent clipping, and inter-row spacing increases by one pixel (0.5 to 1.5). The shared profession renderer keeps its existing sizing until the later profession pass.
- Routed Trainer spell names/icons and rank subtext through `ns.API.GetSpellInfo` and `ns.API.GetSpellSubtext`. This fixes the click-time `UI_ClassData.lua` failure on clients where the legacy global `GetSpellInfo` has been removed in favor of `C_Spell`.
- Extended the Trainer spellbook runtime regression test to cover the native-template layout, final-native-tab anchoring, and the build-69913 orphan-ID bypass.

### Prep43 hotfix — orphan modern category IDs

- Fixed `TabSystemMixin:SetTabShown` failing when Forever's transitional `SpellBookFrame:AddNamedTab()` returned IDs without materializing corresponding `CategoryTabSystem.tabs` buttons.
- Build 69913 now bypasses `AddNamedTab()` entirely because live testing showed that it also overwrites an existing category label with `Training` instead of allocating a new button.
- Training and Skills are icon-only TurboFace buttons laid out horizontally after the last visible button in the live `CategoryTabSystem.tabs` array. Later builds can still use the native named-tab route after it proves well-formed.

## 0.17.87-ForeverPrep43-Forever69913

- Ported the Trainer Spellbook integration to Forever's retail-derived `PlayerSpellsFrame.SpellBookFrame` hierarchy while preserving the existing Era path.
- Added **Training** and **Skills** through the modern spellbook's native category `TabSystem`; selecting either tab swaps only the book contents and continues to use the established Trainer data, classification, ignore, tooltip, and training-queue logic.
- Replaced the old assumptions about global `SpellBookFrame`, `SpellBookSkillLineTab*`, and page-navigation globals on Forever. The modern path hides/restores the native paged-spell/search/settings widgets as a reversible page transition.
- Made spellbook attachment load-on-demand aware. Trainer listens for Blizzard's player-spells addon only while the Trainer Spells option is active, then releases the loader event after attaching.
- The custom page now follows modern spellbook scale, maximize/minimize geometry, and visibility by parenting to the nested spellbook content frame. Native category selection and module disable both restore Blizzard's page.
- Added a Forever-build fallback for the screenshot's horizontal icon-tab variant: if the native category `TabSystem` is absent, the same Training/Skills buttons attach horizontally after the live `SpellBookSkillLineTab*` row instead of using Era's vertical side-tab geometry.
- Professions are intentionally unchanged and remain a later, separate probe.

## 0.17.87-ForeverPrep42-Forever69913

- **Handoff Dev Preset update:** changed the build-69913 hardcoded `TurboFace Dev Preset` from the Nameplate campaign to a broad QoL/utility validation baseline. SavedVariables are still treated as unreliable upstream; `/reload` always returns to this code-defined state.
- Nameplates now start **OFF**. Prep39's detached `ForeverNativeAdapter` remains in the fork for later focused validation; its stored child options stay on the conservative detached-safe values.
- Unit Frames remain **OFF**. Prep38's Forever-native UnitFrame adapter remains available but is intentionally parked for a later campaign.
- Trainer Spells now starts **ON**. This exercises the Prep34 modern `TooltipDataProcessor` hook migration and Prep35 resilient modern/legacy profession event registration. Training is still **probing**, not validated.
- Hearthstone Tracker now starts **ON**, including its timer and one-shot auto-bind helpers. Hearthstone Batching now starts **ON**; FPS Counter remains ON because batching depends on it.
- Enabled **all QoL/Plus section masters**: Automation, Social, Interface, Minimap, Map, Chat, System, and Flight Bar.
- Forced every boolean option in `TurboFaceDB.plus` to `true` for the handoff stress baseline. Non-boolean tuning remains inherited from `Rumblecrush's Preset` / defaults (for example minimap dimensions, map zoom ceiling, release delay, weather density level, invite keyword, and flight-bar size).
- This all-QoL configuration intentionally enables aggressive behaviors (automation, blocking, auto-release/spirit-healer, UI/chat hiding, System tweaks). It is a beta compatibility test state, **not a release-default recommendation**.
- Because build 69913 is not reliably loading addon SavedVariables, Trainer observations and Hearthstone Batch per-character calibration must be treated as session-only; cross-reload learning/persistence is not a valid test signal on this client build.
- Updated `ARCHITECTURE.md` with a full Prep42 handoff snapshot, startup/preset ownership, active/dormant feature list, known beta constraints, and the recommended next validation order. Updated `PORT_STATUS.md` to match the new handoff campaign.

## 0.17.87-ForeverPrep41-Forever69913

- Added a code-defined **TurboFace Dev Preset** for the affected Forever 69913 beta. The preset is applied before normal migrations on every `PLAYER_LOGIN`, so the addon no longer depends on broken SavedVariables loading for its active development configuration.
- The Dev Preset is based on `Rumblecrush's Preset` so existing layout/style preferences remain familiar, then explicitly narrows the active environment to the current Nameplate campaign: Nameplates + Player Ticks on; Unit Frames, Auras, Hotbar Power, Swing Timer rows, Cast Bars, Class Features, and all Plus sections off. On build 69913 it is also the **only built-in preset shown** in the Profiles tab.
- Preserved already-useful development QoL surfaces in the preset: Grocery, Loot Frame, Net Worth, Bag Slots, FPS Counter, Experience Bar, and Movers/layout data.
- Disabled prediction/render consumers that are not part of the current safe Nameplate baseline (`dotPrediction`, heal prediction, Druid extra power, Class Buffs, old Combat Meter, Trainer, Quick Setup, Hearth Batch, Leash Timer, etc.).
- Nameplate native-mutation settings that are still deferred are forced false in the Dev Preset, while detached-safe options (name shadow, job icon, NPC title, threat number, swing timer, combo points) start enabled.
- Removed Prep40's redundant SavedVariables mirror (`ForeverSettingsPersistence`) and its extra account/per-character SavedVariables. The mirror cannot solve a client that does not load addon SavedVariables at all.
- `/tf debug modules` now reports `Forever Dev Preset: ...` instead of persistence mirror revisions. Session Options changes still work, but `/reload` intentionally returns to the hardcoded Dev Preset until Blizzard fixes the beta client.

## 0.17.87-ForeverPrep40-Forever69913

- Restored SavedVariables reliability on the Forever 69913 beta without restoring the removed staging/safe-boot system. Options/profile state remains the sole runtime feature authority.
- Added `Core/ForeverSettingsPersistence.lua`, a redundant persistence transport for the real `TurboFaceDB`: account mirror, per-character mirror, and cache mirror.
- Restore now runs before normal migrations/default merging at `PLAYER_LOGIN`; `/reload`/logout republishes the exact live `TurboFaceDB` root and increments a monotonic revision before Blizzard serializes SavedVariables.
- Preserved the cache mirror across client-build cache invalidation and excluded the internal revision marker from profile snapshots/exports.
- Added `/tf debug modules` persistence diagnostics (`mainRev`, `mirrorRev`, restore source, mirror availability) so beta-client persistence failures are observable.
- This does **not** reintroduce `/tf compat enable`, staged groups, baked validation gates, or any hidden runtime activation policy.

## 0.17.87-ForeverPrep39-Forever69913

- **Nameplates campaign resumed:** replaced Prep37's forced-off Forever block with `Nameplates/ForeverNativeAdapter.lua`, a detached overlay/state architecture for build 69913. The normal Nameplates Options master is again the runtime gate when this adapter is present.
- Blizzard pooled nameplate roots/CompactUnitFrames remain native-owned. TurboFace stores no `_tf*` state on them, creates no child regions on native health bars, installs no Forever `NamePlateDriverFrame` hooks, and performs no native geometry measurements.
- Restored the first native-safe option subset: overlap vertical/horizontal, selected scale/alpha, non-selected alpha, combo points, detached name shadow, friendly NPC name+title, friendly NPC job icon, threat number/font size when readable, aggro audio when readable, and detached enemy swing timing.
- Existing enemy swing state now avoids `UnitAttackSpeed(nameplateN)` on Forever and infers cadence from observed CLEU swing intervals.
- Kept native-mutation options explicitly deferred: Move Rarity Icon Right, Friendly Player/NPC Damaged Only, Center Blizzard Health Text / Center Across Entire Nameplate, Overlap Power Bar, and Power Bar Height.
- Kept legacy Nameplate Aura rows and Warrior/Hunter reactive indicators dormant on Forever because their Era renderers parent frames directly to Blizzard nameplate objects.
- Options refreshes on Forever route directly through the detached adapter and never call Era native-health-text, rarity-icon, name-shadow, or Bubble frame mutation paths.
- Added `Nameplates Forever:` diagnostics to `/tf debug modules`, including active safe features, visible detached overlays, swing activity, and the deferred option list.
- Prep38's UnitFrame adapter remains in the fork but the active port campaign is now Nameplates.

## 0.17.87-ForeverPrep38-Forever69913

- **Unit Frames Forever baseline:** added `UnitFrames/ForeverNativeAdapter.lua`. On build 69913, TurboFace now keeps Blizzard's secure Player/Target/ToT/Pet/Party frames and native StatusBars while rendering fixed artwork from detached UIParent-owned overlays.
- Removed Forever's dependency on the Era UnitFrame ownership model: the adapter stores state externally, never attaches `_tf*`/`_sr*` fields to Blizzard unit-frame objects, and installs no health/power value or geometry method hooks.
- Protected health/power geometry is re-applied only out of combat, anchored exclusively to Frame objects, coalesced to the next frame, and deferred to `PLAYER_REGEN_ENABLED` when necessary.
- Player, Target, Target-of-Target, Pet, and pooled Party surfaces are all included in the first probe; Blizzard retains native portrait/name/value/prediction behavior.
- Custom UnitFrame DoT/heal prediction textures, NanShield, and the embedded Druid power bar are deliberately dormant on Forever until rebuilt as detached surfaces. Era behavior is unchanged.
- Added detailed `UnitFrames Forever:` output to `/tf debug modules`.
- Unit Frames move from Deferred to **Probing** in the Forever port matrix. Nameplates remain separately blocked by Prep37.

## 0.17.87-ForeverPrep37-Forever69913

- **Forever nameplate safety block:** disabled TurboFace nameplate runtime on the 1.60.1.69913 Forever target after repeated `CompactUnitFrame_UpdateHealPrediction` failures proved that mutating Blizzard-owned pooled `UnitFrame`/`healthBar` objects taints later secret-health comparisons.
- The user's Nameplates checkbox/profile value is preserved; only the effective Forever runtime is blocked. This is a compatibility capability block, not a return of the removed staged/safe-boot system.
- Future Forever nameplate work must keep TurboFace state in external side tables and render through detached TurboFace-owned overlay frames rather than storing `_tf*` fields or child regions on Blizzard native plate objects.
- `/tf debug modules` now reports the explicit Forever nameplate safety block and whether the profile still has Nameplates configured on.


### Forever Prep36 — Blizzard Damage Meter bridge for Player DPS/HPS badge

- Added `Combat/BlizzardDamageMeterBridge.lua` and switched the Forever badge backend from TurboFace CLEU accounting to Blizzard's public `C_DamageMeter` sessions.
- Current/Overall and Damage/Healing selections remain profile-compatible through the existing `combatMeterView` / `combatMeterMetric` settings; Reset calls Blizzard's session reset API.
- Local-player selection uses the documented non-secret `isLocalPlayer` source flag. The potentially secret `amountPerSecond` is never inspected or transformed in Lua and is forwarded only to `FontString:SetFormattedText`.
- Retired the TurboFace Combat Meter window/runtime on clients with `C_DamageMeter`: startup skips it, later generic refresh paths hard no-op it, its Global options are hidden, and its Movers entry is omitted. Era keeps the original meter as a fallback.
- Added `/tf meter` bridge controls/status plus `/tf debug modules` diagnostics for API availability, registered events, source discovery, secret-rate state, rendering, and failures.
- Blizzard remains owner of its meter UI/CVar; TurboFace does not skin, reparent, hook, toggle, or force-enable the Blizzard meter window.

## 0.17.87-ForeverPrep36-Forever69913

### Forever Prep35 — resilient Trainer profession events

- Fixed `Trainer:Init` aborting on Forever because `TRADE_SKILL_UPDATE` is no longer a valid event there.
- Profession refresh now listens to both the legacy `TRADE_SKILL_UPDATE` event and modern `TRADE_SKILL_LIST_UPDATE` / data-detail update events.
- All profession event registration now goes through `ns.API.RegisterEvent`, so removed/unknown Blizzard events degrade to unavailable instead of aborting addon load.

## 0.17.87-ForeverPrep35-Forever69913

### Forever Prep34 — protected unit-frame anchors + modern Trainer tooltips
- **Unit Frames:** fixed Forever startup failure `Action[SetPoint] failed because[Cannot anchor protected frames to regions]`. Modern Player/Target health and power bars no longer anchor protected frames directly to TurboFace/Blizzard texture regions; source-art coordinates are translated onto the texture parent frame instead. Era keeps the original texture-relative anchors.
- **Trainer:** replaced modern-invalid `GameTooltip:HookScript("OnTooltipSetSpell"/"OnTooltipSetItem")` registration with `TooltipDataProcessor.AddTooltipPostCall` for Forever/Mainline while retaining the Classic hooks as fallback.
- **Trainer tooltip IDs:** modern callbacks prefer `TooltipData.id` and guard accessibility before comparisons/lookups, with legacy tooltip accessors only as fallback.

### Forever Prep33 — defer native nameplate mutation past Blizzard secret-value dispatch

- Fixed repeated `CompactUnitFrame_UpdateHealPrediction` failures where Blizzard compared secret `health/maxHealth` values while execution was tainted by TurboFace.
- On Forever, native nameplate lifecycle/name/faction/target/heal-prediction/power work now queues until Blizzard's own event/update pass has unwound.
- Removed TurboFace's direct Forever post-hook on `NamePlateDriverFrame:OnNamePlateAdded`; Classic Era retains the original immediate path.
- `NamePlateDriverFrame:UpdateNamePlateOptions` presentation refreshes are deferred one frame on Forever.
- Added a coalesced power-update batch so high-frequency power events stay outside Blizzard's secure dispatch without one timer allocation per event.

## 0.17.87-ForeverPrep34-Forever69913

### Forever Prep32 — secret-safe native player aura fallbacks
- Fixed a Forever combat error where a secret texture identifier from a Blizzard-owned aura button was used as a Lua table key (`AuraStyle.lua` player-aura texture fallback).
- Corrected the shared `API.CanAccessValue` boundary so `issecretvalue()` is consulted before any equality comparison against an unknown value; secret scalars can no longer trip the guard itself.
- Player aura `auraInstanceID` and icon-texture fallback keys now fail closed when unreadable. Blizzard's native aura remains visible; TurboFace simply suspends its custom timer/swipe overlay for that button until the value is readable again.


## 0.17.87-ForeverPrep31-Forever69913

- Fixed a Forever combat/nameplate taint where TurboFace explicitly invoked Blizzard `NamePlateUnitFrameMixin:UpdateAnchors()`, whose Forever implementation can perform restricted `GetPoint()` frame measurements.
- Forever now restores the native friendly-name anchor policy through TurboFace's existing write-only static path instead of calling Blizzard `UpdateAnchors()` from addon code. Classic Era retains the native restore path.
- Normal nameplates now skip anchor restoration entirely unless TurboFace had actually applied its friendly identity-only offset, eliminating an unnecessary native layout call from the common `NAME_PLATE_UNIT_ADDED` path.
- This change is intentionally narrow: it does not re-enable or redesign Nameplates, and it preserves the existing restricted-geometry avoidance contract.

## 0.17.87-ForeverPrep30-Forever69913

- Removed the temporary Forever safe-boot/staging control plane. `core/staged/normal`, baked validated-stage tables, `/tf compat enable|disable|next|reset|all`, and the dedicated `TurboFaceForeverPrepDB` SavedVariable no longer participate in startup.
- `ns.ModuleEnabled()` is now purely the normal Options/profile module gate. Options state is the runtime code gate for user-facing feature families and Plus sections.
- Kept `Core/Compatibility.lua` as diagnostics infrastructure only: capability probes, exact-build identity, secret-state tracking, protected-action incidents, initialization PASS/FAIL isolation, and diagnostic export remain.
- `ns.CompatSafeCall()` now always attempts initialization and isolates failures instead of returning SKIP for an unstaged group.
- Removed safe-boot vetoes from Movers, Combat Meter, and Enemy Leash Timer refresh paths; their ordinary feature/Movers options now decide runtime activation.
- Switched the Forever PlayerFrame adapter from the removed validated-stage table to exact Forever build identity.
- Removed obsolete staging-state preservation from `TurboFaceCacheDB` build invalidation and removed `TurboFaceForeverPrepDB` from the TOC.
- Updated current architecture/port documentation to the options-only gating model.

This changelog records work unique to the WoW Forever fork. It begins with the Classic Era TurboFace 0.17.87 baseline and does not duplicate the complete Classic release history. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the current runtime contract and [`../classic/CHANGELOG.md`](../classic/CHANGELOG.md) for pre-fork Classic history.

Status language is deliberate:

- **Implemented** means the code exists in this fork.
- **Live-validated** means the behavior was exercised successfully in WoW Forever beta.
- **Deferred** or **blocked** means the feature is not part of the working compatibility claim. Historical entries may still mention the staging workflow used by earlier Prep builds.

## Unreleased — 0.17.87-ForeverPrep29-Forever69913

### Party/Pet Aura restriction-refresh fix

- Fixed the Forever compatibility restriction-change callback calling
  `PartyAuras:Refresh()` without its method receiver, which produced `self=nil`
  when combat changed the aura-restriction state.
- The corrected method call preserves the existing combat-safe behavior: Party/Pet
  aura layout work is deferred until `PLAYER_REGEN_ENABLED` when needed.

## Unreleased — 0.17.87-ForeverPrep28-Forever69913

### Plus QoL probe prep: Faster Auto Loot, Map Fix, and Flight Bar

- Routed Plus System and Flight Bar event registration through the shared
  event-validity boundary so missing/renamed Forever events degrade instead of
  aborting module initialization.
- Hardened Faster Auto Loot around optional loot APIs, retained the modern
  `C_PartyInfo.GetLootMethod()` master-loot enum contract, skips locked loot
  slots, and exposes runtime capability/last-run diagnostics.
- Updated MapTweaks for the Mainline-derived `WorldMapFrame` shape by preferring
  `BorderFrame.TitleContainer`, resolving map IDs through `GetMapID()`, and
  guarding optional zoom-ladder methods before hooking or calling them.
- Kept Blizzard ownership of the world-map frame and added diagnostics for the
  frame, scroll container, drag handle, map ID, and zoom hooks.
- Hardened Flight Bar event registration and diagnostics without changing the
  seeded/learned route engine. Core taxi API readiness, `TakeTaxiNode` hooking,
  taxi-map event capture, route snapshots, and optional tooltip hookup are now
  reported separately.
- Extended `/tf debug modules` with focused Faster Auto Loot, Map, and Flight
  probe lines for the first live Plus campaign.
- **Implemented; live Forever validation pending.**

## 0.17.87-ForeverPrep27-Forever69913

### Grocery List item-button compatibility

- Replaced Grocery's `ItemButtonTemplate` inheritance after live testing proved
  that Forever does not register that legacy virtual node.
- Built the 37-pixel Grocery slot from a plain button with owned icon, stack
  count, quality border, normal, pushed, and highlight regions using stable
  Blizzard texture paths.
- Replaced global `SetItemButton*` calls with Grocery-owned setters, avoiding
  assumptions about region names and mixins in the modern client.
- Added a regression contract that prevents the crashing inherited-button call
  from returning.

## 0.17.87-ForeverPrep26-Forever69913

### Grocery List Forever port

- Added normalized merchant adapters for the structured
  `C_MerchantFrame.GetItemInfo()` surface and retained Classic global fallbacks.
- Routed Grocery merchant enumeration, item information, item IDs, costs, stack
  limits, item counts, and purchases through `ns.API`.
- Made merchant-open state event-driven so a Mainline lazy-frame ordering race
  cannot silently cancel Grocery before `MerchantFrame` becomes visible.
- Added modern `isPurchasable` and `hasExtendedCost` handling. Unpurchasable or
  alternate-currency orders remain queued and produce an actionable message.
- Guarded Grocery events through the shared event-validity boundary and added
  `/tfgrocery status` (also `/tfgrocery debug`) for live API/session diagnostics.
- Added a dedicated Forever Grocery compatibility contract.

## 0.17.87-ForeverPrep25-Forever69913

### Secret-safe substrate and native Aura/Nameplate port

- Added explicit secret-value detection, safe stringification, readable unit
  identity/relationship helpers, readable AuraData accessors, and guarded event
  registration to the compatibility boundary.
- Removed the experimental `C_CombatLogInternal` route from TurboFace and the
  embedded LibClassicDurations copy. Forever no longer treats a private Blizzard
  namespace as a supported combat-log replacement; restricted combat
  reconstruction remains disabled.
- Made Player/Target/ToT, Party/Pet, Nameplate Auras, and TurboDebuffs suspend
  addon-owned enumeration, timers, sorting, and icon rows while the aura domain
  is secret.
- Made Party/Pet and Nameplate aura suppression reversible so Blizzard-native
  aura containers return immediately on restriction transitions.
- Kept the Blizzard nameplate health/name/cast chassis as the authoritative
  renderer, added presentation-only native castbar discovery/styling, and made
  friendly damaged-only classification fail open to the full native chassis
  when health is unreadable.
- Routed active Nameplate identity, health, power, Power Cost, pet trainer, and
  queue-diagnostic reads through secret-safe compatibility helpers.
- Added next-frame presentation reconciliation whenever the client's restriction
  state changes.

## 0.17.87-ForeverPrep24-Forever69913

### Secret-domain compatibility model

- Added explicit `C_Secrets.ShouldAurasBeSecret()` and
  `C_Secrets.ShouldCooldownsBeSecret()` adapters instead of discovering a
  restriction only after an operation fails.
- Added runtime restriction tracking across world, combat, encounter,
  challenge-mode, PvP, and `ADDON_RESTRICTION_STATE_CHANGED` events, including a
  next-frame reconciliation for restrictions that are still activating.
- Added the current aura/cooldown restriction state to `/tf compat status`,
  incident history when it changes, and diagnostic exports.
- Suspended both modern and legacy aura index scans while Blizzard reports the
  aura domain secret.
- Added `ns.API.GetOpaqueUnitAuraBySpellID` as an intentionally opaque known-spell
  lookup. Its result is reserved for future renderers that can pass secret fields
  directly to approved native UI setters without inspection or arithmetic.
- Documented the parts of the M33kAuras strategy that transfer to TurboFace and
  retained the conservative rule that opaque values are not ordinary Lua data.

## 0.17.87-ForeverPrep23-Forever69913

### Broad non-Unit-Frame port campaign

- Deferred Unit Frames by project decision and removed `unitframes` from the exact-build baked stage set. On the exact Forever target, the compatibility boundary now refuses Unit Frame startup even if an older staging database or explicit normal mode requested it; `/tf compat enable unitframes` reports the deferral. Prep22 implementation remains on disk for later work.
- Added an explicit engineering port matrix, `/tf compat plan` / `/tf compat matrix`, and matrix data in diagnostic exports. This distinguishes symbol availability from real behavioral validation.
- Changed `/tf compat next` to advance only through the bounded probe order (Plus, Auras, Nameplates, Training). It no longer starts with Quick Setup or silently advances into blocked/deferred systems.
- Hardened modern and legacy aura adapters against secret data. Aura calls now run behind protected conversions and return no aura for a scan when the aura table or any returned field is inaccessible, preventing restricted values from reaching ordinary feature arithmetic, formatting, or caches.
- Made the modern combo-point fallback return no value rather than expose unreadable `UnitPower` data.
- Added centralized readable unit-state adapters for health, maximum health, power, maximum power, incoming heals, absorbs, and threat. Nameplate and prediction code now receives `nil` instead of a restricted scalar and can hide its additive layer safely.
- Routed Skill Tracker item metadata through `ns.API`, removing direct reliance on Retail-absent `GetItemInfo` and `GetItemInfoInstant` globals.
- Routed pet-merchant item/spell metadata through `ns.API` as part of the Training audit.
- Updated embedded LibClassicDurations to feature-detect `C_CombatLogInternal.GetCurrentEventInfo` and the matching internal combat-log event while preserving the Classic event/function fallback. Combat remains staged until this path passes live testing.
- Added the now-retired port-status journal as the live can/can't/test matrix.
- Added a Forever-specific compile, TOC, and contract suite through `tests/run_forever.py` and `tests/forever_port_contract_test.py`.

## 0.17.87-ForeverPrep22-Forever69913

### PlayerFrame post-layout visual adapter

- **Implemented; live verification pending:** added a Forever-specific PlayerFrame visual adapter to survive Mainline Edit Mode and Blizzard layout refreshes.
- Kept Blizzard's native health and power StatusBars so secret values remain Blizzard-owned.
- Added a TurboFace-owned player name FontString centered over the health opening and a TurboFace-owned visible portrait anchored to the custom artwork.
- Parked the native name and portrait visually without removing them from Blizzard's protected lifecycle.
- Added secure post-hooks for PlayerFrame art/layout update functions and concrete Edit Mode methods. Hooks schedule one next-frame reconciliation rather than fighting layout mutations synchronously.
- Deferred protected geometry work during combat and reapply it on `PLAYER_REGEN_ENABLED`.
- Retained the requested alignment target: portrait `+2px` right/`+1px` up; name `+2px` up and centered to health; health/power `+2px` right/`+2px` up and two pixels narrower.
- Advanced the TOC version from the last handed-off Prep21 state to `0.17.87-ForeverPrep22-Forever69913`.

## 0.17.87-ForeverPrep21-Forever69913

- Attempted the requested PlayerFrame pixel alignment with one-time geometry changes.
- Changed the intended player health/power width from 118 to 116 pixels and moved bars, name, and portrait to the requested offsets.
- **Not successful in live testing:** Blizzard's modern layout system reapplied its geometry, so the changes did not visibly stick. This result motivated the Prep22 post-layout adapter.

## 0.17.87-ForeverPrep20-Forever69913

- Made player tick-marker geometry reads secret-safe.
- Added guarded reads for protected StatusBar width and height.
- Used fixed TurboFace artwork dimensions when protected PlayerFrame geometry was unreadable.
- Fixed RegenTicks being evicted from the shared cadence after comparing a secret geometry value.

## 0.17.87-ForeverPrep19-Forever69913

- Fixed exact-build detection for baked validated compatibility stages.
- Replaced a boolean-expression capture of `GetBuildInfo()` that collapsed Lua's multiple returns with a direct multi-value assignment.
- Live-confirmed that Inventory, HUD, Movers, and Unit Frames appeared in the validated stage set on build 69913.

## 0.17.87-ForeverPrep18-Forever69913

- Introduced an exact-build `VALIDATED_BUILD_STAGES` baseline after repeated beta SavedVariables persistence failures.
- Baked Inventory, HUD, Movers, and Unit Frames for the intended 1.60.1/69913/16001/project-1 target.
- **Superseded:** initial build matching was broken by the `GetBuildInfo()` multiple-return bug fixed in Prep19.

## 0.17.87-ForeverPrep16–Prep17-Forever69913

- Added and refined compatibility-control persistence through `TurboFaceForeverPrepDB`.
- Retained upgrade mirrors in the main and cache databases.
- Rebound SavedVariables at login and republished control state at logout/reload boundaries.
- **Outcome:** persistence remained unreliable enough on the beta client that proven stages were later baked for the exact build.

## 0.17.87-ForeverPrep15-Forever69913

- Moved and sized the modern PlayerFrame `HealthBarsContainer` rather than detaching only its child HealthBar.
- Preserved Blizzard's animated loss, absorb, and prediction children with their owning container.
- Added the first PlayerFrame visual-alignment pass.

## 0.17.87-ForeverPrep14-Forever69913

- Added modern Player, Target, and Target-of-Target object resolution.
- Resolved bars, art, portrait, name, level, and related regions from Mainline-derived child hierarchies when Classic globals were absent.
- Restored visible TurboFace Player and Target artwork on Forever.

## 0.17.87-ForeverPrep13-Forever69913

- Audited Unit Frame numeric presentation for secret health, power, maximum, and absorb values.
- Added `ns.API.CanAccessValue` and `ns.API.IsReadableNumber` as the central secret-read boundary.
- Made custom health/power overlays hide or defer when numeric inputs are unreadable while leaving Blizzard's native fills intact.
- Changed NanShield reconciliation to skip secret authoritative absorb totals and retain usable local/modelled state.

## 0.17.87-ForeverPrep12-Forever69913

- Required a fresh post-combat health-event phase before showing the secret-safe HP marker, preventing an old phase from displaying immediately after combat.
- Added an experimental event-timing fallback for secret Rage values.
- **Deferred:** Rage decay behavior remains outside the validated HUD scope and needs a dedicated Forever redesign.

## 0.17.87-ForeverPrep11-Forever69913

- Added modern PlayerFrame health and mana bar discovery through Blizzard accessors and the `PlayerFrameContentMain` hierarchy.
- Restored valid visual parents for player HP/Rage tick markers.

## 0.17.87-ForeverPrep10-Forever69913

- Replaced secret player-health arithmetic with a phase-only event timing fallback.
- Learned the two-second health-regeneration phase from credible out-of-combat `UNIT_HEALTH` event pairs without inspecting the secret HP number.
- Live-validated the predictive HP tick marker.
- Accepted that exact `+X HP` display cannot be calculated when health is secret.

## 0.17.87-ForeverPrep9-Forever69913

- Added initial secret-safe health and power handling to RegenTicks.
- Prevented direct arithmetic and comparison on unreadable player resource values.

## 0.17.87-ForeverPrep8-Forever69913

- Corrected compatibility group ownership: player tick markers belong to HUD; Enemy Leash Timer belongs to Combat.
- Ensured Options refreshes respect compatibility staging so HUD testing cannot initialize Leash Timer.
- Began experimental modern combat-log routing through `C_CombatLogInternal` and `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED` with the Classic path retained as fallback.
- **Combat remains blocked/unvalidated** because the modern route has not passed end-to-end live testing.

## 0.17.87-ForeverPrep7-Forever69913

- Fixed a Lua forward-declaration error in the modern bank hook path.

## 0.17.87-ForeverPrep6-Forever69913

- Added support for pooled modern character-bank buttons through `BankPanelItemButtonMixin`.
- Resolved modern bank tab/container coordinates from live BankPanel state.
- Added purchased-tab discovery for matching-stack withdrawal.
- Live-validated Ctrl+Right-click withdrawal across matching stacks.

## 0.17.87-ForeverPrep5-Forever69913

- Cleared TurboFace item overlays when a pooled button represents an invalid, unusable, or locked extra backpack slot.
- Added dynamic coin formatting through legacy helpers, `C_CurrencyInfo`, or a plain-text fallback.
- Applied the money compatibility path to auto-sell, Grocery, Loot, and auto-repair output.
- Live-validated locked-slot cleanup and merchant auto-sell feedback.

## 0.17.87-ForeverPrep4-Forever69913

- Added modern pooled bag-button discovery and refresh hooks through `ContainerFrameItemButtonMixin`.
- Resolved real coordinates with `GetBagID()` and `GetID()` while retaining the Classic named-button fallback.
- Live-validated item classification overlays in combined and separate bag modes.

## 0.17.87-ForeverPrep3-Forever69913

- Extended safe boot from module initialization to cross-module public refresh paths.
- Made `/tfmove` respect the Movers compatibility group.
- Prevented Movers from invoking unstaged CombatMeter work.
- Added a defensive compatibility guard to CombatMeter refresh handling.

## 0.17.87-ForeverPrep2-Forever69913

- Added the first staging-state persistence workaround and compatibility-control mirrors.
- Established `/tf compat` commands for mode selection, staged groups, capability reporting, and diagnostic export.

## 0.17.87-ForeverPrep1-Forever69913

- Forked TurboFace Classic Era 0.17.87 into `TurboFaceForever`.
- Updated the TOC interface to 16001 and added Forever diagnostic SavedVariables.
- Added `Core/Compatibility.lua` with safe boot, capability contracts, initialization history, incident recording, and feature-group staging.
- Defaulted unknown non-Era clients to core-only startup so missing Classic APIs or incompatible protected UI could not initialize every feature at once.

## Fork baseline — TurboFace 0.17.87

The Forever fork began from the complete TurboFace 0.17.87 Classic Era source. Classic feature history, schema migrations through 79, third-party notices, and shared runtime design predate the fork and remain recorded in the repository-root documentation.

The compatibility investigation established the governing port model:

> WoW Forever has Classic-derived content but a modern/Mainline-derived addon API and UI framework, including secret values and modern protected-frame behavior.

The initial static impact map classified 715 dependencies as 457 safe, 162 verify, 32 compatibility-wrapper, 36 rework, and 28 blocked. These labels were conservative dependency findings, not declarations that the associated user-facing features are impossible.
