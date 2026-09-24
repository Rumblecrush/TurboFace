# TurboFace Forever Architecture

**Last updated:** 2026-09-23  
**Current addon version:** 0.18.0
**Target client:** World of Warcraft Forever beta 1.60.1, Interface 16001, project 1  
**Observed beta build:** 69977  
**Portable saved-variable schema:** 79  
**Forever client settings revision:** 2  
**Source baseline:** TurboFace unified 0.18.0
**Status:** supported multi-client build; shared systems, Forever-specific adapters, and deliberately reduced or dormant features are classified below.

This file is the **present-tense runtime and ownership contract** for TurboFace Forever. It is not a port diary. Release history, regressions, live discoveries, and dated rationale belong in [`CHANGELOG.md`](CHANGELOG.md); validation requirements belong beside the subsystem contracts below.

> **The code and live Forever client are the source of truth.** If this document conflicts with either one, verify the current client, update the implementation if necessary, and update this document in the same change.

---

## 0. Runtime invariants

These rules are load-bearing. A feature port is not complete merely because it renders.

- **Secret values are opaque.** Never compare, divide, round, format, concatenate, stringify, table-key, or otherwise inspect a value after `ns.API.IsSecretValue()` / `ns.API.CanAccessValue()` says it is unavailable. Opaque values may be passed only through specifically verified Blizzard/UI sinks.
- **Blizzard is the substrate owner.** On Forever, TurboFace augments modern Blizzard UI rather than replacing protected unit/nameplate systems or taking ownership of secret-driven StatusBars.
- **Addon visuals are detached when native ownership is risky.** A `UIParent`-owned TurboFace frame may use a Blizzard region as a write-only anchor. It must not become a child of a protected/pool-managed Blizzard object merely for convenience.
- **Native Blizzard objects are not addon state containers.** Do not write `_tf*` fields onto Blizzard action buttons, CompactUnitFrames, health bars, pooled aura buttons, or similar native objects. Use addon-owned side tables, preferably weak-key tables when the native object identity is the lookup key.
- **Protected geometry is out-of-combat work.** Changes to protected frame geometry are deferred until combat ends unless the live client explicitly proves the operation legal.
- **Native event callbacks are read/queue boundaries.** When Blizzard may continue into secret/protected code on the same execution path, TurboFace defers its own visual mutation to a later callback instead of mutating synchronously inside the native event/hook stack.
- **Disabled means dormant.** A disabled subsystem should not own avoidable events, CLEU consumers, cadence clients, timers, protected mutations, CVar ownership, or periodic discovery work.
- **Compatibility belongs at a boundary.** API-shape differences belong in `Core/Compat.lua`; client ownership/capability policy belongs in narrow adapters or client policy, not scattered guesses at call sites.
- **Classic remains a first-class source lineage.** Forever-specific fixes must not degrade the mature Classic Era implementation. Shared logic should stay shared only when the ownership assumptions truly remain shared.
- **Fail closed on uncertain gameplay data.** If Forever makes a required value secret or an identity ambiguous, hide/suspend the TurboFace augmentation rather than infer or reconstruct data the client no longer exposes.

---

## 1. Product and client model

TurboFace Forever is currently a fork of the Classic Era 0.17.87 source line, but it should be treated as a **client flavor**, not as permission to duplicate every Classic subsystem indefinitely.

Forever is identified by the stable tuple:

```text
version   = 1.60.1
interface = 16001
project   = 1
```

The numeric beta build is recorded for diagnostics but is **not** the compatibility boundary. The client advanced from build 69913 to 69977 without changing the stable tuple; exact-build gating therefore disabled correct adapters and re-opened unsafe paths. Client adapters must use the stable identity or direct capability detection.

`Core/Compatibility.lua` owns the current target identity and diagnostic capability inventory. `Core/Compat.lua` owns individual API normalization. `Core/Client.lua` resolves the selected client flavor and is the machine-readable source for feature implementation class/availability; it does not store user preferences.

`Core/Providers.lua` is the shared runtime implementation selector for features that have more than
one valid backend. Providers register under a named surface with a priority and optional
`IsSupported()` predicate; shared consumers ask for the active provider rather than branch on the
client. Current provider surfaces include `combatMeter`, `combatUI`, `nameplates`, `unitframes`,
`plusUI`, and `trainerUI`. Classic's TurboFace CLEU
meter is the priority-10 combat fallback while Forever's public `C_DamageMeter` bridge registers at
priority 100. `Nameplates/Provider.lua` registers the Classic native substrate at priority 10;
`Nameplates/ForeverNativeAdapter.lua` registers the Forever detached substrate at priority 100.
`UnitFrames/Provider.lua` registers Classic's readable/native UnitFrame policy at priority 10;
`UnitFrames/ForeverNativeAdapter.lua` registers the protected/native-safe Forever policy at priority 100.
`Plus/Provider.lua` registers Classic's Map/Interface ownership policy at priority 10;
`Plus/ForeverNativeAdapter.lua` registers native MapCanvas ownership at priority 100 so shared Map
code can yield protected zoom/pan state without asking which client is running.
`Trainer/Provider.lua` registers Classic's embedded/list Trainer presentation at priority 10;
`Trainer/ForeverNativeAdapter.lua` registers Forever's detached/native-card presentation at priority
100. Shared Trainer row/data builders therefore choose grid/card/host behavior through provider
capabilities instead of build checks.
`Combat/Provider.lua` registers Classic's readable combat-presentation policy at priority 10;
`Combat/ForeverNativeAdapter.lua` registers `forever-secret-safe` at priority 100. Shared class
combat modules use that provider for presentation ownership that genuinely differs: Classic's
ClassBuffs talent-point icon and direct Era reactive-nameplate indicator remain enabled, while
Forever yields those concerns to the standalone Speedrun reminder and detached/native nameplate
ownership respectively.

### 1.1 Three implementation classes

Every feature should be understood as one of three implementation classes:

1. **Shared implementation** — the Classic/Forever ownership assumptions are equivalent enough that one implementation can safely serve both clients through `ns.API`.
2. **Shared logic + client adapter** — feature semantics are shared, but Blizzard frame/API ownership differs. Common policy/data remains shared while Classic and Forever provide separate renderer/bridge layers.
3. **Client-specific or unavailable** — the client does not expose enough safe information to reproduce the Classic behavior. The feature is omitted, reduced, or replaced by a Blizzard-native equivalent.

Do not force class 2 or 3 features back into class 1 merely to reduce file count.

### 1.2 Capability beats parity

Forever is not required to expose every Classic checkbox. A missing Forever feature is acceptable when the underlying Classic implementation depends on API access Blizzard intentionally made secret or on native-frame mutations that taint protected execution.

The architectural target is **behavioral clarity**, not artificial checkbox parity:

- supported features behave predictably;
- reduced features state their narrower contract;
- unavailable features are absent/disabled rather than silently half-working;
- Blizzard-native replacements are preferred when they are authoritative.

---

## 2. Compatibility and secret-value boundary

### 2.1 `Core/Compat.lua`

`Core/Compat.lua` is the single low-level API facade. Modules should alias APIs from `ns.API` rather than bind legacy globals directly.

Typical patterns:

```lua
local GetSpellInfo = ns.API.GetSpellInfo
local GetActionInfo = ns.API.GetActionInfo
local IsCurrentSpell = ns.API.IsCurrentSpell
```

The facade currently normalizes modern namespaces such as `C_Spell`, `C_ActionBar`, modern aura APIs, item/container APIs, spellbook APIs, and Forever-specific safe value helpers.

Do not place feature policy in a low-level wrapper when the API itself works but ownership differs. For example, `C_ActionBar.GetSpell` is an API compatibility concern; whether Hotbar Power may attach a child to a protected action button is a feature ownership concern.

### 2.2 Secret-value helpers

The important shared helpers are:

```lua
ns.API.IsSecretValue(value)
ns.API.CanAccessValue(value)
ns.API.IsReadableNumber(value)
ns.API.SafeToString(value, fallback)
ns.API.ShouldAurasBeSecret()
ns.API.ShouldCooldownsBeSecret()
ns.API.SecretRestrictionsActive()
```

`issecretvalue()` must be consulted before ordinary Lua operations on an unknown scalar. A conventional `if value == nil then` guard is not automatically safe for a secret scalar.

Whole returned tables can contain secret fields. Callers must not assume a table-returning modern API is readable merely because the table object exists.

### 2.3 Opaque pass-through is allowed only after live proof

Forever sometimes permits an opaque value to flow into a Blizzard-approved UI sink while forbidding Lua inspection. Current proven examples include:

- addon-owned `StatusBar:SetValue(secretPower)`;
- `UnitPowerPercent(unit, powerType, false, curve)` evaluating a curve internally;
- secret-compatible color/text setters used by Hotbar Power;
- Blizzard-owned aura container/duration binding;
- Blizzard numeric abbreviation writing opaque unit health to a detached FontString.

Do not generalize one proven sink into a rule that all setters accept secret values. Each sink is a separate compatibility surface and must be live-validated.

