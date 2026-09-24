# TurboFace

TurboFace is an all-in-one World of Warcraft interface addon with builds for
Classic Era and WoW Forever. This repository is the canonical multi-client
source tree; installable client packages are generated outputs.

## Supported clients

| Client | Interface | Package version |
|---|---:|---|
| WoW Classic Era | 11509 | 0.18.0 |
| WoW Forever | 16001 | 0.18.0 |

## Repository layout

```text
src/common/   shared implementation used by both clients
src/classic/  Classic-specific compatibility, policy, and assets
src/forever/  Forever-specific compatibility, adapters, and tools
build/        package builder and architectural verification
tests/        repository and runtime-contract regression tests
docs/         architecture, source ownership, and changelogs
dist/         generated local packages (ignored by Git)
```

Portable functionality belongs in `src/common/`. Client differences belong in
the appropriate compatibility, client-policy, or provider boundary. The
remaining same-path client divergences are intentional and verified; files
must not be merged merely to reduce the divergence count.

Do not edit generated packages under `dist/`. Change the source layers and
rebuild both clients.

## Build and verify

Requirements:

- Python 3.10 or newer
- LuaJIT, used to compile-check the Lua 5.1-compatible source during tests

From the repository root:

```bash
python3 build/verify.py
python3 -m unittest discover -s tests -v
python3 build/build_client.py classic --out dist/TurboFaceClassic
python3 build/build_client.py forever --out dist/TurboFaceForever
```

Each generated directory is a complete addon package. Stage the selected
output as `TurboFace/` when creating an installable archive so it extracts to
the expected addon folder.

## Development rules

1. Inspect the shared module and both clients' Compat, policy, and provider
   implementations before deciding where a change belongs.
2. Implement portable behavior once in `src/common/`.
3. Keep `Core/Compat.lua` client-specific; it is the primary API and
   secret-value normalization boundary.
4. Keep genuinely different Blizzard UI ownership in the client layer.
5. Preserve portable SavedVariables schema version `79`. Forever-specific
   schema evolution uses its separate client revision.
6. Treat `build/verify.py` contracts as architectural invariants.
7. Verify and rebuild both clients after structural or runtime changes unless
   a change is explicitly client-specific.

## Documentation

- [Multi-client strategy](docs/MULTICLIENT_STRATEGY.md)
- [Current source map](docs/SOURCE_MAP.md)
- [Classic architecture](docs/classic/ARCHITECTURE.md)
- [Forever architecture](docs/forever/ARCHITECTURE.md)
- [Classic changelog](docs/classic/CHANGELOG.md)
- [Forever changelog](docs/forever/CHANGELOG.md)
- [Forever SavedVariables workaround](docs/forever/FOREVER_SAVEDVARIABLES_WORKAROUND.md)

## Release automation

GitHub Actions verifies every push and pull request and retains both generated
ZIPs as workflow artifacts. Pushing a version tag such as `v0.18.0` runs the
same validation, creates a GitHub Release, and uploads the separate Classic and
Forever ZIPs to CurseForge project `1689135`.

Before publishing a tag, configure the `curseforge-production` GitHub
environment with a secret named `CF_API_TOKEN`. The tag's version without the
leading `v` must exactly match the Classic TOC version; the release stops before
publishing if version metadata has drifted.

The release workflow uploads only generated archives. Repository source,
tests, build tools, and developer documentation are not included in the addon
downloads.

## License

TurboFace's original material is All Rights Reserved. Personal use through
authorized distribution pages is permitted; redistribution and modified
distribution require prior written permission. See [LICENSE](LICENSE) for the
complete terms.

Bundled third-party components remain under their own licenses and notices.
See the client notice files and [`src/common/Licenses/`](src/common/Licenses/).
