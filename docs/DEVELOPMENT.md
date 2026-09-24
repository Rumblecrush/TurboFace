# TurboFace development guide

TurboFace uses one layered source tree to generate complete Classic Era and
WoW Forever packages.

## Repository layout

```text
src/common/   shared implementation used by both clients
src/classic/  Classic-specific compatibility, policy, and assets
src/forever/  Forever-specific compatibility, adapters, and tools
build/        builders and architectural verification
tests/        repository and runtime-contract regression tests
docs/         architecture, source ownership, releases, and changelogs
dist/         disposable local build output, ignored by Git
release/      disposable ZIP output, ignored by Git
```

Generated packages are build outputs. Never edit them directly.

## Architecture rules

1. Inspect the shared module and both clients' Compat, policy, and provider
   implementations before selecting an ownership layer.
2. Implement portable behavior once in `src/common/`.
3. Keep `Core/Compat.lua` client-specific as the primary API and secret-value
   normalization boundary.
4. Use client policy or an existing provider for behavioral and ownership
   differences.
5. Keep genuinely different Blizzard UI ownership in its client layer.
6. Do not merge files merely to reduce divergence.
7. Preserve portable SavedVariables schema version `79`; Forever-only evolution
   uses its separate client revision.
8. Treat verifier contracts as architectural invariants.

The convergence campaign through Phase 32 is complete. Remaining client
divergences are intentional boundaries, not unfinished consolidation.

## Requirements

- Python 3.10 or newer
- LuaJIT for Lua 5.1-compatible compile checks

## Verify and build

From the repository root:

```bash
python3 build/verify.py
python3 -m unittest discover -s tests -v
python3 build/build_client.py classic --out dist/TurboFaceClassic
python3 build/build_client.py forever --out dist/TurboFaceForever
python3 build/package_release.py
```

Each directory under `dist/` is a complete generated client package. Public
archives extract to a top-level `TurboFace/` directory. The archive builder may
exclude source-only helper launchers that distribution platforms prohibit; the
test suite freezes that release boundary.

Build destinations inside the repository must be children of `dist/`. Safety
checks reject destructive destinations such as the repository, source tree,
home directory, or an existing external directory.

## Validation expectations

After structural or runtime changes:

1. Run the architecture verifier and complete tests.
2. Rebuild both packages.
3. Smoke-test the affected client behavior in game.
4. Check the other client when shared code or portable state changed.
5. Update the applicable architecture, source map, and changelog documents.

See the [multi-client strategy](MULTICLIENT_STRATEGY.md) for ownership details
and the [release guide](RELEASING.md) for publication.