### 2.4 Never derive hidden gameplay state from UI internals

TurboFace must not work around secret APIs by scraping protected native text, measuring forbidden regions, reading hidden Blizzard state fields, or reconstructing values from animation geometry. If Blizzard provides only presentation, TurboFace may augment that presentation but does not convert it back into gameplay data.

---

## 3. Startup and load order

`TurboFace.toc` defines source order. The current high-level sequence is:

1. Embedded libraries and Classic profession catalog data.
2. `Core/ForeverRestoreData.lua` before every SavedVariables consumer.
3. `Core/Compat.lua`, `Core/Compatibility.lua`, `Core/Client.lua`, `Core/Providers.lua`, shared
   `Core/Schema.lua`, then `Core/Config.lua`.
4. `Core/ForeverSchema.lua` registers Forever-only defaults/migrations before shared
   `Core/Defaults.lua` / `Core/Migrations.lua` / `Core/Profiles.lua` consume the schema contract.
5. Neutral metadata and shared prediction engines.
6. Classic-compatible feature implementations.
7. Forever adapters loaded after the shared owners they augment or replace.
8. Inventory/HUD/Movers/Plus/Power systems.
9. Trainer data, capture, queue, detached UI, Skills.
10. `Options/OptionsGUI.lua` last.

The decisive runtime boundary remains login/init, not file load. A file listed in the TOC may create inert tables or helper closures, but feature events/drivers should activate only after configuration is available and the feature is effectively enabled.

### 3.1 Why both shared and Forever files are currently in the TOC

The port still ships several Classic implementations because:

- some are safe shared logic;
- some provide non-Forever fallback behavior;
- some Forever adapters reuse shared data/policy but replace only rendering/ownership;
- the installed Forever package still uses its own TOC, while the unified development tree now has an executable overlay build.

This is acceptable during the port, but it is not the preferred final multi-client packaging strategy. See §25.

---

## 4. Saved variables and beta restore ownership

The Forever TOC declares:

```text
TurboFaceDB
TurboFaceCacheDB
TurboFaceProfilesDB
TurboFaceTrainerDB
TurboFaceSpeedrunDB
TurboFaceCompatDB
TurboFaceCharDB              (per character)
TurboFaceTrainerCharDB       (per character)
TurboFaceCVarExportCharDB    (per character)
TurboFaceSpeedrunCharDB      (per character)
```

`TurboFaceDB.dbVersion` / `ns.DB_VERSION` now use portable schema **79** on both Classic and
Forever. Forever-only settings evolution uses an internal client revision owned by
`Core/ForeverSchema.lua`; the current Forever revision is **2**. That revision metadata is runtime
SavedVariables bookkeeping only and is excluded from named profiles / `TF1:` exports.

### 4.1 Normal ownership remains the Classic ownership model

- shared `Core/Defaults.lua` owns the portable settings baseline and calls the active client schema
  adapter for genuinely client-only defaults;
- shared `Core/Migrations.lua` owns portable schema progression, repair, default merge, and
  build-cache invalidation;
- shared `Core/Schema.lua` owns the two-axis portable/client revision contract;
- `Core/ForeverSchema.lua` owns Forever-only defaults/migrations without advancing portable
  `dbVersion`;
- `Core/Config.lua` owns runtime gates, CVar ownership, shared cadence/timer/CLEU infrastructure, and common settings helpers.
- `Core/Profiles.lua` owns named profiles/import/export.
- Trainer, Speedrun, and per-character data remain separated from the main configuration root as in Classic.

### 4.2 Forever beta SavedVariables workaround

The current beta has exhibited unreliable SavedVariables reload behavior. TurboFace therefore has a development-only restore path:

```text
Core/ForeverRestoreData.lua
Core/ForeverDevPreset.lua
FOREVER_SAVEDVARIABLES_WORKAROUND.md
```

The generated restore snapshot must load before any consumer that can read `TurboFaceDB` at file scope. When a valid restore payload is present, it is authoritative for that login. When no valid payload exists, the hardcoded Dev Preset supplies a deterministic testing baseline.

This workaround is **not** the desired release architecture and must never become a second feature-gating system. Normal module/feature Options remain the runtime gates after initialization.

The packaged source-tree `Core/ForeverRestoreData.lua` must remain inert. Development installations may deliberately replace the live copy with an external generated snapshot, but release packaging must never accidentally ship that private active snapshot.

### 4.3 Cache invalidation

Normal discovery/cache data in `TurboFaceCacheDB` is build-specific and is cleared when the client build changes. Exact ownership debt and long-lived observational data are preserved where required, including CVar ownership snapshots, Hearthstone batching observations, and learned flight timings.

---

## 5. Module and feature gating

Module family state lives under:

```lua
TurboFaceDB.modules
```

and is read through:

```lua
ns.ModuleEnabled(family [, element])
```

Missing or malformed gates fail open; only explicit `false` disables a stored gate. Client safety may still impose a **capability fail-closed** boundary when the required Forever adapter is absent.

Current module families are:

| Family | Meaning |
|---|---|
| `unitframes` | Player/Target/ToT/Party/Pet family |
| `nameplates` | Forever detached/native-safe nameplate augmentation |
| `auras` | shared aura family; Forever nameplate aura presentation uses native AuraContainers |
| `hotbarPower` | action-button missing-power overlay and cast counter |
| `playerTicks` | player resource/health tick markers |
| `swingTimers` | player/target swing presentation |
| `castBars` | TurboFace castbar presentation |
| `class` | class features/reminders and class-specific surfaces |
| `plus` | QoL section container |

There are also feature-local gates outside the family tree, including prediction, Trainer, Hearthstone, Speedrun/HUD, Loot, Grocery, Net Worth, and other independent widgets.

### 5.1 Stored preference vs effective availability

A stored setting is a preference, not proof that the current client can implement the feature. Forever may preserve Classic-compatible settings even when their renderer is unavailable.

Example:

```text
Nameplate power overlap preference = ON
Forever safe native-mutation capability = unavailable
Effective Forever feature = dormant
Stored preference = preserved
```

Do not delete a user's cross-client preference merely because Forever cannot currently honor it.

### 5.2 Forever feature-state categories

Use these terms consistently:

- **Shared** — common implementation is active on Forever.
- **Adapted** — feature is active through a Forever-specific ownership/API adapter.
- **Reduced** — a safe subset is active; Classic-only behavior is intentionally omitted.
- **Blizzard-owned** — TurboFace yields the feature to a current native implementation and may provide only surrounding integration.
- **Dormant/blocked** — no safe implementation currently exists.
- **Probe/development-only** — diagnostics/evidence collection, not a user feature contract.

Prep124 makes these categories executable through `Core/Client.lua`. Prep125 freezes the
validation vocabulary so diagnostics cannot invent one-off status labels. The registry records
implementation class, effective availability, ownership, and a coarse live-validation state. It is
not a second gate store: `TurboFaceDB` remains the only owner of user enable/disable preferences.
`ns.ModuleEnabled()` combines the saved preference with group-level client availability, while
feature-specific Options can query `ns.FeatureAvailable(key)` without duplicating Forever checks.

Validation states are:

- `classic-baseline` — the mature Classic implementation is the semantic reference;
- `prepared` — implementation exists but its advertised path still needs current live proof;
- `live-partial` — at least one supported path has been exercised live, but the whole feature family
  is not yet fully validated;
- `live-validated` — the specific advertised behavior has current live proof;
- `blocked` — no supported runtime exists under the current client contract.

### 5.3 Current high-level availability

| Area | Forever state | Architectural owner |
|---|---|---|
| Core config/profiles/gates | Shared + beta restore workaround | `Core/*` |
| Inventory / Bank / Grocery / Net Worth / Bag Slots | Mostly shared/adapted | `Inventory/*` |
| Experience Bar / Speedrun Splits / Loot / FPS / Hearthstone | Mostly shared | root HUD files |
| Movers | Shared for addon-owned surfaces; protected-native caveats remain | `Movers/*` |
| Swing Timers | Shared engine + `swingTimers` runtime provider; Forever `PLAYER_SWING` is authoritative for player clocks | `Combat/SwingTimers.lua`, `Combat/SwingTimerProvider.lua`, Forever adapter |
| DPS/HPS badge | Adapted to Blizzard `C_DamageMeter` | bridge + badge |
| Classic Combat Meter window/runtime | Blizzard-owned/replaced on Forever | legacy runtime dormant |
| Hotbar Power | Adapted and live-validated through secret-safe detached overlays | `Power/PowerCost.lua` |
| Trainer / Skills / profession Training | Adapted; modern spellbook/profession UI + live capture | `Trainer/*`, `Skills.lua` |
| Nameplates | Adapted/reduced; detached overlays + Blizzard-owned native chassis | Forever adapter files |
| Nameplate auras | Adapted through Blizzard AuraContainers | `Nameplates/ForeverAuras.lua` |
| Unit Frames | Shared policy + Forever native-safe provider; some Classic add-ons remain blocked | `UnitFrames/Provider.lua`, `UnitFrames/ForeverNativeAdapter.lua` |
| DoT/Heal prediction rendering | Dormant/blocked where secret numeric inputs are required | prediction engines/consumers |
| NanShield/custom absorb reconstruction | Dormant on Forever baseline | `UnitFrames/nanShield.lua` |
| Enhanced World Map zoom/remember | Dormant; native MapCanvas/pins are Blizzard-exclusive through the Plus UI provider | `Plus/Provider.lua`, `Plus/ForeverNativeAdapter.lua`, `Plus/MapTweaks.lua` |
| Quest numeric levels | Blizzard-owned | TurboFace keeps difficulty tags only |
| Nameplate native name shadow | Blizzard-owned | TurboFace option hidden on Forever |

