# Local Forever testing

The user requests deployment into the live addon folder during iterative tests.
Build and verify before copying; back up the addon under ignored `dist/live-backups/`.
Preserve SavedVariables and all other addons. Do not publish test builds.

Live folder:

```text
/home/dustin/.local/share/Steam/steamapps/compatdata/3213052267/pfx/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/TurboFace
```

## 2026-10-09 — 0.19.5-dev1

- Found live addon still at 0.19.3 without the new rank-chain files.
- Read-only inspection of saved Warrior data confirmed missing rank metadata
  for 6673, 5242, 6343, and 8198. No saved files were edited.
- Captures now preserve ranks when Forever returns category without rank text.
  The normal seed merge restores missing ranks at startup.
- Class service identity uses catalog rank/level before potentially aliased
  tooltip IDs; ambiguous families are not guessed.
- Verified 197 generated Forever files against the live copy after deployment.
- Awaiting level-11 Warrior reload and trainer-visit validation. Battle Shout
  Rank 2 is catalog level 12; Thunder Clap Rank 2 is catalog level 18.

## 2026-10-09 — 0.19.5-dev2

- User reported a restricted dungeon target GUID entering `targetSwingStates`
  during target switching at SwingTimers.lua:1258.
- Both client compatibility layers now expose normalized GUID reads; Forever
  checks accessibility before inspecting identity. Shared target/nameplate
  caches normalize every incoming GUID before indexing.
- Forever estimator resets and event keys reject secret values.
- Architecture verification, 50 tests, Lua compilation, both client builds,
  and development packaging passed. Restricted-to-readable target switching
  is covered with an instrumented cache that rejects the opaque test key.
- Deployed and verified 197 files in the live Forever addon; backup under
  `dist/live-backups/20261009-220150/TurboFace`. SavedVariables unchanged.
- Awaiting dungeon target-switch testing after `/reload`.

## 2026-10-09 — 0.19.5-dev3

- Added the shared personal sticky note, with character-specific text, position,
  and visibility. Open using `/tf note`, `/tfnote`, or the Options button.
- Architecture verification, 51 tests, both client builds, and packaging passed.
- Deployed and verified all 198 generated files in the live Forever addon;
  backup at `dist/live-backups/20261009-224430/TurboFace`. SavedVariables untouched.
- Awaiting visual testing: reload, open note, type multiple lines, drag the
  header, hide/reopen, and reload to verify text/position/open-state persistence.

## 2026-10-09 — 0.19.5-dev4

- Added persistent +/- collapse/expand with a draggable header that stays in
  place across resizing and reload. Changed the note to muted charcoal/light text.
- All 51 tests, architecture verification, both builds, and packaging passed;
  lifecycle coverage includes collapsed dragging, reload, and preserved text.
- Deployed/verified 198 live Forever addon files. Backup:
  `dist/live-backups/20261009-225158/TurboFace`. SavedVariables untouched.
- Awaiting in-game visual/interaction feedback after reload.

## 2026-10-09 — 0.19.5-dev5

- Added default-off `stickyNoteEnabled` Speedrun parent gate with live/profile
  refresh. Disabled startup creates no note UI or character note record and
  unregisters the one-time login listener. Slash/public methods respect the gate.
- Disabling hides/releases focus while preserving saved note text and open state.
- Architecture verification, all 51 tests, both builds, and packaging passed.
- Deployed and verified 198 live files, preserving SavedVariables. Backup:
  `dist/live-backups/20261009-225616/TurboFace`.
- After reload, enable Sticky Note in Speedrun to resume testing.

## 2026-10-10 — 0.19.5-dev6

- Added the shared Class queue weapon-stone reminder, enabled by default. Ordinary Rough through Dense stones are supported; special event/Elemental stones are not in the catalog yet.
- Checks both equipped melee weapons, compatible stone family, bags-only counts, and client-reported minimum level. Existing temporary enchant, death, combat, or unreadable enchant state suppresses the reminder. Class Features, Movers, individual reminder and existing queue visibility gates apply.
- Verified source contracts, all Lua compilation, all 52 unit/regression tests, both client builds, both release archives, and clean diff whitespace.
- Deployed and hash-verified all 198 Forever files to the authorized live directory above. Backup: `dist/live-backups/20261010-201134/TurboFace`. SavedVariables untouched.
- Live check: `/reload`; with Class Features and Movers enabled and “Only show while in combat” off, carry a usable stone and equip a matching uncoated weapon. Apply the coating or remove the stones to dismiss it; check a coated main hand with an uncoated offhand too.

## 2026-10-12 — 0.20.0 release preparation

- User confirmed the live Forever development build is looking good and authorized publication.
- Promoted the tested development changes to 0.20.0, a feature release under the maintainer versioning policy.
- Classic in-game smoke testing has not been performed in this session; both client builds and shared regression tests are verified locally.
- Release handoff: push the development branch, have the maintainer merge the PR, verify the release commit in origin/main, then push annotated v0.20.0 on merged main.
