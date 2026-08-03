# Architecture

## Product scope

AppSleuth is a local-only, terminal-based macOS application discovery and uninstallation tool. Reversible uninstall remains the normal path; permanent deletion exists only as a separately named and guarded workflow. Its product promise is narrower than a general disk cleaner:

1. identify one installed `.app` precisely;
2. discover app-specific artifacts in a bounded catalog of macOS locations;
3. explain the evidence, risk, confidence, and user/system scope of each finding;
4. construct a conservative removal plan;
5. quarantine confirmed items transactionally;
6. restore quarantined items without overwriting conflicts.

An explicit `purge` path reuses the same scanner and point-of-action validation but applies a stricter ownership/category planner before ordinary filesystem deletion. It never becomes an option on `uninstall`.

It also provides a conservative whole-Mac audit for suspected leftovers. That flow compares structured artifact identifiers with the installed-app inventory, requires exact per-finding selection, and reuses the same vault and restore boundary.

Optimize & Check is a separate maintenance surface. Inspection is read-only, progress is observable, and an unavailable check remains unknown. Its small action catalog requires exact current IDs plus confirmation and has no optimize-all path. It does not reuse or weaken application-deletion policy.

The first release targets Apple Silicon and macOS 13+. It does not send telemetry or require a network connection.

## Language choice: Swift

Swift was chosen over Python, Go, and Rust for the macOS-first implementation:

- `Foundation` reads application bundles and binary/XML property lists without shell parsing or third-party packages.
- Swift ships with the Xcode toolchain and produces one native executable.
- Native APIs leave a clear path to code-signing, Endpoint Security-adjacent inspection, ServiceManagement, and notarized distribution.
- Strong value types and `Codable` make the scan report and backup manifest explicit and testable.
- SwiftPM provides builds, tests, and dependency management without introducing a separate build system.

The tradeoff is that contributors need the Apple developer toolchain and CI must run on macOS. That is acceptable for a deliberately macOS-specific utility.

## Command model

| Command | Mutates state? | Purpose |
|---|---:|---|
| `list` | No | Show a grouped inventory of application bundles |
| `services` | No | Group visible running user services under likely third-party owners |
| `leftovers` | No | Audit approved roots for suspected unowned artifacts and active/missing-bundle runtime evidence |
| `leftovers clean <ids>` | No by default | Build an exact-ID plan; `--execute` plus an exact phrase moves eligible items to the vault |
| `scan <app>` | No | Locate the bundle, search approved roots, classify matches, and report warnings |
| `explain <app> [finding]` | No | Show the evidence and deletion eligibility behind findings |
| `uninstall <app>` | No by default | Build a plan; `--execute` plus an exact phrase moves selected items to the vault |
| `purge <app>` | No by default | Build a stricter permanent plan; `--execute` plus an exact phrase deletes eligible local roots with no rollback |
| `restore <id>` | No by default | Preview a manifest; `--execute` plus an exact phrase restores non-conflicting items |
| `optimize [action-ids]` | No by default | Run read-only health checks; exact current action IDs plus `--execute` and a phrase run only those small reviewed actions |

`--include-review` and `--include-system` expand planning only. They never weaken path, identity, confidence, or protected-item checks.

## Component boundaries

```text
CLI
 ├─ TerminalUI ───────── centered alternate-screen keyboard dashboard
 ├─ ProgressReporter ─── spinner, quiet, and verbose modes
 ├─ ApplicationLocator ── reads Contents/Info.plist
 ├─ SystemOverviewInspector ─ disk/app-bundle sizes + current-user active services
 ├─ OptimizationInspector ─── bounded resource/configuration health checks
 │   └─ OptimizationExecutor ─ exact-ID Quick Look, Dock, or one-volume detach actions
 ├─ LeftoverScanner ───── installed-owner comparison + runtime/service evidence
 ├─ Scanner
 │   ├─ PathCatalog ───── bounded user/system roots
 │   ├─ Matcher ───────── filename + plist evidence
 │   └─ ProcessInspector ─ read-only ps snapshot
 ├─ UninstallPlanner ──── deterministic selection policy
 ├─ PermanentPurgePlanner ─ stricter ownership/category allowlist
 ├─ LeftoverCleanupPlanner ─ exact-ID, fail-closed selection
 ├─ SafetyPolicy ───────── shared point-of-action revalidation
 ├─ UninstallService ───── reversible transactional moves
 │   └─ BackupStore ────── manifest + mirrored payload vault
 └─ PermanentPurgeService ─ full permission preflight, scoped app authorization, app bundle last
```