This table is architectural classification, not a test checklist. `Core/Client.lua` is the machine-readable classification source; prose should describe rather than independently redefine those states.

---

## 6. Shared runtime services

Forever retains the mature TurboFace shared runtime model where the underlying API remains safe.

### 6.1 `ns.Cadence`

Periodic addon work should use the shared cadence scheduler rather than creating independent permanent `OnUpdate` handlers. Client callbacks are isolated through `pcall` and repeated failures are evicted so one broken subsystem cannot stop every periodic feature.

The same rules as Classic apply:

- keys are addon-wide and must be unique;
- clients register only while useful work exists;
- the last client leaving parks the scheduler;
- feature teardown removes its cadence ownership;
- high-frequency work must have a documented reason.

### 6.2 `ns.Timers`

Visible per-widget countdown work remains a shared cadence client. Secret-backed Blizzard countdowns are an exception: when the native client owns a duration object/AuraContainer, TurboFace should use the native formatter/binding rather than pull the secret time back into `ns.Timers`.

### 6.3 `ns.CLEU`

The shared combat-log dispatcher remains appropriate for observable combat events. It must not be used to reconstruct a client-secret unit value merely because a combat log event provides related information.

Examples of legitimate Forever CLEU consumers include swing observation, queue cleanup, and other event-level mechanics whose values remain public.

---

## 7. Shared namespace and public contracts

Modules communicate through the addon-local `ns` namespace. Important current owners include:

```text
ns.API
ns.Compat
ns.defaults
ns.Cadence
ns.Timers
ns.CLEU
ns.NP
ns.ForeverNameplates
ns.UF
ns.ST
ns.Castbars
ns.Power
ns.RegenTicks
ns.Trainer
ns.Movers
```

Expose narrow methods rather than sharing mutable implementation tables. Client adapters should present the smallest interface required by shared code.

Avoid creating two owners for one Blizzard frame, one saved setting, or one periodic driver.

---

## 8. Source layout and ownership

The current Forever fork largely mirrors Classic:

```text
TurboFaceForever/
├── Core/          compatibility, config, defaults, migrations, profiles, diagnostics
├── Nameplates/    shared nameplate logic plus Forever detached adapters/AuraContainers
├── UnitFrames/    shared unit-frame logic plus Forever native-safe adapter
├── Combat/        swing/cast/class/prediction/meter logic and C_DamageMeter bridge
├── Power/         Hotbar Power and player regen/tick engine
├── Inventory/     inventory/bank/grocery/net-worth/bag-slot ownership
├── Movers/        mover registry and integrations
├── Plus/          automation/social/interface/map/system/chat/flight utilities
├── Trainer/       training data/capture/queue/UI and Forever profession seeds
├── Options/       configuration UI
├── Libs/          embedded libraries/data
└── Core.lua       initialization and cross-system lifecycle wiring
```

Forever-specific implementation files currently include:

```text
Core/ForeverDevPreset.lua
Core/ForeverRestoreData.lua
Nameplates/ForeverNativeAdapter.lua
Nameplates/ForeverAuras.lua
Plus/ForeverNativeAdapter.lua
UnitFrames/ForeverNativeAdapter.lua
Trainer/data/ForeverProfessions.lua
```

`Core/Compatibility.lua` is Forever-port diagnostics/runtime evidence; it is distinct from the low-level API facade in `Core/Compat.lua`. Prep124 removes its duplicated static `PORT_MATRIX`: `/tf compat plan` and diagnostic exports now consume `Core/Client.lua`'s registry.

### 8.1 Current branching debt

The Prep125 source audit replaced that rough estimate with direct Classic-versus-Forever evidence.
Prep126 performs the first convergence wave: Classic now loads the shared `Core/Client.lua`, exposes
the compatibility aliases needed by shared consumers, and twelve >=99%-similar feature files become
byte-identical. Prep127 then extracts the first runtime provider surface and centralizes the DPS badge
plus both Mover implementation files. Prep128 resolves the final >=99% schema/profile divergence by
sharing Defaults/Migrations/Profiles and moving Forever-only changes to `Core/ForeverSchema.lua`.
Prep129 extracts the Nameplate substrate provider and physically shares six formerly divergent
Nameplate runtime files. Prep130 begins the UnitFrame provider split; Prep131 completes the primary
source convergence by promoting `UnitFrames/UnitFrames.lua` itself into the common layer while
leaving modern/protected execution in `ForeverNativeAdapter.lua`. Prep132 adds the Plus UI provider
and promotes shared MapTweaks/MinimapTracker while Forever keeps only the native MapCanvas ownership
adapter client-specific. Prep133 adds the Trainer UI provider and promotes the reusable row/list/data
builders while keeping the detached profession/spellbook hosts client-owned. Prep134 then promotes
the trainer-service normalization/capture path to common source. Prep135 promotes Trainer events,
legacy-list ownership guards, and Training Queue policy after their modern paths were reduced to
optional compatibility capabilities. Prep136 promotes `Trainer/SkillData.lua` after its two real
client differences were expressed through narrow provider capabilities. Prep137 then promotes the
Chat, Social, and Flight Bar QoL modules after Classic Compat adopts the same guarded chat/Battle.net/
party/event vocabulary used by Forever. Prep138 then promotes Automation and System Tweaks after
player-interaction actions move behind Compat and vendor-price tooltip ownership becomes an explicit
`plusUI` capability. Prep139 then promotes the ClassFeatures/ClassBuffs/QueueDiagnostics cluster
after combat presentation ownership moves behind `combatUI` and diagnostics adopt secret-safe
Compat reads. Prep140 then decomposes SwingTimers behind a dedicated `swingTimers` provider:
Classic keeps the readable CLEU/spellcast runtime, while Forever owns `PLAYER_SWING`, restricted
hostile-speed handling, and Character/PaperDoll damage capture in a client-only adapter. Prep141 centralizes InventoryManager, Bank, and NetWorth;
Prep142 completes the family by centralizing Grocery behind normalized merchant APIs and a
template-free item-cell implementation. Inventory and Combat now both have zero same-path
divergences. Prep143 promotes `PartyPetAuras.lua` into common: Party/Pet aura presentation uses
the Compat secret-domain boundary, reversible native-aura suppression, and guarded event
registration, preserving Era's readable-aura behavior while Forever fails closed when aura data is
protected. This is the main evidence against
both extremes:

- the project has **too much divergence** for one undifferentiated all-client runtime forever;
- it has **too much shared logic** to justify two independently maintained codebases.

The recommended repository/build direction is in §25.

---

## 9. Nameplate architecture

### 9.1 North star: Blizzard owns the plate

Forever nameplates are modern pooled CompactUnitFrame systems. Health and other combat values can become secret, and live testing proved that mutating native plate/health-bar objects can taint Blizzard's later secret execution.

Therefore:

- Blizzard owns the native plate root, CompactUnitFrame, health/power bars, cast/aura/classification internals, pooling, and secret values.
- TurboFace owns only addon-created detached overlays and external state.
- Native objects may be write-only anchors; they are not parents or state tables.
- TurboFace does not measure forbidden native geometry to recreate hidden values/layout.

### 9.2 Shared Nameplate provider contract

`Nameplates/Provider.lua` is the shared substrate-policy boundary for the Nameplate family. It is
loaded after `Core/Providers.lua` and before any Nameplate consumer.

Classic registers `classic-native` at priority 10. Forever's detached adapter registers
`forever-detached` at priority 100. Shared Nameplate code therefore asks the active provider how a
native update must be staged instead of branching on `IS_TARGET_FOREVER_BUILD`.

The current provider contract owns only substrate differences that are proven to matter:

- whether the legacy TurboFace nameplate aura rows may run;
- whether power updates must leave Blizzard's current native event stack before rendering;
- whether heal-prediction updates must be deferred;
- whether target/group/faction refreshes run immediately or on the next native-safe callback;
- how zero-delay Nameplate batches are scheduled.

This is intentionally not a general “client abstraction” object. Pure spell/NPC policy and visual
logic remain shared; native frame ownership remains in the selected client provider.

### 9.3 `Nameplates/ForeverNativeAdapter.lua`

The Forever adapter owns the safe augmented path. It keeps per-plate state outside Blizzard frames and uses `UIParent`-owned overlays.

