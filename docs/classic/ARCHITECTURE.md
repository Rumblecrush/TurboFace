# TurboFace Architecture

**Last updated:** 2026-09-23
**Current addon version:** 0.18.1
**Target client:** World of Warcraft Classic Era 1.15.9+
**TOC interface:** 11509
**Saved-variable schema:** 79
**Current status:** Blizzard's 1.15.9 nameplate substrate is the only baseline renderer.
TurboFace provides additive information layers and the explicitly documented native
presentation amendments; it owns no fallback nameplate renderer.

This file is a present-tense reference for the live runtime, source ownership, invariants,
and validation contract. Release history, migrations, regressions, and dated design
rationale live in [`CHANGELOG.md`](CHANGELOG.md).

### Runtime invariants

- **Dormant means dormant.** Disabled optional subsystems do not own avoidable events, cadence
  clients, timers, OnUpdate work, CVars, or Blizzard mutations. Irreversible hooks are installed
  only when needed and remain predicate-gated.
- **Blizzard is the substrate owner.** TurboFace augments native frames; it does not recreate
  normal Blizzard nameplates, castbars, raid markers, classification art, or stacking geometry.
- **Restricted regions are write-only where required.** Do not measure protected/restricted
  Blizzard nameplate geometry with `GetPoint`, `GetLeft`, `GetWidth`, etc. when the live client can
  reject those reads. Use known native layout policy or TurboFace-owned measurement surfaces.
- **Persist only live configuration.** Fixed implementation constants are not settings. Historical
  migrations may understand retired keys, but current normalization explicitly prunes them.
- **Cache only with an invalidation boundary.** Pooled plate state must be cleared/rebuilt across
  unit recycling, presentation-mode changes, and option refreshes.

TurboFace is a Classic Era all-in-one interface addon. It restyles selected Blizzard UI, adds
TurboFace-owned widgets, and augments Blizzard's native 1.15.9 nameplate chassis with narrowly
scoped combat-information layers.

> **The code on disk is the source of truth.** If this document conflicts with the
> implementation, verify the live 1.15.9 client and update both code and documentation.

## 1. Core development rules

### 1.1 Classic Era only

TurboFace targets Classic Era 1.15.x. Do not add Retail/TBC/Wrath/Cata abstraction for
its own sake. Feature-detect APIs that vary inside the supported Classic client, but
keep the implementation focused on the current 1.15.9 environment.

The 1.15.9 addon API closely resembles the Burning Crusade Classic 2.5.6-era API.
When Blizzard changes FrameXML structures or APIs, use the live 1.15.9 client as the
final authority and treat 2.5.6 FrameXML as the most useful donor/reference surface.

### 1.2 Compatibility belongs in `Core/Compat.lua`

Changed or unstable Blizzard APIs should be normalized once in `Core/Compat.lua` and then
consumed through `ns.API` or a similarly narrow compatibility helper.

Do not scatter version checks across feature files when one compatibility wrapper can
own the difference.

Shared multi-client runtime selection belongs in `Core/Providers.lua`, not in Classic feature
hot paths. Classic remains the readable/native baseline provider for adapted families such as
Combat Meter, Nameplates, and UnitFrames; client-specific implementations may override that provider in other
build flavors without changing Classic's ownership contract.

The only addon-level optional integrations declared by TurboFace are **Baganator** and
**UnstuckSkips**. Keep `## OptionalDeps` synchronized with real runtime integration; do not
retain dependency metadata or compatibility branches for addons TurboFace does not consume.

### 1.3 Protected-frame safety beats convenience

TurboFace modifies Blizzard-owned protected frames, including unit frames and some HUD
components. Changes to module masters and other hook-heavy options are therefore
allowed to use `/reload` as the clean activation boundary.

Rules:

- Do not call protected `Show()`, `Hide()`, `SetPoint()`, or equivalent operations in
  combat unless the client explicitly allows it.
- **Never invoke a Blizzard FrameXML function from TurboFace code.** Hook it with
  `hooksecurefunc`, or use `securecall` when invocation is genuinely unavoidable. A
  direct call taints everything that function writes, and Blizzard reads those values
  back from secure paths for the rest of the session. See §12.2 for a concrete failure
  chain.
- Verify protection empirically rather than assuming it. Protection is **not** inherited
  by every child of a protected frame: `TargetFrameToT` is protected, but
  `TargetFrameToTDebuff1:IsProtected()` returns `false, false`. `/dump` the frame before
  designing around a restriction that may not exist.
- Defer protected geometry changes until `PLAYER_REGEN_ENABLED` when necessary.
- Prefer alpha-only presentation where protected visibility is unsafe. Target-of-Target
  is an important example.
- Never “fight” Blizzard with a permanent `OnUpdate` if a hook/event/one-time apply can
  solve the problem.
- One-way secure hooks are acceptable only when their callbacks are predicate-gated
  after the owning feature is disabled.

### 1.4 Disabled means dormant

This is the central modularity rule.

A feature that is disabled at the effective activation boundary should, wherever
practical:

- not register feature-specific events;
- not register a CLEU consumer;
- not start a ticker;
- not install avoidable hooks;
- not run an `OnUpdate` driver;
- not construct TurboFace-owned visual frames;
- not modify Blizzard-owned frames;
- not modify persistent client CVars;
- not perform periodic scans merely to discover that it is disabled.

A Lua file being listed in the TOC is **not** considered active runtime. Small inert
module tables or event frames with no registered events are acceptable. The target is
zero meaningful feature work while disabled.

### 1.5 No speculative cleanup during unrelated feature work

TurboFace is performance-sensitive and touches protected UI. Refactors should be
narrow and behavior-preserving unless the task explicitly calls for architecture work.
A cleanup that changes ownership, event timing, frame hierarchy, or secure behavior
needs the same live-client testing as a new feature.

---

## 2. Startup and load order

`TurboFace.toc` defines source order. Load order matters because most modules attach
public methods to the shared addon namespace `ns`.

High-level order:

1. Embedded libraries.
2. `Core/Compat.lua` and `Core/Config.lua`.
3. `Core/Defaults.lua`, `Core/Migrations.lua`, and neutral shared metadata such as `Core/ProfessionData.lua`.
4. Debug/profile/media support.
5. `Core.lua` and prediction engines.
6. Nameplate subsystem files.
7. Unit-frame and combat subsystem files.
8. Speedrun/utility singleton widgets and Inventory/Movers/Plus modules.
9. `Power/PowerCost.lua` followed by `Power/RegenTicks.lua`.
10. Trainer core/data/UI, then `Skills.lua`.
11. `Options/OptionsGUI.lua`.

Folder names express **ownership**, not load-on-demand behavior. A file in a folder is
still parsed when listed in the TOC; runtime dormancy is controlled by the activation
contracts in §1.4. Trainer's large catalogs remain deferred by their existing data
loader even though the subsystem itself lives under `Trainer/`.

The decisive runtime boundary is `PLAYER_LOGIN` in `Core.lua`:

```lua
ns:LoadVariables()
ns.QuickSetup:Init() -- early one-shot CVar baseline, when enabled/pending
-- then ordinary module :Init() calls through ns.SafeCall(...)
```

Quick Setup is the deliberate ordering exception: when it has an eligible automatic or pending
manual restore, its saved persistent CVar baseline is applied immediately after DB load and before
Plus/System can acquire temporary CVar ownership. The remaining macro/binding/action/Edit Mode
restore is staged across later frames. When Quick Setup is disabled and no manual apply is pending,
its event frame remains unregistered.

`LoadVariables()` must run before feature activation because it:

- creates/repairs saved-variable roots;
- runs ordered migrations;
- normalizes known setting types;
- merges defaults;
- validates the Plus section map;
- refreshes cached settings used by runtime code.

Modules that once self-registered at file load were moved behind this login boundary.
New feature modules should follow the same pattern.

`ns.SafeCall(tag, fn)` isolates initialization errors so one broken subsystem does not
prevent every later module from loading. It reports each initialization failure once.

---

## 3. Saved variables and schema ownership

The TOC declares:

```text
TurboFaceDB
TurboFaceCacheDB
TurboFaceProfilesDB
TurboFaceTrainerDB
TurboFaceSpeedrunDB
TurboFaceCharDB             (per character)
TurboFaceTrainerCharDB      (per character)
TurboFaceCVarExportCharDB   (per character)
TurboFaceSpeedrunCharDB     (per character)
```

The Trainer databases are owned by the `Trainer/*` subsystem and are intentionally
separate from the main profile/config schema. Speedrun PB/run history likewise lives in
`TurboFaceSpeedrunDB` / `TurboFaceSpeedrunCharDB`, and CVar-browser export state is
per-character in `TurboFaceCVarExportCharDB`. `TurboFaceDB.dbVersion` / `ns.DB_VERSION`
version only the main TurboFace configuration root.

### 3.1 `TurboFaceDB`

Primary user configuration. Profiles/import/export operate on this data.

Configuration ownership is deliberately split:

- `Core/Defaults.lua` owns the canonical `ns.defaults` schema, including each
  feature-local typography setting and every registered mover element default;
- `Core/Migrations.lua` owns `ns.DB_VERSION`, ordered migrations, retired-key pruning,
  type repair/default merge, and `ns:LoadVariables()`;
- `Core/Config.lua` owns runtime module gates, shared config helpers, CVar ownership,
  `ns.CLEU`, and `ns.Timers`.

Current schema: **79**.

When the shape or meaning of persisted configuration changes:

1. increment `DB_VERSION`;
2. append an ordered migration;
3. keep migration logic deterministic and safe on partially malformed data;
4. merge defaults after migration;
5. verify existing profiles/import strings.

Do not silently repurpose an old setting with incompatible semantics.

### 3.2 `TurboFaceCacheDB`

Machine/client-state and cache data that should not travel with profiles.

Important contents include:

- client build marker;
- NPC/title caches;
- persistent CVar ownership snapshots;
- legacy Questie ownership debt retained only until an upgrade can restore it;
- Hearthstone batching observations that deliberately survive build-cache wipes;
- learned DoT cadence by spell ID/name (timing only, never persisted damage samples).

Normal cache data is cleared on a client-build change. Ownership snapshots are
preserved because TurboFace may still owe the user an exact restoration after a patch.

### 3.3 `TurboFaceProfilesDB`

Named profile storage. Profiles snapshot the complete account-wide user configuration rather than
only a hand-maintained subset; per-character XP history is explicitly excluded. Module choices
therefore travel with profiles. Built-in
presets are differential overlays on current factory defaults: Factory Defaults carries
the live schema marker directly, while dated user presets declare the exact schema their
serialized data represents so profile application never replays irrelevant historical
migrations. The current built-in release set is intentionally minimal: **Factory Defaults** and
**Rumblecrush's Preset - 2026-09-13**.

Aura presentation is a shared-default invariant rather than a Rumblecrush-only override.
`Core/Defaults.lua` owns the audited Rumblecrush Aura Styling baseline, and built-in differential
presets must inherit it instead of serializing duplicate Aura values. This keeps Factory Defaults,
Rumblecrush, and future presets aligned as the baseline evolves. Applying a preset or resetting uses
that baseline; normal default merging does not overwrite an existing user's explicit saved choices.

The broader factory baseline was most recently re-audited from the supplied schema-78 user export on
2026-09-11 (addon 0.17.68). All live configuration values represented by `ns.defaults` were adopted.
That refresh specifically locks the standalone Swing/Cast widths to 160px, uses Blizzard Raid Bar for
attack/cast textures, sets the Loot Frame to width 220 / duration 7s / spacing 0, and makes Loot Frame
the selected mover at CENTER (0, 290). Per-character XP measurements and database-version bookkeeping
remain excluded; the empty legacy `map` container has no live setting ownership and is likewise not part
of the defaults schema. Redundant named RGB aliases in an exported color table are also ignored when the
same values are already represented by its canonical positional color entries.

Quick Setup class profiles intentionally live alongside named settings profiles but outside their
snapshots at `TurboFaceProfilesDB.quickSetup.classes[CLASS]`. A class object owns only its portable
setup data (macros, character bindings, action slots 1-180, Blizzard Action Bars 2-8, Edit Mode
selection, and allowlisted CVar values). Ordinary `TF1:` settings save/export/reset operations do
not copy or erase these class profiles.

### 3.4 `TurboFaceCharDB`

Per-character state. Keep truly character-specific information here rather than
polluting account-wide profile configuration. XP Bar run/session history lives at
`TurboFaceCharDB.experienceBarSession`; it is never part of ordinary named profiles,
Factory Defaults, presets, or `TF1:` settings exports. Quick Setup stores only its current
character GUID/bootstrap record and any one-reload manual-apply handoff at
`TurboFaceCharDB.quickSetup`; those records never travel with a class profile.

### 3.5 Import/export safety

Imported data is data, never executable Lua. Profile/import code must continue to:

- validate decoded table shape;
- normalize known types;
- merge current defaults;
- apply current schema expectations;
- avoid trusting arbitrary metatables/functions.

Profile application can replace `TurboFaceDB` wholesale. Any cached settings object
must therefore resolve the **current** DB dynamically rather than retain a stale table
pointer.

XP session transfer is a separate `TFXP1:` format with an exact numeric field allowlist.
The **Profile -> Import / Export** section's **Export XP Splits** and **Import XP Splits** controls
cannot accept `TF1:` settings profiles, and
the settings importer cannot accept XP session strings. Importing XP history replaces only
the current character's session and applies live without reloading or changing settings.

Lvl1 Quick Setup transfer is a third independent data-only format, `TFL1QS1:`. Export requires a
stored class and explicitly identifies its Classic class token; import has no class selector,
validates the payload/schema/allowlists, detects the class from the payload, and replaces only that
stored class object. Import does not touch the active character and therefore does not reload.
`TF1:`, `TFXP1:`, and `TFL1QS1:` are mutually distinct import surfaces.

---

## 4. Module gating model

Module gates live at:

```lua
TurboFaceDB.modules
```

All runtime reads go through:

```lua
ns.ModuleEnabled(family, element)
```

Do not index `TurboFaceDB.modules` directly outside the Config/Options ownership layer.

### 4.1 Fail-open contract

A missing/malformed/not-yet-migrated gate reads as enabled. Only an explicit `false`
disables a module.

This is intentional: corrupted or old data must never silently gut the addon.

### 4.2 Current module families

| Family | Children / meaning |
|---|---|
| `unitframes` | master plus `player`, `target`, `tot`, `party`, `pet` |
| `nameplates` | Blizzard-native nameplate augmentation/presentation |
| `auras` | aura family master; children `tot`, `party`, `pet`; normal Player/Target styling uses `auraEnabled` inside the family |
| `hotbarPower` | action-button missing-power overlay/counter |
| `playerTicks` | Mana/Energy/Rage/Health tick markers on player bars |
| `swingTimers` | Global player/target swing timer rows and their broad timing runtime; enemy nameplate swing is independently feature-gated under Nameplates |
| `castBars` | TurboFace player/target unit castbars |
| `class` | class features, self reminders, Druid auxiliary Mana bar |
| `plus` | section container; no user-facing master |

Some systems intentionally use **feature gates rather than module-family gates** because
they are optional consumers layered on already-owned Blizzard/TurboFace surfaces:

```text
dotPredictionEnabled                 -- shared DoT engine
healPredictionEnabled                -- shared heal engine
combatMeterEnabled                   -- movable meter window preference
leashTimerEnabled                    -- mover-dependent enemy leash countdown
speedrunSplits.enabled               -- partial/full-level /played split tracker
unitframes.showPlayerDPS             -- historical storage path; independent DPS/HPS badge gate
auraEnabled                          -- normal Player/Target AuraStyle consumer
bubbleNameplates.swingTimer           -- independent enemy nameplate swing presentation
bubbleNameplates.jobIcon              -- independent friendly-NPC service/profession glyph
```

The DPS badge key remains under `unitframes.*` only for profile compatibility; it is not a
Unit Frames dependency. Likewise `auraEnabled` does not control the independently gated
ToT/Party/Pet Aura children. `bubbleNameplates.swingTimer` belongs to the Nameplates surface but
is not a Threat Number child and does not depend on the Global Swing Timers presentation gate.
`bubbleNameplates.jobIcon` is likewise a Nameplates-local feature gate and is not a child of
`friendlyNPCNameTitleOnly` or any hostile threat/timing feature. `friendlyNPCNameTitleOnly` is a
presentation-mode selector rather than a TurboFace identity renderer: it preserves Blizzard identity
while suppressing the native non-identity chassis.
These feature gates still obey “disabled means dormant”; do not manufacture module families merely
for symmetry unless ownership genuinely changes.

Plus sections are children of `modules.plus`:

```text
automation
social
interface
minimap
map
chat
system
flightBar
```

### 4.3 Parent gates

GUI placement does **not** imply runtime parentage. `Core/Config.lua` currently has no
`MODULE_PARENT` entries: Player Tick Markers, Swing Timers, and Cast Bars are all
standalone-capable feature families. Turning TurboFace Unit Frames off must therefore
leave those stored gates effective and must not park their runtime merely because their
presentation can optionally integrate with a unit-frame surface.

A future feature may reintroduce a true parent mapping only when the child literally has
no valid runtime/presentation without that parent. Keep that dependency in
`MODULE_PARENT`; do not infer it from which Options tab contains the checkbox.

### 4.4 Stored state vs effective state

A saved checkbox is a **preference**. Runtime activation can have additional
dependencies.

Example:

```text
Net Worth preference = ON
Movers master = OFF
Effective Net Worth runtime = OFF
```

The preference is intentionally preserved. Re-enabling the dependency allows the
feature to return without rewriting the user's setting.

### 4.4a No GUI-only mirrors of a gate

A gate must not be shadowed by a second stored key that only the Options
checkbox handler keeps in step. Profile apply and import replace `TurboFaceDB`
wholesale and never run that handler, so the two drift with nothing to catch it.
There are no live GUI-only gate mirrors; `unitframes.partyEnabled` is retired.

If runtime needs a value derived from a gate, derive it **at read time** through
`ns.ModuleEnabled()`, or recompute it in `LoadVariables()` after migration — both
run on every path into the DB, including import.

A legacy flag may legitimately survive alongside a gate when it is a *separate
user setting* rather than a copy of the gate. `power.actionOverlayEnabled` is the
model: it has its own checkbox, and `PowerCost.OverlayEnabled()` ANDs it with
`modules.hotbarPower`. Mirroring a gate onto that kind of key is a bug — it
overwrites the user's independent choice.

### 4.5 Module changes and `/reload`

Module masters affect protected frames, one-way hooks, and startup subscriptions.
Treat `/reload` as the guaranteed clean boundary for module master changes.

Live `Refresh()` functions may still be used for ordinary child settings where the
implementation explicitly supports live teardown/rebuild.

### 4.5a Native cadence scheduler (`ns.Cadence`) and shared timer bus (`ns.Timers`)

TurboFace runs on clients that can render **hundreds of frames per second**. A
throttled `Frame:OnUpdate` still crosses the C-to-Lua boundary once per rendered
frame just to increment an accumulator and return. A 10 Hz job can therefore be
entered 700-900 times/sec on an uncapped/high-refresh client even though it only
needs to do useful work ten times.

Periodic TurboFace work is therefore routed through the native cadence scheduler
in `Core/Config.lua`:

```lua
ns.Cadence:Add(key, interval, fn [, immediate]) -- fn(key, elapsed)
ns.Cadence:Remove(key)
ns.Cadence:IsActive(key)
ns.Cadence:Count()
```

The scheduler owns at most **one** native `C_Timer.NewTimer` one-shot. Its master
clock runs at the **fastest cadence currently requested by any active client**,
never at the sum of every client's independently-phased deadlines. Slower clients
accumulate elapsed time inside that one pulse and execute only when their own
interval becomes due. This caps native C-to-Lua scheduler wakes at the fastest
active requirement (at most 60 Hz) even when ten or more periodic subsystems are
active together. A UI with only a 1 Hz client therefore wakes about once per
second; 30/33/60 Hz pulses exist only while work at those cadences is actually
active. Each client receives real elapsed time since its previous invocation.
When the last client leaves, the one-shot is cancelled. `immediate` affects only
a newly-added client; repeatedly invalidating an already-active 10 Hz client
cannot accidentally turn it into a higher-frequency job.

The scheduler is mutation-safe: existing entries may remove themselves while it
iterates, and registrations created from inside a callback are staged until the
next pulse. On Classic Era 1.15.9 the native ticker is the normal path; a hidden
`OnUpdate` fallback exists only for stripped test harnesses/clients lacking
`C_Timer.NewTimer`.

**Keys are one addon-wide namespace.** Every client shares `cadenceEntries`, so a
key collision silently replaces another module's driver with no error. Use the
owning frame or module table as the key — unique by construction, and what almost
every current client does — or a `TurboFace`-prefixed string literal. Never a bare
descriptive string such as `"combo"`.

**Error isolation is part of the contract (§4.5b).** Centralizing every periodic
job onto one clock also centralizes their failure modes.

### 4.5b Why the cadence pulse is error-isolated

Client callbacks are invoked through `pcall`. This is not defensive habit; it is
what keeps §4.5a's single-clock design from being a single point of failure.

Without it, an error raised by any one of the ~25 clients propagates out of
`CadencePulse` before it can clear `cadenceTicking` or run its trailing
`ScheduleCadenceClock()`. `cadenceTimer` was already nilled at the top of the
pulse, so no new clock is ever created — and because `Cadence:Add` and
`Cadence:Remove` both guard on the ticking flag, `Add` then stages into
`cadencePending` forever and `Remove` never reschedules. The result is that
**every periodic subsystem in the addon stops** — regen markers, castbars, combo
dots, swing timers, nameplate augmentation animations, XP text, and (because `ns.Timers` is
itself a cadence client) every aura and debuff countdown — until `/reload`,
behind a single Lua error the user has no reason to connect to any of it.

Centralizing periodic work improves wake-up cost but increases the potential blast
radius of one callback failure. Three mechanisms provide isolation:

1. **`pcall` per client callback.** At ~10 active clients and 60 Hz this is a few
   hundred protected calls per second — negligible against what it protects.
2. **Eviction after `CADENCE_MAX_ERRORS` (3) consecutive failures.** The first
   error goes to `geterrorhandler()`; repeats are suppressed so a 60 Hz client
   erroring every pulse cannot flood BugSack. A successful call resets the count,
   as do `Add`/`Remove`, so a re-registered client starts with a fresh budget.
   Eviction reports once, naming that the client's periodic work has stopped.
3. **Stale-flag recovery.** `CadenceTicking()` treats a pulse still "running"
   after `CADENCE_STALE_PULSE` (2 s) as unwound and clears the flag. This covers
   an error raised outside the per-client `pcall`, so the scheduler cannot be
   parked permanently by any path.

`ns.Timers` carries per-widget `pcall` isolation and three-strike eviction for the
same reason: the bus is one cadence client. It does **not** own an independent
stale-flag watchdog; the parent cadence scheduler continues invoking the bus after a
bus-level unwind, and the next pulse re-enters/clears `timerTicking`. Keep that distinction
accurate when changing either layer.

This is the runtime counterpart to `ns.SafeCall` at the init boundary (§2).

Do not "optimize away" the `pcall` on the grounds that clients are trusted code.
Clients read Blizzard frame state that can be recycled, restricted, or nil on
patch day — exactly the conditions under which a whole-UI stall is hardest to
diagnose.

**Epsilon belongs on both sides of the due test.** The pulse fires a client when
`accum + CADENCE_EPSILON >= interval`, so a wake landing up to 0.5 ms early still
counts as due. The remainder written back must clear that same tolerance:
`accum % interval` returns `accum` unchanged when `accum` is just *under*
`interval`, so the entry reads as due again on the very next evaluation,
`CadenceHasDueClient()` arms a zero-delay pulse, and the client runs twice for
one period. A live client's next `dt` breaks the tie, making this a wasted wake
rather than a stall — but under a fixed clock (`dt == 0`) it spins forever, which
is how it was found. `CadencePulse` therefore zeroes a remainder that is still
within epsilon of the interval. Any future change to the due predicate must
change the reset to match.

Cadence validation must exercise the real `Core/Config.lua` under a stubbed client:
a healthy client continues after a neighbour errors; repeated errors are reported once
and evicted after exactly three attempts; add/remove and re-registration still work; a
10 Hz client runs approximately ten times per second rather than twenty; and the scheduler
parks after its last client leaves. The supplied package does not currently ship a
repository-owned behavioral test harness for this contract.

`ns.Timers` remains the per-widget duration API, but it is now a **20 Hz client
of `ns.Cadence`**, not a frame `OnUpdate`:

```lua
ns.Timers:Add(widget, fn)   -- fn(widget, elapsed)
ns.Timers:Remove(widget)
ns.Timers:Count()
```

Its semantics deliberately match visible frame timers:

- callbacks receive `(widget, elapsed)`;
- hidden-via-parent widgets are skipped with `IsVisible`, not merely `IsShown`;
- additions made during a timer iteration are staged safely;
- the shared timer client leaves `ns.Cadence` when no widgets remain.

Current cadence-owned periodic work includes:

- shared aura/debuff timer bus: 20 Hz, with individual consumers internally reducing text
  work where appropriate;
- Player/Target AuraStyle timer text: 4 Hz while timed icons exist;
- AuraStyle dirty flush: 10 Hz only while dirty and **never** registered as immediate;
- Target-of-Target debuff compatibility poll: 4 Hz only while `targettarget` exists and
  the ToT Aura child is enabled;
- Party/Pet aura countdown/expiry driver: 4 Hz only while tracked timed icons exist;
- Party aura reconciliation: 1 Hz only while a party unit exists and Party Aura styling is on;
- Pet aura reconciliation: 1 Hz only while a pet exists and Pet Aura styling is on;
- player Mana/Energy/Rage/Health regen markers: ~33 Hz only while a marker is eligible;
- target nameplate combo points: 10 Hz only while an eligible target plate exists;
- nameplate pooled-frame lifecycle guard: every 0.5s via `C_Timer.After` only while tracked
  native plates exist; it stops when the tracked map is empty and treats silent same-token GUID
  replacement as a full canonical rebind rather than a table-only repair;
- Global Swing Timers: ~30 Hz only while a player/target countdown or auto-shot poll is required;
- Combat Meter: 10 Hz while its movable window is visible, or 4 Hz finalization-only
  while mover-hidden or in badge-only headless-accounting mode;
- independent DPS/HPS badge: 4 Hz while its combat refresh ticker is active;
- player/target castbars: at most 60 Hz while a cast/channel/failure hold exists;
- Bubble spend effects: one shared active-spend pass at at most 60 Hz;
- Nameplate Swing Timer strip: ~30 Hz while at least one tracked hostile plate needs visual progress;
- Class Buff reminder re-evaluation: 10 Hz coalescer only while a player aura/inventory
  change is pending (§16);
- Hunter Feed Pet happiness sampling: 1 Hz only while the relevant Class Buff reminder
  consumer is active (§16);
- Warrior Overpower / class indicator animation: 20 Hz, `OnShow`-gated;
- Hearthstone cooldown text: 1 Hz only while the cooldown cadence is needed;
- Experience Bar and FPS counter text: 1 Hz while their frames are visible.
- Speedrun Splits presentation: 1 Hz while its movable display is visible; XP
  checkpoint capture itself is event-driven and owns no polling client.

This inventory is meant to be exhaustive — §21.2 requires every periodic job to
have a stated reason to be awake, and a client absent from this list has not been
reviewed against that rule. `grep -rn "Cadence:Add" --include=*.lua` is the check.

At very high FPS the C-to-Lua entry cost of even a throttled singleton `OnUpdate` is
measurable. Periodic work uses `ns.Cadence`; reserve a true `OnUpdate` for
work that genuinely must follow every rendered frame (for example an active drag
interaction) and park/remove it immediately when that interaction ends.

### 4.6 Why there is no module factory

An earlier audit proposed collapsing the recurring `DB` / `Enabled` /
`SetEvents` / `ActivateRuntime` / `DeactivateRuntime` quintet into a single
`ns.DefineModule{...}` factory. **That was investigated and rejected.** The
helpers share names, not shapes:

- **`Enabled()` has 14 variants** that differ in ways a factory would have to
  special-case: flat `TurboFaceDB` keys vs nested blocks; `== true` vs
  `~= false` (*opposite* defaults, so a wrong guess silently flips a feature);
  mover-dependent or not; extra capability gates (`HealPrediction` also requires
  `ns.caps.healPrediction` and a live `UnitGetIncomingHeals`); a module-gate
  check (`BubbleNameplates`); and one that takes a `db` argument
  (`ExperienceBar`).
- **`DB()` has two incompatible shapes.** Eight modules return the saved-variable
  root. Four (`ExperienceBar`, `LootFrame`, `Movers`, `PowerCost`) also create
  their nested block and merge defaults into it.
- **`SetEvents()` shares a skeleton but not a payload** — three of the eight need
  `pcall`, capability checks, or unit-filtered registration.

A factory covering all of that needs an escape hatch per axis, which is harder to
read than the explicit code and *hides* the §1.4 dormancy contract instead of
enforcing it. The duplication here is shallow; the variation is real.

What was extracted instead, where semantics are genuinely identical:

- `ns.DB()` — the saved-variable root. The eight root-DB modules now do
  `local DB = ns.DB`, so call sites keep their upvalue lookup and read
  unchanged. The four nested-block modules keep their own.
- `ns.Opt` / `ns.SetOpt` — flat key access (§11.13).
- The Movers gate is now a bare `return ns.MoverDependentEnabled(on)` at all
  nine sites. The old `if ns.MoverDependentEnabled then ... end; return on`
  guard was dead — `Core/Config.lua` loads second and every call is at runtime — and
  its `and`/`or` sibling can convert explicit false into a fallback true. Keep one shape
  with no fallback branch to get wrong.


---

## 5. Movers as a dependency provider

Movers is not merely a convenience switch. Some TurboFace-owned floating widgets do
not have a sensible permanent default placement and therefore require the Movers
framework to be available.

Helpers:

```lua
ns.MoversEnabled()
ns.MoverDependentEnabled(localEnabled)
```

### 5.1 Features that require Movers

The following are effectively disabled while the Movers master is off. Every row
is a **bare `return ns.MoverDependentEnabled(on)`** in the owning file; that list
of call sites and this table must stay in step.

| Feature | Mover element | Gate lives in |
|---|---|---|
| Luxthos-like XP | `ExperienceBar` | `ExperienceBar.lua` |
| TurboFace Loot Frame | `LootFrame` | `LootFrame.lua` |
| Net Worth | `NetWorth` | `Inventory/NetWorth.lua` |
| Skill Tracker | `SkillTracker` | `Skills.lua` |
| Hearthstone widget | `Hearthstone` | `Hearthstone.lua` |
| UnstuckSkips notifier hook | `UnstuckSkips` | `UnstuckSkipsVisual.lua` |
| Tracking Icon | `TrackingIcon` | `MinimapTracker.lua` |
| standalone Class Buff reminder bar | `ClassBuffBar` | `Combat/ClassBuffs.lua` |
| Plus Flight Bar | `FlightBar` | `Plus/FlightBar.lua` |
| Grocery List launcher button (button only, not auto-buy) | `GroceryButton` | `Inventory/Grocery.lua` |
| Combat Meter window | `CombatMeter` | `Combat/CombatMeter.lua` |
| Enemy Leash Timer | `LeashTimer` | `Combat/LeashTimer.lua` |

The Grocery launcher defaults to the Ice Cold Milk icon, layers Blizzard's `Interface\Buttons\CheckButtonHilight` additively above the Milk icon while the Grocery window is open, and plays the Quest Log open/close sound kits when the window opens/closes.

This dependency must be enforced in the **runtime gate**, not only documented in the
Options UI.

