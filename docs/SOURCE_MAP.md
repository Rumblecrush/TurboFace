# TurboFace source map

**Audit date:** 2026-09-23

**Classic:** 0.18.1 / Interface 11509

**Forever:** 0.18.1 / Interface 16001

This document describes the current physical source and package ownership. It
is not a feature-parity matrix: one differing line can represent a critical
protected-frame or secret-value boundary.

## Package inventory

| Class | Count |
|---|---:|
| Classic packaged files | 182 |
| Forever packaged files | 198 |
| Same relative path | 181 |
| Byte-identical same-path files | 176 |
| Same-path but different contents | 5 |
| Classic-only paths | 1 |
| Forever-only paths | 17 |

The union is 199 relative paths. Generated packages are the exact overlay of
`src/common/` with `src/classic/` or `src/forever/`.

Public release archives apply one distribution-only exclusion:
`Save-TurboFaceForever.bat` remains in the Forever source/build tree for local
development but is omitted from ZIPs because CurseForge rejects batch files.

## First-party source

For addon-owned `.lua`, `.xml`, and `.toc` paths outside vendored libraries
and package notices:

| Classification | Count |
|---|---:|
| Byte-identical | 107 |
| Intentional client-owned divergence | 3 |

The three first-party divergences are:

- `Core/Compat.lua`
- `Plus/InterfaceTweaks.lua`
- `TurboFace.toc`

These own API normalization, native UI integration, and client packaging/load
order respectively.

## Client overlay overlap

Exactly five paths exist in both client layers:

- `Core/Compat.lua`
- `Libs/LibClassicDurations/core.lua`
- `Plus/InterfaceTweaks.lua`
- `THIRD_PARTY_NOTICES.md`
- `TurboFace.toc`

`build/verify.py` freezes this set. A path moving between common and a client
layer, or a new client overlap, requires an explicit ownership decision.

## Client-exclusive paths

Classic has one exclusive packaged path:

- `Textures/BankIcon.tga`

Forever has seventeen exclusive packaged paths:

- `Combat/BlizzardDamageMeterBridge.lua`
- `Combat/ForeverNativeAdapter.lua`
- `Combat/ForeverSwingTimerAdapter.lua`
- `Core/Compatibility.lua`
- `Core/ForeverDevPreset.lua`
- `Core/ForeverRestoreData.lua`
- `Core/ForeverSchema.lua`
- `Nameplates/ForeverAuras.lua`
- `Nameplates/ForeverNativeAdapter.lua`
- `Plus/ForeverNativeAdapter.lua`
- `Save-TurboFaceForever.bat`
- `Save-TurboFaceForever.sh`
- `SpendTalentPoint.lua`
- `Tools/Save-ForeverVariables.ps1`
- `Trainer/ForeverNativeAdapter.lua`
- `Trainer/data/ForeverProfessions.lua`
- `UnitFrames/ForeverNativeAdapter.lua`

## Shared ownership

All other package paths are sourced from `src/common/`. Major shared families
include Core configuration/schema/profile logic, Combat engines, Inventory,
Movers, Nameplate feature logic, Options, Power, Trainer data/controllers,
and most Unit Frame behavior.

Shared does not mean identical client behavior. Shared modules consume Compat,
client policy, and provider contracts to obtain the correct implementation
without embedding broad client branches.

## Verification

Run the following after source movement or ownership changes:

```bash
python3 build/verify.py
python3 -m unittest discover -s tests -v
```

The verifier derives current source/package inventories, enforces the five
intentional overlaps, checks direct client-identity boundaries, and confirms
that both generated packages match their source overlays.