Current safe/adapted surfaces include, subject to their own live capabilities:

- selected/non-selected presentation amendments that use safe manager/CVar boundaries;
- combo presentation;
- friendly NPC title/job information;
- detached health text;
- stable-alias threat percentage and Aggro Audio when readable;
- enemy swing presentation;
- detached Blizzard-owned aura rows.

### 9.4 Threat percentage

Threat results can be secret when the mob token is `nameplateN` but readable through stable public aliases. The adapter therefore maps visible plates to target/focus/mouseover/pet-target/group-member-target aliases using secret-safe identity checks, then requests only readable threat fields.

Arbitrary visible plates without a stable alias intentionally show no quantitative threat value.

### 9.5 Detached health text

Forever does not use the Classic native-FontString reanchor path. TurboFace owns a detached FontString and passes opaque `UnitHealth` through the verified Blizzard abbreviation/write path without Lua arithmetic or formatting.

Whole-nameplate and fill-only centering use known anchor identities rather than forbidden coordinate reads.

### 9.6 Native name shadow

Blizzard's Forever nameplate name already owns its shadow. TurboFace does not create the Classic name-shadow amendment on Forever, and the corresponding option is hidden there.

### 9.7 Unsupported native-mutation features

Features that require unsafe mutation of Blizzard pooled internals remain reduced/dormant until a detached or native-owned strategy exists. Examples have included native rarity relocation, friendly damaged-only chassis suppression, native power-bar overlap/height manipulation, and some reactive class indicators.

Do not re-enable the Classic implementation behind a version check just because it appears visually correct out of combat.

---

## 10. Nameplate auras

`Nameplates/Auras.lua` now contains the shared Classic-era aura-row policy but activates only when
the selected Nameplate provider reports that legacy aura rows are valid. On Forever that provider
returns false and `Nameplates/ForeverAuras.lua` is the client-owned renderer.

`Nameplates/ForeverAuras.lua` is the Forever aura renderer.

- Aura containers are addon-created children of `UIParent`.
- The native health bar is used only as an anchor target.
- Blizzard `CustomAuraContainerTemplate` owns aura queries, secret duration state, sorting, cooldown/count binding, and updates.
- TurboFace translates user presentation/filter choices into native groups/candidate filters.
- TurboFace does not run the Classic aura index scanner when the aura domain is secret.
- Generated aura buttons may become forbidden after Blizzard binds secret state. TurboFace styles them only during the safe initialization callback and does not mutate bound buttons during ordinary refresh.

Duration formatting is supplied through Blizzard's binding path; TurboFace does not read a secret remaining time to produce countdown text.

---

## 11. Unit Frames

### 11.1 Blizzard owns secure unit state

`UnitFrames/ForeverNativeAdapter.lua` keeps Blizzard's Player/Target/ToT/Pet/Party secure frame hierarchy and health/power StatusBars authoritative.

TurboFace may add detached fixed artwork and safe text/presentation around that substrate, but it does not create replacement health/power bars fed by secret unit values.

### 11.2 External state and detached artwork

Forever UnitFrame state belongs in addon-owned tables. Fixed TurboFace art is owned by addon frames rather than attached as children/state on protected Blizzard unit frames.

Protected geometry changes are out-of-combat and coalesced after native layout changes. Do not fight Edit Mode with a permanent `OnUpdate` tug-of-war.

### 11.3 Shared UnitFrame provider contract

`UnitFrames/Provider.lua` is the shared capability/ownership boundary for UnitFrame-adjacent
renderers. Classic registers `classic-readable` at priority 10. Forever's native-safe adapter
registers `forever-native-safe` at priority 100 immediately after the shared UnitFrames core loads
and before optional prediction/absorb consumers initialize.

The provider currently owns these proven client differences:

- whether TurboFace's custom DoT/heal prediction textures may attach to the UnitFrame surface;
- whether NanShield's modeled absorb renderer may run;
- whether the Classic Druid auxiliary power StatusBar may run;
- how shared consumers resolve the active Player health/power bars without manufacturing legacy
  globals on Forever;
- whether the selected UnitFrame renderer is detached/native-safe.

`DruidPowerBar.lua`, `Predictions.lua`, `nanShield.lua`, and the primary
`UnitFrames/UnitFrames.lua` body are therefore one physical shared implementation. Classic enters
the shared core's historical readable `UF:Init()` renderer. Forever does **not**: its adapter
replaces `UF:Init()` and `UF:Refresh()` before Core initialization, resolves modern Player/Target/ToT
objects itself, supplies the Forever-specific Player art/reserve geometry used by shared consumers,
and keeps detached artwork/protected native bars authoritative.

The shared primary file still contains the Era renderer implementation because Classic uses it; its
presence in the Forever package is not runtime ownership. Provider/load-order validation must ensure
the Forever adapter replaces the entry points before `Core.lua` invokes UnitFrames.

### 11.4 Current reduced features

Classic features whose implementation requires readable health/aura/absorb numbers or addon regions parented directly to protected native bars remain dormant on the Forever baseline. This includes the Classic prediction renderers, NanShield reconstruction, and the other blocked surfaces classified in this document and `Core/Client.lua`.

### 11.5 ToT / Party / Pet

These are separate validation surfaces even when they share art code. A Player-frame success does not prove Party/ToT/Pet ownership is safe. Every child must be tested through target changes, roster churn, pet summon/dismiss, combat entry/exit, and native layout changes.

---

## 12. Combat systems

### 12.0 Shared combat presentation ownership

`Combat/ClassBuffs.lua`, `Combat/ClassFeatures.lua`, and `Combat/QueueDiagnostics.lua` are shared
source. Client differences are isolated at two boundaries:

- `combatUI` decides whether ClassBuffs owns the historical unspent-talent icon and whether
  ClassFeatures may attach its reactive Overpower indicator to the Era nameplate surface;
- `Core/Compat.lua` owns readable/secret-safe diagnostics through `API.SafeToString()` and the
  `API.ReadUnit*` helpers.

Classic selects `combatUI=classic-readable`: the old talent reminder and reactive nameplate
indicator remain valid. Forever selects `combatUI=forever-secret-safe`: the talent concern is owned
by `SpendTalentPoint.lua`, and the direct native-nameplate reactive renderer stays dormant until a
detached implementation exists. This is presentation ownership only; the shared class spell/buff
catalogs and runtime policy remain common.

### 12.1 Player swing clock

Forever exposes `PLAYER_SWING(swingDuration, swingType)`. When available, it is authoritative for the player's own MH/OH/ranged clocks:

```text
MainHand -> player main-hand timer only
OffHand  -> player off-hand timer only
Ranged   -> ranged timer only
```

Player CLEU swing events must not double-reset those clocks. CLEU remains available for independent consumers such as target/nameplate observation, parry-haste behavior, queue cleanup, and explicit reset effects.

Ranged swings must never reset melee clocks; this is particularly important for wand behavior.

### 12.2 Current-spell/queued-next-melee compatibility

Queue state uses `ns.API.IsCurrentSpell`, which prefers the modern `C_Spell.IsCurrentSpell`. Feature code must not call the removed legacy global directly.

### 12.3 Damage meter ownership

Forever exposes public `C_DamageMeter`. TurboFace therefore does not run its Classic CLEU-backed Combat Meter runtime as the authoritative meter on Forever.

Provider selection now owns this split. `Combat/CombatMeter.lua` registers the shared TurboFace
local-accounting implementation as the low-priority `combatMeter` provider;
`Combat/BlizzardDamageMeterBridge.lua` registers the Forever native provider at higher priority when
`C_DamageMeter` is supported. Core startup, Options refreshes, Movers dependent refreshes, slash
commands, and the PlayerFrame DPS/HPS badge all call the selected provider rather than inspect
`BlizzardDamageMeterBridge` directly.

Both providers expose the same narrow surface for the badge: view/metric selection, reset/display
capabilities, tooltip text, and `RenderPlayerRate(fontString, staleAfter)`. Classic formats its
readable local rate in Lua; Forever forwards the opaque Blizzard rate only into the verified
`FontString:SetFormattedText` secret sink. Shared badge code therefore never needs to know whether
the value is readable or secret.

### 12.4 Predictions

Classic DoT/heal prediction algorithms can depend on readable unit health and aura state. Where Forever makes those values secret, the custom numeric prediction path fails closed. Do not substitute guessed health bases or infer precise missing values from UI pixels.

---

## 13. Hotbar Power architecture

Hotbar Power is the clearest example of the Forever adapter pattern: the user-facing feature is preserved, but native ownership and secret computation differ radically from Classic.

### 13.1 Action-button ownership

TurboFace must not:

- parent overlay frames to protected Blizzard action buttons;
- write addon fields such as `_tfPowerOverlay` onto those buttons;
- hook/mutate protected action-button internals for this feature.

Instead:

- overlays are direct `UIParent` children;
- Blizzard buttons are anchor targets only;
- button-to-overlay identity lives in a weak-key addon side table.

### 13.2 Action resolution