The table and canonical call sites can have matching counts while naming different
features. When editing this table, compare it directly against
`rg -n "MoverDependentEnabled" -g '*.lua'`.

Speedrun Splits is a deliberate hybrid: its `SpeedrunSplits` display requires Movers,
but checkpoint tracking remains active while the feature is enabled even if Movers or
the display is hidden. Hiding presentation must not create a hole in PB history.

**Callers must pass a real boolean.** `ns.MoverDependentEnabled` returns `false`
only on an explicit `false`, because a missing or not-yet-migrated preference has
to fail open like every other gate (§4.1). That makes `nil` read as **enabled** —
correct for a module gate, and wrong for any value that can legitimately be nil.
The dangerous case is `ns.PlusSettings()`, whose proxy returns `nil` for a key
whose section is **disabled** (§6.2): passing that through unconverted turns a
disabled Plus section into an enabled feature, the exact failure the gate exists
to prevent. Coerce at the call site — `~= false`, `== true`, or `and true or
false` — and only then call. Flight Bar is the live example, and `Core/Debug.lua`
coerces for the same reason. Reading the saved-variable root through `ns.DB()`
rather than the bare global also matters here: `TurboFaceDB and TurboFaceDB.key`
yields `nil`, not `false`, before the root exists.

### 5.2 Intentional exceptions: mover-integrated but not mover-dependent

Registering a mover element does **not** imply mover dependency. These exception
families must keep working with the Movers master off:

- **Party class reminders.** Anchored to the party unit frames, so they always
  have a sensible position. Only the standalone self-reminder bar
  (`ClassBuffBar`) is mover-dependent.
- **Free Bag Slots** (`Inventory/BagSlots.lua`). It registers a `BagSlots` mover
  element for convenience but carries its own `FALLBACK_POINT`, so it stays
  usable and correctly placed without the Movers framework. It therefore uses a
  bare `ns.MoversEnabled()` check — for the *hidden* preference, which is
  Movers-owned — and must **not** be converted to `ns.MoverDependentEnabled`.
- **FPS Counter** (`FPSCounter.lua`). `fpsCounterEnabled` is a Speedrun-owned feature gate;
  the `FPSCounter` mover owns only optional placement/hide/click-through. The counter has a
  permanent fallback point and remains live with Movers disabled. Hearthstone Batching requires
  this feature gate and its options dependency keeps the pair valid in both directions.
- **Druid Power Bar** (`UnitFrames/DruidPowerBar.lua`, Class-owned despite the historical path).
  `druidPowerBarEnabled` remains a Class setting. When the TurboFace Player Unit Frame child is
  enabled, the bar is baked into the reserved Druid artwork slot and inherits the Player power-bar
  texture. When that UnitFrame child is disabled, the same runtime switches automatically to a
  12px standalone bar beneath Blizzard's player power bar, using its Class-owned standalone texture,
  the shared Blizzard Tooltip border, and an optional `DruidPowerBar` mover. Movers OFF returns it
  to the deterministic Blizzard-frame-relative fallback rather than disabling the feature. Its text
  presentation is Class-owned but independent of the generic Class typography: `druidPowerBarFont`,
  `druidPowerBarTextStyle`, `druidPowerBarTextSize`, and `druidPowerBarTextFormat` apply identically
  in embedded and standalone mode. `percent-current-blizzard` renders percent inside-left and current
  mana inside-right using two TurboFace-owned FontStrings.
- **Standalone swing/cast timers.** The six combat-timer surfaces have deterministic
  defaults below Blizzard's Player/Target frames. Movers provides independent placement
  and `/tf move` overlays, but disabling Movers must not disable the timer runtime or
  hide otherwise-valid standalone bars.

The distinction is whether the widget has a sensible permanent default placement
(§5). If it does, integrate with Movers but do not depend on it.

### 5.3 Individual mover elements

An individual mover element that is disabled should not create unnecessary helper
anchors/hooks on a clean login. Mover registrations may expose an `isAvailable`
predicate; while it is false, `Movers/Movers.lua` relinquishes geometry, visibility,
click-through, and cyan-overlay ownership without forgetting the saved standalone
position. The feature owner is then solely responsible for live placement. When the
predicate becomes true again, Movers reapplies the retained preference. Combat Meter
uses this path while its window is disabled, and combat timers use it while baked into
UnitFrames.

The Movers tab has only three categories: **Mover Mode**, **Blizzard Movers**, and
**TurboFace Movers**. Blizzard Movers contains `TargetFrameToT`, `QuestTracker`,
`MinimapClock`, `GroupLootRolls`, `MinimapMail` (shown as Minimap Icon), `MinimapLFG`,
`LatencyBar`, `GameTooltip`, `BlizzardLootFrame`, `TargetBuffs`, `TargetDebuffs`, and
`ToTDebuffs`. Every other registered element is presented under TurboFace Movers; this is
UI organization only and does not change element keys, registration, availability, or ownership.
The aura movers remain implemented by `Movers/Auras.lua`, while system registrations including
the standalone-only `DruidPowerBar` remain implemented by `Movers/Systems.lua`.
The former `XPBar` mover for Blizzard's native XP/status-tracking bar is retired because Classic
HUD Edit Mode now owns that placement. `ExperienceBar` is the distinct TurboFace widget and is shown
in Options and mover overlays as **Luxthos-like XP**; do not reintroduce a native XP-bar mover.
TurboFace-owned widgets register their own elements from their owning files (§5.1,
§5.2). The six standalone combat-timer surfaces are `PlayerMainSwingTimer`,
`PlayerOffhandSwingTimer`, `PlayerRangedSwingTimer`, `PlayerCastBar`,
`TargetSwingTimer`, and `TargetCastBar`; each uses `isAvailable` so Movers owns it
only while that surface is actually in standalone mode. The embedded Target timer
stack is deliberately kept one frame strata below `TargetFrameToT` so
Target-of-Target artwork/text always renders above it; cast-over-attack ordering is
preserved with frame levels inside that lower strata.

`Movers/Movers.lua` must remain **same-element re-entrancy safe**. `ApplyElement()` spans
positioning plus the owner's optional `onApply`; if that callback re-registers the same
element, metadata may update but a nested apply is forbidden and one pending overlay
refresh is consumed by the outer call. Mover BackdropTemplate overlays are never measured
with `GetCenter()`/`PointFromCenter()` during apply/update; drag coordinates come from
TurboFace cursor math and idle coordinates from the owned element. These rules prevent
same-element `/tf move` refresh from recursing through its own apply path.

Blizzard player/target/action-bar/durability movers were intentionally handed back to
Blizzard HUD Edit Mode on 1.15.9.

`MinimapLFG` moves the stock Classic Era Looking For Group eye/tracker rather than
replacing it. `LFGMinimapFrame` belongs to the load-on-demand
`Blizzard_GroupFinder_VanillaStyle` addon, so registration is deferred through
`ns.API.OnAddonReady`. A permanent TurboFace anchor remains draggable even while the
stock eye is temporarily hidden; when Blizzard shows or repositions the eye, the
secure hooks defer a re-apply back onto that anchor. TurboFace does not call `Show()`
in the mover path, preserving Blizzard's availability/queue visibility rules and the
Plus `hideMiniLFG` option. Clicks, tooltip, animation, and LFG behavior remain on the
original Blizzard frame.

---

## 6. Plus section architecture

Plus settings remain stored in one flat table:

```lua
TurboFaceDB.plus
```

This is retained for profile compatibility, while user-facing section gates live under
`TurboFaceDB.modules.plus`.

### 6.1 Section classification

`Core/Config.lua` owns the explicit map:

```lua
ns.PLUS_SECTION[key] = section
```

Every key in `ns.defaults.plus` must have exactly one mapping. `ns.ValidatePlusSectionMap()`
runs at login and reports unmapped or stale keys.

Whenever a new Plus option is added:

1. add the default;
2. add the Options GUI control;
3. add the `PLUS_SECTION` mapping;
4. decide whether it is live-applied or reload-applied;
5. verify disabled-section teardown.

### 6.2 Singleton settings proxy

Plus modules read settings through:

```lua
ns.PlusSettings()
```

This returns one persistent read-only proxy. It does **not** allocate a table/metatable
per call.

Its `__index`:

1. checks the setting's Plus section gate;
2. returns `nil` when that section is disabled;
3. resolves the current `TurboFaceDB.plus` table dynamically.

Dynamic lookup is required because profile/import operations can replace
`TurboFaceDB` wholesale.

Plus modules should not write through the proxy.

### 6.3 Reload-applied Plus features

Some Interface/Chat/System features install hooks that cannot be unhooked. Those
options are intentionally reload-oriented. Their callback bodies must still verify the
current predicate where relevant so a disabled owner does not continue doing work.

Dynamic Plus features such as Social/Automation event listeners should register and
unregister their events according to active settings.

---

## 7. Runtime ownership: events, CLEU, timers, and hooks

### 7.1 Event frames

Creating an inert frame is cheap; registering high-frequency events is not. Prefer:

```lua
local frame = CreateFrame("Frame")
-- register only in :Init()/RefreshRuntime() when effective state requires it
```

When disabled, call the narrowest appropriate teardown:

```lua
frame:UnregisterEvent(...)
-- or UnregisterAllEvents() when the frame owns only that feature
```

**Filter `UNIT_*` events in C wherever possible.** A plain
`RegisterEvent("UNIT_AURA")` wakes Lua for every unit the client tracks — player,
party, raid, pet, target, focus and all ~40 nameplate units — even when the
handler discards all but one. Use the shared helper:

```lua
ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_START", "player", "target")
```

TurboFace's supported Classic contract is **at most two unit tokens per
registration**. Consumers needing a small fixed set larger than two should split the
hot event across a few inert helper frames rather than pass undocumented extra
arguments. `UnitFrames/UnitFrames.lua` does exactly this for `UNIT_HEALTH`: party1/2, party3/4,
and targettarget use three C-filtered registrations. Truly dynamic sets such as
nameplates must keep the unfiltered registration and their own unit check. The shared
helper falls back to `RegisterEvent` if the API is missing, so **handlers must keep
their unit checks either way** — the filter is an optimisation, not a guarantee.

### 7.2 Shared combat-log dispatcher

`Core/Config.lua` owns `ns.CLEU`, the sole normal `COMBAT_LOG_EVENT_UNFILTERED` decoder.

Consumers register with:

```lua
ns.CLEU:Register(fn)             -- wildcard / every subevent
ns.CLEU:Register(fn, subevents)  -- filtered set
ns.CLEU:Unregister(fn)
```

A filtered set is a set-like table such as:

```lua
{
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
}
```

The actual WoW CLEU event is registered only while at least one consumer exists. The
dispatcher calls `CombatLogGetCurrentEventInfo()` exactly once, writes the result into
one reusable payload table, and synchronously fans that table out only to wildcard
handlers plus the bucket matching `payload[2]` (the subevent).

**Payload lifetime contract:** consumers may read the shared payload synchronously but
must never retain it across frames/events. It is overwritten on the next CLEU event.

Feature modules must unregister when inactive. Prefer filtered registration for every
consumer with a stable subevent set; wildcard registration is compatibility behavior,
not the default for new code. Do not add a second raw CLEU event frame without a very
strong reason.

`Core/Debug.lua` separately counts:

```text
CLEU/s       = raw combat-log events decoded
handlers/s   = TurboFace consumer callbacks actually dispatched after filtering
```

These are deliberately different metrics. A healthy filtered dispatcher may see many
CLEU events while invoking few handlers.

### 7.2.1 DoT prediction runtime

`Combat/DotPrediction.lua` is the sole owner of periodic-damage prediction state. Its normal tick
learner consumes only `SPELL_PERIODIC_DAMAGE`, `UNIT_DIED`, and `UNIT_DESTROYED` through filtered
`ns.CLEU` registration. `Combat/PvPHealthEstimate.lua` is a subordinate, UI-independent health-basis
service used only by DoT prediction for Classic hostile players whose `UnitHealth/UnitHealthMax`
values are percentage-normalized rather than absolute. It uses a second **filtered handler on the
same shared `ns.CLEU` dispatcher** for ordinary damage/heal events; it never creates another raw
`COMBAT_LOG_EVENT_UNFILTERED` frame.

Both runtimes are active only while the feature is enabled **and at least one valid presentation
surface exists**. Nameplate presentation is an independent additive surface and does not require the
optional Nameplates enhancement family: while that family is off, DotPrediction owns only a minimal
nameplate add/remove GUID bridge and attaches its textures to Blizzard's native health StatusBar.
When enhancements are on, their canonical full lifecycle remains authoritative. Target/Target-of-
Target presentation likewise uses Blizzard's native health bars and does **not** require TurboFace
Unit Frames to be enabled or styled; the two DoT surface preferences are authoritative. If every
usable surface is off, DotPrediction unregisters and the PvP estimator is disabled/cleared rather
than collecting data for nobody.

Nameplates and unit frames are both explicit DotPrediction consumers. `UNIT_AURA` invalidates the
target-GUID cache and notifies the matching renderer immediately. Because Blizzard aura events are
unit-token scoped rather than GUID-broadcast, Target/ToT aura invalidation is also bridged through the
existing O(1) `guidToNameplateUnit` map when that GUID is simultaneously visible as a nameplate.
Nameplate aura changes and completed nameplate binds enter one deduplicated, identity-validated
**50 ms safety reconcile**: it clears any provisional zero projection and asks the renderer once more
after native aura metadata / pooled-frame binding has settled. This is not a periodic poll.

The missed-event recovery scan is anchored to `PLAYER_ENTERING_WORLD`, not `PLAYER_LOGIN`: on a
cold client launch, login may occur while the loading screen is still active and before
`C_NamePlate` can enumerate anything. World entry performs one immediate canonical reconciliation
and bounded 0.5/1.5-second settle passes; a generation guard discards callbacks superseded by a
later zone transition. These passes rebuild the normal unit/GUID binding and all augmentations,
including DoT projection, without adding a permanent nameplate poll.

`SPELL_PERIODIC_DAMAGE` follows the same deterministic nameplate rule. After the real tick updates
damage/timing samples and invalidates the GUID projection cache, DotPrediction immediately resolves
that destination GUID through `guidToNameplateUnit` and repaints only that visible plate. Therefore a
`UNIT_HEALTH` event that happens to arrive before CLEU cannot strand a newly learned prediction until
the next tick. Health events remain the ordinary geometry-follow path as HP changes.

The nameplate consumer resolves `ns.unitToPlate[unit]` at notification time and validates the live
GUID against `myPlate.cachedGUID`. A mismatch re-enters the canonical native nameplate lifecycle
rather than silently dropping the prediction repaint. The independent 0.5-second pooled-frame guard
uses the same rule: same-token GUID replacement is a **full rebind**, not just a lookup-table repair.
This keeps cached GUID identity, DoT state, auras, threat adjuncts, and every other pooled augmentation
in lock-step. Pooled removal explicitly hides the DoT textures and clears their geometry cache.

A newly bound Blizzard health bar can briefly report placeholder width before native layout settles.
The DoT renderer retries reconciliation only in that condition, capped at three 50 ms attempts per
binding; once valid geometry exists the retry state is cleared. There is no permanent prediction
driver or nameplate scan.

Nameplate DoT render order is deterministic and does not rely on same-sublayer texture creation
order. While a drawable prediction exists, TurboFace snapshots the native StatusBar fill's draw
layer and temporarily assigns the overlapping passes as **native fill ARTWORK:-2 -> black DoT
underlay ARTWORK:-1 -> coloured DoT region ARTWORK:0 -> Blizzard border ARTWORK:1**. The native
border is never modified. When the prediction disappears, the feature is disabled, or the pooled
plate is released, the native fill's original layer/sublevel is restored. This is the only narrow
nameplate-native draw-order adjustment owned by the DoT renderer; geometry, value, colour, texture,
and chassis art remain Blizzard-owned.

The renderer's cached RGBA values are optimization hints rather than authority. Every active render
compares them with the live DoT texture, repairs any pooled-frame/native reset, and keeps the
texture-region base alpha at 1 because the user-configured prediction opacity is carried by vertex
alpha. Full rebind and removal clear both geometry and RGBA caches. Thus a recycled texture cannot
remain shown at effective alpha zero merely because its stale plate cache still matches the desired
setting.

Native identity-only suppression is restricted to the immutable Blizzard frame/region sets captured
before TurboFace attaches any augmentation. It never walks newly attached regions as suppression
targets. Restoration also releases any suppression state owned by the native unit frame but absent
from that baseline, repairing pooled plates touched by older builds. This boundary is essential for
health-bar children: otherwise a plate that showed a friendly name-only unit could retain an
alpha-zero hook on its DoT texture when recycled for a hostile unit.

The engine is empirical rather than a full spell-coefficient simulator:

- live `UnitDebuff` data is authoritative for whether an aura currently exists;
- actual `SPELL_PERIODIC_DAMAGE` supplies tick damage and timing observations;
- ordinary periodic hits own the learned damage median. If the first observation is critical,
  a separate half-value fallback makes the prediction drawable without contaminating that median;
  the first ordinary hit supersedes it immediately;
- if Classic omits an owned aura's `sourceUnit`, active destination combat-log state recovers the
  actual caster even if the ownership flag is also transiently absent; broader caster-wide recovery
  remains gated by the player/pet ownership flag;
- state is separated by **target GUID -> caster GUID -> spell ID** so two casters using
  the same DoT cannot corrupt one another;
- player and player-pet damage can be tracked without sharing one target/spell sample;
- target-specific damage is preferred, with caster/spell fallback only when needed;
- learned cadence is kept separately from an individual aura instance;
- cadence may persist in `TurboFaceCacheDB.dotPredictionIntervals` by spell ID and
  `TurboFaceCacheDB.dotPredictionIntervalNames` by spell name so a new rank can inherit
  a known tick interval without persisting stale damage values;
- timing observations are smoothed/validated so a missed tick or clean 2x/3x timing
  multiple does not immediately poison a stable cadence.

### PvP hostile-player health basis

Classic Era can expose hostile players as normalized percentage health (`current/100`) rather than
absolute HP. DoT damage is still known in real damage points, so treating that percentage pair as an
absolute max would make the overlay and lethal test catastrophically wrong. `PvPHealthEstimate.lua`
therefore provides `EXACT`, `ESTIMATED`, or `UNKNOWN` health bases to the DoT engine:

- non-normalized units use Blizzard `UnitHealth/UnitHealthMax` directly and are `EXACT`;
- normalized hostile players begin `UNKNOWN`, so TurboFace suppresses width/lethal prediction rather
  than showing false precision;
- while such a player is observed, the estimator accumulates effective CLEU health damage and healing
  against that GUID and matches the net amount to percentage movement;
- estimates are short-lived in-memory GUID state only; they are never written to SavedVariables and
  are cleared on zone/session-target resets and feature teardown;
- transitions that cannot be reconciled inside a 1.50-second matching window are rejected rather than
  learned (regen, max-health changes, missing CLEU, or ordering mismatch);
- a six-sample rolling model rejects values more than 35% from its median. One large transition of at
  least 8 percentage points may reach `MEDIUM`; otherwise two consistent observations are required.
  Three tightly clustered observations promote the estimate to `HIGH`;
- DoT bar geometry and `WillDie()` accept `MEDIUM` or `HIGH` estimated health. `LOW/UNKNOWN` remains
  intentionally invisible;
- `UnitHealthPercent(unit, true)` is preferred when available so the percentage observation can track
  combat-log movement more promptly; `UnitHealth/UnitHealthMax` is the fallback percentage source.

The estimator has no independent UI. `/tf debug dots` reports its source, confidence, percentage,
estimated max HP, sample count, spread, and pending net combat delta for the current target.

The prediction model intentionally exposes two different concepts:

```text
nextTickDamage     = one next tick from each active DoT
nextEventDamage    = the earliest chronological periodic-damage event
remainingDamage    = total expected damage if active DoTs finish
```

Current target/nameplate purple overlays use **total remaining damage**. The richer API
exists so future UI can show imminent damage without rewriting the engine.

Public consumers should use the prediction API (`GetPrediction`,
`GetProjectedDamage`, `GetNextTickDamage`, `GetBarRegion`, diagnostic breakdowns) and
must not build private tick databases in `UnitFrames/UnitFrames.lua` or nameplate files.

Prediction caching is primarily **event-invalidated**. `UNIT_AURA` and an observed periodic tick
invalidate the relevant GUID immediately. Nameplates additionally use the bounded 50 ms reconciliation
boundaries above so an event that beats Blizzard aura/layout finalization cannot leave a provisional
zero cached. A 0.50-second cache TTL remains only as a passive safety rescan when a consumer later asks;
it is not a ticker. Ordinary health changes should reuse the cache rather than rescan up to 40 debuffs
at 10 Hz per nameplate.

When the feature is disabled **or no valid consumer surface remains**, the engine
unregisters CLEU/aura events, clears runtime state, and asks consumers once to hide
their TurboFace-owned overlays.

### 7.2.2 Heal prediction runtime

`Combat/HealPrediction.lua` is the sole owner of player/group incoming-heal prediction state.
It is UI-independent; `UnitFrames/Predictions.lua` renders the returned segments.

Direct healing comes from Blizzard's native:

```lua
UnitGetIncomingHeals(unit [, casterUnit])
```

TurboFace walks the current player/group roster so attributable native heals remain
per-caster. Any native remainder the client cannot attribute is preserved as an
`unknown` direct-heal segment rather than discarded.

Periodic healing deliberately follows HealBars-style **next-tick-only semantics**:

```text
Rejuvenation with four ticks left -> display the next tick, not all four ticks
```

Helpful auras are authoritative for HoT existence. `SPELL_PERIODIC_HEAL` supplies real
tick amount/timing. HoT state is keyed **target GUID -> caster GUID -> spell ID**.
Known Classic Era Renew, Rejuvenation, Regrowth, and Mend Pet ranks seed first-tick
interval/base values; observed non-critical ticks replace the amount estimate. Critical
HoT ticks advance the tick clock but do not permanently inflate the ordinary-tick
estimate.

Additional Classic-specific behavior:

- Tranquility cadence is learned/handled as a 2-second periodic channel; no invented
  pre-first-tick amount is required when the engine lacks evidence.
- Prayer of Healing secondary targets receive a narrow deterministic subgroup fallback
  when Blizzard's native incoming-heal API omits them while a known PoH cast is active.
- Chain Heal jumps are **not guessed** because proximity makes future jump targets
  unknowable client-side.

`GetSegments(unit)` returns chronological direct/HoT segments. The prediction settings
own colors, own-vs-other distinction, optional class tinting, minimum heal threshold,
maximum visible segments, and optional overheal extension beyond the normal bar width;
`UnitFrames/Predictions.lua` owns only rendering.

`ShowOnUnit(unit)` checks only the Heal Prediction feature/capability and that unit's
presentation switch (`player`, `target`, `targettarget`, `pet`, `partyN`). It deliberately
does **not** consult `modules.unitframes`: the renderer attaches directly to Blizzard's
native health StatusBars, so stock Blizzard Unit Frames are valid consumers. If every
per-unit surface is disabled, the engine unregisters its filtered CLEU consumer and all
feature-specific unit/cast events even when `healPredictionEnabled` itself remains true.
Existing TurboFace-owned renderer textures are hidden by the consumer.

`Nameplates/BubbleNameplates.lua` retains a small hostile-NPC incoming-heal overlay driven by
Blizzard's native `UnitGetIncomingHeals` result. It does not predict casts and must not become a
second owner of `Combat/HealPrediction.lua` state without an explicit redesign.

### 7.2.3 Combat Meter runtime

`Combat/CombatMeter.lua` is intentionally a **lightweight local party/dungeon meter**, not a
raid analytics system.

CombatMeter has two distinct demand gates:

```text
movable window = combatMeterEnabled == true AND Movers dependency available
accounting runtime = movable window OR independent DPS/HPS badge enabled
```

The window gate still controls frame creation, mover registration, ranking/spell rendering,
and window visibility. The accounting runtime owns CLEU/roster/combat collection and may run
headlessly for `Combat/DPSBadge.lua` even when the window and Movers are disabled. In that
badge-only mode the meter frame is not constructed and the shared finalization cadence is
reduced from 10 Hz to 4 Hz; damage/healing accounting itself remains event/CLEU-driven. When
neither the window nor the badge needs data, CombatMeter unregisters CLEU and all of its
feature-specific events and leaves `ns.Cadence`.

The mover-hidden flag is a presentation gate, not an accounting-disable gate. A hidden
window does no row sorting, text formatting, or row updates. It shares the 4 Hz
finalization cadence with badge-only mode, and unhide applies a forced refresh. The
bare `/tf meter` toggle and `/tf meter show` / `/tf meter hide` commands use the same
Mover visibility state as the panel and badge controls.

Collection rules:

- count effective damage (`amount - positive overkill`) rather than padding totals with
  overkill;
- aggregate immediately into `Current` and in-memory `Overall` totals;
- retain counters, not individual combat-log event history;
- attribute known `pet`, `partypetN`, and `raidpetN` GUIDs to their owner;
- preserve pet-origin spell identity in breakdown rows (`Pet: Bite`, `Pet: Melee`, etc.);
- do not guess ownership for arbitrary temporary guardians/summons;
- Current DPS uses one encounter duration shared by actors;
- Overall DPS uses summed finalized/current combat time, not wall-clock login time.

Current encounter segmentation starts on the first tracked outgoing damage. Once
tracked group combat ends, displayed duration freezes while the configurable merge
window remains open so DPS does not sag during grace time. A quick next pull can merge
into the same segment; otherwise it finalizes. A long no-damage fallback prevents a
stuck combat flag from leaving Current active forever.

Rendering is decoupled from collection and throttled (default 0.25 s). The display is a
fixed **5-row party-sized viewport** in both ranking and spell-breakdown modes. Collection
is not capped to those five visible rows: if Overall contains more actors, or a player has
more than five contributing spells, the same five row widgets are reused as a mouse-wheel
window over the complete sorted result. Entering/leaving breakdown, changing metric/view,
or resetting the meter returns that window to the top. The footer exposes the visible range
when scrolling is available.

The meter width is independently configurable from **160–380 px** in 5 px steps. Narrow
widths tighten the name/number gutters and automatically abbreviate header labels so the
header does not become the minimum-width constraint. The old `combatMeterMaxRows` value
is retained only for import/SavedVariable compatibility and no longer controls runtime
geometry.

Ranking view shows damage/DPS/share; clicking a row opens aggregate spell breakdown. No
addon communication, boss database, encounter archive, timeline, death recap, or raid
reconciliation belongs in this module. Dedicated raid analysis remains the job of addons
such as Details.

### 7.2.4 Independent DPS/HPS badge

`Combat/DPSBadge.lua` is a presentation consumer of CombatMeter accounting, **not** a
child of the Combat Meter window and not a Unit Frames child. Its effective demand can
keep CombatMeter accounting active headlessly while `combatMeterEnabled == false` and/or
Movers is disabled. The badge itself owns no CLEU; it reads `ns.CombatMeter:GetPlayerRate()`.

The badge frame is deliberately a top-level `UIParent` child on `MEDIUM` strata at frame level 100.
It remains visually anchored to Blizzard's Player level text and mirrors the resolved PlayerFrame
art owner's effective scale, but it is not parented inside Blizzard's PlayerFrame hierarchy. That
top-level ownership and level floor keep it above PlayerFrame glow/art and TurboFace's baked player
swing/cast rows, while Blizzard's `HIGH`/`DIALOG` menu surfaces cover it normally. Baked rows reassert
their art strata during placement and use `ns.DPSBadge:GetFrame()` for the same-strata fallback
ceiling.

The badge's 0.25 s refresh cadence runs only while its combat ticker is active. Disabling
the badge removes that cadence and its event subscriptions; accounting may remain active
only if the meter window itself still needs it.

### 7.2.5 Enemy Leash Timer runtime

`Combat/LeashTimer.lua` owns the optional Speedrun Enemy Leash Timer. It is independent of
TurboFace Nameplates and Unit Frames; Blizzard unit tokens/nameplates are observation surfaces,
not runtime parents. The floating list is intentionally **Mover-dependent** and its feature gate is
`leashTimerEnabled`. Hiding the `LeashTimer` mover also parks the runtime because there is no
headless consumer for leash state.

The timer is GUID-authoritative. `NAME_PLATE_UNIT_ADDED` records recyclable unit-token-to-GUID
identity and enriches state with name, level, classification, raid marker, and the NPC's live combat
relationship to the player. `NAME_PLATE_UNIT_REMOVED` removes only the recyclable token mapping while
the nominal countdown is still live. Target/focus can reattach another concrete token for the same GUID.
At nominal expiration, an entirely unobservable GUID is retired because Classic provides no later
per-GUID reset signal; an observable row instead switches to overtime (`+0.1s`, `+0.2s`, ...) so observed
leash variance remains visible. Confirmed timers may also end early after a debounced explicit disengagement;
estimated body-pull timers intentionally ignore transient threat/victim/combat disagreement before zero,
then become eligible for the same debounced real-reset cleanup after crossing the nominal boundary.
Target/focus are fallback observation tokens so the feature still gains metadata when the relevant NPC is directly selected.

Loss-of-control suppression is project-owned data in `LeashTimer.lua`. One canonical Blizzard spell
ID per localized control-effect name is grouped by the behavior that invalidates normal chase timing
(incapacitate/disorient/fear, roots, stuns, and engineering explosive control). The IDs are resolved
to localized names once; ranks sharing a name inherit the rule without a rank table.

Leash duration is TurboFace's current Classic level estimate:

```text
below 30         11 s
30-39            12 s
40-44            13 s
45-49            14 s
50+ or skull     15 s
```

The module subscribes to a filtered set of shared `ns.CLEU` subevents rather than creating a raw
combat-log frame. Player-origin `SWING_DAMAGE`, `RANGE_DAMAGE`, `SPELL_DAMAGE`,
`SPELL_CAST_SUCCESS`, and immune misses are authoritative interaction timestamps and no longer
require a second threat-table confirmation before starting/resetting a visible GUID state. Periodic
damage is deliberately excluded. If a CLEU interaction arrives before a usable unit token exists,
the module stores the timestamp/name as pending metadata and enriches it when that GUID becomes
observable. An outgoing miss with result `EVADE` is an explicit per-GUID reset and removes only that
mob's timer even if another hostile keeps the player in combat.

Pure body/proximity pulls require a broader admission model because Classic can put the player and
NPC in combat before `UnitThreatSituation` returns anything useful. A visible hostile NPC is therefore
considered engaged when **either** the player has any non-nil threat status (including status 0) **or**
`unit.."target"` resolves to the player. `UNIT_TARGET`, `UNIT_FLAGS`, threat events, target/focus changes,
and nameplate lifecycle events all feed that relationship check. `PLAYER_REGEN_DISABLED` and
`NAME_PLATE_UNIT_ADDED` also arm a short 10 Hz acquisition window (1.5 s at combat entry; 0.75 s for
a newly added plate) so event ordering cannot permanently miss a pull. As a last-resort body-pull
fallback, TurboFace remembers each visible GUID's pre-combat `UnitAffectingCombat` state. A real
false->true transition can seed an estimated timer only when it lands within 0.35 seconds of the
player's own combat transition, there is currently no active leash state, and exactly one visible
unconfirmed hostile satisfies that condition. Multiple candidates are treated as ambiguous and are
left pending until threat, victim-target, or CLEU evidence identifies ownership. A nameplate first seen
already in combat is baseline-only and never counts as a transition, preventing nearby pre-existing
fights from being admitted merely because their plates entered visibility. Once an estimated body-pull
timer is admitted it is sticky through the nominal countdown boundary because Classic can oscillate
threat, victim, and combat flags before the first real interaction. At zero it enters overtime observation
mode while a concrete token remains; without any nameplate/target/focus observation it retires at that
boundary. After zero, a stable observed disengagement can remove an overtime row as a real reset.
A direct CLEU interaction upgrades the state from estimated to confirmed.

