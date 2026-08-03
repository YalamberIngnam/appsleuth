# MVP implementation plan and roadmap

## v0.1.0-beta.1 — working prerelease MVP

- [x] Define versioned scan, finding, plan, and backup-manifest models.
- [x] Locate apps by exact path, display name, or bundle identifier.
- [x] Search bounded user and system macOS locations.
- [x] Match with bundle-ID, app-name, and structured plist evidence.
- [x] Report risk, confidence, scope, reasons, and JSON output.
- [x] Detect running executables inside the selected app bundle.
- [x] Report embedded LoginItems, LaunchServices helpers, and SystemExtensions.
- [x] Make uninstall and restore dry-run by default.
- [x] Require application/backup-specific interactive phrases.
- [x] Revalidate approved roots and filesystem identity before every move.
- [x] Quarantine to a manifest-backed vault with rollback and restore.
- [x] Add isolated filesystem tests and Apple Silicon GitHub Actions.
- [x] Add README, architecture/safety documentation, MIT license, contribution guide, and security policy.
- [x] Add an interactive terminal home, progress modes, and a local source installer.
- [x] Add a grouped application inventory and conservative whole-Mac suspected-leftover audit.
- [x] Require exact finding IDs and reversible moves for leftover cleanup.
- [x] Group leftover findings under colored likely-owner headings without changing safety eligibility.
- [x] Add a centered dashboard with disk/app-bundle space and read-only active user-service inventory.
- [x] Add per-application indexed sizes to the grouped application inventory.
- [x] Expand bounded discovery to web data, crash reports, XPC/plug-in/framework content, audio components, fonts/profiles, extensions, CLI/shell integrations, and package-manager evidence.
- [x] Add a separate keyboard-selectable, dry-run-first permanent purge for high-confidence non-shared local data.
- [x] Add GitHub community templates and ARM64 release automation.
- [x] Add an explicit scan-coverage ledger with numbered live progress and unavailable-state reporting.
- [x] Add a diagnosis-first Optimize & Check report plus narrowly reviewed exact-ID maintenance actions.

## v0.2 — richer macOS evidence

- [ ] Read code-signing Team ID, signing identifier, and designated requirement.
- [ ] Correlate installer package metadata without deleting receipts.
- [ ] Inspect embedded XPC services/frameworks and correlate helper bundle identifiers beyond their parent bundle.
- [ ] Add supported modern background/login item inventory.
- [ ] Add `backups list`, `backups inspect`, and retention reporting.
- [ ] Calculate sizes asynchronously without following symlinks or blocking first output.
- [ ] Add snapshot-based tests for Adobe-style multi-product fixtures.
- [ ] Add memory-pressure, battery-health, physical-disk SMART, and optional offline update-catalog evidence through supported APIs.

## v0.3 — reviewed system operations

- [ ] Design a minimal privileged helper/XPC protocol for system-level moves.
- [ ] Preview launchd unload actions separately from filesystem moves.
- [ ] Sign vendor recipes and validate them against the central safety policy.
- [x] Add per-finding selection by stable ID for suspected-leftover cleanup.
- [x] Add an optional terminal UI over the core library.

## Distribution milestone

- [ ] Reproducible universal release archives (arm64 first, x86_64 after CI coverage).
- [ ] Developer ID signing and Apple notarization.
- [ ] Publish and maintain a Homebrew tap/formula after the first online tagged release.
- [x] Checksums, release provenance, and documented release process.
- [ ] Generate and attest a release SBOM.

Reversible uninstall remains the primary product path. Permanent purge is a separate, stricter exception: it does not weaken the restore-vault policy for uninstall/leftover cleanup and will not expand into blind shared/system deletion.
