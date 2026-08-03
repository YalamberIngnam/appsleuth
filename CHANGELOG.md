# Changelog

All notable changes to AppSleuth will be documented here.

## [Unreleased]

### Added

- Read-only `appsleuth list` application inventory with user/shared/system labels and JSON output.
- Conservative whole-Mac suspected-leftover audit and exact-ID, dry-run cleanup planning.
- Reversible selected-leftover moves with active-job blocking and system-scope opt-in.
- `appsl` short command alias installed as a collision-safe symbolic link; retired the colliding provisional `aps` name.
- Up/down-arrow and Return navigation in the interactive terminal menu.
- Keyboard-driven alternate-screen home menu when `appsleuth` runs without arguments.
- Animated terminal progress, `--quiet`, and per-location `--verbose` output modes.
- Source installer, uninstall helper, Make targets, and GitHub release automation.
- Open-source operations, language choice, distribution, governance, and community templates.
- `appsleuth doctor` permission/process diagnostics with an optional System Settings shortcut.
- Centered interactive dashboard with disk capacity, external app-bundle size/count, and active user-service status.
- Read-only `appsleuth services` inventory grouped under likely third-party owners.
- Alphabetically grouped, color-coded suspected-leftover output with extracted likely-owner labels.
- Per-application Spotlight-indexed sizes in the grouped application list and keyboard selector.
- Expanded bounded artifact discovery covering web data, crash reports, embedded XPC/plug-ins/frameworks, audio components, fonts/profiles, extensions, CLI/shell integrations, and package-manager evidence.
- Separate dry-run-first `purge` command and red keyboard application selector for explicitly confirmed permanent local deletion without rollback.
- Progressive home-dashboard loading states for Disk, Apps, and Jobs, plus an application-name preview.
- Cached keyboard application browser showing the highlighted app's version, size, scope, bundle ID, and path.
- Always-visible large centered AppSleuth logo on ordinary terminal heights, with a compact two-column home menu.
- Whole-plan recursive permission preflight and narrowly scoped administrator removal for root-owned application bundles.
- Versioned scan-coverage ledger with numbered progress, checked/absent/unavailable states, category summaries, and explicit unsupported-state disclosure.
- Diagnosis-first `optimize`/`health` command with eight read-only checks, JSON/live output, and a narrow exact-ID action catalog for Quick Look, Dock, and individually revalidated mounted disk images.
- Read-only app discovery and categorized macOS artifact scanning.
- Evidence explanations, risk levels, scopes, confidence, and JSON output.
- Dry-run uninstall planning with review/system opt-ins.
- Interactive, reversible quarantine and conflict-safe restore.
- Point-of-action path, root, symlink-parent, and filesystem-identity validation.
- Isolated test fixtures and Apple Silicon GitHub Actions.
- Pinned GitHub Actions dependencies, release provenance attestations, and automated action-update checks.

### Fixed

- Replaced the verbose three-line-per-app inventory with a compact grouped table and optional details.
- Distinguished an unavailable service inspection from a valid zero-service result.
- Replaced a slow recursive startup size walk with bounded Spotlight metadata lookup and explicit partial-index coverage.
- Prevented process inspection from deadlocking when `ps` output exceeds the pipe buffer.
- Updated the interactive spinner with the current scan location so long scans visibly advance.
- Reported process-inspection failures as scan warnings instead of silently omitting them.
- Reused the home-screen application inventory in the interactive list instead of rescanning and printing one oversized block.
- Prevented administrator-authentication failure from occurring after earlier purge items had already been deleted.
- Suppressed unrelated `com.apple.parsec.*` macOS components when scanning the third-party Parsec application.
- Distinguished unreadable preference and launch-job data from malformed data in health reports instead of labeling permission failures as corruption.

### Documentation

- Documented common macOS application artifacts, their purposes, and what dragging an app to Trash leaves behind.
- Documented common installation methods and why the leftover audit is separated from exact-ID cleanup.
- Added troubleshooting guidance for slow scans, progress traces, permissions, PATH issues, installed-build checks, and terminal recovery.