Tracked loss-of-control/root effects are resolved from spell IDs to localized spell names once and
maintained as a per-GUID CC count. While any tracked CC is active, normal leash display state is
suppressed. When the final tracked CC falls off, a still-visible NPC that still has a live player engagement
relationship starts a fresh estimated state. `UNIT_DIED` / `UNIT_DESTROYED` clear state immediately.

Engagement ownership is event-driven through `UNIT_THREAT_LIST_UPDATE`,
`UNIT_THREAT_SITUATION_UPDATE`, `UNIT_TARGET`, and `UNIT_FLAGS`. When Blizzard reports a concrete
nameplate token, only that unit is checked; when a threat event reports the actor (commonly `player`),
the module sweeps only its already-known visible nameplate map plus target/focus. The short
combat-entry acquisition window re-samples that same concrete visible set and never synthesizes or
scans `nameplate1..40`.

Rendering uses one reusable multiline FontString sorted by soonest nominal expiration. Normal rows
switch to warning color below 7 seconds and danger color below 3 seconds, with raid markers preserved.
At or below zero, the danger-colored value becomes a counting-up overtime display (`+0.0s`, `+0.1s`,
...) anchored to the original nominal expiration. Late reset-like CLEU signals cannot recycle an overtime
row back to a fresh level-derived countdown; they may still confirm engagement for cleanup purposes.
Overtime requires a current nameplate, target, or focus observation token; an unobservable GUID retires
at its nominal boundary instead of lingering until unrelated player combat ends.
There is no frame `OnUpdate`: the display joins `ns.Cadence` at 10 Hz only while at least one timer exists.
Confirmed timers, plus estimated timers after they cross zero, require 0.60 seconds of stable explicit
disengagement before removal, preventing a single bad API sample from tearing down and recreating a visible row. A separate acquisition token can briefly join the same shared Cadence at 10 Hz for at most 1.5 s
around combat entry (or 0.75 s after an in-combat nameplate add), then removes itself even if no timer
was found. With zero timers outside that short admission window, the display shows a static
`No tracked enemies` line during combat and Cadence is parked for this feature. Combat end, feature
disable, Movers disable, or mover hide unregisters CLEU/events and removes both cadence clients.

### 7.3 `OnUpdate`

A frame `OnUpdate` is **not** the standard mechanism for periodic TurboFace work.
At high client FPS even an accumulator that returns immediately can become a
major source of C-to-Lua dispatch overhead.

Use `ns.Cadence` (§4.5a) for work that has a real frequency requirement: 1 Hz,
4 Hz, 10 Hz, 20 Hz, 30/33 Hz, or 60 Hz. Use `ns.Timers` for scalable per-widget
aura/debuff countdowns.

A direct `OnUpdate` is justified only when the behavior genuinely needs rendered-
frame synchronization or exists solely during a short interactive state. Current
examples include mover/minimap dragging, an active taxi/flight animation, and the
Hearth batching interaction. Those scripts must be installed/shown only for the
active interaction and removed/hidden immediately afterward.

Do not write this pattern for a periodic task:

```lua
frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.10 then return end
    acc = 0
    DoTenHzWork()
end)
```

Register the 10 Hz job with `ns.Cadence` instead.

### 7.4 Tickers

Feature modules should normally register with `ns.Cadence` rather than creating
independent high-frequency `C_Timer.NewTicker` objects. The scheduler centralizes
periodic dispatch and cancels its native clock when empty.

A dedicated low-frequency ticker remains acceptable when it is truly feature-
local, demand-gated, and simpler than joining the scheduler. The Class Buff
reminder's 0.5-second ticker is the canonical example; it exists only while
self/test reminder evaluation is needed and is cancelled when inactive.

### 7.5 One-way hooks

`hooksecurefunc` cannot be removed. Therefore:

- install it lazily if possible;
- install it only when the startup setting needs it;
- make the callback cheap;
- predicate-gate callbacks whose owner can later become inactive;
- mark the setting `/reload`-required if true teardown is impossible.

---

## 8. Persistent external-state ownership

TurboFace must never “restore” a persistent game setting by guessing Blizzard's default.
If TurboFace temporarily overrides a CVar, it must restore the exact value that existed
before TurboFace took ownership.

### 8.1 CVar ownership API

`Core/Config.lua` owns:

```lua
ns.ApplyOwnedCVars(owner, active, values)
ns.ReleaseOwnedCVars(owner)
ns.ApplyOwnedCVarBits(owner, active, values)
ns.ReleaseOwnedCVarBits(owner)
```

Ownership snapshots live in:

```text
TurboFaceCacheDB.cvarOwners
TurboFaceCacheDB.cvarBitOwners
```

Behavior:

1. first activation captures the current CVar value once;
2. TurboFace enforces its desired value while active;
3. deactivation restores the captured value;
4. ownership record is removed after restoration.

Scalar ownership captures the whole CVar. Bitfield ownership captures and restores only
the requested indexes. The helpers skip unknown/removed CVars, verify writes by reading the
result back, and retain failed restore debt for a later retry instead of silently discarding it.

The snapshot persists across reloads and client builds so TurboFace cannot strand an
override merely because the game patched while a feature was enabled.

### 8.2 Current owned CVar groups

Ownership is used for TurboFace-managed settings such as:

- screen glow;
- death/nether screen effects;
- weather density;
- camera max zoom;
- rested-area emote sounds;
- audio output synchronization;
- the Enemy bit of `nameplateStackingTypes`;
- nameplate max distance;
- nameplate overlap values.

For 1.15.9, TurboFace owns only the Enemy stacking bit; Friendly stacking remains a user/
Blizzard setting. Nameplate visibility CVars, including `nameplateShowEnemies`,
`nameplateShowFriendlyPlayers`, and `nameplateShowFriendlyNpcs`, are Blizzard/user-owned.
Upgrade cleanup releases any `nameplates.visibility` snapshot captured by older builds and never
takes that ownership again. The removed scalar CVars `nameplateMotion`, `nameplateShowFriends`,
and `nameplateAllowOverlap` are pruned from stale ownership records.

`nameplateSize`, `nameplateStyle`, native scale/alpha settings, `nameplateInfoDisplay`,
`nameplateCastBarDisplay`, `nameplateThreatDisplay`, and native aura-display bitfields remain
Blizzard/user-owned. `nameplateShowCastBars` is read-only and must never be written.

Do not add direct persistent `SetCVar` behavior that bypasses ownership unless the
setting is explicitly intended to be permanent user configuration.

### 8.3 Retired external-nameplate ownership cleanup

TurboFace does not change Questie's nameplate offset. Upgrade compatibility keeps only a one-time
restoration path for `TurboFaceCacheDB.questieOwners.nameplateXCaptured` written by older builds.
When Questie becomes available, TurboFace restores the exact captured `profile.nameplateX`, asks
Questie to redraw its icons, and deletes the ownership record. No new Questie ownership is created.

---

## 9. Shared namespace and public contracts

Modules communicate through the addon-local namespace `ns` rather than new globals.
Important owners include:

```lua
ns.API
ns.defaults
ns.DB_VERSION
ns.CLEU
ns.Cadence
ns.Timers
ns.ProfessionData
ns.NP
ns.UF
ns.PartyAuras
ns.ST
ns.Castbars
ns.Power
ns.RegenTicks
ns.DotPrediction
ns.HealPrediction
ns.CombatMeter
ns.DPSBadge
ns.PetHappiness
ns.Movers
ns.DruidPowerBar
ns.ClassBuffs
ns.Inv
ns.NW
ns.HS
ns.Tracker
ns.XP
ns.Loot
ns.PlusAutomation
ns.PlusSocial
ns.PlusInterface
ns.PlusSystem
ns.PlusChat
ns.PlusFlight
```

Expose narrow integration methods instead of sharing internal tables. Examples:

```lua
Power:RefreshMarkers()
Movers:RegisterElement(...)
PartyAuras:Refresh()
ClassBuffs:Init()
```

Avoid creating two owners for the same Blizzard frame or saved setting.

### 9.1 Shared helper functions

These exist once and must not be re-implemented locally. Every one of them
replaced two or more byte-identical copies:

| Helper | Owner | Purpose |
| --- | --- | --- |
| `ns.DB()` | `Core/Config.lua` | saved-variable root, never nil. Alias it as `local DB = ns.DB` |
| `ns.Opt(key, default)` / `ns.SetOpt` | `Core/Config.lua` | **flat** `TurboFaceDB` key access. Not a gate — use `ns.ModuleEnabled` for that |
| `ns.IsNameplateUnit(unit)` | `Core/Config.lua` | `"nameplate1".."nameplateN"` test |
| `ns.GetFont(name)` / `ns.GetFontPath(name)` | `Core/Config.lua` | Blizzard-native font resolver; accepts only TurboFace's four stock font choices/aliases and falls back to Blizzard Default |
| `ns.GetTexture(name)` | `Core/SharedMedia.lua` | LibSharedMedia-backed statusbar resolver |
| `ns.GetFontOptions()` | `Core/Config.lua` | Public font catalog: Blizzard Default/Narrow/Quest/Combat only |
| `ns:StyleFont(...)` / `ns:StyleFeatureFont(...)` | `Core/Config.lua` | Central renderer for feature-local face/style ownership; assigns cached runtime FontObjects so Outline/Shadow/None follow Blizzard-native FontObject styling |
| `ns.ResolveStatusBarTexture(name)` | `Core/SharedMedia.lua` | Alias of `ns.GetTexture`; `ns:GetFontPath(name)` remains a styling wrapper |
| `ns.RegisterUnitEvent(f, ev, u1, u2)` | `Core/Config.lua` | C-side unit filtering (§7.1) |
| `ns.MoverDependentEnabled(on)` | `Core/Config.lua` | the Movers dependency gate. **Pass a real boolean** (§5.1) |
| `ns.MoversEnabled()` | `Core/Config.lua` | bare Movers master state, for the §5.2 exceptions |
| `ns.Cadence` | `Core/Config.lua` | the single native periodic scheduler (§4.5a, §4.5b) |
| `ns.KillTrace(prefix, event, fn, ...)` | `Core/CPUProfiler.lua` | post-kill measurement boundary (§21.5) |
| `ns.Timers` | `Core/Config.lua` | shared per-widget tick driver (§4.5a) |
| `ns.API.IsKnownSpellID(id)` | `Core/Compat.lua` | trained **or** talent/form-granted |
| `ns.API.GetPlateUnitToken(plate)` | `Core/Compat.lua` | a plate's unit token (§11.11) |
| `ns.CreateTextureBorder(parent, t)` | `Nameplates/Nameplates.lua` | the shared/legacy border implementation (§11.13) |

Modules that own a **nested** settings block (`ExperienceBar`, `LootFrame`,
`Movers`, `PowerCost`) keep their own `DB()`: theirs also creates the sub-table
and merges defaults into it, which `ns.DB()` deliberately does not do.

### 9.2 Typography ownership

TurboFace ships **no font files**. Public font dropdowns expose four portable aliases --
**Blizzard Default**, **Blizzard Narrow**, **Blizzard Quest**, and **Blizzard Combat** --
which resolve through Blizzard-owned FontObjects at runtime so the client supplies the
appropriate font for its locale. Typography is completely independent of LibSharedMedia:
unknown/external font names normalize to Blizzard Default, and external registrations never
enter TurboFace's font dropdowns or built-in presets. LibSharedMedia remains only for statusbar
and border media.

There is no addon-wide Font or Text Style preference and no user-facing `INHERIT` state.
Configuration ownership is feature-local while rendering remains centralized:

- most nested owners use `font` / `textStyle` in their own tables (`auras`, `experienceBar`,
  `lootFrame`, `speedrunSplits`, `power`); Unit Frames deliberately split typography by role:
  `unitframes.nameFont` / `nameTextStyle` / `nameFontSize` own Player/Target/ToT/Pet/Party names,
  while `unitframes.barFont` / `barTextStyle` / `barFontSize` own ordinary HP/Power value text.
  Shield Bars are an independent numeric presentation and own the legacy profile keys
  `unitframes.nanShieldFont` / `nanShieldTextStyle` / `nanShieldFontSize` for both Player and Priest Party shield values;
- flat singleton/feature-family owners use explicit pairs such as `hearthFont` / `hearthTextStyle`,
  `combatMeterFont` / `combatMeterTextStyle`, `swingTimersFont` /
  `swingTimersTextStyle`, and `classFont` / `classTextStyle`; the generic Class pair owns reactive
  indicators and class-buff reminder text, while the Druid Power Bar owns its dedicated
  `druidPowerBarFont` / `druidPowerBarTextStyle` pair and `druidPowerBarTextSize`;
- Player regen tick amounts use `power.tickFont` / `power.tickTextStyle`, independent of
  Hotbar Power counter typography;
- intentionally artwork-like or Blizzard-owned text remains fixed: native nameplate names,
  TurboFace's supplemental name/title text, Threat Number, the DPS/HPS badge, Free Bag Slot Counter,
  FPS counter, mover labels, Trainer/Plus Blizzard text, and other documented fixed surfaces.

`ns:StyleFont()` is the single renderer for nested/fixed call sites and
`ns:StyleFeatureFont()` is the convenience wrapper for flat feature keys. Classic Era's Blizzard
unit-frame fonts establish shadow through FontObject inheritance (`PlayerName -> GameFontNormalSmall
-> SystemFont_Shadow_Small`), so TurboFace mirrors that model with cached runtime FontObjects keyed
by face/size/style. **Shadow** uses Blizzard's native FontObject shadow mechanism with a black `2,-2` TurboFace offset (Blizzard's stock `SystemFont_Shadow_Small` reference is `1,-1`); **Outline** uses
the font's `OUTLINE` flag with shadow disabled; **None** disables both. `SetFontObject()` is the normal
application path; direct FontString `SetShadow*()` is only a defensive fallback. Do not recreate
duplicate black shadow FontStrings for TurboFace text: the same FontObject-owned shadow is used by
fixed Shadow surfaces such as Threat Number, FPS Counter, and Free Bag Slots. UnitFrame names
are no longer a fixed artwork exception: their face/style are independently configurable from
bar/value text, allowing Blizzard Default + Shadow names alongside Blizzard Narrow + Outline
values without cross-coupling.

Schema 64 retires the former `globalFont`, root `textStyle`, and `auraTimerFont` keys. This
schema boundary predates the public release, so development-era profiles are not promised visual
fidelity across the typography cutover; missing or invalid local values merge to the canonical
feature defaults, and unknown font names normalize to Blizzard Default. Schema 65 adds the
standalone Speedrun-owned `fpsCounterEnabled` feature gate. Schema 66 splits UnitFrame Name and
Bar typography ownership; the public factory defaults are Blizzard Default + Shadow for names and
Blizzard Narrow + Outline for bar/value text. Schema 67 gives Party, Pet, and ToT independent
Name Text Size and Bar Text Size ownership while retaining the shared Name/Bar font and style
families. Schema 68 gives the Class-owned Druid Power Bar its own font/style/size/format settings,
including `Percent Current (Blizzard)`. Schema 69 gives NanShield feature-local typography and
enables its formerly inaccessible factory-disabled absorb number. The dated Rumblecrush preset is
authored against schema 68 and upgrades through the normal ordered migration path.

---

## 10. Source layout and module ownership

The root directory is reserved for the addon entry point and genuinely standalone
features. Multi-file subsystems live in folders so source location mirrors runtime
ownership. Do not create one-file folders merely for symmetry.

```text
TurboFace/
├── Core/          shared config/defaults/migrations/profiles/media/metadata
├── Nameplates/    Blizzard-native nameplate augmentation, auras, threat, and swing information
├── UnitFrames/    Blizzard unit-frame restyle, predictions, absorb/Druid-power surfaces
├── Combat/        prediction engines, swing timers, class combat features, meter
├── Power/         hotbar power-cost overlay + player regen/tick engine
├── Inventory/     junk/bag/grocery/net-worth ownership
├── Movers/        mover registry and integrations
├── Plus/          TurboFace utility/social/map/chat/system/flight modules
├── Trainer/       training engine/UI, MIT class/pet seeds, and live trainer discovery
├── Options/       configuration UI
├── Libs/          embedded libraries
└── Core.lua       login/init and central nameplate lifecycle entry point
```

| File | Primary ownership |
|---|---|
| `Core/Compat.lua` | 1.15.9 API normalization and patch-day compatibility helpers |
| `Core/Config.lua` | runtime config APIs, module gates, CVar ownership, shared helpers, CLEU, `ns.Cadence`, `ns.Timers` |
| `Core/Defaults.lua` | the canonical `ns.defaults` schema only |
| `Core/Migrations.lua` | DB versioning, migrations, saved-variable repair/load |
| `Core/ProfessionData.lua` | locale-safe Classic profession identity/name/icon/secondary metadata shared by Trainer and Skills |
| `Core/Debug.lua` | lightweight diagnostics, SafeCall, counters, compatibility/module probes |
| `Core/CVarBrowser.lua` | lazy developer CVar browser; client-registry enumeration, search, metadata, paged copy export, optional per-character SavedVariables snapshot, direct SetCVar/default testing |
| `Core/CPUProfiler.lua` | opt-in function profiler, always-on native metric helpers, baselines, and hostile-death/post-kill tracing |
| `Core/Profiles.lua` | profiles, presets, import/export |
| `Core/SharedMedia.lua` | LibSharedMedia registration |
| `Core.lua` | login/init chain, nameplate lifecycle maps, common plate handling |
| `QuickSetup.lua` | TurboFace-native fresh-character bootstrap, class-profile capture/restore, `TFL1QS1:` transfer, Level-1 cinematic skip |
| `Nameplates/Provider.lua` | shared nameplate substrate contract; Classic registers `classic-native` and preserves immediate Era update behavior |
| `UnitFrames/Provider.lua` | shared UnitFrame capability contract; Classic registers `classic-readable` and enables the historical prediction/NanShield/Druid auxiliary renderers |
| `Nameplates/TurboDebuffs.lua` | TurboFace-owned Classic Era priority-aura classifier and nameplate surface |
| `Nameplates/Auras.lua` | TurboFace-owned nameplate aura icons/pooling/countdown and unit-event batching |
| `Nameplates/Nameplates.lua` | current nameplate DB cache, native substrate resolution, aura-border helpers |
| `Nameplates/NameplateVisuals.lua` | additive DoT/absorb/health-linked overlays, combo dots, aura/quest augment refresh |
| `Nameplates/NameplateUnits.lua` | unit-event pipeline, full augmentation updates, quest indicators |
| `Nameplates/NativeNameStyle.lua` | Blizzard-native NPC/player name FontObject shadow amendment |
| `Nameplates/NativeHealthTextStyle.lua` | restricted-safe native health-text centering amendment |
| `Nameplates/NativeRarityIconStyle.lua` | Blizzard PvE rarity-texture right-edge anchor amendment |
| `Nameplates/BubbleNameplates.lua` | current additive Job Icon, Threat Number/Aggro Audio, swing strip, NPC power/effects, subtitle supplement, CVar ownership; historical filename only |
| `Nameplates/Stacking.lua` | tall-boss WorldFrame extension only; Blizzard owns actual stacking (§11.13) |
| `Combat/DotPrediction.lua` | empirical DoT timing/damage engine and consumer API |
| `Combat/HealPrediction.lua` | incoming-heal + next-HoT-tick prediction engine |
| `Combat/CombatMeter.lua` | lightweight local Current/Overall damage/HPS accounting engine + optional movable meter window |
| `Combat/DPSBadge.lua` | independent UIParent-owned, Blizzard-PlayerFrame-anchored DPS/HPS badge; headless CombatMeter consumer |
| `FPSCounter.lua` | standalone Speedrun FPS HUD + optional Hearthstone Batch estimate; mover-integrated, not mover-dependent |
| `Combat/LeashTimer.lua` | GUID-authoritative hostile-NPC leash countdown; filtered shared CLEU, threat/nameplate metadata, CC suppression, demand-driven cadence |
| `Combat/ClassFeatures.lua` | class-specific combat indicators such as Warrior Overpower |
| `Combat/ClassBuffs.lua` | self/party class-buff catalog/reminders |
| `Combat/SwingTimers.lua` | Global player/target swing engine plus the separately gated lightweight enemy-nameplate SWING state owner; shared standalone/embedded combat-timer stack placement |
| `Combat/SwingTimerSpellData.lua` | project-owned canonical spell-family identities and swing-interaction queries |
| `UnitFrames/UnitFrames.lua` | Blizzard Player/Target/ToT/Pet/Party restyle and shared UF behaviors |
| `PartyPetAuras.lua` | independent Blizzard Party/Pet-frame aura augmentation, party class reminders, expiry/reconcile drivers |
| `UnitFrames/Predictions.lua` | DoT/heal prediction overlays drawn onto unit-frame bars (§12.7) |
| `UnitFrames/DruidPowerBar.lua` | Class-owned Druid auxiliary Mana bar; embedded with TurboFace Player UF, standalone + mover otherwise |
| `UnitFrames/PetHappiness.lua` | Hunter Feed Pet happiness state sampler consumed by Class Buffs; historical source path, no UnitFrames runtime gate |
| `Combat/Castbars.lua` | standalone/embedded player/target castbars and optional Blizzard player-castbar suppression |
| `UnitFrames/ShieldData.lua` | TurboFace-owned Classic Era shield-family model, school palette, and direct-cast PW:S rank classification |
| `UnitFrames/nanShield.lua` | Shield Bar runtime: Player absorb estimate/reconciliation plus Priest-only direct-cast PW:S Party surfaces; legacy internal/API name retained for compatibility |
| `Power/PowerCost.lua` | action-button missing-power overlay/counter and shared power-event orchestration |
| `Power/RegenTicks.lua` | shared 2-second regen heartbeat, 5SR, Mana/Energy/Rage/HP markers and `+X` popups |
| `Inventory/InventoryManager.lua` | per-character Junk/Useful/Bank state, icons, auto-sell, bag valuation, hovered-item actions, bag-addon integration |
| `Inventory/Bank.lua` | bank-session events, batched marked-item deposits, all-stack withdrawal |
| `Inventory/Grocery.lua` | queued vendor consumables, grocery window, merchant auto-buy |
| `Inventory/NetWorth.lua` | money + junk-value display |
| `Inventory/BagSlots.lua` | free-bag-slot display |
| `Movers/Movers.lua` | mover registry, persistence, overlays, grid, drag behavior |
| `Movers/Auras.lua` | target/player aura mover integration |
| `Movers/Systems.lua` | tooltip/FPS/quest/loot/group-roll/system mover integrations |
| `Plus/*` | TurboFace automation/social/interface/map/system/chat/flight features |
| `Trainer/*` | training engine, capture, queue, Spellbook class/general-skill UI, MIT class/pet seeds, live profession/recipe discovery |
| `Skills.lua` | skill scanner/HUD; consumes `Core/ProfessionData.lua`, not Trainer internals |
| `Options/OptionsGUI.lua` | lazy configuration UI and apply paths |
| root singleton files | Hearthstone/batching, minimap widgets, AuraStyle, XP, LootFrame |
| `Bindings.xml` | Junk & Inventory and Grocery List keybinding declarations |

### 10.1 Folder rule

Create a folder when **two or more files share one lifecycle/ownership domain** or when a
large file is split along an established API seam. Keep independent singleton features
at root until they actually gain siblings. Folder movement by itself is not a runtime
optimization and must never be used as justification for changing behavior.

### 10.2 Neutral metadata rule

Shared catalogs that identify game concepts belong under `Core/` (or a subsystem-neutral
data owner), not under the first feature that happened to need them. Profession metadata is the precedent: Trainer and Skills both consume
`ns.ProfessionData`; Skills must not depend on Trainer being active merely to recognize
Alchemy, Fishing, etc. The catalog itself builds lazily on first use, so moving it to a
neutral owner does not add unconditional profession-spell lookups at login.

## 11. Nameplate architecture

### 11.0 North star: one Blizzard plate, additive TurboFace information

TurboFace has **no replacement nameplate renderer**. Classic Era 1.15.9 Blizzard FrameXML owns
the pooled NamePlate root and its normal `UnitFrame`. TurboFace may attach its own unprotected
children or make a narrowly scoped, reversible presentation amendment, but it must never create a
second normal name/health/cast chassis.

If the expected Blizzard native health substrate cannot be resolved, the correct behavior is to
**fail open**: hide/park the TurboFace augmentation host and leave the Blizzard plate untouched.
Do not resurrect a synthetic fallback plate.

The persisted settings table is still named `bubbleNameplates` for profile compatibility. Current
runtime caches are `c_nameplate*`; the historical table name does not imply Bubble-era baseline
ownership.

The multi-client source tree now routes substrate-specific scheduling through
`Nameplates/Provider.lua`. On Classic, the `classic-native` provider is the active implementation:
legacy TurboFace aura rows remain valid, target/faction/heal/power updates retain the historical
immediate Era behavior, and zero-delay batching uses Classic's native timer path. The shared
Nameplate event/render files therefore need no Forever build checks while Classic semantics remain
unchanged.

#### Ownership matrix

| Surface | Owner | TurboFace contract |
|---|---|---|
| NamePlate creation/pool/unit binding/root geometry | Blizzard | Observe lifecycle only. Never reposition the restricted plate root. |
| `HealthBarsContainer.healthBar` | Blizzard | Canonical HP StatusBar. TurboFace overlays DoT/absorb/heal/spend information on it. |
| Normal health art/color/value | Blizzard | Do not recolor/retexture/replace as a baseline skin. |
| Native health text content/font/color/visibility | Blizzard | Optional TurboFace centering changes anchors only, using restricted-safe write policy. |
| `CastBarsContainer` / native castbar | Blizzard | No TurboFace nameplate castbar replacement exists. |
| Normal unit name + level | Blizzard | Preserve native text. TurboFace may apply the independent FontObject shadow amendment and NPC title supplement. |
| Classification art | Blizzard | No TurboFace elite/rare/worldboss replacement art. The optional rarity-icon setting moves only Blizzard's existing PvE texture to the chassis right edge. |
| Raid-target marker | Blizzard | No TurboFace duplicate raid-marker texture or raid-marker option. |
| Hover / target highlighting and target scale | Blizzard + CVar preference | No TurboFace target arrows/glow or mouseover recolor/intersect-alpha engine. TurboFace may reversibly set Blizzard's selected scale/alpha CVars from the explicit Nameplates sliders. |
| Plate positioning / anti-overlap | Blizzard | `nameplateStackingTypes`/overlap CVars only; no Lua-side plate-position solver. |
| Friendly identity-only presentation | Hybrid | Blizzard name survives; TurboFace selectively suppresses non-identity native chassis and may add NPC title/Job Icon. |
| Job Icon | TurboFace | Independently gated friendly-NPC service/profession glyph anchored to visible native name edge. |
| Name Text Shadow | TurboFace | Temporary private FontObject with Blizzard's live face/size/flags plus black `2,-2` shadow; restored to Blizzard's original FontObject when inactive. |
| Threat Number | TurboFace | Quantitative hostile-NPC threat text only; independent of native threat art. |
| Aggro Audio | TurboFace | Current-target/group transition audio; no health-color engine. |
| Nameplate Swing Timer | TurboFace | Independent full-chassis hostile attack timing strip. |
| NPC power | TurboFace | Additive resource strip, optionally embedded in bottom of native HP bar. |
| DoT / absorb / incoming-heal / spend effects | TurboFace | Additive overlays whose geometry derives from the native HP substrate. |
| Nameplate auras / TurboDebuff | TurboFace | TurboFace icon rows remain additive; normal Blizzard full-plate aura region is suppressed only where TurboFace owns the replacement row. |
| Quest indicators / combo dots / reactive class indicators | TurboFace | Additive child regions only. |

### 11.1 Master gate and runtime boundary

The `nameplates` module gate owns all TurboFace nameplate runtime. A reload is the clean boundary for
changing the master gate. Starting disabled must not activate the core plate event pipeline, unit
events, combo cadence, swing renderer, TurboDebuffs, tall-boss extension, or owned nameplate CVars.
`BubbleNameplates:ApplyNameplateCVars()` may still run once while disabled to repay persistent CVar
ownership captured by a previous enabled session/build.

Individual live options remain independently gated:

- `bubbleNameplates.centerHealthText` / `centerHealthTextOnNameplate`;
- `bubbleNameplates.rarityIconRight`;
- `bubbleNameplates.nameTextShadow`;
- `bubbleNameplates.friendlyNPCNameTitleOnly`;
- `bubbleNameplates.friendlyPlayerDamagedOnly`;
- `bubbleNameplates.friendlyNPCDamagedOnly`;
- `bubbleNameplates.jobIcon`;
- `bubbleNameplates.threatNumber`;
- `bubbleNameplates.swingTimer`;
- `bubbleNameplates.powerBarOverlap` / `powerBarHeightPct`;
- `bubbleNameplates.overlapV` / `overlapH`;
- `bubbleNameplates.selectedScale` / `selectedAlpha` / `notSelectedAlpha`;
- Aggro Audio mute/gain/loss settings;
- top-level `showComboPoints`;
- current quest/aura/TurboDebuff settings.

### 11.2 Lifecycle maps: direct native ownership, no adapter layer

`Core.lua` owns the direct mapping from Blizzard pooled frames to TurboFace augmentation state:

- `unitToNameplate[unit]` -> Blizzard NamePlate root;
- `unitToNameplateGUID[unit]` / `guidToNameplateUnit[guid]` -> identity bookkeeping;
- `unitToPlate[unit]` -> TurboFace augmentation host **only while full augmentation is active**;
- `nameplate.myPlate` -> reusable TurboFace augmentation host attached to the pooled Blizzard root.

There is no `NameplateAdapter` component registry. Consumers resolve the live native substrate from
`nameplate.UnitFrame` directly. Pooled unit changes clear stale unit/GUID mappings before the frame is
reused.

The player's own personal nameplate stays completely Blizzard-owned and is not mapped into the
TurboFace full-augmentation path.

### 11.3 Full-native plate path

`Nameplates/Nameplates.lua:EnsureFullPlate()` resolves only Blizzard's native health bar. It never
constructs a fallback health/name/level/cast surface. When successful it stores the native HP bar as
`myPlate.hp` and lazily attaches TurboFace-owned overlay textures as needed. When resolution fails,
`FullPlateUpdate()` parks the augmentation host and removes its hot `unitToPlate` mapping.

`ConfigureNativeNameplateChassis()` begins by restoring Blizzard's captured baseline presentation,
then suppresses Blizzard's native aura row **only when the TurboFace Auras module is active**. If
`modules.auras` is disabled, Blizzard keeps its native aura row untouched. Normal name, level, health,
cast, classification and raid-marker surfaces remain Blizzard-owned.

### 11.4 Friendly presentation modes

Friendly special modes are policies on the **same native Blizzard plate**, not alternate renderers.
Eligibility excludes pets/player-controlled non-player units and the player's own plate.

#### Friendly NPC: Name + Title Only

`bubbleNameplates.friendlyNPCNameTitleOnly` uses a hybrid identity cluster:

- Blizzard owns the NPC name and pooled lifecycle;
- TurboFace applies Blizzard's known show-only-name anchor policy with an additional 10px downward
  offset, using write-only native anchor calls;
- TurboFace renders the cached/scanned NPC title 1px below the native name;
- the title is inherent to this mode and does not depend on the ordinary subtitle setting;
- the native health/cast/art/classification/level/aura/soft-target chassis is selectively
  alpha-suppressed rather than hiding the whole UnitFrame; Blizzard keeps the raid marker;
- the TurboFace full augmentation host is parked and removed from `unitToPlate`;
- independently enabled Job Icon stays root-owned and visible.

