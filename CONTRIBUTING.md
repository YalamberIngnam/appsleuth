# Contributing to AppSleuth

Thank you for helping make macOS cleanup safer and more transparent.

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Ground rules

- Safety regressions are release blockers.
- New discovery roots must be bounded and documented.
- A new match rule needs positive, negative, vendor-sharing, and symlink/race-oriented tests where applicable.
- Scanner and planner code must remain read-only.
- Filesystem mutation must stay inside the reviewed mutation services: reversible app/leftover moves in `UninstallService` under `SafetyPolicy`, permanent deletion in `PermanentPurgeService`, and the fixed exact-ID maintenance catalog in `OptimizationExecutor`.
- A pull request must not add a second path-policy, confirmation, privilege, or deletion implementation.
- Do not add telemetry or network calls to the core.

## Development setup

Requirements: macOS 13+, Xcode Command Line Tools, and Swift 6.

```bash
git clone <your-fork-url>
cd AppSleuth
swift build
swift test
```

Run the CLI directly during development:

```bash
swift run appsleuth scan /Applications/SomeApp.app
swift run appsleuth uninstall /Applications/SomeApp.app --dry-run
```

Never use a personally important app as a mutation test. The test suite creates isolated fake bundles and Library trees under `.build/test-fixtures`.

## Pull requests

1. Open an issue for changes that alter matching, risk, confirmation, privilege, or backup behavior.
2. Keep the patch focused and explain false-positive/false-negative tradeoffs.
3. Add tests that demonstrate the safety boundary.
4. Update the architecture, safety model, CLI help, and README when behavior changes.
5. Run `swift test` and `swift build -c release` before opening the pull request.
6. Do not mix safety-sensitive behavior with unrelated refactoring; reviewers must be able to audit the complete policy change.

## Vendor recipes

Vendor knowledge must contribute evidence; it must not directly delete files. Recipes should identify the exact product/version tested, distinguish shared suite components, and cite the source of each relationship in their review description.

## Reporting security issues

Please follow [SECURITY.md](SECURITY.md) rather than opening a public issue for a vulnerability that could cause unintended data movement.