Action metadata resolves through `ns.API` and modern `C_ActionBar` first.

For macro-backed actions, Forever uses:

```lua
C_ActionBar.GetSpell(actionSlot)
```

as the primary resolver. Blizzard therefore remains authoritative for stance-conditioned macro logic; TurboFace consumes the spell Blizzard currently represents instead of parsing secure macro conditionals itself. The historical macro-body path remains a compatibility fallback outside the modern native resolver.

Stance/bonus-bar changes trigger structural re-resolution.

### 13.3 Secret player power

Current Rage/power can be secret. The Forever render path therefore has two separate data flows:

```text
opaque UnitPower(player)
    -> detached addon StatusBar:SetValue()

readable spell cost + readable UnitPowerMax
    -> build normalized [0,1] numeric/color curves
    -> UnitPowerPercent(player, powerType, false, curve)
    -> native-evaluated secret result
    -> verified addon-owned UI sink
```

TurboFace does **not** call `CurveObject:Evaluate(secretPower)` directly. Live validation proved that boundary is rejected even when the curve object itself works.

### 13.4 Fill semantics

The colored resource overlay means only **missing power for the first cast**.

- Below the spell cost: show the bottom-up missing-power progress.
- At or above the spell cost: hide the fill completely.
- The cast counter is independent and may continue to show `1.x`, `2.x`, etc.

The visibility breakpoint is expressed in normalized `cost / maxPower` coordinates because `UnitPowerPercent(..., curve)` evaluates over `[0,1]`.

### 13.5 Counter precision

Readable Classic/Era values retain the legacy arithmetic/formatting path. Forever secret counters use bounded whole/one-decimal curve steps so the client can display useful affordability counts without Lua inspecting the current secret resource.

### 13.6 Diagnostics

`/tf powerprobe` is read-only and bounded. It reports action resolution, overlay allocation, secret-path capabilities, and ordinary per-stage success booleans. It must never print or stringify opaque current power or secret curve results.

---

## 14. Player regen/tick markers

Player tick markers remain a separate feature family from Hotbar Power. They must not inherit Hotbar's action-button ownership or be hard-parented to TurboFace Unit Frames merely because they can integrate visually with them.

Any Forever path that needs direct current resource arithmetic must independently prove readability. A Hotbar secret sink does not grant the tick engine permission to inspect secret resource values.

---

## 15. Trainer, Skills, and professions

Trainer/Skills is a major shared-logic + client-adapter subsystem.

### 15.1 Spell metadata

Spell names/icons/subtext resolve through `ns.API` (`C_Spell` on modern clients). Direct reliance on removed spell globals is forbidden in Forever-specific Trainer paths.

### 15.2 Trainer service identity

Queue automation must meet an NPC trainer row and a stored Training row at a stable numeric spell ID whenever both sides expose one.

Numeric mismatch must not fall through to same-name matching because Forever may omit rank text, causing several ranks to share one localized service name.

Name/rank fallback exists only when numeric identity is genuinely unavailable and must fail closed on ambiguity.

`Trainer:GetTrainerServiceInfoCompat()` is the normalization boundary for legacy/Forever trainer return shapes.

### 15.3 Load-on-demand spell data

Modern spell metadata can require `C_Spell.RequestLoadSpellData`. Requests are deduplicated; `SPELL_DATA_LOAD_RESULT` schedules a retry rather than creating an unbounded loop.

### 15.4 Shared Trainer UI provider contract

Trainer data, queue semantics, grouping, and the reusable row renderer are shared. Presentation
substrate ownership is selected through the `trainerUI` provider:

- Classic registers `classic-embedded` at priority 10. It uses the Era embedded Spellbook/Trainer
  host, one-column list rows, and the ordinary TurboFace row presentation.
- Forever registers `forever-detached` at priority 100. It uses detached addon-owned pages,
  native-styled Trainer cards, an 8px Spellbook list size bump, and the 2/4-column grid layout.

`Trainer/UI_Core.lua`, `Trainer/UI_ClassData.lua`, `Trainer/UI_ClassList.lua`, and
`Trainer/UI_Skills.lua` are physically shared and contain no direct Forever build check. The large
profession and Spellbook host controllers remain client-owned because their native frame ownership
and lifecycle are genuinely different.

### 15.5 Shared trainer-service compatibility and capture

Prep134 moves `Trainer/Init.lua`, `Trainer/TrainerCapture.lua`, and
`Trainer/PetMerchantCapture.lua` into the physical common layer. The shared implementation is a
strict compatibility superset rather than a Forever branch hidden inside common code:

- Era's normal `GetTrainerServiceInfo(index)` layout (`name`, `rank`, category in return #3,
  expanded in return #4) is recognized directly as `category-third`;
- alternate/structured trainer-service returns are accepted only at the normalization boundary and
  unknown layouts fail closed;
- Classic's `GameTooltip:SetTrainerService()` / `GetSpell()` numeric spell identity remains the
  normal tooltip-first path when available;
- `C_TooltipInfo.GetTrainerService`, seeded class-catalog identity, and
  `C_Spell.RequestLoadSpellData` are guarded fallbacks for clients where unlearned spell metadata is
  no longer synchronously exposed;
- profession capture stores explicit `skillReq` / `skillName` metadata so modern native-card
  presentation never confuses a profession bucket with a character-level requirement;
- pet-trainer merchant tooltips prefer `TooltipDataProcessor` when available and fall back to the
  Era `OnTooltipSetItem` hook; pet existence/health reads go through `ns.API` so Forever can fail
  closed on inaccessible values while Classic remains readable.

### 15.6 Shared Trainer events, list ownership, and Training Queue

Prep135 moves `Trainer/Events.lua`, `Trainer/TrainerListUI.lua`, and `Trainer/TrainingQueue.lua` into
the physical common layer:

- trainer-close and spell-data events are optional registrations, so a client without a companion
  event cannot fail Trainer initialization;
- the legacy `ClassTrainerFrame_Update` replacement installs only when the complete Era XML/function
  surface exists. A modern/native trainer therefore keeps exclusive presentation ownership;
- Training Queue resolves every trainer row through `GetTrainerServiceInfoCompat()` and every known
  spell check through `ns.API.IsKnownSpellID()`;
- when both the queue record and trainer row have numeric spell IDs, a mismatch is final. Same-name
  fallback is allowed only when one side genuinely lacks numeric identity, preventing an unavailable
  later rank from replacing the exact queued rank;
- load-on-demand spell warming and `SPELL_DATA_LOAD_RESULT` retries remain guarded capabilities and
  are inert on Classic clients without those modern APIs;
- `/tf debug trainer` uses the same read-only queue/service diagnostics on both flavors.

### 15.7 Shared SkillData capability contract

Prep136 moves `Trainer/SkillData.lua` into the physical common layer. Weapon skills, profession
starters, proficiency ranks, captured general-skill metadata, queue migration, and skill-gate logic
now have one implementation on both clients.

The remaining data-source differences are narrow `trainerUI` provider capabilities rather than
client branches inside SkillData:

- Classic preserves the generic `Weapon Master` source and uses the shared Skills engine as the
  profession-rank authority;
- Forever may show detailed trainer/city weapon-master sources and may consult
  `C_TradeSkillUI.GetBaseProfessionInfo()` when the matching profession page is open and the legacy
  skill-line path is unavailable.

Human requirement text is stored in `requirementText`; `requires` is reserved for prerequisite
spell-ID tables. This keeps profession text from being interpreted as a spell dependency.

### 15.8 Detached Spellbook pages

Forever's Player Spells UI is retail-derived. TurboFace's Training/Skills launchers use native artwork but remain addon-owned; they do not join or mutate Blizzard's internal tab collection/layout state.

TurboFace observes native navigation with secure post-hooks and closes/restores its detached page on a later callback. It does not synchronously mutate the book inside Blizzard's native tab call stack.

### 15.9 Professions

Forever's professions UI and recipe catalog differ materially from Classic. `C_TradeSkillUI` is authoritative for active profession identity, current skill, recipe IDs, and learned state.

The Classic LibProfessionDB catalog is useful reference/evidence but **not** proof that a Forever recipe is trainer-taught. Forever-specific static Training seeds are added only when live trainer evidence confirms teaching identity/requirements. Live trainer capture overrides static seed metadata.

Bulk profession probes/capture are development evidence tools, not runtime recipe-discovery requirements for ordinary users.

---

## 16. Inventory

Inventory remains one of the most reusable areas because much of its behavior is data/policy rather than protected combat UI.

Modern pooled bag/bank surfaces still require client-aware frame/template handling, but TurboFace ownership remains:

- item state classification;
- junk/useful/bank intent;
- sell/deposit/withdraw policy;
- grocery planning and merchant interaction;
- Net Worth aggregation;
- free-slot presentation.

Do not assume a Classic item-button template/global exists on Forever. Resolve modern containers/buttons through compatibility helpers and keep protected/merchant operations within normal Blizzard permission boundaries.

---

## 17. Movers and Edit Mode