Blizzard may re-run `UnitFrame:UpdateAnchors()` on pooled plates; TurboFace's post-hook reasserts only
this mode's write-only 10px amendment. Releasing the mode disables the amendment first and returns
anchor ownership to Blizzard.

#### Friendly Player / NPC: Show Only When Damaged

Both damaged-only options share one native two-state machine:

1. **Full health:** preserve Blizzard identity, suppress non-identity chassis, park/remove the
   TurboFace full host from `unitToPlate`.
2. **Damaged:** release native suppression, restore Blizzard's complete chassis, remap/show the
   TurboFace host, and perform one full augmentation rebuild.
3. **Healed to full:** return to the identity-only state.

The health batch evaluates the nameplate unit token directly so a full-health identity plate can be
completely absent from `unitToPlate` yet still react immediately when it takes damage. If NPC
Name + Title Only is also enabled, its TurboFace title remains in the full-health identity state.

### 11.5 Restricted-region rules

Native nameplate regions can reject geometry reads on Classic 1.15.9. Therefore:

- do not call `GetPoint`, `GetLeft`, `GetRight`, `GetTop`, `GetBottom`, or equivalent measurements on
  restricted Blizzard name/plate regions as a prerequisite for a feature;
- friendly identity name movement mirrors Blizzard's known anchor policy and writes the adjusted
  anchors directly;
- Job Icon visible-edge placement for the centered identity name measures `UnitName(unit)` on a
  hidden TurboFace-owned FontString using Blizzard's live font rather than measuring the native
  FontString geometry;
- native health-text centering is also an anchor-only amendment with its own restricted-safe state;
- native rarity positioning writes only the Blizzard `classificationIndicator` texture anchors; it
  leaves `ClassificationFrame` in place because Blizzard's buff-list layout also depends on that frame;
- TurboFace-owned children may be measured normally.

### 11.6 Native name shadow styling

`bubbleNameplates.nameTextShadow` uses the same Classic-native FontObject shadow mechanism proven by
the typography refactor. TurboFace clones the live Blizzard nameplate font face/size/flags (including
`SLUG`) into a private runtime FontObject, adds a black `2,-2` shadow, and assigns that complete
FontObject to the Blizzard-owned name FontString. The previous mirrored-glyph underlay is retired.
It applies to eligible enemy/friendly NPC and player names, including both states of Friendly Player
damaged-only. Pets/guardians/player-controlled non-player units and the player's personal plate are
excluded. TurboFace does not replace the native text, color, alpha, or lifecycle; it only swaps the
FontObject presentation while the option is active and restores Blizzard's original FontObject on exit.

### 11.7 Job Icon

`bubbleNameplates.jobIcon` is independent of Friendly NPC Name + Title Only, Threat Number and Swing
Timer. Job classification uses the existing NPC ID/title/name rules and title cache. The icon frame is
owned by the Blizzard nameplate root so it can survive while the TurboFace full host is parked.

On ordinary full-native plates it anchors beside Blizzard's native name region. On the centered
identity-only layout, the native FontString spans the whole chassis, so TurboFace measures the visible
name text on its own hidden FontString and places the icon at `name CENTER - halfTextWidth - 4px`.
No native geometry read is used.

### 11.8 Threat Number and Aggro Audio

The retired tank/DPS health-color threat engine is gone. There is no off-tank/Vigilance color palette
or TurboFace health recoloring.

`bubbleNameplates.threatNumber` owns only hostile-NPC quantitative text. Enemy players and
player-controlled pets/guardians are explicitly excluded even when their plates enter the shared
threat-event refresh path. Color is derived from the
rounded integer the player actually sees: green <=30, yellow 31-70, orange 71-99, red exactly 100,
then orange/blue/purple overcap bands. The number is a single colored FontString using TurboFace's
native FontObject-owned black `2,-2` shadow; the old duplicate black glyph is retired. Aggro Audio is independent of whether the number is visible and
only retains transition state for the current target when group audio has demand. Threat API work is
skipped when neither consumer needs it. While either consumer has demand, Blizzard's
`UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` events feed a 0.05-second deduplicated
nameplate batch; this is the additive threat-state refresh path, not a return of the retired
health-color engine. The threat events park when Threat Number is hidden and grouped Aggro Audio has
no demand.

### 11.9 NPC power and health overlays

NPC power is additive and never replaces Blizzard HP ownership. **Overlap Power Bar** is the
presentation and runtime-demand gate: with `powerBarOverlap=true`, the resource fill occupies the
configured fraction of the bottom of the live native HP bar. When unchecked, TurboFace does not
query NPC power, create or update a resource holder, or subscribe to nameplate power events; the
former development-only separate row beneath the native chassis is retired.

DoT prediction, absorb, incoming-heal and spend effects attach to the native HP substrate. Their
textures are TurboFace-owned children; Blizzard still owns the actual StatusBar min/max/value, health
texture, border and color. Geometry caches must be invalidated when Blizzard changes nameplate size or
style. The DoT texture renderer is an explicit DotPrediction consumer: aura invalidation, target-token
alias invalidation, and newly learned periodic ticks repaint the current GUID-validated nameplate
deterministically. A newly bound plate gets one delayed settle pass, and placeholder native HP width
can request at most three additional 50 ms retries. Health events continue to reposition the region
as the native value changes; none of these safeguards is a permanent renderer ticker.

### 11.10 Auras and TurboDebuffs

TurboFace still owns its nameplate aura presentation. `Nameplates/Auras.lua` owns the compact
buff/debuff rows, filtering, pooling, sorting, shared 0.25s countdown presentation, and batched
unit-aura refreshes. Aura placement derives from native font metadata and known layout policy; it
does not measure restricted native-name geometry. `Nameplates/TurboDebuffs.lua` owns the priority aura surface. Its classification data is a TurboFace-owned Classic Era catalog of high-information control/cooldown spell families. One canonical Blizzard spell/effect ID is used only to resolve the localized aura name at runtime, so rank variants collapse naturally without rank-by-rank ID dumps or parent-alias graphs. TBC/Wrath/private-server entries are intentionally outside this catalog. The legacy `interrupts` profile category remains for compatibility, but aura-only TurboDebuffs does not claim to represent Classic school lockouts until a future CLEU-backed producer exists. Normal full-native
chassis mode suppresses Blizzard's competing aura row **only while `modules.auras` is active**; if
the Auras module is disabled, Blizzard's native aura row is left alone. This is a narrow exception
and does not imply ownership of the rest of the native plate.

Countdown presentation is ceiling-rounded with seconds below 90s, minutes from 90s, hours from one
hour, and no decimal sub-second phase.

### 11.11 Swing timing and combo dots

Nameplate Swing Timer is independently gated by `bubbleNameplates.swingTimer` and does not depend on
Global Swing Timers or Threat Number. The swing-state producer observes real hostile swings; the
renderer runs at about 30 Hz only while active frames exist. An engaged hostile with no observed swing
may present the ready state, but combat entry must not fabricate a cooldown.

Top-level `showComboPoints` owns the small target-nameplate combo dots for classes that use them.
Their cadence exists only while a valid target plate and combo-capable class require it.
Classic Era combo capacity is a Nameplates substrate constant (`ns.NP.MAX_CP = 5`); `NameplateVisuals.lua` also retains a local fallback of 5 so a future split/load-order regression cannot crash and evict the combo cadence client.

### 11.12 Quest indicators and reactive class indicators

Quest icons and reactive class indicators are additive. They anchor to Blizzard identity regions or
the native health substrate and must not create replacement name/level text. Quest refreshes remain
throttled because Classic quest APIs can settle after the initial event.

### 11.13 Blizzard stacking/CVar ownership and tall bosses

TurboFace does not position nameplates in Lua. Blizzard owns stacking. The Nameplates module owns only
its documented CVar contract through reversible CVar ownership helpers:

- Enemy bit of `nameplateStackingTypes`;
- `nameplateOverlapV` / `nameplateOverlapH` from the Nameplates overlap options;
- `nameplateSelectedScale`, `nameplateSelectedAlpha`, and `nameplateNotSelectedAlpha` from the
  Nameplates selection-presentation options;
- the retained geometry minimum for `nameplateMaxDistance`.

Disabling the module restores captured user values rather than merely stopping writes. Legacy
visibility/Questie release helpers in `BubbleNameplates.lua` exist only to repay snapshots captured by
older TurboFace builds; they never acquire new legacy ownership and become inert once debt is cleared.

`Nameplates/Stacking.lua` no longer contains a stacking engine. It owns only the tall-boss WorldFrame
extension: WorldFrame is made vertically taller so very tall models whose native nameplate anchor
would otherwise fall above the screen can still receive a Blizzard plate. Do not reintroduce
restricted-frame coordinate reads or a Lua anti-overlap solver.

### 11.14 Current file ownership

| File | Current responsibility |
|---|---|
| `Core.lua` | Blizzard nameplate lifecycle maps, pooled baseline capture/restore, friendly native suppression modes, supplemental root-level NPC title |
| `Nameplates/Nameplates.lua` | live DB cache, native substrate resolution, aura-border helpers, full-host native HP binding |
| `Nameplates/NameplateUnits.lua` | nameplate unit-event batching, full augmentation update, quest indicators |
| `Nameplates/NameplateVisuals.lua` | additive DoT/absorb/health-linked overlays, combo dots, aura/quest augmentation refresh |
| `Nameplates/NativeNameStyle.lua` | native-name FontObject shadow amendment |
| `Nameplates/NativeHealthTextStyle.lua` | optional restricted-safe native health-text centering |
| `Nameplates/NativeRarityIconStyle.lua` | optional Blizzard PvE rarity-texture right-edge positioning |
| `Nameplates/Auras.lua` | pooled nameplate aura rows and timer/layout batching |
| `Nameplates/TurboDebuffs.lua` | TurboFace-owned Classic Era priority-aura classifier and nameplate surface |
| `Nameplates/BubbleNameplates.lua` | current additive Job Icon, Threat Number/Aggro Audio, swing strip, NPC power/effects, subtitle supplement, nameplate CVar ownership; historical filename only |
| `Nameplates/Stacking.lua` | tall-boss WorldFrame extension only |

There is intentionally **no** `NameplateAdapter.lua`, `NameplateThreat.lua`, or Nameplates-specific
`Castbars.lua`. Blizzard owns the substrate directly.

### 11.15 Validation contract

For nameplate changes, static success is necessary but not sufficient. Validate in the live Classic
client:

- ordinary hostile NPC and enemy-player full native plates;
- friendly NPC/player full-health -> damaged -> full-health transitions;
- Friendly NPC Name + Title Only, including title cache refresh and the 10px native-name offset;
- Job Icon beside short/long centered names and ordinary full-native names;
- native name shadow on NPC and player plates;
- target switching, pooled-frame reuse, faction changes, and plates appearing before/after login;
- Blizzard raid marker, classification art, castbar, hover and target presentation remain intact;
- native health-text centering on supported Blizzard styles;
- Threat Number/Aggro Audio and independent swing timer;
- NPC power embedded/separate modes;
- DoT/absorb/heal overlays, aura rows/TurboDebuff, quest icons, combo dots;
- no protected-action errors, restricted-region measurement errors, taint, or persistent mutation after
  the Nameplates module is disabled/reloaded.

## 12. Unit Frames architecture

TurboFace restyles Blizzard frames rather than replacing the entire secure unit-frame
system.

### 12.0 UnitFrames is split below the Lua local ceiling

Lua 5.1 allows **200 active local variables per function**, and a file's main chunk is a
function. The former monolithic UnitFrames file reached that ceiling. The organizational
pass removed the largest natural seam instead of relying on local-budget tricks:

- `UnitFrames/UnitFrames.lua` owns Blizzard frame layout/styling and the UF lifecycle.
- `UnitFrames/Predictions.lua` owns only DoT/heal rendering.
- `PartyPetAuras.lua` is deliberately outside UnitFrames: it owns Party/Pet buff/debuff
  widgets, Party class reminders, cooldown text/pulse state, dedicated C-filtered aura
  event boundaries, and low-frequency freshness reconcilers. It can run against stock
  Blizzard Party/Pet frames or against TurboFace-restyled frames.

`PartyPetAuras.lua` owns its pooled-party-frame lookup chain instead of depending on
`ns.UF`. Its settings live under `TurboFaceDB.auras`, its runtime gates are
`modules.auras.party` / `modules.auras.pet`, and `Core.lua` initializes it independently
before ClassBuffs and UnitFrames. `UnitFrames/UnitFrames.lua` may call the narrow layout
API after applying fixed artwork so the same owned icons re-anchor to TurboFace art, but
UnitFrames never activates/deactivates the aura runtime.

This is now the preferred response to local-budget pressure: **move an ownership domain
into its own file** rather than adding more scoped-block gymnastics. A real Lua 5.1
compile remains a packaging requirement because the 200-local error is load-fatal.

**Do not hard-code local-budget headroom in this document.** Measure main-chunk local counts
with a Lua 5.1-aware check when reviewing a package; those values change as files move. Split
a real ownership domain before approaching the 200-local ceiling. The ceiling is a compile
constraint, not a file-size target: large files are acceptable when ownership is coherent and
their Lua 5.1 local budget remains safe.

`UnitFrames/Predictions.lua` calls prediction `RegisterConsumer` functions at file scope,
so it must remain after both prediction engines and after `UnitFrames/UnitFrames.lua`.

The multi-client tree now places UnitFrame-adjacent optional renderers behind
`UnitFrames/Provider.lua`. Classic's active `classic-readable` provider enables custom DoT/heal
prediction textures, NanShield reconstruction, and the Druid auxiliary power StatusBar, and resolves
the native Player health/power bars directly. Other client flavors may override those capability
decisions without adding client checks to the shared renderer files. The primary Classic
`UnitFrames/UnitFrames.lua` implementation remains the readable Era renderer and is not forced into
the protected/native Forever geometry contract.

### 12.1 Child isolation

The Unit Frames master contains independent gates for:

```text
Player
Target
Target of Target
Party
Pet
```

Shared styling helpers must check the relevant child before touching a Blizzard frame.
A disabled Target frame must not be styled merely because Party or Player is enabled.

Target-of-Target is an independent child. Do not implicitly couple it to the Target
child unless a specific feature truly requires Target.

The fixed ToT presentation uses `Textures/UnitFrames/UI-ToT-Portrait.tga`, a native **98×48**
composition stored in a transparent 128×64 canvas. The current artwork keeps the portrait at
`37×37` `(5,6)`, health `49×8` at `(45,17)`, and power `49×8` at `(45,28)`. Name placement is
presentation-only and user-selectable: Blizzard-style **below bars** is the default (`49×13` at
`(45,38)`, leaving a 3px gap below power), while `unitframes.totNameAboveBars=true` uses the
compact above-bars anchor at `(45,2)`. TurboFace may re-anchor these presentation regions only out
of combat; Blizzard retains secure ToT visibility, unit assignment, portrait selection, and click behavior.

### 12.1a Pet fixed-art ownership

The Pet child now uses `Textures/UnitFrames/UI-Pet-Portrait.tga` as a fixed **119×48**
composition, stored on disk in a transparent 128×64 canvas so Classic texture loading follows the
same padded-source convention as Party and ToT. TurboFace owns the decorative pet frame art, the
black backing behind the two bar openings, the fixed HP/power geometry, and the foreground value
text placement. The v3 artwork retains the active bar-fill geometry established with v2:
health `70×13` at `(45,8)`
and power `70×13` at `(45,22)`;
the portrait opening is `37×37` at `(5,6)`.
- Blizzard retains the Hunter-only `PetFrameHappiness` state, texture, and tooltip. TurboFace fits
  that icon above the fixed art at `17×16`, 0.5px left of the health opening and with its top
  2px above the health fill's top edge, so it remains within the pet frame.
- The native happiness icon remains a presentation-only Pet-frame child. Its separate reminder runtime
  belongs to Class Features (§16), not the protected Pet-frame layout.
- Pet fixed-art name placement is user-selectable. New/factory profiles default to the clear strip
  below the power bar (`unitframes.petNameAboveBars=false`, name top at artwork Y 37); enabling
  **Name Above Bars** uses the compact top anchor with its bottom 2px below the frame top reference.
  Schema 76 seeds profiles without an explicit choice to the new below-bars default.


Blizzard retains ownership of the live pet portrait, unit assignment, pet-state updates, and secure
click/hover behavior. TurboFace only re-anchors/resizes that portrait into the fixed art and applies
Blizzard's `TempPortraitAlphaMask`; it never substitutes a static portrait. Native `PetFrameTexture`,
flash, and attack-mode chrome are alpha-suppressed and pinned so Blizzard refreshes cannot bleed the
old shell through the new artwork. Pet health/power remain Blizzard StatusBars, rendered beneath the
TurboFace art with TurboFace-owned center-text overlays above it. Bar anchor guards restore the fixed
slots after Blizzard repositions them; protected geometry changes are deferred while in combat.

The historical `unitframes.hidePortrait` value is no longer a runtime ownership gate for Pet. The
fixed-art layout always retains the live portrait because the supplied art is designed around that
portrait opening.

### 12.1b Target classification artwork

The Target child selects one of four 256×128 fixed-art sheets without changing its established
geometry: normal, Elite, Rare, or Rare Elite. `UnitClassification("target")` maps `elite` and
`worldboss` to `UI-EliteTarget-Portrait.tga`, `rare` to `UI-RareTarget-Portrait.tga`, and
`rareelite` to `UI-RareEliteTarget-Portrait.tga`; every other value falls back to
`UI-Target-Portrait.tga`. Selection remains inside `ApplyTargetFrameArtTexture()`, whose recursion
guard and Blizzard classification post-hook already own native texture replacement. The
`PLAYER_TARGET_CHANGED` path also applies the selection explicitly so correctness does not depend
on Blizzard choosing to swap its texture for two consecutive targets of the same classification.
The three classified sheets have their pixels shifted 1px left inside their 256×128 canvases so their
active bar-border coordinates match the normal sheet while every consumer retains the shared
`TARGET_LAYOUT` geometry and one common texture anchor. This must be an asset correction: the live
health and power bars anchor to the art texture, so moving that texture would move art and bars together
without changing their relative alignment.

### 12.2 Protected ToT behavior

Target-of-Target is a protected `SecureUnitButton`. TurboFace owns only its presentation
layers and fixed out-of-combat geometry; Blizzard keeps secure visibility, unit updates,
portrait selection, and click behavior. Keep the alpha-only presentation strategy for the
frame itself — never call `Show()`/`Hide()` on `TargetFrameToT`.

The important hazard is not limited to `Show`/`Hide`: a tainted field written by a direct
FrameXML call can be read later by an unrelated secure path. A concrete failure chain is:

1. `UnitFrames/UnitFrames.lua` called `ComboFrame_UpdateMax(ComboFrame)` directly to “seed” state.
2. That function's first line is `self.maxComboPoints = ...`, so the field became
   TurboFace-tainted.
3. On `PLAYER_ENTERING_WORLD`, Blizzard's `PlayerFrame_ToPlayerArt` calls
   `ComboFrame_Update`, which reads `self.maxComboPoints` — tainting that execution.
4. Control returned to `PlayerFrame_OnEvent`, which re-sets the unit on the next line via
   `UnitFrame_SetUnit`. `PlayerFrame.unit` was written under taint, permanently.
5. `TargetOfTargetMixin:Update` reads `UnitIsUnit(PlayerFrame.unit, parent.unit)` before
   calling `self:Show()`. Every ToT update inherited the taint; every `Show()` was blocked.
6. `TargetFrameMixin:OnUpdate` retries `totFrame:Update()` whenever `IsShown()` disagrees
   with `UnitExists()`, so one blocked call became a per-frame error storm.

The lesson is §1.3's rule, not a ToT-specific one: a single direct call into Blizzard
FrameXML anywhere in the addon can surface as a blocked action in a completely unrelated
frame. When a `TargetFrameToT:Show()` block appears, do not start by auditing ToT code —
run `/console taintLog 2`, then `/dump issecurevariable(frame, "field")` on every value
read at the reported taint line.

### 12.3 ToT debuffs

Blizzard's ToT has exactly four debuff slots, `TargetFrameToTDebuff1..4`, declared
statically in `TargetFrame.xml`. There is no lazy creation past four; more than four
would mean TurboFace-owned frames.

Two things about these frames are load-bearing:

- **They are not protected.** `IsProtected()` returns `false, false`, so `Show`, `Hide`,
  and `SetPoint` are all legal on them in combat, unlike their parent.
- **Blizzard's refresh cadence is target-change only.** The slots are populated from
  `TargetOfTargetMixin:Update` → `AuraUtil.RefreshAuras`, and `Update` runs only on
  `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`, `GROUP_ROSTER_UPDATE`, and the `IsShown()`
  mismatch check in `TargetFrameMixin:OnUpdate`. `TargetFrame` never registers
  `UNIT_AURA` for `targettarget`, and `UNIT_AURA` does not fire for indirect units.
  Stock behavior is therefore stale icons until the player re-targets.

TurboFace consequently **owns the content** of these four frames, not just their styling,
when the independent `modules.auras.tot` child is enabled. This Aura child does **not**
inherit `modules.unitframes.tot` and does not inherit the normal Player/Target
`auraEnabled` switch. `AuraStyle.lua` reads `UnitDebuff("targettarget", i, filter)`, sets
the icon texture, tints the border by dispel school, shows/hides the slot, and applies
`auras.totDebuffScale`, the shared swipe/timer presentation, and LCD-backed duration
resolution. This is a deliberate exception to the
restyle-don't-replace principle in §12 — the alternative was calling
`AuraUtil.RefreshAuras` ourselves, which is exactly the anti-pattern in §1.3 and §12.2.
Writing the refresh out by hand touches no Blizzard function.

This is also a sanctioned exception to §1.3's “never fight Blizzard with a permanent
`OnUpdate`”: with no event available for `targettarget`, a driver is the only option. It
is a 0.25 s `ns.Cadence` client, woken by the `TargetFrameToT:Update` post-hook, and it
stops itself as soon as `UnitExists("targettarget")` is false or the ToT Aura child is
disabled, so idle cost is zero. The shared aura timer cadence is started from the ToT
path as well, so ToT countdown text remains live even when normal Player/Target aura
styling is disabled.

Slot placement belongs to the `ToTDebuffs` mover element (`Movers/Auras.lua`), which lays
out **all four slots by fixed index in one row of four**, not by visible order. The old `totPerRow` SavedVariable is retired and pruned on load/import; runtime ignores it,
and the Movers UI exposes no per-row slider for ToT debuffs. Blizzard fills the set as a
contiguous prefix, and nothing re-anchors these frames after load — under visible-only
layout a hidden slot would never receive a point and would appear at its stock XML anchor
the moment it showed. The default anchor clears the 98×48 fixed artwork, which slightly overdraws
the button's real 93×45 footprint, and the slots are lifted to `baseLevel + 8` so they
draw above the art and text layers.

When the Movers master, aura-layout ownership, or the corresponding `TargetBuffs`/
`TargetDebuffs`/`ToTDebuffs` mover element is disabled, Blizzard retains that aura group's
positioning. AuraStyle adds a static X correction to the Blizzard chain root only: `+3px`
for Target buffs/debuffs and `+1px` for ToT debuffs;
descendants follow their native relative anchors. The correction is anchor-snapshot guarded so
repeated aura refreshes never accumulate it, and it is bypassed completely for each group while
its mover owns placement. Blizzard propagates the visible Target buff root's correction into the
debuff group even when `GetPoint()` does not expose a direct buff-button relationship, so a shown
nudged buff root suppresses the debuff root's own correction. With no buffs shown, the debuff-only
layout receives the correction directly. Transitions restore TurboFace's prior direct anchor before
ownership changes, preventing either a stale correction or a compounded offset. ToT's stock
debuff-border overlay is expanded outward by 0.5 layout pixels on each edge so the enlarged
overlay renders slightly thinner, without altering its dispel tint or the button/icon geometry.
Its countdown text uses the shared Aura Timer Font Size minus one visual font-size step; the
button-scale counter-correction is applied afterward, and stack-count sizing remains shared.

### 12.4 Shared bar/text ownership

TurboFace owns custom status text on the frames it actively styles. Generic
`TextStatusBar` hooks must never restyle bars from disabled TurboFace children or
unrelated addons.

Player and Target level presentation remains Blizzard-owned. TurboFace adds a decorative
`Interface\\CharacterFrame\\TotemBorder` badge behind the native level presentation. The badge's
black backing uses one authoritative Texture object alpha of **0.50** (vertex alpha remains 1.0),
matching the independent DPS/HPS badge. Refreshes may reassert that configured 0.50 alpha but must
never hard-pin it to 1.0; doing so was the historical reason Level-badge transparency edits appeared
ineffective. For a skull-level target (`UnitLevel("target") == -1`), Blizzard hides the level FontString
and shows its high-level skull texture; the same badge reanchors behind that skull rather than
disappearing with the hidden FontString. TurboFace does not replace or control the native skull texture.

### 12.5 Party and pet auras; party class reminders

Party and pet buffs/debuffs are TurboFace-owned **Aura** surfaces and use the same rounded
icon styling, cooldown swipe, stack count, countdown typography, and configured normal
party-aura icon size/max/per-row settings. They are not UnitFrame children. With TurboFace
Unit Frames enabled they anchor helpful auras on the left and harmful auras on the right
of the fixed artwork; with Unit Frames disabled the same containers fall back to Blizzard's
stock PartyFrame/PetFrame geometry.

The controls live under **Global → Auras → Party & Pet Auras**. `Style Party Auras` and
`Style Pet Auras` are independent Aura child gates (`modules.auras.party` / `.pet`). The
shared sizing/list settings live under `TurboFaceDB.auras`; Party class-only reminders are
Party-only. Migration 46→47 moves the former `unitframes.party*` aura settings and seeds
these new child gates from the old effective Party/Pet UnitFrame gates so upgrades preserve
what the user was seeing before the split.

Two modes exist:

- all-party-buffs mode: compact aura icons;
- class reminder mode: larger class-relevant icons, active/missing state, cooldown
  swipe, bottom countdown, and expiry warning pulse.

For Shamans, class reminder mode also shows a learned party-benefiting totem effect
only while it is active on that party member. Totem entries never become missing
reminders because each elemental slot has mutually exclusive totem choices, and they
never enter the player's self-buff reminder bar.

Class reminder mode is party-only. Pet helpful auras always use the normal list; pet
debuffs, like party debuffs, remain visible even if the optional helpful-aura list is
disabled.

Party-owned helpful and harmful auras deliberately use two rounded border primitives:

- **buffs / class reminders** use the TurboFace-authored silver `Icon-Border-Buff` frame with a tighter 1 px party-icon outset (the larger Class Buff reminder bar keeps its own 2 px treatment)
  plus `Icon-Mask-Rounded`, matching `Combat/ClassBuffs.lua`; missing reminders communicate
  state through the existing pulse rather than a different border colour;
- **debuffs** use Blizzard's rounded `UI-Debuff-Overlays` ring via
  `ns.CreateBlizzardAuraBorder`, tinted by `DebuffTypeColor` (`Magic`, `Curse`, `Disease`,
  `Poison`, or `none`). `PartyPetAuras.lua` carries the standard Classic colour values as a
  local fallback so an unavailable/missing global table never produces a black border.

The icon crop, cooldown swipe, stack count, and countdown remain PartyAuras-owned. Do not
collapse helpful auras back onto the debuff-ring primitive or reintroduce a square black
party-aura backdrop.

**Freshness ownership lives in `PartyPetAuras.lua`.** Do not piggyback aura correctness
on `PartyMemberFrameMixin:OnEvent`: the pooled 1.15.9 frame can expose an `OnEvent` method
without guaranteeing that every party `UNIT_AURA` transition is routed through that frame.
PartyAuras therefore owns two C-filtered `UNIT_AURA` listeners
(`party1`/`party2` and `party3`/`party4`) and refreshes only the affected member on the
normal event path. This avoids waking Lua for player/target/nameplate aura traffic.

A shared **1 Hz reconciliation cadence** runs only while at least one party unit exists.
It rescans all four party slots as a self-healing fallback for a missed client event,
unit reassignment, or an aura expiration that did not produce the expected update. This
is intentionally redundant with the event path: party aura correctness is more important
than trusting a single Blizzard lifecycle hook, and the bounded party-only scan is small.
The cadence parks completely when there is no party or the Party Aura child gate is off.

Pet auras have their own C-filtered `UNIT_AURA` and player `UNIT_PET` boundary, gated
by the Pet Aura child and independent of both UnitFrames and the Party Aura child. A 1 Hz pet-only
reconciliation cadence runs only while a pet exists. A pet replacement therefore never
makes party-aura runtime a dependency of pet-aura correctness.

All timed Party/Pet aura icons — ordinary compact helpful buffs, active Party class-reminder
buffs, and Party/Pet debuffs — use the existing 0.25 s shared timer driver. Their countdown
formatter follows the same Target/ToT blueprint as `AuraStyle.lua`: ceiling-rounded whole units,
minutes at >=90 s, seconds below 90 s, no decimal sub-second phase, and `1` remains visible until
actual expiry. When a tracked timer reaches zero, the driver rescans that member after finishing
its timer-table walk, so the icon itself cannot remain stale merely because the expiration
`UNIT_AURA` was missed. Indefinite helpful auras remain event/reconciliation-owned and display no
countdown. No aura icon owns a private `OnUpdate`.

Party class reminders are anchored to the party unit frames and do not depend on the
Movers master. The configured `partyClassBuffWarnSeconds` value is read directly from
`TurboFaceDB.auras`; do not gate that lookup on UnitFrames.lua or its private DB cache.

### 12.6 Druid auxiliary Mana bar

The Druid Mana bar belongs to the `class` module runtime and integrates with the Player
unit-frame bar stack. Class disabled means no form/power event subscription for this
feature.

---

### 12.7 Prediction overlays (`UnitFrames/Predictions.lua`)

Both the DoT and heal overlays live in **`UnitFrames/Predictions.lua`**, not
`UnitFrames/UnitFrames.lua`. They are consumer-side rendering only: `Combat/DotPrediction.lua` and
`Combat/HealPrediction.lua` own the data and are UI-independent.

Load order is a real constraint and is recorded in the TOC. The file calls
`RegisterConsumer` at **file scope**, so it must load after both engines, and it
reads `ns.UF`, so it must load after `UnitFrames/UnitFrames.lua`. It opens with
`local UF = ns.UF; if not UF then return end`, so a wrong order fails inert
rather than erroring on a nil index. Its only other tie to the parent file is
`UF.GetPartyHealthBar`, published there so the
`HealthBar`/`healthBar`/`_G` fallback chain has one definition.

Prediction rendering is deliberately **independent of TurboFace Unit Frames styling**. DoT Target
and ToT surfaces call `DotPrediction:ShowOnUnitFrames(unit)` and Heal Prediction calls
`HealPrediction:ShowOnUnit(unit)`, but those predicates gate the prediction engine/surface preference
only; they do not require `modules.unitframes`. The renderer attaches its TurboFace-owned textures
directly to the existing Blizzard health StatusBars, so a player can keep completely stock Blizzard
unit frames and still use DoT/Heal Prediction.

The `UnitFrames/Predictions.lua` location is a historical/source-layout seam, not a runtime parent
contract. It may use `ns.UF` compatibility helpers (notably pooled party-health lookup) because
`UnitFrames/UnitFrames.lua` is loaded and publishes those helpers even when its styling gate is off.

Heal prediction textures are TurboFace-owned children of the existing Blizzard health
status bars for Player, Target, Target-of-Target, Pet, and the four classic Party frames.
The renderer never changes the Blizzard bar's value, unit, visibility, parent, or secure
state. First-time texture-pool creation and one-way `OnValueChanged` hooks are deferred
while `InCombatLockdown()` is true; `PLAYER_REGEN_ENABLED` completes deferred setup.