Core models are `Codable`; the same report/plan structures drive human-readable and JSON output. The terminal dashboard reads a `SystemOverview`, using bounded Spotlight metadata rather than a recursive app-bundle walk at startup, while `services` emits the same active-service records directly. Mutation is isolated in `UninstallService` and `PermanentPurgeService`. Scanners and planners have no mutation API.

## Repository structure

```text
.
├── Package.swift
├── Sources/
│   ├── AppSleuth/                 # CLI, progress, and alternate-screen terminal UI
│   └── AppSleuthCore/             # discovery, policy, backup, restore
├── Tests/AppSleuthCoreTests/      # isolated filesystem fixtures
├── docs/                          # architecture, safety, roadmap
├── scripts/                       # local install/uninstall helpers
└── .github/workflows/ci.yml       # Apple Silicon build and tests
```

## Data flow

1. `ApplicationLocator` accepts an exact path, display name, or bundle identifier. It searches standard application roots to a fixed depth of two (root/app or root/container/app), and ambiguity is an error.
2. `Scanner` emits a versioned `ScanReport` plus a location ledger. It enumerates only direct children of catalog roots and records checked, absent, and unavailable locations separately.
3. `Matcher` produces a score and human-readable evidence. Weak matches remain visible but non-removable.
4. `UninstallPlanner` creates selected/kept decisions from fixed thresholds plus opt-in flags.
5. The CLI shows the complete plan before asking for the app-specific phrase.
6. `SafetyPolicy` revalidates every selected item, including path normalization, parent root, symlink-resolved parent, filesystem identity, and app identity.
7. `BackupStore` writes a `preparing` manifest before moves start. Each successful move is journaled.
8. On failure, `UninstallService` attempts rollback and retains a `partial` audit manifest.

Permanent purge diverges only after scanning: `PermanentPurgePlanner` selects the approved app bundle, high-confidence disposable user data, and—when separately opted in—high-confidence non-shared app-specific user data. It refuses system-level artifacts, shared/startup/extension categories, package-manager records, receipts, and uncertain ownership. `PermanentPurgeService` validates the whole selection and recursively preflights deletion permissions before mutation. Non-app blockers fail closed. A root-owned bundle in the approved `/Applications` layout may use `SudoApplicationRemover`: authentication happens before mutation, and only the revalidated app path is elevated. The service revalidates each item, deletes the application bundle last, creates no vault, and never rolls back earlier deletions.

The leftover flow first inventories applications, normalizes reverse-DNS and Team-ID-prefixed identifiers, suppresses installed/Apple vendor namespaces, and requires stronger multi-category or startup evidence for reporting ordinary artifacts. `LeftoverCleanupService` adapts only explicitly selected eligible findings into the same `UninstallService`; it does not introduce a second mutation engine.

Optimize & Check uses supported macOS commands and Foundation parsing behind bounded timeouts. Its default report is offline and read-only. Execution accepts only actions returned by the immediately preceding inspection, requires a typed phrase, revalidates dynamic disk-image mount targets, passes arguments without a shell, and never elevates privileges. The small maintenance action set has no rollback vault, so it cannot be selected implicitly or mixed with uninstall execution.

## Extension points

- signed vendor recipes that contribute candidate identifiers and paths;
- code-signing Team ID and designated-requirement evidence;
- modern login/background item inspection through supported macOS APIs;
- a privileged helper with an auditable XPC protocol for system items;
- Homebrew distribution, signing, notarization, and SBOM/release provenance;
- a selection UI/TUI that consumes the same JSON-safe models.

Recipe and UI layers must call the same planner and safety policy; they do not get a parallel removal path.