Movers remain the placement owner for TurboFace-created surfaces that have no sensible fixed Blizzard anchor.

Forever adds two constraints:

1. Native Edit Mode/layout can reapply Blizzard geometry after a one-shot mutation.
2. Protected frame movement may be illegal in combat.

Prefer moving TurboFace-owned detached frames. When a supported feature must amend Blizzard geometry, apply only through a documented adapter, defer combat-unsafe work, and reapply after known native layout changes rather than polling every frame.

Do not insert TurboFace-owned elements into Blizzard's internal Edit Mode systems merely to make them draggable; shared TurboFace Movers remain the addon placement owner.

The Objective Tracker is the first mover ownership boundary expressed entirely through the client
feature registry rather than an explicit Forever branch. `movers.questTracker` is available on
Classic and Blizzard-owned/unavailable to TurboFace on Forever. The physically shared
`Movers/Movers.lua` and `Movers/Systems.lua` consult that capability before registering tracker
events, hooks, mover state, or Options rows. Forever therefore installs **zero** Objective Tracker
hooks while Classic retains the existing mover behavior from the same source files.

---

## 18. Speedrun and HUD utilities

The root-level utility widgets remain intentionally independent where possible:

- Experience Bar;
- Speedrun Splits;
- Loot Frame;
- FPS Counter;
- Spend Talent Point reminder;
- Hearthstone Tracker and batching;
- Minimap tracker/button;
- UnstuckSkips visual;
- Grocery/Bag Slots/Net Worth through Inventory.

These features should not acquire client-specific branches unless the underlying Blizzard API actually differs.

The Spend Talent Point reminder is Speedrun/HUD-owned rather than a ClassBuff dependency. Forever may use modern talent APIs through `ns.API.GetUnspentTalentPoints` while Classic retains its compatible fallback.

---

## 19. Quick Setup

Lvl1 Quick Setup remains a high-risk subsystem because macros, bindings, action slots, Edit Mode, and protected bar state cross secure boundaries.

Forever macro/action restore must use the modern action-slot scope and refuse unsafe/destructive cleanup when identity is uncertain. It must never use the SavedVariables workaround as an excuse to mutate protected action state during combat.

Quick Setup should remain one of the last systems revalidated after a client update.

---

## 20. QoL / Plus subsystem

The visible QoL tab retains the flat `TurboFaceDB.plus` profile namespace for compatibility, while section masters gate reads through `ns.PLUS_SECTION` and the read-only settings proxy.

Forever differences are feature-specific:

- modern Minimap objects may be Frames/NineSlices rather than legacy textures;
- GameTime/day-night presentation is split across modern/hybrid objects;
- World Map canvas/provider/pin ownership is protected and Blizzard-exclusive on Forever;
- numeric quest levels are already native, so TurboFace keeps only optional difficulty tags;
- tooltip hooks use modern `TooltipDataProcessor` where appropriate;
- automation must continue to obey normal secure interaction restrictions.

### 20.1 World Map hard boundary

`Plus/MapTweaks.lua` is physically shared as of Prep132. It does not decide ownership from a build
check. `Plus/Provider.lua` registers `classic-ui`, where TurboFace may augment the Era MapCanvas,
and `Plus/ForeverNativeAdapter.lua` registers `forever-native-ui`, where Blizzard owns the modern
MapCanvas. Shared MapTweaks therefore keeps the Classic cursor-centred zoom / extended zoom ladder /
remembered pan+zoom code while refusing to install any of those hooks when the active provider says
the native canvas is Blizzard-owned.

TurboFace must not replace `WorldMapFrame.ScrollContainer` zoom levels, hook native mouse-wheel
behavior to mutate MapCanvas internals, or touch provider/pin pools on Forever. The top-level
draggable window remains independent because it never touches the ScrollContainer lifecycle.
MapCanvas readiness checks (map ID, child dimensions, zoom levels, and map-art metadata) are shared
hardening and remain active on Classic as well.

### 20.2 Minimap

`MinimapTracker.lua` is physically shared as of Prep132. `Core/Compat.lua` on each client resolves
the native minimap children into `ns.API.GetMinimapParts()`, so the tracker has one object vocabulary
without hard-coding either the Era globals or Forever's `MinimapCluster` hierarchy.

`Plus/InterfaceTweaks.lua` intentionally remains client-owned: Classic still owns legacy quest-level
presentation and legacy minimap geometry, while Forever preserves Blizzard's numeric quest levels,
adds difficulty tags only, and works against modern Frame/NineSlice minimap objects. Resolve modern
border/GameTime objects by capability/object type; do not call Texture methods on NineSlice Frames
or assume the old `GameTimeTexture` global exists.

### 20.3 Shared Chat, Social, and Flight utilities

Prep137 moves `Plus/ChatTweaks.lua`, `Plus/Social.lua`, and `Plus/FlightBar.lua` into the physical
common layer. These are compatibility differences rather than ownership differences:

- Chat iteration goes through `ns.API.ForEachChatFrame()` and guarded event registration. Classic's
  adapter enumerates the legacy `ChatFrame1..50` globals; Forever may use `ChatFrameUtil`.
- Social/Battle.net/party actions go through `ns.API.GetBattleNetFriendInviteInfo()`,
  `InviteBattleNetFriend()`, `CanInviteParty()`, and `InviteUnit()`. Classic retains the legacy
  `BN*`/party globals as its fallback path.
- Flight Bar keeps the same seeded/learned route model on both clients. The shared implementation
  guards `hooksecurefunc`, records which taxi events actually registered, and supports either the
  legacy `TaxiNodeOnButtonEnter` tooltip hook or native taxi-button `OnEnter` hooks when available.

These modules must remain client-neutral. New client API drift belongs in `Core/Compat.lua`; do not
reintroduce direct Forever checks into the shared QoL hot paths.

### 20.4 Shared Automation and System policy

Prep138 moves `Plus/Automation.lua` and `Plus/SystemTweaks.lua` into the physical common layer.
Automation owns policy and lifecycle; client actions live behind `ns.API`:

- spirit-healer confirmation uses `API.ConfirmSpiritHealer()` (`AcceptXPLoss` on Classic, the
  current player-interaction API with legacy fallback on Forever);
- battleground release uses `API.ReleaseSpirit()` (`RepopMe` on Classic/when available);
- repair summaries use `API.GetCoinText()`;
- quest turn-in readiness uses `API.QuestReadyForTurnIn()`;
- event drift remains guarded through `API.RegisterEvent()`.

The shared quest controller keeps serialized selection confirmation/retry behavior. This hardening is
valid on Era as well: unsupported companion events fail closed, while ordinary Classic quest events
continue through their legacy APIs.

System Tweaks also uses one shared implementation. Fast loot guards the loot APIs, resolves either
modern or legacy loot-method identity, preserves master-loot thresholds, skips locked slots, and
exposes diagnostics. Vendor-price tooltip injection is **not** assumed portable: the `plusUI`
provider exposes `SupportsVendorPriceTooltip()`. Classic returns true; Forever returns false, so
stale/imported `showVendorPrice` state cannot reclaim a Blizzard-owned Forever tooltip surface.

`Plus/InterfaceTweaks.lua` remains client-owned. Its legacy Classic quest/minimap presentation and
Forever's modern pooled/NineSlice/native-level presentation differ semantically rather than merely
by API spelling.

---

## 21. Options GUI contract

The Options UI is not the capability source of truth. It presents settings whose effective runtime is governed by module/feature gates and `Core/Client.lua` capability policy.

Forever-specific rules:

- hide controls for behavior Blizzard already owns and TurboFace intentionally does not replace;
- disable or annotate controls whose preference is preserved but implementation is unavailable;
- do not leave a visible working-looking checkbox that can only route into a blocked Classic renderer;
- module toggles that have a fully reversible detached Forever lifecycle may refresh live;
- protected/hook-heavy changes may still require `/reload`.

Prep124 begins that migration. Existing Forever-specific availability for the native name shadow,
World Map canvas enhancements, and legacy Combat Meter window now reads the client registry instead
of directly re-deriving the client boundary in `OptionsGUI.lua`. Client-specific *refresh ownership*
may still branch where the actual adapter differs; additional control availability should move to the
registry incrementally rather than via a mass GUI rewrite.

---

## 22. Diagnostics and live validation

Static parsing cannot prove a Forever port safe. Every protected/secret/UI ownership change requires live validation.

Important current probes include:

```text
/tf compat status
/tf compat caps
/tf compat export
/tf debug modules
/tf powerprobe
/tfswing
/tf debug trainer
/tf professionprobe
/tf professiondataprobe
/tf nameplateapiprobe
```

Diagnostics must obey the same secret rules as production code. A probe is not allowed to stringify a secret value merely because it is development-only.

### 22.1 Probe lifecycle

One-shot reverse-engineering probes should not become permanent periodic runtime. After a capability is understood and encoded in a stable adapter, retire or bound the probe so it cannot turn the addon into a continuous client-inspection framework.

---

## 23. Performance rules

Forever does not relax the Classic performance contract.

