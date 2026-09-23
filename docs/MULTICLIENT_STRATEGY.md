# TurboFace multi-client strategy

TurboFace is one product with one source repository and two generated client
packages:

```text
TurboFace-Classic.zip
TurboFace-Forever.zip
```

The clients share feature logic wherever their semantics are genuinely
portable. Client layers own API normalization, native Blizzard UI integration,
and behavior that cannot safely share an implementation.

## Source ownership

```text
src/common/   portable implementation and shared data
src/classic/  Classic Era implementations, providers, and overrides
src/forever/  WoW Forever implementations, providers, and overrides
```

The builder copies `src/common/` and overlays the selected client directory.
An overlapping path is therefore an explicit client override, not an ordinary
duplication mechanism.

Use this ownership order when making a change:

1. Put portable behavior in `src/common/`.
2. Express an API difference through the client's `Core/Compat.lua`.
3. Express a behavior or availability decision through `Core/Client.lua`.
4. Use an existing provider when the clients need different runtime owners.
5. Keep an implementation in the client layer when Blizzard UI ownership or
   protected/secret-value behavior is genuinely different.

Do not add broad Classic/Forever branches to shared feature modules. Direct
client identity is intentionally restricted to the small policy/provider
boundary enforced by `build/verify.py`.

## Compatibility boundary

Each client owns `Core/Compat.lua`. Shared code consumes the normalized
`ns.API` vocabulary rather than calling divergent Blizzard APIs directly.

Classic Compat presents readable Era APIs through that common vocabulary.
Forever Compat also owns modern API shapes, secret-value checks, protected
data handling, and fail-closed reads. Shared modules must not attempt to
inspect or transform opaque values outside those contracts.

## Policy and providers

`Core/Client.lua` describes capability and ownership policy. It answers
whether a feature is available and which client or Blizzard surface owns it;
it is not a second user-preference store.

`Core/Providers.lua` and the feature provider modules select runtime
implementations. Current provider boundaries include Combat, Swing Timers,
Nameplates, Unit Frames, Plus/native UI, and Trainer UI.

Adapters may replace or extend a shared runtime at these boundaries. They
should not duplicate complete portable feature engines.

## Intentional overlay boundaries

Five paths intentionally exist in both client layers:

| Path | Reason |
|---|---|
| `Core/Compat.lua` | Blizzard API and secret-value normalization |
| `Plus/InterfaceTweaks.lua` | Genuinely different native UI ownership |
| `TurboFace.toc` | Client metadata and semantic load order |
| `Libs/LibClassicDurations/core.lua` | Client-specific third-party adaptation |
| `THIRD_PARTY_NOTICES.md` | Package-specific notices |

The first three are first-party implementation divergences. The other two are
third-party/package metadata boundaries. New overlaps require explicit
architectural review and verifier updates.

## SavedVariables

Portable settings use `dbVersion = 79` on both clients. Profile snapshots and
exports remain portable.

Forever-only evolution is stored under the separate client revision owned by
`Core/ForeverSchema.lua`. A client-only change must not advance the portable
schema version. Unsupported settings should normally remain preserved but
inactive so moving a profile between clients does not destroy configuration.

## Build model

`build/build_client.py` creates a complete package from the common layer plus
one client overlay. It does not generate or reorder TOC entries; each client's
`TurboFace.toc` is the load-order contract.

```bash
python3 build/build_client.py classic --out dist/TurboFaceClassic
python3 build/build_client.py forever --out dist/TurboFaceForever
```

Build destinations inside the repository must be named children of `dist/`.
The builder rejects repository, source, metadata, home/root, ancestor, and
pre-existing external destinations that could be damaged by cleanup.

Legacy snapshot manifests were removed because their contents are derivable
from the source layers and they had become duplicate state. `build/verify.py`
now derives both inventories and enforces the current overlap, identity, and
package contracts directly.

## Change workflow

Before changing a shared or client-specific feature:

1. Read the shared implementation and both relevant client boundaries.
2. Identify whether the difference is API shape, product policy, provider
   ownership, or a genuinely client-specific renderer.
3. Preserve fail-closed behavior around protected or secret data.
4. Update documentation when ownership or a verified invariant changes.
5. Run the verifier and complete test suite.
6. Rebuild both packages and perform client smoke tests appropriate to the
   affected feature.

The convergence campaign is complete. Remaining divergences are maintained
architectural boundaries, not unfinished consolidation work.