When the TurboFace Party UnitFrame child is enabled, Party frames use the padded
`UI-Party-Portrait.tga` fixed-art sheet while retaining Blizzard's native portrait, health
bar, power bar, and secure click/hover behavior. With that restyle disabled, prediction
textures still attach to Blizzard's stock health bars. Party/Pet aura containers make the
same independent choice between TurboFace-art anchors and stock-frame anchors (§12.5).
TurboFace-owned party names resolve from each pooled frame's assigned `frame.unit`, with the
visual layout index used only as a compatibility fallback. `UNIT_NAME_UPDATE` refreshes an
already-created name string (or completes deferred frame styling) when the initial roster pass
ran before the client's unit-name cache was ready; it does not override Show Names or NanShield
visibility.
Because fixed-art styling suppresses Blizzard's legacy party chrome, the party leader marker is a
TurboFace-owned copy of `UI-Group-LeaderIcon` on the foreground text layer. Its state resolves from
the same assigned unit during normal member styling and refreshes directly on
`PARTY_LEADER_CHANGED`; it remains independent of party-name and NanShield visibility.
The 16x16 marker is anchored at `(16, 4)` from the fixed artwork's top-left corner.

Segments begin at the current health edge and are drawn in predicted landing order. A
HoT contributes only one `hot_tick` segment (its next tick), while each attributable direct
cast is a separate `direct` segment. Optional overheal may extend TurboFace-owned textures
past the normal 100% bar width; it never alters the underlying status bar range. The
renderer has a bounded preallocated/lazy pool (`healPredictionMaxSegments`) and hides
unused textures rather than allocating on every prediction event.


## 13. Auras and LibClassicDurations

There are three related but independently gated aura presentation domains:

1. TurboFace nameplate auras (`Nameplates/Auras.lua`).
2. Blizzard Player/Target styling plus the independently gated ToT debuff consumer (`AuraStyle.lua`).
3. Blizzard Party/Pet augmentation (`PartyPetAuras.lua`).

All are controlled by the Auras family, but their runtime needs differ. User-facing Aura
settings live under **Global -> Auras**; there is no separate Auras tab. `auraEnabled`
continues to opt normal Player/Target swipe/timer styling in or out, while
`modules.auras.tot`, `.party`, and `.pet` independently own those three stock-frame
surfaces.

The shipped baseline enables Player/Target styling and the ToT child, uses 11px Outline timer/aura
text, and uses 1.0 Target buff, Target debuff, and ToT debuff scales. The Nameplate Aura defaults
that originated in the audited Rumblecrush preset—buff/debuff dimensions, 3px debuff Y offset, and
Party class reminders—also live only in `Core/Defaults.lua`; presets inherit these values.

`AuraStyle.lua` styles Player/Target auras but *populates* the four ToT debuff slots
outright when the ToT Aura child is enabled — see §12.3 for why that exception exists and
how its driver is bounded.

### 13.1 Demand-driven LCD activation

Embedded LibClassicDurations is available to multiple TurboFace consumers. It must not
run permanent maintenance/CLEU work merely because the library was loaded from XML.

TurboFace registers LCD consumers only when a duration-based feature actually needs it.
Current consumers include AuraStyle and class-buff reminders.

This is important because Class Buff reminders may need LCD durations even when normal
AuraStyle presentation is not being used.

---

## 14. Swing timers and cast bars

Player/Target swing and cast presentation is a **Global combat-timer system**, not a Unit Frames child.
`Combat/SwingTimers.lua` also exposes the separate lightweight enemy-nameplate swing state owner, but
that consumer is independently gated under Nameplates and must not inherit the Global Swing Timers
presentation gate. `Combat/Castbars.lua` owns player/target cast lifecycle, cast-row rendering, and
optional Blizzard player-castbar suppression.

The runtime has **two presentation renderers**. Placement/presentation is selected per player/target side:

- **Standalone (whenever TurboFace Unit Frames is unavailable/disabled, or when
  `unitframes.embedCombatTimers == false`):** TurboFace recreates the older pre-compact presentation
  on independent `UIParent` frames. Player MH, OH, and Ranged swing rows use the shared tooltip-style
  bar border, cropped weapon/form icon on the left, cached current damage range in the center, and
  remaining time on the right. Player/Target cast bars use the same border with spell icon on the left,
  spell name centered, and remaining time on the right. The hostile Target swing row intentionally
  omits weapon icon/damage metadata because Classic does not expose reliable hostile equipment tooltip
  data. Movers owns six independent elements: `PlayerMainSwingTimer`, `PlayerOffhandSwingTimer`,
  `PlayerRangedSwingTimer`, `PlayerCastBar`, `TargetSwingTimer`, and `TargetCastBar`. On Druids using
  the standalone Druid Power Bar, untouched player swing rows automatically stack beneath that bar
  while it is visible; explicit swing-row mover positions remain authoritative. Standalone attack
  and cast geometry is user-configurable through independent width/height settings. Attack height also
  owns the untouched default stack stride/offset, while Cast height affects only the cast frame itself.
  These settings never resize the embedded artwork.
- **Embedded:** when `unitframes.embedCombatTimers` is true **and** the corresponding TurboFace
  Player/Target Unit Frame child is effectively enabled, the established compact 121x14 fixed-art
  presentation remains unchanged. Player melee may combine MH/OH in the compact row and the existing
  compact ranged/cast/target rows continue to use the current UnitFrame artwork/stack logic.

Only the compact embedded renderer synchronizes its row scale to the active TurboFace frame's effective
scale. Standalone rows remain normal `UIParent`-scale mover-owned frames, matching the old free-floating
presentation model.
The texture preferences remain stored at legacy `unitframes.attackTexture` /
`unitframes.castTexture` paths for profile compatibility, but they are Global combat-timer settings
and must not be treated as Unit Frames dependencies.

### 14.1 Swing Timers

The Global Swing Timers player/target rows should have no broad swing event/CLEU/cadence runtime while
`modules.swingTimers` is disabled. Unit Frames state is irrelevant to that activation. The independent
Nameplate Swing Timer is the deliberate exception: while Nameplates + `bubbleNameplates.swingTimer` are
effective it owns only its SWING-only shared-CLEU consumer, `PLAYER_REGEN_DISABLED/ENABLED` boundary
events, GUID snapshots, and demand-driven ~30 Hz renderer. Disabling the Global Swing Timers rows must
not disable that nameplate path. Behavioral rules already established by the project:

- entering combat must not fabricate a swing cooldown when the weapon is actually ready;
- leaving combat preserves an already-running player MH/OH countdown until it reaches ready;
  an immediate next pull carries that unelapsed remainder back into combat, while a completed
  timer parks the driver and no new out-of-combat swing is fabricated;
- ordinary completed hard casts reset both melee timers unless explicitly exempted;
- Classic instant/special reset behavior is data-driven from `SwingTimerSpellData.lua`;
- `SwingTimerSpellData.lua` is a TurboFace-owned interaction layer. It stores one canonical
  Blizzard spell identity per behavior family and resolves localized spell names at runtime, so
  ranks inherit the same rule without maintaining rank-by-rank imported ID dumps. Its four narrow
  queries own instant/special melee resets, hard-cast reset exemptions, on-next-swing identity, and
  the Oil of Immolation damage reset consumed by CLEU;
- on-next-swing attacks (Heroic Strike/Cleave/Maul/Raptor Strike) remain a separate
  behavior category and reset from the actual replacement melee swing rather than
  being treated as ordinary instant spell resets;
- target and form changes re-read `IsCurrentSpell` through the canonical
  on-next-swing family model; they never clear TurboFace's queued presentation by
  inference. `Combat/QueueDiagnostics.lua` provides the opt-in `/tfqueue on|off|dump|clear`
  observer. While enabled for the current session it keeps a bounded event history,
  announces client-reported queue transitions, hooks cancellation/action entry points
  only for attribution, and records spellcast, rage, target, form, combat, UI-error,
  and player melee-CLEU context without ever casting or cancelling anything;
- Physical ranged shots (Auto Shot, Shoot Bow/Gun/Crossbow, and Throw) restart the ranged clock
  without disturbing MH/OH. Wand Shoot restarts the ranged clock **and both melee clocks**.
  Classification must not depend on the success-event spell ID alone: the ranged kind is recognized
  from canonical ID/localized spell identity and pinned to its cast GUID from SENT/START through
  SUCCEEDED/FAILED/STOP so an ambiguous 1.15.9 wand payload retains its melee-reset behavior;
- `UNIT_INVENTORY_CHANGED` is not synonymous with “weapon swap.” The engine compares equipped
  item identity first: a real MH/OH change may reset that melee state, while ranged-weapon/ammo
  churn cannot reset MH/OH;
- the baked Target swing surface must initialize hidden. It becomes visible only through the
  normal hostile-target/in-combat predicate; no empty baked target row may flash after `/reload`;
- periodic visual work is registered with `ns.Cadence` only while an active timer/auto-shot poll
  actually requires it.

### 14.2 Player/Target Cast Bars

`Combat/Castbars.lua` owns player/target TurboFace castbars and optional suppression of Blizzard's
player castbar. Cast Bars disabled means:

- no spellcast event subscriptions;
- no new suppression hooks;
- Blizzard's player castbar is not suppressed by TurboFace;
- starting disabled is a no-op against Blizzard state.

If TurboFace suppressed the Blizzard bar earlier in the same session, teardown may restore only state
TurboFace actually owns. Cast animation uses the shared cadence scheduler at at most 60 Hz only while
a player/target cast or failure hold exists. In **embedded** mode the baked cast background/fill extends
one pixel farther on the visual right edge. Player is left-anchored; mirrored Target also moves its right
inset and spark origin so the added pixel does not expand left. Standalone legacy castbars keep their
independent tooltip-border geometry unchanged.

Nameplate castbars are entirely Blizzard-owned through the native `CastBarsContainer`. TurboFace has
no Nameplates-specific castbar renderer; `Combat/Castbars.lua` is only the independent Global
player/target castbar subsystem.

---

## 15. PowerCost architecture

The Power subsystem has two independently gated consumers with separate implementation
owners:

- **Hotbar Power** — `Power/PowerCost.lua`: action-button missing-power overlay/counter.
- **Player Tick Markers** — `Power/RegenTicks.lua`: Mana/Energy/Rage/Health regeneration
  markers, shared heartbeat, 5SR state, and `+X` tick popups.

`Power/PowerCost.lua` keeps the single coalesced event frame because Hotbar Power and
Player Ticks overlap on player power/form events. It forwards tick-relevant events to
`ns.RegenTicks`; all clock/marker state lives exclusively in `Power/RegenTicks.lua`.
`ns.Power:ShowTickAmount`, `GetTickAmountColor`, `GetRegenDebugState`, and
`RefreshMarkers` remain compatibility facades for existing consumers such as the Druid
auxiliary Mana bar and debug commands.

### 15.1 Shared regen heartbeat and five-second rule

Player regeneration uses one shared visual heartbeat plus an independent 5SR clock:

```text
2-second Classic regen heartbeat -> Mana / Energy / Health marker phase
5-second rule (5SR)               -> independent countdown from a real mana spend
Rage out-of-combat decay          -> next known server boundary, then observed 2-second decay phase
```

Starting or refreshing 5SR must **never** reset the learned 2-second regen heartbeat.
The 5SR marker can therefore cross the heartbeat marker on the power bar. This matters
for partial regen-while-casting mechanics and for correctly predicting the first natural
Mana tick after 5SR expires.

5SR start detection correlates a mana-costing `UNIT_SPELLCAST_SUCCEEDED` with an actual
Mana decrease. The code tolerates either Classic event order (power drop before spell
success or spell success before power drop) and does not start 5SR for a nominally
mana-costing cast that consumed no Mana.

### 15.2 Regen phase learning is CLEU-free

Player Tick Markers deliberately **do not subscribe to CLEU**. A previous implementation
used heal/energize CLEU merely to reject potions/heals; that made an otherwise tiny
visual feature participate in every combat-log burst. The current model uses unit
resource events plus phase confidence instead.

The Mana, Energy, and Health marker types render from `GetSharedRegenTickAnchor()`, so they can never
free-run on separate client clocks once a real server phase has been learned. Source
priority is deliberately conservative:

1. **Mana** is preferred once a validated natural Mana heartbeat is known.
2. **Energy** is the strong fallback; a natural Classic +20 Energy heartbeat can seed
   the shared phase when Mana has not ticked yet.
3. **Health** owns phase only when neither resource clock is available.

A newly observed resource that agrees with the current phase snaps to the existing
anchor instead of replacing it with its slightly later event-delivery timestamp. This
prevents shifted Druid Mana, Cat Energy, and HP markers from walking a few milliseconds
ahead/behind one another after each server heartbeat.

For Mana, a first gain must agree with an already-known Energy/Health phase before Mana
is allowed to become authoritative. A one-off potion/proc therefore cannot steal the
clock merely because Mana had not produced a natural tick yet. If the stored phase
really became stale, two consecutive out-of-phase Mana gains roughly two seconds apart
can still reacquire it.

`UNIT_HEALTH` delivery jitter may supply the `+HP` amount but normally may not move an
actively observed resource-owned shared phase. The deliberate exception is **capped
Mana**: once Mana reaches maximum it stops producing gain events, so validated
out-of-combat Health heartbeats may refresh that otherwise-stale preferred anchor.
Health keeps its last validated observation as the continuity reference across the Mana
cap, and two consecutive ~2-second gains are still required before an out-of-phase
Health signal may relearn the clock. Health marker presentation remains out-of-combat
only. Energy may use a provisional local baseline only while **no** shared heartbeat
has yet been learned; as soon as Mana, Energy, or Health confirms the phase, all visible
markers use it.

### 15.3 Tick driver

The visual marker driver is approximately 33 Hz **only while at least one marker is
actually eligible to animate**. It parks itself and hides all markers when Mana/Energy
is capped, Rage is zero/in combat, Health is full/in combat, phases are unknown, or the
relevant settings are disabled. Rage is intentionally outside the shared regeneration
heartbeat: `PLAYER_REGEN_ENABLED` starts its slower grace sweep, the first observed
natural-sized loss changes to the two-second decay sweep, and later losses re-anchor it.
The learned Rage phase survives combat re-entry so the next pre-decay sweep targets the
upcoming server boundary rather than reusing the previous pull's variable wait duration.
Both Rage phases travel right-to-left; the other resource markers retain their established
directions.

Marker presentation uses one visual language. Mana, 5SR, Energy, Rage, and Health each own an
independent border toggle and border color; all share `tickWidth` and `tickBorderWidth` geometry.
Health defaults to the same dark backing/border stripe treatment as Mana and Energy but may now
be configured independently rather than borrowing Mana's `tickBorderColor`.
The `+X` amount popups are owned exclusively by `power.tickFont`, `power.tickTextStyle`, and
`power.tickAmountSize`. Popup FontStrings are created without a baked-in outline and are restyled
immediately on option refresh, including pooled/hidden instances, so no legacy Blizzard-default
font or static `OUTLINE` state can override the selected tick typography.

Tick-amount **presentation** is intentionally more tolerant than phase authority. Mana/HP
gains inside the strict ±0.35 s phase-validation window may validate/relearn the shared
heartbeat; a clearly near-phase positive gain inside ±0.55 s may display its observed `+X`
amount without moving the heartbeat. This prevents harmless Classic event-delivery jitter
from suppressing every few popup texts while keeping potions/procs/HoTs from becoming timing
authority. Energy amount text remains direct positive-delta presentation.

`UNIT_POWER_FREQUENT` and `UNIT_HEALTH_FREQUENT` are intentionally not subscribed; the
normal update events are sufficient for this 2-second timing model and avoid duplicate
high-frequency work.

The runtime event set is split according to which consumer is active.

| Hotbar Power | Player Ticks | Expected runtime |
|---|---|---|
| OFF | OFF | no PowerCost event engine |
| ON | OFF | action/spell/power events only |
| OFF | ON | resource tick/player events only; no CLEU |
| ON | ON | shared union of required non-CLEU events |

`TurboFaceDB.power.enabled` is a legacy shared kill switch beneath both consumers. Do
not fold it into one module master because historical profiles used it before the two
features were separated.

Hotbar Power must not perform a full action-button spell/macro/cost rebuild merely
because combat ended. `PLAYER_REGEN_ENABLED` schedules the post-combat rebuild only
when structural work was actually skipped during combat or an overlay frame could not
be created safely while locked down. Ordinary fights with no deferred structural change
therefore have no 50 ms post-kill PowerCost rebuild.

`SPELL_UPDATE_USABLE` is intentionally **not** a structural rebuild trigger. It is noisy
around combat/target usability transitions, and a full scan is materially more expensive
than the presentation update it normally requires. It now requests only the
coalesced overlay render. Structural identity/resolution rebuilds remain owned by
`ACTIONBAR_SLOT_CHANGED`, `ACTIONBAR_PAGE_CHANGED`, `SPELLS_CHANGED`,
`UPDATE_SHAPESHIFT_FORM`, `UPDATE_BONUS_ACTIONBAR`, and `UPDATE_BINDINGS`. Those
resolution rebuilds must keep the already-collected Blizzard button-frame list and
per-spell cost cache warm unless the triggering event actually invalidates them.
`SPELLS_CHANGED` invalidates spell costs/known-spell state; login/manual full refreshes
recollect buttons and invalidate costs. The spell-cost cache key includes the player's
active power type so druid/stance changes cannot reuse a cost chosen for the wrong
resource. If a future conditional-macro case proves that usability changes require extra
resolution work, add a targeted macro-only refresh rather than restoring a whole-bar
rebuild on this event.

Do not re-introduce broad cache invalidation on noisy presentation/usability events without
new live evidence.

`/tf debug regen` exposes the private phase state without making any UI consumer a
second timing owner.

## 16. Class features

`modules.class` gates class-specific runtime.

Current responsibilities include:

- Warrior Overpower indication;
- standalone self-buff/imbue/proc/reactive reminders, including target-independent
  Warrior Revenge, Rogue Riposte, and Hunter Mongoose Bite windows;
- Hunter Feed Pet reminder when the pet is Content or Unhappy;
- party class-reminder data/evaluation;
- Druid auxiliary Mana bar.

Class disabled should unregister class-specific CLEU/event/ticker work.

The Class Buff spell/name/icon/known-spell catalog is rebuilt only for events that can
actually change it (spell learning, level/equipment/login state). Combat start/end only
changes reminder visibility/ticker policy and must not rebuild that catalog as generic
post-combat cleanup.

**Aura-driven re-evaluation is coalesced at 10 Hz.** Player `UNIT_AURA` and
`UNIT_INVENTORY_CHANGED` set a dirty flag and wake a `ns.Cadence` client rather than
running a full `Evaluate()` synchronously per event. This is the same reasoning as
the `AuraStyle.lua` coalescer (§13), and post-combat is the case that motivates it:
every proc, shout, seal and HoT expires within a second or two of a fight ending,
each one its own event, each one previously a full layout pass. The client is
deliberately **not** registered as `immediate` (§4.5a) and is removed in
`DeactivateRuntime` so a queued evaluation cannot outlive the runtime (§1.4). The
0.5 s ticker still drives countdown text, so a missed coalescing window is invisible.

**One aura walk per evaluation.** `HasBuff` reads a snapshot taken once at the top of
`Evaluate` instead of restarting `UnitBuff("player", 1..40)` for every catalog entry.
The snapshot stores the **aura index** alongside the expiration and resolves ties by
lowest index to preserve Blizzard aura order when a name set matches two live auras —
Mark of the Wild with Gift of the Wild, or any two of the three Mage armor families.
Looking names up with `pairs()` instead would pick an arbitrary winner and can report the
wrong remaining time in the countdown text. Differential validation must include randomized
buff lists and an explicit overlapping-name-set case.

The standalone self-reminder bar is mover-dependent. Party reminders are not. The class-agnostic
unspent-talent reminder is project-owned and reads `UnitCharacterPoints("player")` directly; it has
no external aura/runtime dependency.

`UnitFrames/PetHappiness.lua` owns the Hunter-only Feed Pet state cache. It reads
`GetPetHappiness()` through one 1 Hz `ns.Cadence` client while the corresponding Class Buff reminder
is active. It has no native frame mutations, events, CLEU subscription, swipe, timer, or estimate.
Content or Unhappy makes the `Feed Pet` entry (icon `132165`) appear in the normal reminder queue;
Happy or no pet clears it. The `classBuffFeedPet` toggle follows the existing Class Buff master,
combat-only, mover, pulse, size, spacing, and growth behavior.

`/test`-style positioning may temporarily activate a reminder presentation, but the
runtime must return to its normal effective state after the test window ends.

---

## 17. Movers and Blizzard Edit Mode

TurboFace no longer competes with Blizzard HUD Edit Mode for systems that 1.15.9 can
position natively.

Removed TurboFace mover ownership includes the major Blizzard unit-frame/action-bar
placement jobs now served by Edit Mode.

TurboFace Movers remain for:

- TurboFace-owned free-floating widgets, including the standalone Druid Power Bar when the
  TurboFace Player Unit Frame is disabled;
- the six standalone combat-timer surfaces (`PlayerMainSwingTimer`, `PlayerOffhandSwingTimer`,
  `PlayerRangedSwingTimer`, `PlayerCastBar`, `TargetSwingTimer`, `TargetCastBar`), each independently
  movable and available only while that side uses standalone presentation;
- Target-of-Target where needed;
- target aura anchors;
- systems not independently exposed by Edit Mode, such as Blizzard loot/group-roll
  positioning;
- tooltip/FPS/quest tracker integrations.

Mover positions are stored relative to screen/UIParent space so scaled frames remain
under the expected cursor position.

Combat-sensitive protected movement is deferred.

---

## 18. Speedrun / utility widgets

The Speedrun options presentation order is: **Lvl1 Quick Setup, Speedrun Splits, Loot Frame, Net Worth, Junk & Inventory, Free Bag Slot Counter, Grocery List, Trainer Spells, Luxthos-like XP Bar, Hearthstone Tracker, Hearthstone Batching, FPS Counter, UnstuckSkips Notifier, Skill Tracker, Enemy Leash Timer**. This ordering is UI-only; it does not change feature ownership or dependencies (notably, Hearthstone Batching still requires FPS Counter even though Batching is displayed first).

### 18.1 Luxthos-like XP Bar

Mover-dependent. Starting effectively disabled means no custom bar, XP/quest event
suite, time-played requests, or Blizzard XP-bar suppression hooks.

If `hideBlizzardXPBar` is enabled, TurboFace only restores Blizzard state that it
actually suppressed; starting disabled must not force Blizzard bars visible/hidden.

Quest XP scanning must preserve the player's quest-log selection and avoid unsafe
selection churn.

XP run/session counters are per-character in `TurboFaceCharDB.experienceBarSession`. Schema 72
migrates the legacy `TurboFaceDB.experienceBar.session` table once, and the current-schema guard
removes that legacy subtree from old imports. Normal profile save/load/export strips embedded
legacy sessions defensively. Dedicated **Export XP Splits** / **Import XP Splits** controls live
under **Profile -> Import / Export** and use the data-only `TFXP1:` format so history can be
transferred intentionally without coupling it to the XP Bar's appearance or the rest of the addon
configuration.

### 18.2 Speedrun Splits

`SpeedrunSplits.lua` is a clean TurboFace-native implementation of cumulative
`/played` split tracking. It records every full-level boundary and every 10% XP boundary;
integer ordinal keys avoid floating-point saved-variable keys (`121` means `12.1`, `130`
means Level 13). A large XP award that crosses multiple boundaries assigns the same event
timestamp to each crossed checkpoint, matching the fact that they were reached together.

The current run and its frozen PB reference live per character in
`TurboFaceSpeedrunCharDB`. Account-wide race/class PBs and best individual segments live
in `TurboFaceSpeedrunDB`; neither dataset enters TurboFace profiles or the disposable
client-build cache. The runtime anchors one `TIME_PLAYED_MSG` total to `GetTime()` and
extrapolates between responses rather than requesting `/played` or incrementing an
independent counter every second. XP and level events capture checkpoints. The shared 1 Hz
cadence only refreshes visible text and parks when the mover display is hidden.

The display can show partial rows or full levels only without changing what is tracked.
Current times compare against the PB snapshot taken at run creation/reset; green is ahead,
red is behind, and yellow marks a best segment. Manual save/reset/print/import operations
are available through the Speedrun options and `/tfsplits`. Legacy import reads only the
original addon's already-loaded saved-variable globals and maps its full-level checkpoints
to ordinal keys; TurboFace does not embed or execute the supplied addon code.
The `Total` footer anchors to the rendered bottom of the final visible split row rather
than an estimated rows-times-font-height table size. A dynamic half-row-height gap separates
the final split from `Total`, so the spacing remains visually stable across font size,
row count, and UI scale changes. An interactive button directly below the total timer reads
`Hide Partial Levels` while partials are visible and `Show Partial Levels` in whole-level
mode. It updates only the row presentation setting; checkpoint capture always retains
partials. The mover includes
the button in its interaction ownership and defaults click-through off so the control is
usable, while users may still deliberately enable click-through from Movers.

### 18.3 Lvl1 Quick Setup

`QuickSetup.lua` is the TurboFace-native successor to standalone Lvl1QuickSetup 1.0.4.9. It is a
root singleton because it is an independent Speedrun utility, not an Inventory/Plus/Profile child.
The standalone globals and SavedVariables (`L1QS_*`, `saveAll`, `_G.L1QS_SaveAll`) are not retained.
Guidelime, RXP, WeakAuras, Scrap/Peddler, and ActionbarPlus compatibility baggage is intentionally
not part of the integrated subsystem.

Configuration lives at `TurboFaceDB.quickSetup`. The **Enable Automatic Lvl1 Quick Setup**
restore toggle defaults **off** and is a normal checkbox inside the ungated **Lvl1 Quick Setup**
category, immediately after **Auto-skip Level 1 cinematic**. The two controls are independent:
automatic restore may remain off while cinematic skipping stays active. Enabling automatic restore
mid-session arms it for the next `/reload` instead of starting a destructive restore after
Plus/System CVar owners have already initialized. With automatic restore off and no pending manual
apply, only the optional `CINEMATIC_START` listener may remain registered.

The account-wide class library lives at `TurboFaceProfilesDB.quickSetup.classes[CLASS]`.
**Save Class Profile** captures account + character macros (with scope), character keybindings,
action placements across slots 1-180, Blizzard Action Bars 2-8, the selected Edit Mode layout, and
only the defined Quick Setup CVar allowlist. Class profiles are independent from normal TurboFace
settings profiles and from XP split history. Action Bars 2-8 are read from Blizzard's live
`PROXY_SHOW_ACTIONBAR_*` Settings values when available, with `GetActionBarToggles()` retained as a
fallback when the Settings system is not ready.

Automatic restore is eligible only at **Level 1 with 0 XP** and is keyed to the player's GUID, so a
recreated same-name character is detected as new while an already completed GUID is not cleaned
again. Incomplete automatic restores receive at most three login attempts. The restore engine is
staged across frames: synchronize macros -> bindings -> place saved actions -> clear stale actions
(exact fresh-character restores only) -> verify Blizzard action-bar options -> Edit Mode. Placement
always precedes cleanup so a mid-restore failure leaves extra inherited actions instead of an empty
bar. Unavailable item/spell actions get the preserved delayed retry pass.

Blizzard Action Bars 2-8 use a two-layer no-reload restore. Quick Setup **never writes** the live
`PROXY_SHOW_ACTIONBAR_*` Settings values and never calls `MultiActionBar_Update()`: testing showed that
even routing those writes through `securecallfunction()` could contaminate Blizzard's later
`ActionBarMixin:UpdateShownButtons()` execution and block protected individual button/container
`SetShown()` calls in combat. Instead, `SetActionBarToggles()` persists the complete seven-bar state
for the next ordinary login while `RegisterStateDriver(frame, "visibility", ...)` mirrors each changed
bar immediately for the current session in Blizzard's secure visibility environment. Visible secondary
bars use `[vehicleui] hide; [overridebar] hide; [possessbar] hide; show`; hidden bars use a constant
`hide` driver. These drivers are **bootstrap-temporary**, not session owners: once the staged restore
and delayed action retry are finished, TurboFace explicitly calls `UnregisterStateDriver()` for every
driver it installed. If finalization happens during combat, that cleanup is deferred only until
`PLAYER_REGEN_ENABLED`, then ownership is released. The restore-only `EDIT_MODE_LAYOUTS_UPDATED` and
`PLAYER_REGEN_ENABLED` listeners are also unregistered as soon as no staged job, deferred Edit Mode
selection, or driver cleanup remains. The independently enabled cinematic listener is unaffected.
On the next login the persisted Blizzard settings already own visibility and TurboFace does not install
a driver for a character whose GUID is already marked complete.
If state-driver registration is unavailable/fails, persistence still self-heals on the next login;
TurboFace never performs a protected programmatic reload.

**Apply Stored Profile** still uses a user-entered `/reload` for a different reason: its stored CVar
baseline must currently cross the early Core login boundary before temporary Plus/System CVar owners
initialize. That manual CVar handoff is independent from action-bar visibility.

CVar ownership has a strict ordering rule. On an eligible login, or after **Apply Stored Profile**
sets a per-character pending handoff and the user performs `/reload`, Quick Setup applies the stored
persistent CVar baseline synchronously immediately after `ns:LoadVariables()`. Only after that does Core initialize
Plus/System, allowing temporary owners such as Max Camera Zoom to snapshot the Quick Setup value as
the user's real baseline. The staged restore never reapplies CVars later in the session.

**Auto-skip Level 1 cinematic** is owned here and calls `StopCinematic()` under a Level-1 gate,
followed by the preserved `CameraZoomOut(50)` behavior. It is independent from **Enable Automatic
Lvl1 Quick Setup** and does **not** require either the automatic-restore master or the destructive
`0 XP` cleanup gate, matching the standalone cinematic behavior; exact action-slot cleanup still
requires Level 1 with 0 XP. The former Plus/System `fasterMovieSkip` hook is retired; schema 75 and the
current-schema guard delete that old key.

Profile transfer uses strict data-only `TFL1QS1:` payloads. Export offers only classes already stored
and defaults to the current class when available. Import reads the class token from the payload,
validates class/action/macro/Edit Mode/CVar allowlists, asks for confirmation, and replaces only the
matching stored class profile; it never applies it to the active character.

### 18.4 Loot Frame

Mover-dependent. Starting effectively disabled means no toast frame and no loot/money
event subscriptions.

Each loot toast keeps the configured rectangular row footprint but uses Blizzard's scalable
Tooltip edge for rounded corners and an inset dark fill. The item/money texture is clipped by
`Textures/Icon-Mask-Rounded.tga` and framed by `Textures/Icon-Border-Buff.tga`; the frame tint
follows item quality, or coin gold for money. These are presentation-only children of the existing
loot button, so hover, tooltip, dismissal, stacking, and expiry behavior are unchanged. The visible
rounded shell adds **3px of padding per side** around the configured content width/row height; this
clearance is deliberately outside the content box so the Tooltip edge clears the rounded icon frame
without leaving an oversized gap. The finalized shell presentation is static: Blizzard's Tooltip border
uses a **7px edge size** with a **1.2px backdrop inset**. Its Tooltip edge is tinted near-black
(**RGB 0.01 / 0.01 / 0.01, alpha 1**) against the slightly lighter **RGB 0.03 / 0.03 / 0.03**
interior fill, so the rounded perimeter reads darker than the row background without altering the fill
alpha control. These are presentation constants in `LootFrame.lua`, not profile-facing settings. The temporary 0.17.61 tuning keys are retired in schema 77
and pruned by the current-schema guard so imports cannot resurrect them. Stacking and mover bounds use
the same fixed 3px shell padding, producing a +6px visual width/height. **Row Height is now the sole
vertical sizing control**: the item/money icon is derived as `rowHeight - 3px` (the fixed shell padding),
so changing row height keeps the rounded icon visually proportional without a second Icon Size setting.
Schema 78 retires/prunes the old `lootFrame.iconSize` key so imports cannot restore independent sizing.
The rounded icon receives a static **0.5px left optical nudge** inside that shell to compensate for the icon border outset; this does not alter shell padding, content dimensions, stacking, or mover bounds. Text sizing remains controlled separately by Font Size.