- Disabled features remain dormant.
- Avoid per-frame scans when an event or bounded deferred reconciliation works.
- Use `ns.Cadence` for periodic work and leave it when idle.
- Do not scan full Blizzard UI trees on a steady cadence. Tree scans are acceptable only as bounded probes or one-shot capture/recovery where no stable API exists.
- Pooled native objects require identity validation before cached addon state is reused.
- Secret-value failures should suspend the affected augmentation rather than repeatedly fault on every pulse.
- Compatibility wrappers belong outside hot loops when the result/capability can be cached safely.

Forever-specific detached overlays add frame count; therefore create them on demand, pool/reuse where safe, and release/hide them when native units disappear.

---

## 24. Validation and release contract

### 24.1 Static checks

Every build should verify at least:

- Lua syntax / Lua 5.1-compatible compilation where the target still uses the Classic Lua limits;
- every TOC path exists;
- XML/media references exist;
- no protected Blizzard action button/nameplate/unit-frame fields are used as TurboFace state storage;
- Forever adapter files load after their shared owners;
- the packaged restore snapshot is inert;
- version strings agree across package/docs/contracts;
- client-specific blocked features cannot accidentally initialize their Classic renderer;
- `ns.PLUS_SECTION` remains synchronized with current Plus defaults;
- periodic-driver inventory is reviewed after new cadence/timer work.

The repository's Forever validation suite remains the authoritative automated contract when available.

### 24.2 Restore snapshot safety

Release packaging must distinguish:

1. the inert packaged `Core/ForeverRestoreData.lua`; and
2. the intentionally active developer live-install snapshot.

A build/install script must never overwrite the active developer snapshot unless that is the explicit operation being performed. After any live install, verify the expected active snapshot hash.

### 24.3 Live client matrix

At minimum, validate:

- login and `/reload` with BugSack;
- combat entry/exit;
- target/ToT changes;
- pet summon/dismiss and party roster changes;
- protected-frame interactions both in and out of combat;
- action-bar macros, stance swaps, and bonus bars for Hotbar Power;
- player swing MH/OH/ranged separation;
- nameplate pooling/recycling and secret combat health;
- nameplate aura expiration/pooling;
- Trainer queue identity across multiple ranks;
- profession Training with modern `C_TradeSkillUI` learned/skill state;
- Minimap/Map features that touch modern Blizzard UI;
- profile/restore behavior under the current beta SavedVariables limitation.

Do not call a feature port complete based only on syntax or a clean login.

---

## 25. Recommended multi-client repository architecture

The recommended long-term direction is **one repository, two distributable client flavors**.

Do **not** maintain two independent source trees unless Blizzard divergence eventually becomes so large that most shared modules cease to be shared. The current branch has substantial client-specific work, but the majority of addon logic is still common.

Do **not** ship one all-client TOC that blindly loads every Classic and Forever implementation forever. That leaves unavailable features, client checks, and protected ownership assumptions intertwined in too many runtime files.

### 25.1 Target model

```text
TurboFace repository
│
├── shared source/data/policy
│
├── Classic client adapters/presentation
│
└── Forever client adapters/presentation
        │
        ├── build -> TurboFace-Classic.zip
        └── build -> TurboFace-Forever.zip
```

Users still experience “TurboFace”; developers get explicit client ownership boundaries.

### 25.2 Incremental directory direction

Do not perform a giant folder rewrite. Introduce a client layer first:

```text
Core/
  Client.lua              resolved client identity + feature registry
  Compat.lua              API-shape normalization only

Client/
  Classic/
    Manifest.lua
    Nameplates.lua
    UnitFrames.lua
    ...
  Forever/
    Manifest.lua
    Nameplates.lua
    UnitFrames.lua
    HotbarPower.lua        only if the shared file becomes too branch-heavy
    Professions.lua

Features/ or existing folders/
  shared policy/data/runtime where ownership is genuinely common
```

The existing folder layout can remain while the `Client/` layer is introduced; files move only when a subsystem proves sufficiently divergent.

### 25.3 One feature registry

Prep124 introduces `Core/Client.lua` as the first executable version of this registry. Prep125
formalizes its validation vocabulary. Prep126 promotes the same file into the Classic source/build
as well, so both flavors consume one capability vocabulary. Prep127 adds the complementary
`Core/Providers.lua` implementation selector for runtime backends. `Client.lua` answers *whether and
who may own a feature*; `Providers.lua` answers *which registered implementation is active*.
They load before `Core/Config.lua` evaluates effective module gates. Conceptually and in the current
implementation the client registry records entries such as:

```lua
features = {
    hotbarPower = { state = "adapted", owner = "forever" },
    dotPrediction = { state = "blocked", reason = "secret-health" },
    questLevels = { state = "blizzard-owned" },
}
```

That registry is the intended source for:

- Options visibility/availability;
- debug status;
- documentation generation/checks;
- build manifest inclusion where practical.

It does **not** become a second user preference system. User enable/disable state remains in `TurboFaceDB`; the registry answers only whether/how the current client can implement that preference. Prep124 already routes group availability into `ns.ModuleEnabled()` and replaces the stale compatibility port matrix with registry-derived diagnostics.

### 25.4 Build ownership verification

The original convergence campaign used snapshot manifests to plan source moves. Phase 33 removed
those lists after they became stale duplicate state. `build/verify.py` now derives both client
inventories directly from `src/common + src/<flavor>`, freezes the five intentional same-path package
divergences, and rejects client-owned copies of files assigned to the common layer. The canonical
human-readable inventory is `docs/SOURCE_MAP.md`.

The unified development tree now physically stores byte-identical package paths once under
`src/common/` and keeps only divergent/exclusive files under `src/classic/` or `src/forever/`.
`build/build_client.py` reconstructs each package by overlaying the client layer on the common layer;
it does **not** generate or reorder TOC entries. Each client's existing `TurboFace.toc` remains the
semantic load-order contract inside its client layer.

Similarity is never a promotion rule. A file moves to `src/common/` only when the implementations are
actually reconciled and byte-identical with a valid ownership contract on both clients.

Classic-only renderers need not ship in the Forever package once an adapter fully replaces them, and vice versa.

This reduces accidental activation and makes “feature unavailable on Forever” a build/registry fact instead of another runtime `if IS_TARGET_FOREVER_BUILD` branch. Prep129 applies that rule directly to the shared Nameplate event/render pipeline; Prep130 applies the same rule to UnitFrame-adjacent prediction/absorb/Druid renderers; Prep131 applies it to the primary UnitFrame source body itself; Prep132 applies it to shared World Map policy and minimap tracking; Prep133 applies it to shared Trainer presentation policy; Prep134 applies it to the trainer service/capture compatibility surface; Prep135 applies it to Trainer event/list/queue ownership; Prep136 applies it to Trainer SkillData source/rank capabilities; Prep137 applies the same boundary discipline to Chat/Social/Flight API drift through Compat rather than client branches; Prep138 applies it to Automation/System policy and vendor-tooltip ownership; Prep139 applies it to class-combat presentation ownership and secret-safe diagnostics; Prep140 applies it to the player-swing/hostile-speed/Character-damage substrate while keeping the shared SwingTimer state/render engine client-neutral; Prep141 applies the same compatibility-first rule to bag/bank storage and net-worth presentation; Prep142 completes Inventory by normalizing merchant access through Compat and replacing the missing Forever item-button virtual template with a shared owned cell. Prep143 extends the same compatibility-first rule to Party/Pet aura ownership, secret-aura readability, reversible native suppression, and guarded event registration.

### 25.5 Shared profiles and settings

The portable configuration schema is **79** on both clients. Client-only evolution does not advance
that number. `Core/Schema.lua` stores client revisions under `TurboFaceDB.__clientRevisions`; shared
`Core/Profiles.lua` strips that internal table from snapshots and exports so `TF1:` remains portable.

Forever revision 1 owns the standalone talent reminder migration that formerly advanced dbVersion
79 -> 80. Forever revision 2 owns the combined-bag mover option that formerly advanced 80 -> 81.
Prep127-and-earlier saves/exports carrying dbVersion 80/81 remain accepted as transitional legacy
Forever encodings and are adopted into schema 79.

Keep the main configuration shape as a superset where practical so profile exports remain portable.
A preference unsupported on one client should normally be preserved but inactive, not deleted. Only
create client-specific defaults/migrations when the setting has genuinely client-specific meaning or
ownership rather than merely a different renderer.

### 25.6 Documentation layout

Canonical repository docs:

```text
README.md                         public overview and development entry point
docs/MULTICLIENT_STRATEGY.md      shared ownership and change rules
docs/SOURCE_MAP.md                current physical source inventory
docs/classic/ARCHITECTURE.md      Classic runtime contract
docs/forever/ARCHITECTURE.md      Forever runtime contract
docs/classic/CHANGELOG.md         Classic release history
docs/forever/CHANGELOG.md         Forever release history
```

If each distributable package should remain self-documenting, the build can copy/compose the relevant shared + client architecture into the package-local `ARCHITECTURE.md`.

