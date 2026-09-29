# TurboFace development-to-CurseForge workflow

This is the canonical maintainer runbook for moving a TurboFace change from
local development through GitHub and into CurseForge. It complements the
[development guide](DEVELOPMENT.md) and [release checklist](RELEASING.md):

- `DEVELOPMENT.md` explains source ownership and validation;
- this document explains the complete branch-to-deployment workflow;
- `RELEASING.md` is the short checklist used once a release is ready.

## Pipeline at a glance

```text
origin/main
  -> codex/<focused-branch>
  -> source changes under src/
  -> verify + tests + both generated client builds
  -> live client smoke test
  -> version/release documentation
  -> commit and push branch
  -> GitHub pull request
  -> merge into protected main
  -> annotated v<version> tag on the merged main commit
  -> GitHub Actions: verify, test, package, GitHub Release
  -> separate Classic and Forever uploads to CurseForge
  -> CurseForge processing/moderation and final smoke test
```

The tag is the deployment trigger. Pushing a branch or merging a pull request
does not publish to CurseForge.

## Permanent pipeline configuration

These settings should already exist. Recheck them only when diagnosing the
pipeline or moving it to another repository.

- GitHub repository: `Rumblecrush/TurboFace`
- Protected release branch: `main`
- Release workflow: `.github/workflows/release.yml`
- Release trigger: pushed tags matching `v*`
- GitHub environment: `curseforge-production`
- Environment secret: `CF_API_TOKEN`
- Environment deployment tag rule: `v*`
- CurseForge project ID: `1689135`
- Classic game version: `1.15.9`
- Forever game version: `1.60.1`

The workflow uploads two independently built files to the same CurseForge
project. CurseForge may approve, reject, or delay them independently.

## 1. Start development from the public baseline

Never start release work from an old local branch merely because it still
exists. Begin with the current remote `main`:

```bash
git fetch origin main --tags
git switch main
git pull --ff-only origin main
git switch -c codex/<focused-description>
```

Before editing, inspect `git status` and preserve unrelated local work. Read
the relevant shared module and both clients' Compat, policy, provider, or
native-UI ownership boundaries. Generated packages are outputs and must not be
edited directly.

Use the ownership order from [MULTICLIENT_STRATEGY.md](MULTICLIENT_STRATEGY.md):

1. portable behavior in `src/common/`;
2. API and secret-value normalization in client `Core/Compat.lua`;
3. availability/behavior decisions in client policy;
4. established provider boundaries for different runtime owners;
5. client layers for genuinely different Blizzard UI ownership.

## 2. Implement and validate locally

After structural or runtime changes, run the complete baseline from the
repository root:

```bash
python3 build/verify.py
python3 -m unittest discover -s tests -v
python3 build/build_client.py classic --out dist/TurboFaceClassic
python3 build/build_client.py forever --out dist/TurboFaceForever
git diff --check
```

The two `dist/` directories are disposable generated packages. Rebuild both
clients even when a change is intended for only one client; this catches shared
load-order, packaging, and architecture regressions.

Install the applicable generated package into a development client and smoke
test the changed behavior. The destination must end as:

```text
<WoW client>/Interface/AddOns/TurboFace/TurboFace.toc
```

When replacing an existing development copy, verify the destination identifies
only the `TurboFace/` addon directory. Do not use a broad wildcard or delete an
`AddOns/`, client, Steam, home, or workspace directory. Preserve SavedVariables
unless the task explicitly requires a clean-profile test.

For shared changes, smoke test both clients when practical. For a Forever
change, test the relevant protected/secret-value transitions, including combat,
target changes, pooled frames, `/reload`, and opening panels when applicable.

## 3. Prepare a release version

Use semantic product versions:

- patch: compatible fixes (`0.18.3` -> `0.18.4`);
- minor: a meaningful feature release (`0.18.x` -> `0.19.0`);
- major: reserved for a deliberate product-level compatibility break.

Before the release commit, update every current-version surface:

- `src/classic/TurboFace.toc`;
- `src/forever/TurboFace.toc`;
- the supported-client table in `README.md`;
- current markers/contracts in `build/verify.py`;
- current version markers in `docs/SOURCE_MAP.md`;
- applicable architecture headings;
- both client changelogs as appropriate;
- `docs/releases/<version>.md`.

Search for stale previous-version references rather than relying on memory:

```bash
rg -n "0\.18\.3|Version:" README.md docs src build .github
```

Replace `0.18.3` above with the version being superseded.

Build the exact public archives and inspect their contents:

```bash
python3 build/package_release.py --version <version>
unzip -l release/TurboFace-Classic-<version>.zip
unzip -l release/TurboFace-Forever-<version>.zip
```

Each ZIP must contain exactly one top-level `TurboFace/` directory, match its
generated package, and contain no prohibited source-only files. In particular,
do not ship `.bat` launchers; CurseForge rejected the original Forever 0.18.0
archive for that reason.