This custom frame is separate from the Blizzard Loot Window mover. Loot bursts are
coalesced at the presentation boundary: multiple item/money messages received in the
same frame update the entry model immediately but schedule only one toast `Render()`.
Each active entry owns at most one cancellable expiry timer; merging or refreshing an
entry replaces that timer rather than leaving stale delayed callbacks behind.

Item rows optionally reserve a right-aligned vendor-value column (`lootFrame.showVendorValue`).
The value uses Classic's native `GetItemInfo` sell price multiplied by the toast's combined stack
count; it does not introduce auction-house or external pricing. Money rows and unsellable items keep
the column empty. `GET_ITEM_INFO_RECEIVED` refreshes active entries whose item cache was incomplete at
loot time. Disabling the option removes the column anchor so the item link regains the full row width.

Classic can surface the same coin pickup through both `CHAT_MSG_MONEY` and
`PLAYER_MONEY`, and the latter may represent the aggregate delta from several rapidly
looted bodies. Money reconciliation therefore uses short-lived **per-source amount
credits**, not an exact `(amount, source, time)` duplicate test. This preserves two
legitimate bodies that happen to drop identical coin amounts while consuming the
corresponding chat/money duplicate or aggregate delta exactly once.

### 18.5 Junk & Inventory Management

Inventory runtime can be disabled without removing pure valuation helpers needed by Net
Worth. The binding targets required by `Bindings.xml` remain as stable inert objects
when inventory automation is off.

`TurboFaceCharDB.discardPile[itemID]` is a per-character, mutually exclusive item-state
map. `true` means Junk, `false` means explicitly Useful/protected, and `"bank"` means
Bank. An absent value uses the default classification: Poor-quality items are Junk and
other items are Useful. The Hearthstone exclusion prevents Junk classification but does
not prevent an explicit Bank mark.

Junk & Inventory owns three Blizzard keybinding actions:

- `Cycle Hovered Item: Junk / Useful / Bank` — the existing mark action owns all three
  states for the carried item ID under the mouse. The cycle is Useful -> Junk -> Bank ->
  Useful. An unmarked Poor item begins at its automatic Junk classification, so its first
  transition is Bank; Junk-excluded items skip the invalid Junk state.
- `Delete Cheapest Junk Item` — destroys the lowest total-vendor-value junk stack.
- `Delete Hovered Bag Item` — intentionally destructive and protected by the
  `invDeleteHoveredEnabled` safety gate. When that checkbox is enabled, the action
  immediately destroys the carried bag item under the mouse and suppresses the normal
  deletion confirmation path for that action only. It can delete **any** carried bag
  item, not only junk.

Because Blizzard's binding UI does not reliably capture modified Right Button
combinations, `invMarkMouseShortcut` provides an addon-scoped modifier+RightClick cycle.
`invDeleteHoveredMouseShortcut` provides the
same type of backup shortcut for Delete Hovered, but is inert unless
`invDeleteHoveredEnabled` is also enabled. Both shortcuts are handled only on carried
bag item buttons, so they do not globally consume modified camera/world right-click
input. If the two actions use the same shortcut, Delete takes priority while its safety
gate is enabled, so one click cannot both delete and change state.

Junk/Bank marking and deletion resolve only carried Blizzard ContainerFrame buttons or
supported live bag-addon buttons; bank, equipment, and other storage locations are rejected.
For Baganator, prefer the live button's `BGR.itemLocation`/live bag-button state rather
than assuming its pooled visual frame hierarchy matches Blizzard ContainerFrames.

**Baganator integration is an intentional lifecycle exception:** the lightweight junk
provider and Junk/Bank corner-widget registrations occur during addon loading, before
`PLAYER_LOGIN`, because Baganator constructs its Junk Detection provider choices from
registered plugins. Registration callbacks remain preference-gated and add no recurring
TurboFace runtime while Junk & Inventory is disabled. Baganator item-button hooks and
TurboFace inventory events still activate only from the normal `INV:Init()` boundary.
TurboFace must never attach bookkeeping fields to Baganator-owned runtime objects or
hook Baganator mixin tables directly: current Baganator builds may freeze those tables.
Per-button hook state belongs in TurboFace-owned weak tables instead.

`BAG_UPDATE_DELAYED` must **not** call `Baganator.API.RequestItemButtonsRefresh()` as a
generic bag-change reaction. Baganator already processes the underlying bag mutation;
its `ItemWidgets` refresh reason intentionally reevaluates third-party widgets across
the live bag view and can create a redundant second refresh pass after loot. TurboFace
requests that explicit widget refresh only when TurboFace-owned state changes without a
bag-data mutation (for example changing an item state, clearing marks, or changing the
item-widget setting).

`Inventory/Bank.lua` owns live bank behavior. On `BANKFRAME_OPENED`, it waits briefly for
Blizzard/Baganator container state to settle, then moves every carried stack whose item ID
is marked Bank. Transfers operate only on physical container coordinates, in batches of
eight with 0.20-second rescans, so default Blizzard bags/bank and Baganator share the same
engine. The shared addon-owned `Textures/BankIcon.tga` identifies the state while it is
pending and is also the banker nameplate Job Icon. Once every carried
stack of an item ID has deposited successfully, TurboFace changes that item ID from `"bank"`
to `false` (Useful) in `discardPile`; the banked items and any copies acquired later therefore
return to the neutral Useful state, including items that would otherwise be automatic Junk.
If space or locking leaves any carried stack behind, the Bank mark remains so a later visit can
finish the deposit.

While a live bank session is open and `invBankWithdrawAll` is enabled, exact
Ctrl+Right Click on any bank stack starts a bank-to-bags rescan for that item ID. It includes
the main bank container and purchased bank bags, merges into partial carried stacks when
Blizzard permits, and continues until no matching bank stack remains or space/lock retries
reach the safety cap. It is deliberately inactive for carried bags, guild/account storage,
and Baganator offline views. A user-requested withdrawal cancels an automatic deposit already
in progress; the delayed initial deposit never replaces an active withdrawal.

Vendor selling is based on physical bag/slot state, never Baganator visual-frame state.
The scanner uses the container slot's `hasNoValue`/`isLocked` fields rather than requiring
a cached `GetItemInfo()` vendor price. With Baganator loaded, TurboFace prefers the
cursor-to-merchant sale path (`PickupContainerItem` -> `PickupMerchantItem`) and restores
the cursor item immediately if the merchant rejects it; the normal `UseContainerItem`
merchant path remains as a compatibility fallback. Locked slots are skipped and retried.

All three binding actions and both backup mouse shortcuts must no-op while `invEnabled`
is false. Delete Hovered must additionally no-op while `invDeleteHoveredEnabled` is
false, regardless of whether it was invoked from the Blizzard binding or the backup
mouse shortcut.

### 18.6 Grocery List

A standing shopping list of vendor consumables. The queue lives in
`TurboFaceCharDB.grocery` (`[catalogKey] = count`) because what a character keeps
stocked is character-specific, exactly like the junk `discardPile`. Ordinary
catalog rows use their real itemID as the key; negative keys are reserved for
synthetic catch-all food-tier requests. Settings are flat `grocery*` keys in
`TurboFaceDB` behind the `groceryEnabled` dbKey gate.

Runtime is one event frame on `MERCHANT_SHOW`/`MERCHANT_CLOSED`, plus a second
frame registered for `GET_ITEM_INFO_RECEIVED` and `PLAYER_LEVEL_UP` **only while
the window is open**. No ticker and no `OnUpdate`. Purchases are spaced with
`ns.After` and are
generation-scoped, so `MERCHANT_CLOSED` cancels pending work.

Only the floating launcher button is mover-dependent (element
`GroceryButton`). The list window is an ordinary draggable dialog and the
auto-buy runtime is independent of Movers, so disabling Movers costs the button
and nothing else; `/tfgrocery` still opens the list.

**Window.** Built on Blizzard's own frame templates rather than hand-drawn
backdrops, so the window *is* native Blizzard art instead of an approximation of
it. This follows how Baganator obtains its "Blizzard" look: its skin file barely
does anything, because the styling comes free from the templates underneath.

| Template | Used for |
| --- | --- |
| `ButtonFrameTemplate` | the window and the popout — title bar, close button, border art, `Bg`, `TopTileStreaks`, `Inset` |
| `InsetFrameTemplate` | the recessed wells behind the item grid and the shopping list rows |
| `ItemButtonTemplate` | every item cell — slot art, icon, corner count, highlight/pushed states, `IconBorder` |

Cells are driven by Blizzard's own `SetItemButtonTexture` / `SetItemButtonCount`
/ `SetItemButtonDesaturated`. The corner count is the merchant's "5" badge, free.
`SetItemButtonQuality` is effectively inert on Classic, so the quality ring is
coloured directly from `BAG_ITEM_QUALITY_COLORS` and hidden below Uncommon —
the same approach Baganator takes on this client.

Both `ButtonFrameTemplate` close buttons are re-scripted rather than left on
their default hide-parent behaviour: the window's routes through `G:Hide()` so
the `GET_ITEM_INFO_RECEIVED` listener is released, and the popout's routes
through the same toggle as the tab handle so the choice persists.

**Template defects corrected on 1.15.9.** Hiding the portrait exposes two bugs
in `ButtonFrameTemplate`, both measured from a live frame with
`/tfgrocery frames` and `/tfgrocery art` rather than guessed:

1. *Unpainted strips.* `TitleBg` covers y −3..−20 and `Bg` starts at −21, so
   nothing paints across y 0..−3 or the 1px seam at −20..−21. Both sit inside
   the top border art, whose centre is transparent, so the world showed
   through. `TitleBg` is grown to span 0..−21 exactly, with its height set
   explicitly because the template gives it only `TOPLEFT`/`TOPRIGHT`.

2. *Stretched top-left corner.* `TopLeftCorner` and `TopRightCorner` are two
   sprites in the same 128×128 sheet (fileID 374156), but their regions differ:
   the left spans 0.2500 of the sheet (32×32) and the right 0.2578 (33×33) —
   while the template sizes **both** at 33×33. The left corner is therefore
   stretched ~3%, putting the border's inner edge about a pixel below where the
   straight `TopBorder` strip puts it. That step is the visible break just in
   from the left end, and it is a *size* error, not a position error — which is
   why re-anchoring and nudging the corner never fixed it. The right corner
   draws 1:1, so it is used as the reference: pixels-per-texcoord-unit is
   derived from it and the left corner resized to its own region, with a ±3px
   sanity clamp so an unexpected sheet layout leaves the frame untouched.

The general lesson for diagnosing this class of bug: dividing a texture's pixel
size by its texcoord span yields the source sheet's dimension, and any piece
whose result disagrees with its neighbours is being drawn at the wrong scale.

**Never call `SetAtlas` in this addon's Classic path.** Retail atlases such as
`bags-item-slot64` do not exist on Classic Era — Baganator ships its own texture
file precisely for this reason. Everything the grocery window draws is either a
template or a plain texture path present on 1.15.9.

The portrait is hidden on both frames. A shopping list is not an NPC panel, so
the top-left circle has nothing to show and would leave a hole in the corner.

The grid is two columns filled row-major with Prev/Page/Next pagination.
`CATALOG` is sorted once at load by category then required level, with category
order Drink -> Food -> Potion -> Ammo. Five checkbuttons in the header filter
the catalog before pagination: Food, Drink, Potions, and Ammo independently
include/exclude their categories, while Usable hides only items whose required
level exceeds `UnitLevel("player")`. Category filters default on and Usable
defaults off, preserving show-all behavior.
The six synthetic food-tier rows use the corresponding fruit progression icons
(Shiny Red Apple through Deep Fried Plantains). The floating Grocery launcher
uses the Ice Cold Milk icon by default.

Blizzard Key Bindings exposes `Toggle Grocery List` under the `TurboFace`
category. `Bindings.xml` targets a stable `TurboFaceToggleGroceryList` click
button created at file load; the binding is inert while `groceryEnabled` is off.

The filter state lives in the flat profile settings (`groceryFilterFood`,
`groceryFilterDrink`, `groceryFilterPotion`, `groceryFilterAmmo`,
`groceryFilterUsable`) and the window also refreshes on `PLAYER_LEVEL_UP` while open. The shopping-list popout
is a fixed-height panel, so `MAX_QUEUE_ROWS` is derived from the real layout
constants and any lines past it are summarised on the total line rather than
drawn outside the inset.

**Catch-all food tiers.** Food additionally exposes synthetic `Level 1 Food`,
`Level 5 Food`, `Level 15 Food`, `Level 25 Food`, `Level 35 Food`, and
`Level 45 Food` rows. These six synthetic rows are pinned to the top of the Food
category, so with the default category filters enabled page 1 is the six Drink
rows followed by these six catch-all Food rows. They queue exactly like a normal
five-at-a-time food line,
but do not name a concrete item until a merchant is scanned. `ScanMerchant`
retains merchant slot order; a catch-all resolves to the first concrete
`category = "Food"` catalog entry in the matching *player-use* tier that the
vendor actually stocks. This deliberately makes Bread/Meat/Cheese/Fish/Fruit/
Fungus/regional-food ties vendor-order dependent rather than introducing another
preference table. The one exception is the Level 5 tier: item 4592, Longjaw Mud
Snapper, is checked first because it is substantially cheaper than the other
foods in that tier. If it is absent, normal vendor-slot order resumes.

The six food tiers are player-use levels, not item levels. The first tier has no
formal required-level field and is surfaced as `Level 1 Food`; the remaining
tiers are required levels 5/15/25/35/45. Catalog `minLevel` fallbacks for the
basic food/drink progressions mirror those player-use levels so the Usable
filter stays correct even before a cold client cache has returned full item
info.

**Prices are observed, never estimated.** A merchant's asking price is not
derivable from an item's sell price because it moves with the player's
reputation discount with that vendor's faction. `ScanMerchant` therefore records
the real unit price of any catalog item it sees into
`TurboFaceCharDB.groceryPrices`, and the window shows a price only once it has
observed one.

**Purchase units.** The indivisible Grocery interaction is a *vendor purchase*,
not an abstract single item. Classic food/drink rows queue five items per
right-click. Ammo rows queue **200 items per right-click for every listed ammo
type, including throwing axes and throwing knives**. Catalog entries carry
`perBuy` for this, `SetQueued` snaps stored counts to whole multiples of it, and
the window reports both the item count and the purchase count. Snapping on write matters because a queue of 3 against a
five-at-a-time vendor is a promise the merchant step cannot keep — it would
round up to 5 and the chat summary would contradict the list. `perBuy` is the
UI's step only; at an open merchant the live `quantity` return is authoritative,
so a vendor that disagrees still buys correctly. Ordinary Grocery lines retain
the 500-item queue sanity ceiling; Ammo uses a 10,000-item ceiling so 200-round
lots are not artificially capped at two purchases.

**Ammo catalog.** The Ammo category follows Potions and contains 18 supplied
entries: Rough/Sharp/Razor/Jagged Arrow (2512/2515/3030/11285),
Light/Heavy/Solid Shot and Accurate Slugs (2516/2519/3033/11284),
Crude/Weighted/Sharp/Deadly/Gleaming Throwing Axe
(3111/3131/3135/3137/15326), and Small/Balanced/Keen/Heavy/Wicked Throwing
Knife (2947/2946/3107/3108/15327). All 18 use `stack = 200` and `perBuy = 200`.
Catalog fallback `minLevel` is zero unless/until live item metadata supplies a
required level; TurboFace does not invent a requirement absent source data.

**Merchant arithmetic.** Only the first five returns of `GetMerchantItemInfo`
are stable across Classic client revisions, so the tail is never read
positionally; alternate-currency items are detected with
`GetMerchantItemCostInfo`, as Blizzard's own MerchantFrame does. Quantities are
computed in batches: `numAvailable` is a batch count, `GetMerchantItemMaxStack`
and `BuyMerchantItem`'s amount are both item counts. Keeping cost arithmetic in
whole batches keeps it in integer copper.

**Vendor phase ordering.** Inventory auto-sell owns the first merchant phase.
When both Inventory auto-sell and Grocery auto-buy are enabled, Grocery asks
`ns.Inv` to ensure the sell handshake is running, waits while either the
merchant-start handshake or sell pass loop is active, then waits through the
final short settle window before beginning purchases. This ordering does not
depend on which module receives `MERCHANT_SHOW` first. The modules remain
independently gated: Grocery buys immediately when Inventory/auto-sell is off,
and Inventory continues to sell normally when Grocery/auto-buy is off. Sell
passes use 10-item bursts at 0.15s intervals; the burst cap remains conservative
for Classic merchant throttling. The 0.25-second interval gives Blizzard time to
process each burst before the next one begins.

**Clearing contract.** Once an item's order has been attempted, that line is
cleared — including the insufficient-funds case, which buys what the player can
afford and reports the shortfall in chat. Four conditions deliberately leave a
line queued because the player can fix them on the spot: the vendor does not
stock the item, there is no bag room, the item requires an alternate currency,
or the vendor window closed mid-order (in which case delivered items are
credited against the line rather than clearing it). Bag room accounts for
partial stacks, not just free slots.

### 18.7 Training

Gate: `trainerEnabled`. TurboFace owns the Training runtime: trainer/merchant capture, Spellbook tabs, profession side views, ignore/filter state, auto-training queue, and persistent discovery stores. The historical `TrainerSpells` local/module alias is retired; runtime ownership is `ns.Trainer`.

**Provenance boundary.** The bundled Classic Era **class and pet** seed catalog (`Trainer/data/Druid.lua`, `Hunter.lua`, `HunterPet.lua`, `Mage.lua`, `Paladin.lua`, `Priest.lua`, `Rogue.lua`, `Shaman.lua`, `Warlock.lua`, `WarlockPet.lua`, `Warrior.lua`) is distributed under the permissive **What's Training?** MIT lineage. Every retained seed file identifies that source, and the required license text ships as `Licenses/WhatsTraining-MIT.txt`; `THIRD_PARTY_NOTICES.md` records the integration. TurboFace's UI, queueing, live capture, skills presentation, profile integration, and persistence architecture are separate TurboFace implementation.

**Profession training data and static recipes.** No TrainerSpells profession or recipe seed database ships in TurboFace. `TrainerCapture.lua` reads Blizzard's trainer APIs and stores Training observations in `TurboFaceTrainerDB.professionData[profession][skillReq]`. The separate Recipes view consumes the embedded MIT-licensed LibProfessionDB Classic Era catalog and never writes it into SavedVariables. Apprentice/Journeyman/Expert/Artisan proficiency services remain owned by the Spellbook Skills view rather than the profession Training panel. The 0.17.75 migration marker `TurboFaceTrainerDB.provenanceProfessionResetV1` clears older mixed profession/recipe caches once so no previously merged TrainerSpells rows survive the provenance boundary. The normalized `recipeData` container is retained only so older SavedVariables remain harmless; normal capture no longer writes it and current presentation does not read it.

**Saved variables.** `TurboFaceTrainerDB` is account-wide and stores class/pet seed merges plus observed trainer/merchant metadata; it is intentionally outside `TurboFaceDB` profiles and outside build-invalidated `TurboFaceCacheDB`. `TurboFaceTrainerCharDB` stores character-local ignore lists, collapsed groups, known pet state, and Training Queue state. `InitSavedVariables()` is idempotent and normalizes every owned container at login and before capture.

**Deferred static data.** Retained `Trainer/data/*.lua` files register loader closures in `Trainer.BuiltinLoaders`; no large table is constructed when Training is disabled. `BuiltinMerge.lua` merges only class, Hunter pet-trainer, and Warlock pet seed facts, then releases staging tables. LibProfessionDB's generated files independently register `ns.LibProfessionDBDataLoaders`; those closures materialize the recipe tables only on the first Recipes view and are then released. Profession/recipe SavedVariable seed merge branches no longer exist.

**Spellbook views.** `Trainer/UI_Spellbook.lua` owns `Class Training` and `Skills` side tabs. Class Training consumes the class seed/discovery store and evaluates current known/talent state at render time. Skills owns Weapon Master entries, profession starters, and profession proficiency ranks from `Trainer/SkillData.lua`; it combines character-level and profession-skill requirements and keeps book/quest-only secondary-profession ranks visible but non-queueable.

**Profession side views.** `Trainer/UI_Profession.lua` owns `Training` and `Recipes` next to the native profession window. Training builds an always-available baseline from trainer-only recipes in the embedded MIT-licensed LibProfessionDB 1.7.0 subset, filters proficiency-rank rows into the Skills owner, and overlays the persistent live-trainer snapshot for authoritative cost/status details. When LibProfessionDB deliberately lacks a verified Vanilla trainer learn requirement, Training keeps the row conservatively under Not Yet Available as `Skill ?`; it never substitutes the recipe's crafting-difficulty threshold. Recipes admits recipes with a confirmed vendor, quest, container, or drop path. LibProfessionDB's client-derived recipe-item index excludes profession-rank books. Because its community-derived trainer flags over-classify some externally acquired recipes, mixed trainer/external rows remain in Recipes while only trainer-without-external-source rows seed Training; observed live rows overlay the baseline by spell ID. Auto-taught, unknown-source, and never-implemented rows remain excluded. The currently open Classic TradeSkill book supplies live known state and icons. Recipes separates missing, ignored, and already-known entries, exposes only external acquisition sources in tooltips, and refreshes on `TRADE_SKILL_UPDATE`. The generated database files register deferred closures at startup and materialize when either profession view first needs them.

**General-skill classification.** `Trainer/SkillData.lua` owns weapon-skill identities, primary/secondary profession starters, and profession rank requirements. `TrainerCapture.lua` resolves Weapon Master and profession-rank services into `skillData` so they cannot leak into the class-spell catalog. Current profession ownership is read through `ns.Skills`, with the legacy skill-line APIs used only as compatibility fallback.

**Training Queue.** Queue state is per-character. Class-spell rows, queueable Skills rows, and trainer-taught profession rows can be ordered for auto-training. The worker respects explicit queue order, stops when the next eligible priority cannot be afforded, submits selected trainer indices in descending index order only to survive Blizzard list reindexing, and removes intent only after the trainer/known-state confirms success. Book/quest ranks and profession Recipes remain non-queueable.

**Dormancy.** UI construction is deferred through `Trainer:AddBuilder`; a disabled Training module owns no avoidable event frame or child UI. Live enable builds once, while later disable unregisters detachable events and predicate-gates irreversible hooks. Large hidden lists mark themselves dirty rather than rebuilding on unrelated level/spell churn until shown.

**Accepted exception to §1.3: `ClassTrainerFrame_Update`.** `Trainer/TrainerListUI.lua` replaces the Blizzard global while Training is active so ignored trainer rows can be removed without a second full FrameXML layout pass. This filtering approach is retained from the MIT-licensed What's Training? lineage. The replacement is predicate-gated and hands control to the captured Blizzard original when Training is inactive. Revisit this immediately if taint/blocked-action reports name `ClassTrainer*`, or if Blizzard exposes a supported trainer-list filtering API.

### 18.8 Net Worth

Mover-dependent. It combines current money with TurboFace's bag-junk vendor valuation.
When effectively disabled it should not keep money/bag/merchant event listeners alive.

The junk-value component is cached by InventoryManager and invalidated only when bag
contents or TurboFace junk state changes. `PLAYER_MONEY` therefore updates the displayed
coin total without rescanning every carried bag slot; `BAG_UPDATE_DELAYED` invalidates
the cached junk valuation before the next Net Worth calculation.

### 18.9 Hearthstone Tracker

Mover-dependent TurboFace widget. No frame/events when effectively disabled. The
base widget always owns `Hearth: <bind location>`; its two helpers are independently
profile-gated from Speedrun -> Hearthstone Tracker:

- `hearthTimerEnabled` controls the left-side Hearthstone cooldown / green `Ready`
  state. Disabling it hides that text, unregisters `BAG_UPDATE_COOLDOWN`, and removes
  the 1 Hz cadence client immediately.
- `hearthAutoBindEnabled` controls the right-side one-shot auto-bind checkbox and
  its gossip/confirmation automation. Disabling it hides the checkbox, clears any
  armed one-shot state, and unregisters `GOSSIP_SHOW` / `CONFIRM_BINDER`.

Both settings default on. They do not replace `hearthEnabled`: the parent Hearthstone setting and
Mover dependency still gate the entire widget. The dynamic frame/mover width is
recomputed from only the enabled pieces, so turning either helper off does not leave
an empty gap or oversized mover target.

Cooldown ownership stays local to `Hearthstone.lua`: item ID `6948` is queried via
the 1.15.9 item-cooldown API and the display joins `ns.Cadence` at 1 Hz only while
a real cooldown is active *and* `hearthTimerEnabled` is true. `BAG_UPDATE_COOLDOWN`
starts/re-evaluates that cadence only in that mode; ready Hearthstones park it
completely and display green `Ready` text. There is no permanent `OnUpdate`.

When Auto-Bind is enabled, the right-side checkbox is intentionally one-shot runtime
state, not a saved armed state. When armed, the next innkeeper binder interaction is
automated: `GOSSIP_SHOW` identifies the locale-independent Binder gossip option and
selects it. The resulting Classic `CONFIRM_BINDER` event is then deferred by one
frame so Blizzard can finish creating its `CONFIRM_BINDER` StaticPopup; TurboFace
invokes that popup's real Accept path with `StaticPopup_OnClick(..., 1)`. This is
important: blindly calling `ConfirmBinder()` can confirm the engine interaction but
leave Blizzard's confirmation popup visible, and event-handler ordering can also run
an addon callback before UIParent has shown the popup. Clicking the actual deferred
popup both calls the client's confirmation and dismisses the dialog exactly like a
player click. A successful accept clears the checkbox. A legacy direct
`ConfirmBinder()` fallback exists only for UI replacements that do not expose the
stock popup. If no Binder option is present, the arm remains set for the next NPC.
The checkbox itself remains clickable even when the mover element is configured
click-through; the rest of the Hearthstone widget still honors mover click-through,
and hidden, disabled, or Auto-Bind-off states disable the checkbox so an invisible
control cannot eat input.

This one-shot bind helper is separate from Hearthstone batching below. Explicitly
arming auto-bind consumes the binder confirmation normally, so there is no binder
popup left for a batching attempt on that same interaction.

### 18.10 UnstuckSkips notifier hook

`UnstuckSkipsVisual.lua` is presentation-only integration with the optional UnstuckSkips addon.
UnstuckSkips retains ownership of all partition data and target selection: TurboFace calls the loaded
`UnstuckSkipsFrame:UpdateTarget()` method and reads its resulting text, then suppresses only the
original notifier frame while the TurboFace visual is active. Disabling the TurboFace visual restores
the native notifier when its own UnstuckSkips setting permits it.

The row mirrors the Hearthstone widget: `Ready` or `H:MM:SS`, `UnstuckSkip: <target>`, and an
interactive checkbox. Checking the box records `GetServerTime() + 14400` in
`TurboFaceCharDB.unstuckSkip.readyAt`; an absolute epoch deadline makes the four-hour estimate advance
while logged out. Unchecking clears the estimate. This is deliberately a user-started representation
of Blizzard's service cooldown, not a claim that the service exposes a queryable cooldown API.
The shared 1 Hz cadence updates both countdown and delegated target text only while the optional addon,
feature, mover, and display are active. No UnstuckSkips data or implementation is copied into TurboFace.

### 18.11 Tracking Icon

Mover-dependent replacement indicator. Its user-facing settings live under **Plus -> Minimap Tracking Icon**; runtime ownership remains `MinimapTracker.lua` / `ns.Tracker`, independent of the Plus module family. Blizzard's own tracking control should only be restored if TurboFace previously suppressed it; starting disabled is a no-op.

### 18.12 Minimap Button
Not mover-dependent. It rides the minimap edge. Its drag `OnUpdate` exists only
during an active drag.

**Always on — no enable setting.** It is the primary route to the config panel and
mover lock. Only `minimapButtonAngle` persists; `minimapButtonEnabled` is a retired key
that current normalization removes and runtime never reads. The canonical TurboFace branding
art is Blizzard FileID **237572**. `MinimapButton.lua` uses that FileID directly, and
`TurboFace.toc` declares the same asset through `## IconTexture: 237572` for the AddOns-list icon.

### 18.13 Shield Bars

`unitframes.nanShieldEnabled` is the shared **Shield Bars** feature gate. The `nanShield*`
profile keys and `ns.NanShield` method table are legacy compatibility names only; the current
implementation is TurboFace-owned and is split into `UnitFrames/ShieldData.lua` (Classic Era
shield facts/model metadata) and `UnitFrames/nanShield.lua` (runtime state + rendering).

Player and Party are separate presentation demands:

- **Player:** requires the Player UnitFrame child. Known player-accessible Classic Era shield
  families are modeled from named metadata (`school`, base/per-level progression, coefficient,
  power source, and optional talent modifier). The current catalog covers Priest Power Word:
  Shield, Mage Mana/Fire/Frost/Ice Barrier, Warlock Sacrifice/Spellstone/Shadow Ward, and the
  Classic protection-effect ranks. NPC, test/DNT, Season-of-Discovery, and expansion-only
  entries are intentionally excluded. If `UnitGetTotalAbsorbs()` proves authoritative by returning
  a non-zero total on the running client, TurboFace reconciles modeled school proportions to that
  total and can surface otherwise-unmodeled absorbs as an all-school remainder.
- **Party:** requires the Party UnitFrame child and `UnitClass("player") == PRIEST`. Only a
  directly observed local-caster **Power Word: Shield** application may create party absorb
  state. External shields are never estimated from the local Priest's stats.

The shield school palette is TurboFace-owned and lives in `ShieldData.lua`. Player-local spell
power is applied only when the family declares a power source: Power Word: Shield uses healing
power, while Ice Barrier uses Frost spell power. Improved Power Word: Shield and Improved
Voidwalker are detected from the learned passive spell ranks with a Classic talent-index fallback.
The former Season-of-Discovery Advanced Warding rune branch is not part of the Classic Era model.

Party PW:S state is keyed by destination GUID. The application uses the same TurboFace PW:S rank
model, local bonus-healing calculation, and Improved Power Word: Shield modifier. Matching
`SPELL_ABSORBED` events decrement the remaining value. Two C-filtered `UNIT_AURA` watchers
(`party1/2`, `party3/4`) validate only the tracked shields so expiration, dispel, or another
caster's replacement clears the estimate. `GROUP_ROSTER_UPDATE` prunes recycled/departed GUIDs.
On `PLAYER_ENTERING_WORLD`, Party shield state is intentionally discarded rather than
reconstructed because the remaining amount cannot be known exactly without having observed the
original local cast.

The Party surface lives in the fixed 70x10 name opening and fills left-to-right as remaining/max
absorb. While active it hides the TurboFace-owned party name; removal restores the name according
to `showPartyNames`. `UnitFrames.lua` owns the fixed coordinates and exposes only
`UF.LayoutPartyNameOverlay`/`UF.GetPartyOwnedName` to the Shield Bar renderer. Party surfaces are
prepared/re-laid out only during the existing out-of-combat party styling path, so a first shield
cast in combat never needs to create or re-anchor a child of a protected PartyFrame.