---

## 26. Known architectural limitations

### 26.1 Secret data permanently reduces some features

Some Classic features may never be reproducible with equivalent fidelity if Blizzard intentionally withholds the required numeric/aura state. The correct response is a reduced/native implementation, not escalating attempts to bypass the boundary.

### 26.2 Protected Blizzard UI is not a stable addon parent

Forever increasingly uses protected/pool-managed modern FrameXML. A child frame that appears harmless out of combat can taint a later Blizzard secret-value path. Detached ownership is the default when the safety of native parenting is uncertain.

### 26.3 Beta SavedVariables workaround is temporary debt

`ForeverRestoreData.lua` / Dev Preset exist because of observed beta behavior. They should be removed or retired as soon as the client reliably persists SavedVariables; they are not part of the desired long-term product model.

### 26.4 Capability ownership

`Core/Client.lua` is the machine-readable availability and implementation source. Runtime capability
describes behavior, while `docs/SOURCE_MAP.md` describes physical source ownership; neither should be
reconstructed from the other. Present-tense validation requirements belong with the relevant
subsystem contract in this document.

### 26.5 One-way hooks remain one-way

Secure post-hooks cannot be removed. Install them lazily where possible, keep callbacks predicate-gated, and treat `/reload` as the clean lifecycle boundary when perfect teardown is impossible.

---

## 27. Change discipline

Before merging a Forever or shared feature change, answer:

1. **Which client(s) own this implementation?** Shared, Classic adapter, Forever adapter, or native Blizzard replacement?
2. **Who owns the setting?** Is the setting meaning portable across clients?
3. **What is the effective gate?** User preference plus what capability/adapter boundary?
4. **Does the code touch a Blizzard protected/pool-managed object?** If yes, can ownership be detached?
5. **Can any API value be secret?** What is the first secrecy check and what is the fail-closed behavior?
6. **Does the code parent addon regions to Blizzard objects or write addon fields onto them?** If yes, justify with live proof or redesign.
7. **What events/CLEU/cadence/timers does it own?** What tears them down?
8. **Does it mutate persistent CVars/external state?** How is exact prior state restored?
9. **Does native Blizzard UI already provide the feature?** If so, why is TurboFace duplicating it rather than integrating/yielding?
10. **Does the change introduce another client check into shared feature code?** Could it instead be an adapter/capability method?
11. **What live scenario can static tests not reproduce?** Combat secrecy, protected state, pooling, stance/macro resolution, Edit Mode, etc.
12. **What documentation becomes false?** Update architecture for present-tense contracts and changelog for dated rationale in the same change.

If these answers are not clean, the feature is not ready to merge into the multi-client architecture.

### Prep144 / Phase 21 — shared media asset policy

`Core/SharedMedia.lua` is now physically common. The only prior client divergence was the banker
artwork used by both Bank item-state marks and the nameplate Banker job icon. That choice is now
owned by the shared `Core/Client.lua` policy registry through `Client:GetAsset("bankIconTexture")`:
Classic keeps TurboFace's bundled square bank artwork, while Forever keeps Blizzard's native Banker
tracking artwork. Shared media registration no longer needs to know which client is running, and
both downstream consumers continue to share one `ns.BANK_ICON_TEXTURE` contract.


### Prep145 / Phase 22 — shared OptionsGUI policy

`Options/OptionsGUI.lua` is now physically common. The former 99%-similar client copies differed
primarily in feature visibility and refresh lifecycle, not widget mechanics. Those decisions now
flow through `Core/Client.lua`: `Client:IsFeatureAvailable()` owns user-facing capability presence,
while `Client:GetOptionPolicy()` owns non-setting GUI lifecycle/presentation choices such as the
detached Forever nameplate refresh path and health-label wording. The shared GUI contains no direct
Forever/build identity branch. Classic therefore keeps its quest-level and vendor-price controls
and ClassBuffs talent reminder, while Forever exposes its standalone talent HUD and combined-bag
mover and continues to hide Blizzard-owned replacements.


### Prep147 / Phase 24 — shared ExperienceBar quest-reward capability

`ExperienceBar.lua` is now physically common. Quest reward XP lookup is selected by API capability,
not client identity. Legacy clients retain selection-based reward lookup with Quest Log visibility
deferral and selection restoration. Clients exposing `HaveQuestRewardData` use asynchronous reward
readiness/loading, hold the previous complete snapshot while any reward is pending, and reconcile on
quest-data completion/removal events. The shared module contains no direct Forever/build branch.


### Prep148 / Phase 25 — shared AuraStyle protected-aura boundary

`AuraStyle.lua` is now physically common. The shared styler never decides client identity: it asks
`ns.API.ShouldAurasBeSecret()` whether addon-side aura rendering is safe and consumes
`GetReadableAuraDataByIndex` / `GetReadableAuraDataByAuraInstanceID` for table-form aura records.
Classic Compat normalizes readable Era aura data into that contract. Forever Compat preserves the
secret-value boundary. When data is protected, TurboFace clears/suspends its timer overlays and
re-enables Blizzard's native duration font string instead of inspecting opaque identifiers or textures.
This keeps visual ownership reversible and fail-closed without a Forever branch in the shared feature.


### Prep149 / Phase 26 — shared Core runtime lifecycle

`Core.lua` is now physically common. Runtime differences that are ownership/lifecycle policy rather
than API shape are declared in `Core/Client.lua` through `Client.corePolicy`. Classic keeps the Era
native-driver hook path, immediate nameplate callbacks, native `UpdateAnchors` restoration, and its
historical DPS badge/Combat Meter startup order. Forever selects the detached nameplate adapter,
next-frame staging around protected native callbacks, write-only friendly-identity restoration,
presentation-only native castbar styling, and extended port diagnostics. Secret-safe unit reads remain
behind `Core/Compat.lua`. The shared Core does not inspect Forever/build identity directly.

### Prep150 / Phase 27 — shared Quick Setup persistence and action placement

`QuickSetup.lua` is now physically common. Client-specific persistence and action semantics are policy,
not forks: Classic keeps reload-bound SavedVariables/manual apply and legacy macro indexing; Forever keeps
immediate staged apply, external save-helper persistence, normalized macro limits/scope resolution,
reload-free CVar baselines, one-based Edit Mode translation, and fail-safe unsupported-action preservation.
The shared engine does not branch on Forever identity.


### Prep151 / Phase 28 — shared RegenTicks secret-resource boundary

`Power/RegenTicks.lua` is physically shared. Resource arithmetic is performed only after an accessibility check.
When a client exposes readable values, the historical amount-based cadence logic remains authoritative. When
values are opaque, the engine falls back only to observable event timing for Rage decay and health regeneration,
without attempting to infer the hidden amount. PlayerFrame bar lookup is capability-based and falls back to Era globals.


### Prep152 / Phase 29 — shared PowerCost protected-action/resource boundary

`Power/PowerCost.lua` is physically shared. TurboFace action overlays are owned by `UIParent` and tracked in a weak side table; protected Blizzard action buttons are used only as anchors and receive no addon fields or child frames. Action metadata flows through `ns.API`, with native action-slot spell resolution preferred when available and legacy macro parsing retained as fallback. Readable player power uses the historical arithmetic renderer. If the client exposes opaque power, the shared renderer passes the secret scalar only to approved native StatusBar/curve/color/text sinks and never stringifies or performs Lua arithmetic on it. No direct Forever/build identity branch is present.


### Prep153 / Phase 30 — shared diagnostic surface

`Core/Debug.lua` is physically shared. Diagnostics are observational rather than ownership-bearing: the richer Forever probes use guarded object/API discovery and can exist on Classic without enabling Forever renderers or changing feature lifecycle. Client-specific implementations remain behind Compat/providers/adapters; Debug only reports what is actually present.

### Phase 31 trainer host ownership

`Trainer/UI_Profession.lua` and `Trainer/UI_Spellbook.lua` are shared controllers. Client-specific Blizzard host ownership is selected through the `trainerUI` provider: Classic retains the embedded Era host; Forever's higher-priority native adapter selects detached Retail-derived profession/spellbook presentation. This keeps data/row/controller behavior common without pretending the Blizzard host surfaces are equivalent.

### Phase 32 convergence end state

The unified tree now treats `Core/Compat.lua`, `Plus/InterfaceTweaks.lua`, and `TurboFace.toc` as the only intentional first-party same-path Classic/Forever divergences. Compat owns Blizzard API/secret-value shape, InterfaceTweaks owns genuinely different native interface lifecycles, and the TOC owns client metadata/load order. `build/verify.py` freezes this overlap so converged modules cannot silently fork again.


### Phase 33 repository baseline

Canonical repository documentation lives under `docs/`; runtime source overlays no longer carry duplicate architecture/changelog/build-manifest snapshots. `tests/` and `build/verify.py` jointly enforce the Phase 32 convergence boundary, direct client-identity allowlist, documentation freshness, safe build destinations, and package inventory. Generated `dist/` output is disposable and ignored by Git.
