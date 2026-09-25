# TurboFace release guide

TurboFace releases publish separate Classic Era and WoW Forever packages from
one verified source tag.

## Prerequisites

- The release changes are merged into protected `main`.
- Both client TOCs contain the intended version.
- `docs/releases/<version>.md` exists.
- Current version markers and changelogs are updated.
- The `curseforge-production` GitHub environment contains `CF_API_TOKEN`.
- Only `v*` tags may deploy to that environment.

CurseForge project ID `1689135` receives both packages. The workflow targets
Classic Era `1.15.9` and WoW Forever `1.60.1`.

## Pre-release verification

```bash
python3 build/verify.py
python3 -m unittest discover -s tests -v
python3 build/package_release.py --version <version>
```

Inspect both ZIPs before tagging. They must:

- contain exactly one top-level `TurboFace/` directory;
- match the applicable generated client package exactly;
- contain no `.bat` launcher files;
- carry matching TOC and archive versions.

## Publish

Create and push an annotated tag from the verified `main` commit:

```bash
git tag -a v<version> -m "TurboFace <version>"
git push origin v<version>
```

The `Publish release` workflow then:

1. verifies the architecture and runs regression tests;
2. builds both release archives;
3. creates the GitHub Release using `docs/releases/<version>.md`;
4. uploads Classic and Forever separately to CurseForge.

Do not move or reuse a published tag. If packaged contents must change after a
release, correct the pipeline and publish a patch version.

## Post-release checks

- Confirm the GitHub workflow completed successfully.
- Download and inspect both GitHub Release assets.
- Confirm both CurseForge files remain present after moderation, not merely
  after the upload API returns success.
- Confirm each file is assigned to the correct game version.
- Install each approved package into a clean addon directory and smoke-test it.