`nanShieldShowText` is the single visibility gate for Player combined values, Player per-school
values, and Priest Party values; it defaults enabled. `nanShieldPerSection` selects per-school
Player values when multiple school segments coexist, otherwise the Player surface shows one
centered total. Both Player and Party text use the feature-local `nanShieldFont`,
`nanShieldTextStyle`, and `nanShieldFontSize` settings exposed under **Unit Frames -> Shield Bars**.

The Player Shield Bar geometry deliberately extends **one pixel farther left** while preserving
its previous right edge. In the fixed-art name-slot layout this is implemented as +1 px width plus
a 0.5 px leftward center shift; the fallback-above-health layout moves only its left anchor
outward. Segment sizing derives from the final bar width.

### 18.14 Skill Tracker

The mover-dependent Skill Tracker may optionally limit its Weapon Skills category to
the weapon types currently equipped in the main-hand, off-hand, and ranged slots.
The filter is off by default. When enabled, it can display at most three distinct
equipped-weapon rows, always retains Defense, and substitutes Unarmed when neither
main-hand nor off-hand slot contains a weapon. `PLAYER_EQUIPMENT_CHANGED` redraws the
tracker without rescanning skill lines; the listener is registered only while this
optional filter is active.

---

## 19. Hearthstone batching (`HearthBatch.lua`)

Batching fires `ConfirmBinder()` so that it reaches the server in the same batch
tick as a Hearthstone cast completing. The result is that the bind updates to the
innkeeper you are standing at *and* the hearth teleports you to your old home.
Off by default; hooks install lazily on enable.

### 19.1 Timing model

The server processes packets in discrete batch ticks (`W`, taken as ~10ms). At
the tick boundary where the cast completes it also processes everything received
since the previous boundary, so the safe arrival window is `(T_end - W, T_end]`.
Failure is asymmetric — early is survivable, late is not:

| Arrival | Result |
| --- | --- |
| Same tick as `T_end` | Bind updates and you teleport away — success |
| One or more ticks early | Bind updates first, then you hearth to it — wasted |
| After `T_end` | You teleport, the popup dies with you — wasted |

**A batch always teleports you.** The discriminator between success and an early
fire is *which destination* you land at, not whether a teleport happened. This
is why outcome classification measures displacement.

### 19.2 The anchor (do not "improve" this)

The anchor is `GetTime()` at the `UseAction`/`UseContainerItem` hook — the moment
the client sends the use packet — **not** `UNIT_SPELLCAST_START`.

Both the use packet and the confirm packet travel the same upstream path, so
firing at `anchor + 10s` arrives at the same phase in the tick cycle as the cast
start did, and upstream latency cancels with no need to estimate it. Anchoring on
`UNIT_SPELLCAST_START` would bake in a full round trip of error. That event is
registered only to confirm the cast began and to sample round-trip time.

### 19.3 Frame rate is the limiting factor

`ConfirmBinder()` can only be called from a frame, so the send lands somewhere
inside one frame interval. Against a ~10ms window, a 60fps client (16.7ms frames)
cannot reliably hit it; past ~150fps quantization is comfortably inside the
window and network jitter dominates instead.

Two consequences:

- The driver selects the **nearest** frame boundary to the target, not the first
  one past it. First-past biases every send late, which is the unsafe direction.
- `maxfps` is raised during the cast as a **floor, never a ceiling** — applied
  only when the player's existing cap is lower, and never to an uncapped client.
  It is owned via `ns.ApplyOwnedCVars` so a crash mid-cast cannot strand a
  persisted CVar; `Init` and every `PLAYER_ENTERING_WORLD` restore orphans.

### 19.4 Calibration and its failure modes

Outcomes are classified from bind location plus map displacement, and the lead is
nudged toward whichever side failed. Two rules matter more than the mechanism:

- **Classification runs on `PLAYER_ENTERING_WORLD`, not a fixed delay.** A hearth
  runs a loading screen and position APIs read stale or empty until it completes.
  A 2s timer raced that screen and reported genuine hits as "did not teleport".
  The timer survives only as a backstop for a hearth that never crossed a map.
- **An uncertain read must change nothing.** A false "early" walks the lead toward
  the window edge and makes real failures more likely, so a misclassification is
  worse than no classification. Unknown position data, or a cast-end event near
  the fire moment that we could not confirm as completion, records no outcome and
  nudges nothing.

`UNIT_SPELLCAST_STOP` fires on success too. Inside `CAST_END_GRACE` of the fire
moment it is never treated as an abort — tearing the driver down there would lose
a batch about to land — but unless `UNIT_SPELLCAST_SUCCEEDED` confirmed the cast,
the attempt is marked suspect and excluded from calibration.

### 19.5 Storage: pooled by realm, account-wide

Timing data describes a connection path, not a character, so it pools in
`TurboFaceCacheDB.hearthBatch.realms[realm]`. A rerolled character inherits the
converged lead — arguably worth more than the readout, since it means the first
hearth fires at the optimum instead of walking there from the default.

- Keyed by realm: merging a US-West and an EU path inflates apparent jitter on
  both. Fallback chain is realm → all realms → prior.
- In `CacheDB` because that is outside profile/import snapshots, with an explicit
  exception in the build-change wipe (`Core/Config.lua`) — it is measured behaviour,
  not discovery cache, and wiping it each patch would cold-start a speedrunner at
  the worst moment.
- Everything is timestamped and age-evicted (30 days). Pooling removes the
  recency that per-character data had implicitly, and stale samples produce a
  confident number about conditions that no longer exist.

### 19.6 The success estimate, and how much to trust it

`P = F(lead) - F(lead - W)` where `F` is the CDF of frame quantization (uniform)
convolved with transit jitter (normal). Validated against Monte Carlo to three
decimals. Latency does not appear — only its variance does.

Jitter is estimated from **successive differences** of temporally adjacent
samples, never their global spread. Samples are far apart in time, so their
spread is dominated by slow baseline drift; differencing cancels it. Two lessons
are encoded in the constants:

- The pairing window must match the cadence that produces samples. A 3600s window
  was unsatisfiable against a 60-minute hearth cooldown and silently rejected
  every pair. It is now 20 minutes, which admits alt-hop and Astral Recall pairs,
  with a wider baseline-subtracted route for anything further apart.
- Quadrature subtraction of the nuisance variance does **not** work here: a
  MAD-scaled figure is not a standard deviation for a uniform-plus-normal
  mixture. Fit the model instead.

Known limits, all of which argue for treating the observed hit rate as ground
truth: `W` is assumed and now load-bearing in two places; the jitter fit carries
~±1.2ms of irreducible noise; and the sample is a round trip during a cast, which
is a proxy for the upstream difference between two packets 10s apart. The Beta
blend exists for exactly this reason — the model's weight scales with how many
clean pairs back it, so it cannot outvote a real record it has not earned.

### 19.7 Performance rules specific to this module

The estimator must never degrade the thing it measures. Section 21 applies, plus:

- The jitter refit (~0.9ms) and the model tabulation (~10ms one-off) are both
  gated behind `attempt` — a new sample arrives at `UNIT_SPELLCAST_START`, mid-cast,
  with the fire frame still ahead.
- The driver's frame-interval median reuses a scratch table and recomputes at most
  4×/sec. Allocating per frame meant ~8000 throwaway tables per cast, and a GC
  stall is milliseconds against a 10ms window.
- Constant per-frame cost is timing-neutral (it shifts both packets equally and
  cancels); **uneven** cost is not. Optimise for spikes and allocations, not
  total CPU.

## 20. Plus subsystem contracts

### 20.1 Automation

Event-driven features register only the events their enabled options require.

The shared StaticPopup hook is lazy. It is installed when Spirit Healer automation,
PvP release, or the popup debug tracer requires it.

Single-option gossip does not rely on an NPC-ID catalog or on Classic's inconsistently
populated `selectOptionWhenOnlyOption` field. TurboFace selects only when the gossip window
contains exactly one option and zero available or active quests. The 1.15.9 option-ID path
is preferred, with order-index and legacy title/type API fallbacks for compatible UI replacements.

Auto Quest Accept and Auto Quest Turn-in are independent, default-off settings. They enter
completed quests before available quests at gossip/quest-greeting NPCs, accept
`QUEST_DETAIL`, advance only completable `QUEST_PROGRESS`, and claim `QUEST_COMPLETE`
only when Blizzard reports zero or one selectable reward. Two or more reward choices remain
manual. After each accept or reward, a bounded delayed re-scan continues through additional
ready turn-ins and available quests exposed by that NPC, including quests unlocked by the
preceding turn-in. Per-NPC processed IDs prevent stale gossip payloads from reopening the
same quest while in-progress entries are skipped. Holding Shift bypasses every automated
quest action, and disabling both settings removes the quest event listener entirely. The implementation uses current `C_GossipInfo`
quest IDs with legacy Classic gossip and quest-greeting selectors as compatibility fallbacks.
Modern active-quest iteration uses Blizzard's explicit active count rather than relying on Lua
table length, and reconciles each gossip entry's completion flag with `C_QuestLog.IsComplete`;
this is required when one NPC mixes completed and in-progress quests and the gossip payload's
completion field is missing or stale.

Spirit Healer automation is destructive (durability/sickness), defaults off, is
ghost-gated, and supports Shift cancellation.

### 20.2 Social

Duel, party invite, friend request, shared quest, and whisper-invite listeners are
registered independently according to active settings.

### 20.3 Interface and Chat

Many of these features are reload-applied because they alter Blizzard frame scripts or
install one-way hooks. Do not pretend they have perfect live teardown.

The section gate must still prevent new hooks from being installed on a clean login
when the section is off.

The former Plus/Interface **Show free bag slots on backpack** feature is retired; Classic Era now owns that display natively. TurboFace must not hook `MainMenuBarBackpackButton_UpdateFreeSlots` or add backpack free-slot tooltip text. This does not affect the standalone Speedrun **Free Bag Slot Counter** in `Inventory/BagSlots.lua`.

The Chat section's optional **Text outline** setting is presentation-only. It iterates
existing Blizzard `ChatFrame1..50` scrolling message frames once at initialization and
adds the `OUTLINE` font flag while preserving the frame's current font file, point size,
and any unrelated font flags. It does **not** call shadow setters, so Blizzard's existing
subtle chat-text shadow remains intact. A lazy `FCF_OpenTemporaryWindow` hook applies the
same outline to temporary chat windows created later; there is no polling/`OnUpdate`.
Because Blizzard's chat font-size path reuses the frame's existing font flags, subsequent
font-size changes retain the outline without a TurboFace maintenance driver.

### 20.4 System

CVar features use persistent ownership rather than guessed defaults.

Dynamic listeners such as rested-emote, audio-device, and loot-warning handling are
registered only when the corresponding feature needs them. Taxi ownership belongs only
to Flight Bar.

Reload-applied hook features (for example faster looting or vendor tooltip behavior)
are installed only when enabled at initialization.
Level-1 cinematic auto-skip is **not** a Plus/System feature; Quick Setup owns that behavior so
there is one cinematic owner.

### 20.5 Flight Bar

Mover-dependent and reload-oriented. The taxi hook is installed only when the feature
is effectively enabled at initialization; its callback is predicate-gated.

The Flight Bar category defaults enabled and owns the bar without a separate visibility
setting. On a learned taxi route the bar shows its background and destination and fills
forward as the flight progresses. Width and scale are its only presentation settings.
The former visibility, background, destination, fill-direction, and TTS settings were retired
in schema 74; Flight Bar does not call the voice-chat text-to-speech API.

TurboFace uses a hybrid flight-time model. `Plus/FlightData.lua` supplies the attributed CC BY 2.0
Flight Timer Classic baseline for immediate first-flight estimates on the original Classic network.
The seed identifies endpoints by Flight Timer Classic's taxi-map X-coordinate hash. TurboFace also
identifies the complete Blizzard route from every segment coordinate, times completed flights, and
stores those observations account-wide under `TurboFaceCacheDB.flightTimes` by faction + continent +
full route key. A learned full-route value always overrides the endpoint seed. Measurements use a
bounded running mean so later flights can correct a laggy sample without allowing one outlier to
dominate; the seed itself is retained only as comparison metadata and is not blended into the
observed mean. This cache survives client-build resets and remains outside profile export/import.

Routes absent from the seed show a visible count-up `Learning` bar on their first flight rather than
silently hiding the widget. The ordinary `PLAYER_CONTROL_GAINED` completion event saves a measurement,
while the bar independently observes the `UnitOnTaxi` true-to-false transition as a landing fallback.
Early landing cancels the pending measurement so a shortened trip cannot corrupt the full-route mean.

Taxi routes are snapshotted synchronously while `TAXIMAP_OPENED` owns valid node/segment APIs.
This is required because TurboFace's safe `TakeTaxiNode` post-hook runs after Blizzard's protected
function, when the taxi map may already be closing and live route queries can return nothing. The
post-hook consumes the immutable snapshot first and uses live resolution only as a fallback, so an
unknown route always retains the continent/key needed to save its first completed measurement.

Taxi destination hover and `TakeTaxiNode` share the same multi-hop route identity. A learned
destination adds `Flight Time: M:SS` (or `H:MM:SS`) to Blizzard's existing tooltip; an uncovered
route reports that it will learn on the first flight. The normal Classic `TaxiNodeOnButtonEnter` path
is hooked when present. Clients that
create taxi buttons lazily use a `TAXIMAP_OPENED` fallback that hooks each button once after
Blizzard builds the map—there is no tooltip polling and no bundled timing database.

---

## 21. Performance rules

TurboFace is feature-rich but should remain lightweight. Optimize ownership and wake-up
frequency before micro-optimizing arithmetic.

### 21.1 Hot-path rules

- Decode raw CLEU once through `ns.CLEU`; new stable consumers should register a
  subevent filter.
- Never retain the dispatcher's reusable CLEU payload table.
- Prefer event invalidation + cached summaries over repeated aura scans.
- Do not allocate event-history tables in meters/predictors when aggregate counters are
  sufficient.
- Cache spell/media/settings lookups outside high-frequency render loops where safe.
- Avoid creating temporary tables solely to sort/filter every health event; reuse work
  buffers when a hot path needs sorting.
- Do not poll an API at 30/60/100 Hz when a Blizzard event can invalidate the value.

### 21.2 Driver rules

Every periodic job must have an explicit **reason to be awake**, an explicit
cadence, and an explicit idle path that removes it from `ns.Cadence` (or cancels
its dedicated low-frequency ticker).

Current examples:

- RegenTicks: ~33 Hz only while a Mana/Energy/Rage/Health marker is eligible.
- Combat Meter: 10 Hz while the movable window is visible; 4 Hz finalization-only cadence while mover-hidden or in badge-only headless mode; damage/healing collection remains event/CLEU-driven.
- DPS/HPS badge: 4 Hz only while its combat refresh ticker is active; it owns no CLEU.
- DoT prediction: no continuous predictor driver; consumers reuse event-
  invalidated cache summaries.
- Heal prediction: event/cast/aura driven; renderer updates from engine
  notifications.
- Nameplate combo points: 10 Hz only while an eligible target plate exists.
- Nameplate pooled-frame lifecycle guard: every 0.5s only while tracked native plates exist;
  it is a lifecycle-repair timer, not a renderer ticker, stops when the tracked map is empty, and
  fully rebinds any stable token whose live GUID changed.
- Swing Timers: ~30 Hz only while an active countdown/poll is required.
- Player/target castbars: at most 60 Hz, and only while a cast/channel/failure hold exists.
- Bubble spend/swing: shared active sets, 60/30 Hz respectively, parked when
  their sets empty.
- Aura dirty/ToT compatibility polls: 10/4 Hz and demand-gated; Party/Pet aura reconciliation is 1 Hz per active surface and their shared timed-icon expiry driver is 4 Hz only while needed.
- Hunter Feed Pet happiness, Hearthstone cooldown text, XP text, and FPS text: 1 Hz only while their respective consumer/visual is active.

A periodic job must **not** use rendered-frame `OnUpdate` merely to implement its
own throttle. This matters especially on uncapped/high-FPS clients, where the
empty throttle checks themselves can dominate otherwise tiny subsystems.

### 21.3 Combat-path contract

The combat path obeys these current contracts:

1. `ns.CLEU` routes by subevent instead of invoking every consumer for every event.
2. Player regen/tick markers have **zero CLEU dependency**.
3. `Power/PowerCost.lua` does not subscribe to duplicate `UNIT_*_FREQUENT` events.
4. DoT prediction no longer lets a 0.10-second TTL force repeated 40-debuff scans on
   actively changing nameplates. Aura events invalidate and notify the explicit nameplate/unit-frame
   consumers immediately; tick/health events update damage geometry, and a 0.50-second TTL is only a
   safety rescan.
5. CombatMeter accounting is dormant only when **both** consumers are absent: no movable meter window and no independent DPS/HPS badge. A disabled window alone may still leave headless accounting active for the badge (§7.2.3–§7.2.4).
6. The obsolete legacy nameplate castbar event dispatcher and fallback renderer have been removed; native Blizzard castbars own the complete nameplate cast lifecycle.
7. Nameplate combo polling is owned by Nameplates, not Unit Frames, and is demand-driven.
8. Prediction engines require at least one enabled presentation surface. Target/ToT DoT and all Heal Prediction unit-frame surfaces attach to Blizzard bars and therefore do **not** require TurboFace UnitFrame child gates; their own per-surface preferences are authoritative.
9. Warrior Overpower is a Nameplates consumer and cannot keep CLEU/nameplate runtime
   alive when the Nameplates master is off.
10. Trainer live-disable removes detachable child events and predicate-gates every
    irreversible UI hook/callback that can remain installed.
11. The aura first-layout queue uses a boolean `C_Timer.After` scheduling guard;
    `C_Timer.After` is never treated as if it returned a timer handle.
12. Frame-rate-throttled periodic drivers were migrated to `ns.Cadence`; one dynamic
    native master clock runs only at the fastest active 1/4/10/20/30/33/60 Hz cadence,
    services slower clients from accumulated elapsed time, and cancels itself when empty.
13. Nameplate castbars and Bubble spend effects use shared active sets rather than one
    animation driver per plate/bar.
14. The always-visible Experience Bar and optional FPS counter no longer enter Lua every
    rendered frame merely to run 1 Hz text updates.
15. Shifted Druid Mana, Cat Energy, and Health markers render from one shared 2-second
    heartbeat. Energy/Health may seed or maintain that phase under the confidence rules in
    §15.2; capped Mana explicitly permits validated out-of-combat Health heartbeats to keep
    the shared phase fresh.
16. Generic combat exit is not a license to rebuild caches. Hotbar Power performs its 50 ms
    post-combat structural rebuild only when work was actually deferred during lockdown, and
    Class Buffs does not rebuild its spell/name/icon catalog merely because combat started or
    ended.
17. `BAG_UPDATE_DELAYED` is a TurboFace bag-state invalidation, not a reason to force a second
    Baganator `ItemWidgets` pass. Explicit Baganator widget refresh is reserved for TurboFace-
    only state changes such as junk marks/settings (§18.5).
18. Loot-toast bursts coalesce presentation rendering, each live entry owns at most one
    cancellable expiry timer, and money duplicate suppression uses chat-vs-player amount
    credits so same-value multi-body drops and aggregate `PLAYER_MONEY` deltas reconcile
    correctly (§18.4).
19. Net Worth caches carried-junk valuation. Money-only events update the coin component
    without rescanning every bag slot; bag/junk-state changes invalidate the cache (§18.8).
20. Performance diagnosis is native-first: `C_AddOnProfiler` baseline/delta and post-kill
    traces are the low-overhead tools. Legacy `scriptProfile` function attribution is opt-in
    deep diagnosis only because its own sampling overhead can exceed normal TurboFace CPU.

`/tf debug` reports both raw CLEU/s and dispatched handlers/s. A small one-to-one count
means the dispatcher is not a fan-out hotspot; do not keep optimizing CLEU merely
because combat naturally produces occasional event bursts.

### 21.4 Disabled-state audit

For every optional feature, be able to answer all of these while it is off:

```text
registered feature events?     expected: no
registered CLEU consumer?      expected: no, unless another enabled feature owns it
running OnUpdate/ticker?       expected: no
TurboFace visual frames made?  expected: no avoidable construction
periodic scans?                expected: no
external CVar/state override?  expected: restored/not acquired
```

One-way hooks installed during a previously active session are the exception; their
callback bodies must be cheap and predicate-gated.

### 21.5 Performance diagnosis

Use measurement before speculative refactors.

`/tf debug` gives low-overhead activity counters including:

```text
CLEU/s
handlers/s
UNIT_AURA/s
Aura flush/s
HP batch/s
Threat batch/s
Lua memory / memory delta
```

For addon CPU snapshots, enable Blizzard script profiling only temporarily:

```text
/console scriptProfile 1
/reload
/tf debug cpu
```

For subsystem attribution and intermittent spikes, use the opt-in peak profiler.
`Core/CPUProfiler.lua` owns this system independently from the lightweight debug
harness. The short `/tf cpu ...` commands are canonical; `/tf debug cpu ...` is
retained as an equivalent compatibility route.

```text
/tf cpu status
/tf cpu native        # always-on Blizzard metric; scriptProfile not required
/tf cpu native baseline  # capture a local baseline for delta measurements
/tf cpu native delta     # show threshold-count deltas since that baseline
/tf cpu native top       # top addons by recent average and peak native CPU
/tf cpu kill start       # 4s hostile-death + 5s post-combat native tracer
/tf cpu kill report      # show recent kill windows and measured cleanup paths
/tf cpu kill stop        # stop death tracing and print saved windows
/tf cpu start
# reproduce normal idle/out-of-combat play and at least one combat window
/tf cpu report
/tf cpu stop
```

The detailed profiler samples registered TurboFace entry points every 0.5 seconds
with `GetFunctionCPUUsage()`, keeps combat and out-of-combat windows separate, and
reports both aggregate subsystem CPU and the highest peak windows. Detail rows use
**inclusive call-tree CPU** so an externally-driven entry point answers the useful
question "how much work did this callback cause?" Parent/child rows can therefore
overlap and must **never** be summed to derive exact coverage or an `untracked`
remainder. The profiler reports its own previously-completed `Sample()` call-tree CPU
separately so diagnostic bookkeeping cannot be mistaken for gameplay work. Embedded-library hot paths (notably LibClassicDurations CLEU handling) should also be
registered when they contribute to TurboFace's addon-wide CPU total.

Classic Era 1.15.9 also exposes Blizzard's newer `C_AddOnProfiler` metrics. They are
always enabled and do **not** require `scriptProfile=1`, so `/tf cpu native` is the
preferred low-overhead sanity check for session/recent/last/peak addon time and counts
of ticks over 1/5/10/50 ms. Because client builds may not always exhibit the documented
UI-reload reset behavior consistently, diagnostic comparisons should prefer `/tf cpu
native baseline` followed by `/tf cpu native delta`; this measures local counter
increments and does not depend on Blizzard zeroing the absolute metrics.

`C_AddOnProfiler.GetTicksPerSecond()` is the native profiler-clock frequency used by
measured-call tick counters; it is **not** a UI-frame rate and must not be multiplied by
`RecentAverageTime` to derive a CPU percentage. Native average values therefore remain
in their documented `ms/tick` units.

For kill/post-combat-correlated spikes, `/tf cpu kill start` adds a dormant native
diagnostic. A hostile `UNIT_DIED`/`UNIT_DESTROYED` opens a four-second aftermath trace,
while `PLAYER_REGEN_ENABLED` starts a **fresh five-second post-combat trace**. The latter
is deliberately a new record instead of merely a marker: the final hostile death can be
more than four seconds before combat actually drops, which made the old tracer blind to
exactly the suspected post-combat burst. Each window samples native `LastTime`, records
XP/target/nameplate/loot/bag/combat-state ordering, and uses
`C_AddOnProfiler.MeasureCall` on selected TurboFace cleanup/update boundaries when
available. The tracer is independent of `scriptProfile`; its 50 Hz sampler exists only
while one of those short windows is active. The legacy `GetFunctionCPUUsage()` session
remains the opt-in deep-attribution tool and may alter performance because
`scriptProfile` itself has substantial overhead.

**Adding a boundary: use `ns.KillTrace`, and put it on the flush.**

```lua
ns.KillTrace(prefix, event, fn, ...)   -- Core/CPUProfiler.lua
```

It does nothing measurable outside a kill window, builds the tag string only inside
one (it is per-event concatenation and must not run on the normal path), and preserves
the handler's arguments and error semantics either way. Twelve sites wrote that guard
by hand before the helper existed; those are equivalent and may migrate
opportunistically rather than in a dedicated sweep (§1.5).

The placement rule matters more than the helper. For any coalesced subsystem the
`OnEvent` handler only sets a dirty flag and arms a latch, so instrumenting it reports
approximately zero while the real cost lands one flush later — and the subsystem looks
innocent. Boundaries therefore go on `ProcessDirtyHealth`/`ProcessDirtyThreat`/`ProcessDirtyAbsorb`/`ProcessQuestUpdate`, `FlushAuraBatch`,
and the `AuraStyle` dirty-flush restyles — not on the events that mark them dirty.

Current production boundaries cover `AuraStyle.lua`, `Nameplates/Auras.lua`,
`Nameplates/NameplateUnits.lua`, `Combat/CombatMeter.lua`, `Combat/SwingTimers.lua`,
`PartyPetAuras.lua`, and `Power/RegenTicks.lua`. `PartyAuras` owns its party
`UNIT_AURA` boundary plus a 1 Hz reconcile cadence; its trace belongs on full refresh/
reconcile work rather than cheap event dispatch. `RegenTicks` keeps its boundary on the
single `PowerCost` forwarding site.

Production hot paths contain no investigation-only native wrappers or work-volume counters.
The tracer keeps 4s/5s windowing, event markers, native threshold deltas, and established
low-frequency cleanup/flush boundaries. Cadence and shared timers are passively registered
with the detailed `/tf cpu start` profiler for opt-in deep attribution.

The detailed profiler's sampler uses a native `C_Timer.NewTicker(0.5)` rather than an
`OnUpdate`, and its hot sampling path avoids building/sorting a temporary table of
every target on every window; only qualifying peak windows copy their top entries.
Each peak records tracked-nameplate count, active `ns.Cadence` clients, active
aura/debuff timer widgets, TurboFace-attributed memory delta, and measured profiler
sampler CPU. Registration is passive: when the profiler is not running, targets are
only retained function references and add no hot-path timing wrappers.

Then disable it after the test because profiling itself costs performance:

```text
/console scriptProfile 0
/reload
```

If CPU spikes remain while CLEU/handler counts stay low, investigate non-CLEU paths
(nameplate health/aura/threat batches, active drivers, or garbage-collection pressure)
rather than assuming the centralized dispatcher is responsible.

Nameplate batch scheduling uses explicit boolean latches. `C_Timer.After()` does not
return a timer handle, so health/threat/absorb/quest coalescers must set their
`pending` field to `true` before scheduling and clear it in the callback. Assigning
the return value of `C_Timer.After()` would leave the latch nil and permit redundant
burst callbacks both in and out of combat.

## 22. Options GUI contract

`Options/OptionsGUI.lua` is lazy-built. It owns user-facing module/section controls and apply
paths; it should not become a second runtime owner of feature behavior.

Rules:

- module masters use `ns.ModuleEnabled()` / `ns.SetModuleEnabled()`;
- dependencies such as Movers must be communicated in UI text **and** enforced in
  runtime code;
- options requiring reload must say so;
- live options should call the owning module's public `Refresh`/apply method;
- every numeric slider uses the shared cyan direct-entry value box: dragging the slider and typing the value are two views of the same setting. Typed input is validated numerically, clamped to that slider's min/max endpoints when outside the range, snapped to its configured step when in range, and applied through the slider's normal `OnValueChanged` path; non-numeric input restores the last valid slider value. The edit field is explicitly layered above the slider mouse region so the full value box remains clickable. Percentage-formatted controls accept their displayed percentage units rather than the underlying normalized fraction;
- Options chrome keeps Blizzard `GameFont*` FontObjects for ordinary labels/buttons so Blizzard owns their native UI shadows. TurboFace category headers, collapse glyphs, and the Config title intentionally use Outline, but that override must go through the shared cached FontObject renderer rather than direct per-FontString `SetFont(..., "OUTLINE")`;
- concise feature descriptions may be passed through `Header(..., tooltipText)` so hovering the
  category heading reveals them without consuming permanent panel height; headers without tooltip
  text retain their existing hover behavior. Category tooltips anchor at the cursor and use a
  wrapped 320px width cap;
- `ApplySettings()` currently refreshes the shared DoT Prediction, Heal Prediction,
  Combat Meter, DPS/HPS Badge, PowerCost, Movers, and other live owners after updating cached DB state;
- the top-level tab order is **Movers, Global, Nameplates, Unit Frames, Class, Plus,
  Speedrun, Profile**. Profile owns profiles/import-export/presets/reset, including separate
  Settings, XP Splits, and Lvl1QuickSetup export/import pairs; Global owns Hotbar Power Overlay, DoT/Heal
  Prediction, Combat Meter, Player DPS/HPS Badge, Auras, player/target Swing Timers, and Cast Bars.
  Font/Text Style controls live with the feature they affect; there is no addon-wide typography section. There are no
  separate Auras or Power tabs and the former Misc tab is named Speedrun;
- Hotbar Power Overlay, DoT Prediction, Heal Prediction, Combat Meter, and the independent Player DPS/HPS Badge live in the **Global** tab
  because they are cross-surface/global feature gates rather than private UnitFrame/Nameplate ownership;
- the **Nameplates** tab is deliberately flat: TurboFace Nameplate Enhancements is its only visual
  parent, and every setting lives directly beneath that master without category headers. The
  headerless content container still participates in master gating and measured scroll layout.
  Checkbox rows use the explicit three-column grid, while sliders use the shared left-to-right
  `FlowPlace` behavior. Overlap Power Bar, Show Threat Number, and Mute Aggro Sounds are deliberate
  paired-row exceptions: each controller occupies column one, with its related height, font-size, or
  gain/loss volume sliders in the adjacent columns on that same row. The two-row CVar slider block
  precedes all checkboxes and owns Overlap Vertical/Horizontal, Selected Scale, Selected Alpha, and
  Not Selected Alpha through the reversible `nameplates.geometry` owner;