## 4. Push the development branch and merge it

Review the final diff, then commit and push the focused branch:

```bash
git status --short
git diff --check
git add <intentional-files>
git commit -m "Prepare TurboFace <version> release"
git push -u origin codex/<focused-description>
```

Create a pull request into `main`. Confirm that:

- CI passes;
- the diff contains only intended source, tests, and documentation;
- generated `dist/` and `release/` artifacts are not committed;
- both client builds remain valid;
- required live testing is recorded.

Merge the pull request through GitHub. Do not tag the branch commit before the
merge. The public release tag belongs on the resulting commit in protected
`main`, normally the GitHub merge commit.

## 5. Verify `main`, then tag the release

Refresh the remote state and prove the release commit was merged:

```bash
git fetch origin main --tags
git log --oneline --decorate -5 origin/main
git merge-base --is-ancestor <release-commit> origin/main
git tag --list v<version>
```

The ancestry command must succeed and the tag must not already exist. Then
create an annotated tag directly on the verified remote-main commit:

```bash
git tag -a v<version> origin/main -m "TurboFace <version>"
git show -s --decorate v<version>
git push origin v<version>
```

Never move, overwrite, or reuse a published version tag. If release contents
need to change, make a new patch release.

## 6. What GitHub Actions does

Pushing `v<version>` starts the `Publish release` workflow. It:

1. checks out the exact tag;
2. installs Python and LuaJIT;
3. runs `build/verify.py`;
4. runs the complete regression suite;
5. builds both ZIPs with `build/package_release.py`;
6. stores the validated ZIPs as workflow artifacts;
7. creates the GitHub Release from `docs/releases/<version>.md`;
8. uploads Classic and Forever separately to CurseForge.

The GitHub Release job and both CurseForge matrix jobs consume the same
validated artifacts. CurseForge never packages the GitHub repository itself;
it receives only the generated ZIP selected for that client.

## 7. Post-release checks

Do not treat a successful upload API response as final publication.

- Confirm every GitHub Actions job succeeded.
- Open the GitHub Release and verify both ZIP assets exist.
- Inspect or install the downloaded assets, not only local build directories.
- Confirm both CurseForge files remain present after processing/moderation.
- Confirm Classic is assigned to `1.15.9` and Forever to `1.60.1`.
- Install each approved package into a clean addon directory and smoke test it.

CurseForge can briefly show a file as pending and then remove it after rejection.
Check the project notifications or file status for the rejection reason.

## Failure and recovery rules

### Before tagging

Fix the branch, rerun verification, push another commit, and update or merge the
pull request. Nothing has deployed yet.

### Workflow fails before artifact publication

Inspect the failed job. A transient runner failure or corrected environment
secret can be handled by rerunning the same workflow. Do not create another tag
unless release contents or version metadata must change.

### Packaged contents are wrong after tagging

Do not force-move the tag or replace history. Correct the source/pipeline and
publish the next patch version.

### Only one CurseForge package is approved

Inspect the rejected client's file contents and moderation reason. If an archive
must change, publish a patch release so GitHub and CurseForge remain reproducible
from a unique source tag.

### Token or environment failure

Confirm `CF_API_TOKEN` is stored as an environment secret in
`curseforge-production`, and that the environment permits `v*` tags. Never put
the token in source, workflow variables, command output, commits, or prompts.

## Prompt template for a future Codex session

Copy this block into a future task and replace the bracketed values:

```text
We are working in the TurboFace unified repository. Follow
docs/DEV_TO_CURSEFORGE.md, docs/DEVELOPMENT.md, and docs/RELEASING.md.

Start from the current origin/main and create a focused codex/ branch. Preserve
unrelated local changes. Make the requested change in the correct common or
client ownership layer; never edit generated packages directly.

Task: [describe the feature or fix]
Target release: [version, or say "development only for now"]
Affected clients: [Classic, Forever, or both]
Live test location/client: [optional path or client]

Run build/verify.py, the complete unittest suite, and rebuild both clients.
Install the applicable development package only if I ask or provide the target.
Update tests and relevant architecture/changelog/release documentation.

Do not push, merge, or tag until I explicitly authorize that stage. When I ask
to publish: push the focused branch, have me merge the pull request, verify the
release commit is in origin/main, then create an annotated v<version> tag on the
merged main commit. The tag should trigger GitHub Release and the two separate
CurseForge uploads. Never move an existing published tag.
```

## Quick release handoff

At the end of a development session, record:

- branch name and latest commit;
- intended version;
- tests/verifier/build results;
- which clients were smoke-tested;
- whether the pull request is open or merged;
- whether the release tag exists;
- GitHub Actions result;
- GitHub Release asset status;
- Classic and Forever CurseForge moderation status.

That state is enough for a later session to resume without guessing or
repeating completed release actions.
