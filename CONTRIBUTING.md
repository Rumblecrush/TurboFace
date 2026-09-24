# Contributing to TurboFace

Thanks for helping improve TurboFace. Bug reports and focused pull requests are
welcome.

Before changing code, read the [development guide](docs/DEVELOPMENT.md) and the
[multi-client strategy](docs/MULTICLIENT_STRATEGY.md). A change must preserve
both client builds unless it is deliberately client-specific.

## Pull requests

1. Create a branch from `main`.
2. Make source changes under `src/common/`, `src/classic/`, or `src/forever/`.
   Do not edit generated packages.
3. Update tests and documentation when behavior, ownership, or a verified
   contract changes.
4. Run the verifier and test suite described in the development guide.
5. Explain the affected client or clients and the in-game validation performed.

Keep changes focused. Portable functionality belongs in `src/common/`; genuine
client differences belong at the established Compat, policy, provider, or
native-UI ownership boundary.

By submitting material, you confirm that you have the right to submit it.
Review the repository [license](LICENSE); a public repository and accepted
contribution do not make TurboFace an open-source redistribution license.

For release procedures, see the [release guide](docs/RELEASING.md).