- **Nameplates -> Friendly NPC: Name + Title Only** owns `bubbleNameplates.friendlyNPCNameTitleOnly` as a live hybrid native presentation mode. It preserves Blizzard's NPC name text/lifecycle, temporarily applies Blizzard's show-only-name anchor policy with an additional 10px downward offset using write-only anchor calls, renders TurboFace's cached/scanned NPC title 1px beneath that name, and alpha-suppresses the native health/cast/art chassis without hiding the entire Blizzard UnitFrame. The title is inherent to this option and does not depend on the ordinary subtitle toggle; the amendment is reasserted after the pooled `UnitFrame:UpdateAnchors()` lifecycle and released by returning anchor ownership to Blizzard on exit/recycle. When NPC damaged-only is also enabled, this identity cluster remains the full-health state and the complete native chassis returns while damaged;
- **Nameplates -> Friendly Player: Show Only When Damaged** and **Friendly NPC: Show Only When Damaged** own `bubbleNameplates.friendlyPlayerDamagedOnly` / `friendlyNPCDamagedOnly`. Both are Blizzard-native two-state presentation modes: full health preserves native identity while selectively suppressing non-identity chassis and parking/removing the TurboFace augmentation host from `unitToPlate`; damage restores Blizzard's full native chassis and remaps/rebuilds the host. A feature-gated health-batch transition check uses the nameplate unit token directly so full-health identity plates need no hot TurboFace mapping;
- **Nameplates -> Job Icon** owns `bubbleNameplates.jobIcon`. It is a live independent checkbox under the Nameplates master. It applies only to recognized friendly/non-attackable NPCs, does not depend on `Friendly NPC: Name + Title Only`, and positions the glyph directly left of the NPC name on both identity-only and full-native presentations;
- **Nameplates -> Move Blizzard Rarity Icon to Right** owns `bubbleNameplates.rarityIconRight`. It is opt-in and changes only the anchor of Blizzard's existing PvE Elite, Rare, and Rare Elite `classificationIndicator`, placing its left edge at the right edge of `HealthBarsContainer`. Blizzard's `nameplateInfoDisplay` rarity bit, classification choice, atlas, scale, visibility, raid-target suppression, and PvP classification behavior remain native-owned. The texture returns to its XML `CENTER` anchor when disabled or recycled; `ClassificationFrame` itself never moves, preserving Blizzard aura geometry;
- **Nameplates -> Show Nameplate Swing Timer** owns `bubbleNameplates.swingTimer`. It is a live independent checkbox in the flat settings grid; it requires the Nameplates master but not Threat Number and not Global Swing Timers;
- **Nameplates -> Show Threat Number** owns `bubbleNameplates.threatNumber` plus the live `bubbleNameplates.threatTextFontSize` 6–16px slider. The number is anchored 5px left of the live HP bar, uses the rounded displayed integer for both text and color, renders true bright red `(1, 0, 0)` at visible 100, and uses the shared native FontObject-owned black `2,-2` shadow. Adjacent flat controls expose Aggro Audio (`muteAggroSounds`, `gainVolume`, `lossVolume`); audio remains runtime-independent from text visibility and only owns transition state while grouped/raiding and unmuted;
- Auras live under **Global -> Auras**. The Auras family master gates the family; normal Player/Target styling uses `auraEnabled`, while ToT, Party, and Pet use independent `modules.auras.tot/party/pet` children. Target icons-per-row, horizontal/vertical spacing, and Target/ToT growth controls are presented here while retaining their established `movers.aura` storage paths. The three Target/ToT aura position elements are classified under Movers -> Blizzard Movers. These surfaces must remain usable with stock Blizzard UnitFrames;
- **Unit Frames -> Player Bar Tick Markers** is the first section on the tab, above the
  **Enable TurboFace Unit Frames** master. It uses an independent section header (`ignoreMaster`) so
  its gate/settings remain reachable when the Unit Frames master is off. The master block participates
  in the section anchor chain, so collapsing Tick Markers pulls the master and all following sections up
  without leaving dead space. This is an explicit exception to the normal tab-master hiding rule because
  the renderer targets Blizzard player bars. Its concise feature summary uses the same wrapped,
  cursor-anchored category tooltip as ordinary headers;
- within Player Bar Tick Markers, marker gates come first, followed by shared marker geometry and
  the five marker/border color pairs. The HP and Power `+X` amount gates appear beneath those color
  controls, followed by the complete amount-only font, style, size, and X/Y offset group. Health
  Regen and Rage have the same dependent border toggle and independent border color as Mana, 5SR, and Energy;
- the Unit Frames checkbox **Bake Swing / Cast Timers into TurboFace frames** changes presentation
  mode only and refreshes timers + Movers; it must never become a runtime parent gate;
- Unit Frame value-format controls live with the frame they affect: Player, Target,
  Target-of-Target, Pet, and Party each own their Health Text and Power Text dropdowns. Player also
  owns its static Health Color, and Target owns Tagged Mob Grey. There is no combined
  `Health & Power Text` category. Bar Border Color remains General because it is shared, as do
  Class Colored Health, Color by HP %, Friendly Health, and Enemy Health: `SetHealthColor()` applies
  those policies across Target, Pet, and Party rather than Target alone;
- after the Unit Frames master, category order is fixed as **General, Shield Bars, Player, Target,
  Target of Target, Pet, Party**. Keep frame-local controls inside that sequence so ownership is
  visible without a separate cross-frame text category;
- do not duplicate feature logic inside GUI callbacks;
- preserve hidden stored preferences when a parent/dependency is disabled.
- scroll children start at a neutral 1px height until their lazy builder measures the real section
  stack. Every section resize explicitly refreshes the Classic scroll-child rectangle and clamps a
  stale vertical offset to the new range; do not restore a large placeholder height.

**Three-column flow.** The options scroll child is 504px wide and uses a shared
three-column grid: 164px controls at `x = 0`, `170`, and `340`, with two 6px gutters filling the
504px scroll-child width through the scrollbar-side edge. Standard sliders and dropdowns fill
left -> middle -> right through `FlowPlace` before advancing to the next row.
This keeps the placement rule centralized even though the builders continue to
pass `x = 0`.

`FlowPlace` stores the rendered row top, deepest next-y, and next column. Mixed
44/46px dropdown/slider rows therefore use the tallest control to determine the
following row. Any explicit spacer, checkbox/header transition, or control wider
than one grid column breaks the pending row and starts fresh. Deliberately wide
300px QoL controls keep their requested width and own a full row.

Paired checkbox/color helpers align to the first two grid columns; sections may
use the third column explicitly when three peers belong on one row. Movers uses
the full three-column grid for its element list, and Hotbar Power Overlay uses
all three columns for its top-level toggles. Slider labels remain single-line and
clamped so they cannot render under the neighboring control. `ColorPicker` itself
does not auto-flow because `ColorRow` owns its explicit row placement.

The visible options tab is named **QoL**; the internal `plus` namespace is retained for
saved-profile compatibility. Its section map is manually classified because that persisted
table is flat.
The login validator protects against a new UI setting accidentally bypassing a section
master. The visible QoL category order is fixed as **Map, Flight Bar, Automation, Social,
Interface, Chat, System, Minimap, Minimap Tracking Icon**. Each category is constructed by its
own local builder so presentation order can change without moving settings between runtime owners.

The Interface category's **Hide raid group labels** path owns the PlayerFrame raid indicator,
legacy raid-pullout titles, and all eight compact-raid group titles. It defers hooks separately
for `Blizzard_RaidUI` and `Blizzard_CompactRaidFrames`, then performs an immediate sweep so it
does not depend on joining a raid after login. **Show raid frame toggle button** also defers to
`Blizzard_CompactRaidFrames`, reparents the hidden-mode toggle to `UIParent`, explicitly shows it,
and reapplies that placement after Blizzard rebuilds the raid manager. The retired mail, quest,
and book font-resize settings and runtime FontObject mutation are pruned by schema 79.

---

## 23. Debugging and live validation

Useful commands:

```text
/tf debug              toggle live low-overhead counters
/tf cpu status         Profiler/API readiness and current session state
/tf cpu native         Blizzard always-on absolute addon metrics
/tf cpu native baseline Capture local threshold-counter baseline (no reset assumption)
/tf cpu native delta   Delta of >1/>5/>10/>50 ms ticks since baseline
/tf cpu native top     Top addons by native recent-average and peak metrics
/tf cpu kill start     Start native-only 2s hostile-death aftermath tracing
/tf cpu kill report    Show saved death windows, event sequence, and measured cleanup paths
/tf cpu kill stop      Stop kill tracing and print the saved report
/tf cpu snapshot       Addon-wide CPU/memory snapshot (requires scriptProfile)
/tf cpu start          Start 0.5s subsystem peak profiler
/tf cpu report         Print current combat/out-of-combat profiler report
/tf cpu stop           Stop profiler and print report
/tf debug cpu ...      Equivalent compatibility route for the same commands
/tf debug reset        reset live counters
/tf debug diag         patch-day API/frame/nameplate probe
/tf debug plates       nameplate add/remove event trace
/tf debug popups       StaticPopup name trace
/tf debug compat       compatibility report
/tf debug shadow       live nameplate shadow probe
/tf debug modules      effective module/Movers/Plus/CVar-owner report
/tf cvars [search]     open/toggle the developer CVar browser (optional initial filter)
/tf debug cvars        open the same CVar browser through the debug route
/tf debug dots         detailed target DoT prediction/timing state
/tf debug heals        direct + next-HoT prediction segments
/tf debug regen        Shared regen heartbeat / 5SR / source phase state
/tf debug meter        Combat Meter runtime/current/overall/roster state
```

Combat Meter commands:

```text
/tf meter current      show Current view
/tf meter overall      show Overall view
/tf meter reset        clear Current and Overall aggregates
```

Feature commands:

```text
/tfgrocery             open the Grocery List window
/tfgrocery buy         re-run the order at the currently open vendor
/tfgrocery clear       empty the queue
```

Live counters are deliberately low-overhead: instrumented hot paths only increment
existing numbers when `ns.DebugCounters` is non-nil. The debug frame itself refreshes
once per second while visible.

### 23.1 Recommended modularity matrix

Before a release that changes module activation, test at least:

1. **All major modules OFF** after `/reload`.
   - No TurboFace nameplates/unit-frame styling/custom widgets.
   - No unexpected Blizzard frame suppression.
   - `/tf debug modules` reflects the stored state.

2. **Unit Frames ON, each child OFF individually**.
   - Disabled Player/Target/ToT/Party/Pet remains Blizzard-native.
   - Enabled siblings still function.

3. **Unit Frames OFF with standalone-capable consumers ON**.
   - Player Tick Markers still run on Blizzard player bars.
   - Swing/Cast timers use standalone presentation and their six movers.
   - DoT/Heal Prediction still renders on enabled Blizzard target/player/pet/party bars.
   - DPS/HPS badge still works and can keep CombatMeter accounting headless.
   - Party/Pet Aura children and ToT Debuffs still work on stock Blizzard frames.

4. **Nameplates OFF**.
   - No TurboFace plate presentation/stacking.
   - Nameplate CVar ownership and any legacy external-state debt restored.
   - No incompatible-nameplate warning from TurboFace.

5. **Auras family OFF / Class ON**.
   - Class reminders still get any duration support they independently require.
   - Nameplate Aura runtime, Player/Target AuraStyle, ToT Debuffs, and Party/Pet Aura
     presentation remain off.

6. **Auras family ON with consumers mixed independently**.
   - `auraEnabled` OFF does not disable ToT/Party/Pet children.
   - ToT OFF does not disable normal Player/Target styling.
   - Party OFF / Pet ON and Party ON / Pet OFF both work on stock or TurboFace frames.
   - Class OFF removes class reminder CLEU/evaluation while normal Party/Pet aura lists remain valid.

7. **Hotbar Power and Player Ticks in all four combinations**.

8. **Movers OFF with every dependent feature stored ON**.
   - XP/Loot/Net Worth/Hearth/Tracker/self Class Buff/Flight Bar/Combat Meter window remain dormant as appropriate.
   - Party class reminders and the independent DPS/HPS badge still work.
   - Standalone combat timers keep sensible default positions but their mover editing UI is unavailable.

9. **All Plus sections OFF**.
   - System CVars restore.
   - dynamic Social/Automation/System listeners are absent.
   - reload-applied hook features are not newly installed.

10. **DoT Prediction OFF / Heal Prediction OFF / Combat Meter window OFF / Player DPS-HPS Badge OFF**.
    - no prediction/meter CLEU consumers remain solely for those features;
    - no avoidable prediction textures/meter UI are constructed on a clean login;
    - Combat Meter mover is unavailable;
    - Player Tick Markers still have no CLEU dependency.

11. **Prediction features ON individually**.
    - DoT overlays use one shared engine on target/nameplates;
    - Heal Prediction shows direct heals plus one next HoT tick only;
    - disabling either engine hides its consumer textures and unregisters its runtime.

12. **Combat Meter window ON** in solo and 5-player content.
    - pet damage attributes to owner;
    - Current rolls cleanly between pulls;
    - Overall uses summed combat time;
    - ranking and spell breakdown render exactly five rows;
    - mouse-wheel scrolling reaches actors/spells beyond the five-row viewport;
    - 160 px minimum width remains readable via compact header labels;
    - disabling the window removes its UI/mover work; CLEU/group accounting remains only if the independent DPS/HPS badge is enabled.

13. **Badge-only accounting**: Unit Frames OFF, Combat Meter window OFF, Movers OFF,
    DPS/HPS Badge ON.
    - badge remains visible beside the stock PlayerFrame level text;
    - `CombatMeter` reports headless accounting runtime active but no meter frame/mover;
    - `/tf debug meter` distinguishes `window`, `badgeConsumer`, `runtimeNeeded`, and `runtime`.

14. **Profile switch/import** between radically different module states.
    - singleton Plus proxy follows the new DB;
    - module state survives snapshot/import;
    - reload prompt behavior is correct.

15. **Combat entry/exit** with protected UI changes pending.
    - no blocked actions/taint;
    - deferred geometry applies after combat.

16. **BugSack/BugGrabber session** covering login, combat, party, loot, taxi, death,
    merchant, target switching, and UI reload.

### 23.2 Performance validation

Start with Blizzard's **always-on native profiler** and keep legacy script profiling off.
This is the preferred before/after or intermittent-spike workflow because it does not add
the large `GetFunctionCPUUsage()`/`scriptProfile` instrumentation cost:

```text
/console scriptProfile 0
/reload
/tf cpu native baseline
# reproduce normal idle, combat, loot, and post-combat behavior
/tf cpu native delta
```

For a spike that appears correlated with killing/looting a mob **or with combat ending**, use the native-only
kill/post-combat tracer instead of enabling the detailed profiler:

```text
/tf cpu kill start
# kill/loot several mobs and reproduce the symptom
/tf cpu kill report
/tf cpu kill stop
```

Only when native metrics prove a real issue but do not identify its owner should the
high-overhead function profiler be enabled:

```text
/console scriptProfile 1
/reload
/tf cpu status
/tf cpu start
# reproduce the smallest useful test window
/tf cpu report
/tf cpu stop
/console scriptProfile 0
/reload
```

Detailed profiler percentages are diagnostic, not a normal-gameplay baseline: on a
high-FPS client the profiler's own sampling work can exceed the addon runtime being
measured. Use `/tf cpu snapshot` only when an addon-wide legacy snapshot is specifically
needed.

The strongest disabled-state check is not only CPU. Confirm that expected events/CLEU
counters do not move and that no feature-created frames appear.

---

### 23.3 Developer CVar browser

`Core/CVarBrowser.lua` is an opt-in patch-day/client-research utility inspired by the
workflow of AdvancedInterfaceOptions, but implemented as a native TurboFace debug tool.
It is intentionally **not** a normal settings owner. `/tf cvars` lazily creates the
window and enumerates the current client registry with `ConsoleGetAllCommands()` (or
`C_Console.GetAllCommands()`), retaining entries whose command type is a real CVar and
whose `C_CVar.GetCVarInfo()` lookup succeeds. The optional command tail seeds the search,
for example `/tf cvars nameplate`. `/tf debug cvars` is an equivalent debug route.

The browser exposes name, console category, current/default value, client help text and
`GetCVarInfo` metadata (`secure`, locked, read-only, account-stored, character-stored).
Rows whose current value differs from the client default are visually distinguished.
Selecting a row provides a direct value editor plus a reset-to-default action. Secure
CVars are refused while `InCombatLockdown()` is true; locked/read-only CVars are never
written. Browser edits call the client's `SetCVar` directly and therefore have the same
scope/persistence semantics as any other direct CVar change; they are **not** copied into
TurboFaceDB and do not claim TurboFace's normal CVar-owner registry.

**Export** snapshots the entire currently filtered result set, not only the rows visible
in the scroll window. A blank search therefore exports the full discovered registry,
while a query such as `/tf cvars nameplate` followed by **Export** produces a focused
nameplate report. The human-copy report uses a visible ASCII ` | ` separator instead of
tab characters because Classic EditBox fonts can render tabs as square/tofu glyphs.
Literal pipes inside client-provided fields are escaped as `\|`. Each row includes CVar
name, category, current value, default value, modified/default state, flags, and the
client-provided help description, plus client build/interface metadata and the active
search query. Copy output is split on line boundaries into <=30k-character pages before being
placed in a multiline EditBox. Before pagination, export-only field formatting also
escapes raw C0 control bytes (for example `0x01` -> `\x01`). Some Blizzard CVars store
compact bitfields/serialized state rather than printable text; feeding those bytes
directly to Classic's multiline EditBox can make an otherwise valid page render blank.
The structured SavedVariables snapshot retains the raw client values; only the human-copy
representation is sanitized. The window primes the EditBox and applies the real page on
the next frame, provides Prev/Next navigation, and auto-selects the current page for
Ctrl+C. AIO/AceGUI's established `SetMaxLetters(0)` multiline behavior is used; TurboFace
does not attempt direct clipboard access.

WoW's addon sandbox cannot create arbitrary standalone `.txt` files. For a durable
file-backed export, **Save** stores the filtered result set as structured data in the
opt-in per-character `TurboFaceCVarExportCharDB`. The snapshot contains build/interface
metadata, filter/count metadata and an `entries` array with name/category/current/default/
modified/flags/description fields. Structured rows are preferred to one giant escaped
report string because an uploaded SavedVariables file is directly inspectable. The client
serializes the snapshot on `/reload`, logout, or normal SavedVariables flush into the
character-level file:
`WTF/Account/<ACCOUNT>/<REALM>/<CHARACTER>/SavedVariables/TurboFace.lua`. Saving again
replaces the prior snapshot, so the utility cannot accumulate unbounded history.

Runtime contract: the file allocates no frame until the command is invoked, installs no
permanent `SetCVar`/`ConsoleExec` hooks, and owns no cadence or OnUpdate. The optional
`TurboFaceCVarExportCharDB` exists only after an explicit developer save. While the browser
is visible it listens for `CVAR_UPDATE` only to refresh the affected row; closing the
window unregisters that event. Explicit **Refresh** rebuilds the console registry so
CVars registered late by Blizzard load-on-demand code can be discovered. This keeps the
utility effectively zero-cost during normal play.

## 24. Release checklist

Before packaging a release candidate:

### Static checks

- Repository-owned tests live in the top-level `tests/` directory and intentionally remain outside
  the shippable addon directories. Run `python3 -m unittest discover -s tests -v`; the Phase 33
  baseline validates both overlays, destructive build-path safety, LuaJIT compilation, TOC/XML load
  graphs, package ownership, and documentation invariants. Continue migrating focused behavioral
  regressions as features change; static contracts do not replace live-client validation.
- Parse every Lua file and compile every Lua file with a real Lua 5.1-compatible compiler.
  An AST parse alone does not catch main-chunk limits such as the 200-local ceiling (§12.0).
- Validate Movers-gate usage. Reject these three shapes:
  `f and f(on) or on`; `ns.MoversEnabled and ns.MoversEnabled() or true`; and the
  dead `(not ns.MoversEnabled) or ns.MoversEnabled()` load-order fallback. The
  second makes `/tf debug modules` report Movers as enabled even when it is not.

  Any namespace/static setting-consumer scan must remain alias-aware. If a module aliases the addon
  namespace rather than using `ns.` directly, that alias must be included so live settings are not
  falsely reported as dead.

- **Pin Lua 5.1 explicitly in any new tooling.** Lupa's default `LuaRuntime` may be
  newer; use `from lupa import lua51` when Lupa provides the compiler. Lua-version drift
  defeats the compile check because the local ceiling and accepted syntax differ.
- Behaviorally exercise the cadence isolation cases in §4.5b and the Class Buff
  overlapping-name/aura-order cases in §16 until those focused runtime regressions are migrated.
- Verify every TOC path exists.
- Verify XML file references exist.
- Verify local texture/font/media paths used by new code. For the native-nameplate cutover, assert
  `Nameplate-SwingGlow.tga` and `Nameplate-AttackIndicator.tga` exist and that retired
  `ThreatBubble-Slot.tga` / `ThreatBubble-Fill.tga` are absent and unreferenced.
- Typography release check: the shipped addon tree contains no `.ttf`/`.otf` assets; public font
  dropdowns enumerate `ns.GetFontOptions()` rather than LibSharedMedia; runtime code outside
  migrations/preset history has no `globalFont`, root `textStyle`, `auraTimerFont`, or user-facing
  `INHERIT` dependency.
- Search for retired nameplate threat/swing identifiers outside migrations (`threatBubble`,
  `threatScale`, `threatXOffset`, `threatYOffset`, `threatPulseGrowth`, `bubbleThreat`,
  `bubbleSwing`, `c_bubbleSwingRing`). Also assert there are no runtime references to the fully
  retired legacy text surface (`myPlate.threatText`, `c_threatTextAnchor`,
  `UpdateThreatTextAnchor`, `threatLeadCache`).
- Search for accidental direct `TurboFaceDB.modules` runtime reads.
- Validate `ns.PLUS_SECTION` against `ns.defaults.plus`.
- Search new code for unconditional high-frequency events/tickers/OnUpdate. TurboFace
  periodic `OnUpdate` ownership is forbidden outside the explicit interactive/
  compatibility allowlist.
- Verify aura dirty batching never registers its 10 Hz coalescer as `immediate`; repeated
  invalidation must not collapse coalescing into one callback per Blizzard hook.
- Verify generic `BAG_UPDATE_DELAYED` handling does not call Baganator's broad
  `RequestItemButtonsRefresh(ItemWidgets)` path; only TurboFace-only widget-state changes
  may request that explicit refresh.
- Search new code for direct persistent `SetCVar` writes.
- Run a whitespace/diff check.
- Test ZIP integrity.

### Saved-variable checks

- Fresh install.
- Upgrade from previous schema: retired Global Font/Text Style keys disappear; pre-release typography
  appearance preservation is not a compatibility requirement at the schema-63 -> 64 boundary.
- Existing profile apply.
- Import/export round trip.
- Corrupt/missing known-value type normalization.
- Module preferences preserved.

### Live client checks

- login/reload with BugSack or equivalent;
- typography smoke test: switch Blizzard Default/Narrow/Quest/Combat plus Shadow/Outline/None on
  representative nested and flat owners (UnitFrame names/values, Auras, Combat Meter, Speedrun
  Splits, Hearthstone Tracker, Player tick amount). Verify each refreshes live, unrelated features
  do not change, UnitFrame Name vs Bar typography remain independently configurable, and Party/Pet/ToT
  Name Text Size + Bar Text Size sliders affect only their own fixed-art frame;
- combat lockdown and combat exit;
- target/ToT changes, including ToT debuffs with TurboFace ToT styling both on and off;
- party join/leave, pet summon/dismiss, and Party/Pet aura updates with both TurboFace and stock UnitFrames;
- hostile/friendly nameplates;
- Nameplate Swing Timer independence matrix: Threat Number off/on, Global Swing Timers off/on, and
  Nameplates master off/on. Verify combat entry shows the ready core before the first observed swing,
  the first real hostile swing starts the red countdown, friendly/non-attackable visible units never
  receive state, disabling the feature parks its CLEU/cadence runtime, and multiple Blizzard
  nameplate styles keep the strip aligned to the full `HealthBarsContainer` chassis;
- Threat Number presentation: 6px and 16px font extremes, native black `2,-2` FontObject shadow, 5px HP-bar
  gap, rounded/color agreement around 99.5–100.5 (visible 100 must be true red), overcap blue/purple
  bands, Threat Number hidden with Aggro Audio still enabled, and Aggro Audio mute/unmute without a
  stale transition replay;
- nameplate aura countdown parity against TargetFrame debuffs at boundary values: verify 2.1 -> `3`,
  1.9 -> `2`, 1.0 -> `1`, 0.9 -> `1`, and text disappears only at expiry; verify neither normal
  nameplate debuffs nor TurboDebuffs ever display `0.9`/other decimal countdown text;
- cross-surface aura countdown parity: verify Target, ToT, Nameplates, Party buffs/debuffs, and Pet
  buffs/debuffs all use ceiling-rounded whole units (`1.9 -> 2`, `0.9 -> 1`) and clear only at expiry;
- class reminder behavior;
- swing timer cast resets plus ranged/melee clock isolation in both standalone and baked modes;
- player/target casts in standalone and baked modes, including DPS-badge overlap/layering;
- loot and merchant flows;
- death/spirit healer where automation changes touched popup logic;
- taxi when Flight Bar changes are involved;
- Movers lock/unlock, same-element re-registration safety, and all six standalone combat-timer movers;
- profile change followed by required reload;
- stock Blizzard UnitFrames with Tick Markers, Prediction, DPS/HPS badge, Party/Pet Auras, and ToT Debuffs independently enabled;
- Plus Chat Text outline on/off across normal and temporary chat windows.

Do not call a module refactor “complete” based solely on syntax parsing. Static review
cannot detect secure-frame taint, Blizzard lifecycle timing, or client-only API quirks.

---

## 25. Known architectural limitations

### 25.1 One-way hooks

WoW secure hooks cannot be removed. Some reload-applied Interface/Chat/System behavior
therefore cannot support perfect live teardown. The contract is clean behavior after
reload and cheap predicate-gated callbacks where a hook can outlive its owner.

### 25.2 Blizzard pooled/protected UI

Nameplates, party aura containers, Target-of-Target, and other retail-derived 1.15.9
FrameXML systems can be recycled or restricted. Never assume a one-time frame mutation
will remain permanent without understanding Blizzard's update path.

### 25.3 Manual Plus classification

The Plus settings table is flat for compatibility, so `ns.PLUS_SECTION` remains a
manual classification map. The validator catches mismatches but cannot infer the
correct section automatically.

### 25.4 Movers dependency is intentional coupling

The mover-dependent widgets intentionally become unavailable when Movers is disabled.
Do not “fix” this by giving each one an unrelated private drag system; shared placement
ownership is the point.

### 25.5 Live module toggling is not the design goal

Because TurboFace touches protected Blizzard frames and one-way hooks, full module
masters are reload-oriented. Do not add complex mid-combat teardown machinery merely
to avoid a reload prompt.

---

### 25.6 Regression-sensitive invariants

- **Plus Chat text outline:** optional outline-only styling preserves Blizzard shadow state.
- **Independent DPS/HPS badge:** the badge is independent from TurboFace Unit Frames and
  may keep CombatMeter accounting alive headlessly.
- **Nameplate debuff Y offset:** the signed UI range is **-50 px through +50 px** and is an
  **anchor-only amendment**; it does not alter aura ownership, size, or duration logic.
- **Native-name shadow amendment:** the **Name Text Shadow** is optional,
  **enabled by default**, and applies a private Blizzard-derived FontObject with black `2,-2` shadow
  to eligible native NPC/player names. The original Blizzard FontObject is restored when inactive;
  pets/guardians and the player's own personal plate remain excluded.
- Removed nameplate controls remain removed: **Health Text Format**, **Power Text Format**,
  **Lock Nameplates On**, and **Questie Compatibility**. Nameplate visibility is Blizzard/user-owned.
- **Tick-amount delivery jitter:** authoritative regen phase acceptance stays
  strict; a separate **presentation-only window** may display a matched tick amount without moving
  the learned phase.
- **Priest Party Shield Bar:** party absorb state must never be inferred from an external caster or reconstructed after reload. Test initial group join with no shield -> Party name visible/no Lua error; local Priest PW:S apply -> absorb depletion -> expiration/name restore; another Priest replacing PW:S -> immediate invalidation; party member recycle/leave; Player UnitFrame disabled while Party remains enabled; and a first shield application during combat when the optional overlay was not prepared -> no protected geometry mutation and Party name remains visible.

### Namespace and media ownership hygiene

The shared `ns` table is an inter-file API, not a convenience scratchpad. A helper whose callers
all live in one file should stay local; a public namespace function should have at least one real
external consumer or a documented compatibility contract. Release checks treat write-only `ns`
functions as cleanup candidates. Font and statusbar path resolution is owned by `Core/SharedMedia.lua`; feature modules should
consume `ns.GetFont`, `ns.GetTexture`, or their retained compatibility wrapper rather than creating
private font resolver copies. Public font selectors must use `ns.GetFontOptions()` rather
than enumerating LibSharedMedia, and configurable TurboFace text must render through
`ns:StyleFont()` / `ns:StyleFeatureFont()` so local Text Style is authoritative.

## 26. Change discipline for future contributors

When adding or modifying a feature, answer these before merging:

1. **Who owns the setting?**
2. **What is its module/Plus section gate?**
3. **Does it have a parent/dependency gate?**
4. **What events/CLEU/timers/OnUpdate does it own?**
5. **What tears those down?**
6. **Does it modify a protected Blizzard frame?**
7. **Does it modify persistent external state/CVars?**
8. **If yes, how is exact prior state restored?**
9. **Does a profile/import replace a table this code cached?**
10. **Does the Options UI accurately state reload/dependency behavior?**
11. **What disabled-state test proves it is dormant?**
12. **What live-client scenario could static analysis miss?**
13. **If it registers with `ns.Cadence`: is its key unique, is it in the §4.5a
    inventory, and does it park itself when idle?**
14. **Which sections of this document does the change make untrue?** Update them
    in the same commit, and record dated rationale in `CHANGELOG.md` when the change
    alters ownership or removes a subsystem.

If those questions have clean answers, the feature fits the TurboFace architecture.


### Options dependency layout
The shared three-column options grid distinguishes independent controls from true dependencies. A dependent checkbox is rendered directly below its parent in the same grid column, indented 16px, and disabled/dimmed while the parent is off. This preserves hierarchy without sacrificing the three-column packing of independent option groups.

## Unit Frame value text — Blizzard dual format (2026-09-09)

- Every Unit Frames Health/Power format dropdown includes `Percent Current (Blizzard)` (`percent-current-blizzard`).
- This is a TurboFace-owned dual-text presentation: **percentage inside-left**, **current value inside-right**.
- The two strings use the shared Unit Frame Bar Font / Bar Text Style and the relevant per-unit Bar Text Size.
- Blizzard native `LeftText`/`RightText` objects remain suppressed because the client rewrites them from the global status-text CVar; TurboFace owns both dual strings so the selected per-unit format is deterministic.
- Compact Pet/Party/ToT bars split the available width at center so unusually long values clip rather than overlap.

### Level-up work budgeting (0.17.33-0.17.35)

`PLAYER_LEVEL_UP` is treated as a burst boundary rather than a reason to rebuild unrelated caches. Class Buffs and Class Features do not subscribe solely for level changes; their learned-spell/name caches are invalidated by spell-learning events instead. Skill Tracker handles the level-driven weapon/Defense cap change by updating cached `maxRank` values in place and leaves full skill-line scanning to genuine skill-line invalidations. Trainer Spells does not rebuild its class/skills ScrollBox while hidden; it marks the view dirty and performs the authoritative rebuild on `OnShow`. The temporary level-up allocation profiler used to identify these costs was removed after validation, leaving no level-up-specific diagnostic wrapper in release runtime.


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

`QuickSetup.lua` is now physically common. Client-specific action semantics are policy, not forks: Classic
keeps manual apply and legacy macro indexing; Forever keeps immediate staged apply, normalized macro
limits/scope resolution, reload-free CVar baselines, one-based Edit Mode translation, and fail-safe
unsupported-action preservation. Both clients use Blizzard's normal SavedVariables lifecycle.
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

The unified tree now treats `Core/Compat.lua`, `Plus/InterfaceTweaks.lua`, and `TurboFace.toc` as the only intentional first-party same-path Classic/Forever divergences. Compat owns Blizzard API shape, InterfaceTweaks owns genuinely different native interface lifecycles, and the TOC owns client metadata/load order. `build/verify.py` freezes this overlap so converged modules cannot silently fork again.


### Phase 33 repository baseline

Canonical repository documentation lives under `docs/`; runtime source overlays no longer carry duplicate architecture/changelog/build-manifest snapshots. `tests/` and `build/verify.py` jointly enforce the Phase 32 convergence boundary, direct client-identity allowlist, documentation freshness, safe build destinations, and package inventory. Generated `dist/` output is disposable and ignored by Git.
