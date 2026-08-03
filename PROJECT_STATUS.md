# AppSleuth project status

> This file is the project ledger and continuity source of truth. Update it after every material decision, implementation milestone, verification result, release, or newly discovered blocker. Do not infer that a planned item is complete unless it is recorded here with evidence.

## Current position

- **Project:** AppSleuth
- **Version:** `0.1.0-beta.1` prerelease MVP, not yet published
- **Date last updated:** 2026-08-03
- **Local repository:** initialized on branch `main`
- **Commit state:** one complete initial import commit on `main`; online publication remains pending
- **Online hosting:** not configured
- **Git remote:** not configured
- **Homebrew tap:** not created
- **Primary target:** Apple Silicon, macOS 13+
- **Implementation language:** Swift 6 with Foundation and no third-party runtime dependencies

## Product promise

AppSleuth is an evidence-first macOS application uninstaller, cleanup, and diagnosis CLI. Discovery and dry-run are the default. Every match has a confidence score, risk level, scope, and explanation. Normal uninstall and leftover cleanup move eligible files into a restore vault. The separately named `purge` workflow is the narrow exception: after layered confirmation it permanently removes only a strictly limited, high-confidence local plan and creates no rollback. Optimize & Check is diagnosis-only by default and exposes only small, individually reviewed maintenance actions.

## Non-negotiable safety decisions

- `scan` and `explain` are read-only.
- `optimize` is read-only unless exact current action IDs and `--execute` are supplied; there is no optimize-all path.
- Optimization execution requires an exact count-based phrase, never elevates privileges, and supports only the fixed reviewed action kinds enforced by `OptimizationExecutor`.
- Unreadable, denied, timed-out, or unsupported health evidence is labeled unavailable; it is never converted into a passing result or described as corruption.
- `uninstall`, leftover cleanup, `restore`, and `purge` are dry-run unless `--execute` is explicitly supplied.
- Execution requires an exact app- or backup-specific confirmation phrase.
- No non-interactive `--yes` bypass exists in the MVP.
- Fuzzy matches, package receipts, shared vendor folders, and protected OS paths are never automatically removed.
- Items are revalidated immediately before mutation.
- Restore manifests are treated as untrusted and cannot redirect files outside approved roots.
- Restore never overwrites an existing original path.
- Running related processes block execution; AppSleuth does not kill them automatically.
- Whole-Mac leftover matches are labeled suspected, never proven solely by absence of an app bundle.
- Product/vendor names extracted from identifiers are labeled likely owners and never affect confidence or cleanup eligibility.
- Leftover cleanup has no select-all path; it requires exact current finding IDs and remains dry-run by default.
- Active/unknown-domain launchd jobs, running processes, and privileged helpers are report-only.
- Interactive reversible uninstall remains preview-only. The separately red-labeled purge selector may execute only after the user opts into execution and types `PERMANENTLY DELETE <bundle-id>` exactly.
- Permanent purge may select the approved app bundle, high-confidence disposable user cache/log data, and—only with `--include-user-data`—high-confidence non-shared user Application Support, preferences, saved state, web data, sandbox containers, and Application Scripts.
- Permanent purge never selects Group Containers, system-level artifacts, launch/background jobs, privileged helpers, active processes, plug-ins, shared frameworks, fonts, profiles, extensions, receipts, command-line/package-manager records, or uncertain matches.
- The permanent-deletion eligibility rules are enforced independently by the execution service, every path is revalidated, and the application bundle is deleted last.
- Permanent purge recursively preflights every selected tree before mutation. Any non-app permission blocker stops the entire plan before deleting anything.
- A non-writable application bundle is eligible for administrator removal only when it is the exact revalidated selected `.app` within the approved `/Applications` layout. Authentication occurs before the first mutation; scanning and user-data deletion never run as root.
- “Without any trace” and secure SSD erasure are not promised. APFS snapshots, Time Machine, Keychain/TCC/BTM state, package managers, and vendor services can retain records or copies.
- Do not add a second deletion-policy implementation in Python or another language.

## Completed implementation

- App lookup by absolute path, display name, or bundle identifier.
- Bounded lookup for direct and one-folder-nested application layouts, including Adobe-style installations.
- User and system artifact scanning across Application Support, preferences, caches, logs/crash reports, saved state, web data, containers, group containers, scripts, launchd items, privileged helpers, plug-ins, frameworks, fonts/profiles, extensions, command-line/shell integrations, package-manager records, receipts, and related processes.
- Read-only reporting of embedded LoginItems, LaunchServices helpers, XPC services, plug-ins/frameworks, Quick Look/Spotlight components, SystemExtensions, and Mac App Store receipt data.
- Structured filename and plist matching with confidence thresholds.
- `SAFE`, `REVIEW`, `HIGH`, and `PROTECTED` risk classifications.
- `scan`, `explain`, `uninstall`, `purge`, and `restore` commands, with JSON output for non-executing plans.
- Read-only `list` application inventory across user, shared, and Apple system application roots, with `--no-system` and JSON output.
- Compact grouped human-readable application inventory with optional verbose bundle IDs and paths.
- Per-application Spotlight-indexed bundle sizes in the grouped inventory, with unavailable metadata shown honestly rather than estimated.
- Alphabetically grouped, color-coded leftover inventory with heuristic likely-owner titles, category summaries, and exact finding IDs.
- Conservative `leftovers` audit using normalized reverse-DNS identifiers, installed vendor namespaces, multi-category evidence, broken launchd paths, loaded jobs, and missing-bundle processes.
- Exact-ID leftover cleanup planning with system opt-in, restore-vault moves, rollback, and ordinary `restore` support.
- `doctor` read-only permission/process diagnostics and an explicit System Settings shortcut.
- Transactional restore vault, journaled manifests, rollback, and conflict-safe restore.
- Animated per-location progress plus `--quiet`, `--verbose`, and `--json` output modes.
- Versioned app-scan coverage ledger with numbered catalog/embedded/runtime progress; checked, not-present, unavailable, matched-location, category, and unsupported-state summaries.
- Diagnosis-first `optimize`/`optimise`/`health` command with eight bounded checks: resources, one-shot CPU, disk images, preference-plist integrity, launch-job integrity, VPN, DNS, and local Homebrew availability.
- Exact-ID optimization dry runs and confirmed execution for Quick Look cache refresh, current-user Dock restart, and one individually revalidated mounted disk-image target; no blanket reset/repair actions or optimize-all mode.
- Centered keyboard-driven alternate-screen terminal dashboard with a larger logo, highlighted selection, Up/Down navigation, Return activation, and shortcut keys.
- Large six-line AppSleuth ASCII logo centered on ordinary terminals with at least 22 rows; a two-column compact menu keeps every action visible beneath it, while physically smaller terminals retain a compact fallback.
- Progressive home rendering: Disk, Apps, application names, and Jobs show independent in-place loading states until their inspections finish.
- Cached keyboard application browser with Up/Down navigation and selected-app name, version, indexed size, scope, bundle ID, and path; returning to the list does not repeat inventory or size inspection.
- Red keyboard-driven permanent-purge application selector with scrolling, per-app sizes, cancellation, full plan preview, layered confirmation, and exact typed execution phrase.
- Dashboard storage overview for total/used/available disk capacity, non-Apple third-party app-bundle space/count, and active user-service availability/count.
- Separate dry-run-first permanent purge planner/service with no vault, no rollback, app-bundle-last ordering, and execution-time policy enforcement.
- Whole-plan recursive deletion-permission preflight with `READY`, `ADMIN REQUIRED`, and `BLOCKED` reporting.
- Narrow `sudo` boundary for root-owned application bundles: preauthorize first, then pass only the exact revalidated app path as a separate argument to administrator-authorized removal.
- Third-party app scans suppress Apple-owned identifier matches, preventing Parsec from being associated with unrelated `com.apple.parsec.*` macOS components.
- Read-only `services` command grouping visible running current-user launchd jobs under likely third-party owners, with Apple identifiers excluded and JSON output available.
- Collision-safe `appsl` short command alias installed as a symbolic link to the canonical executable; the provisional colliding `aps` alias is safely migrated away.
- Local `scripts/install.sh`, `scripts/uninstall.sh`, and Make targets.
- GitHub CI and tag-triggered ARM64 release workflow.
- GitHub Actions are pinned to immutable full commit SHAs, with weekly Dependabot checks for action updates.
- Beta-aware release publishing, SHA-256 checksums, and GitHub artifact provenance attestations.
- Documented release, support, versioning, review, and solo-maintainer branch-protection practices.
- README, MIT license, changelog, architecture, safety, roadmap, language, distribution, contribution, security, conduct, maintainer, issue, and PR documentation.

## Verification evidence

- **Automated tests:** 39 passing, 0 failures after the `0.1.0-beta.1` release-preparation changes.
- **Production build:** successful ARM64 Mach-O executable reporting `appsleuth 0.1.0-beta.1`; SHA-256 `0e7ce1ac4fc5bab90982654ca31aeb1ce442d07f18daaaad9264acec1e2b45cb`.
- **CLI fixture checks:** `scan`, `explain`, dry-run uninstall, quiet output, verbose output, and JSON output exercised.
- **Mutation fixture:** application and cache moved into an isolated vault and restored successfully.
- **Tampered manifest fixture:** redirected restore rejected.
- **Large process output:** a regression test drains more than 300 KB without blocking, covering the former pipe-buffer deadlock.
- **Calculator scan:** completes in approximately 0.33 seconds in the verification environment and returns five findings.
- **Scan-coverage verification:** Calculator JSON emits schema version 2 with more than 50 explicit catalog/embedded/runtime location outcomes; the human report distinguishes 48 checked, 19 not-present, and two unavailable locations in the restricted verification session.
- **Optimize verification:** real-Mac diagnosis completes all eight checks with progressive spinner/verbose output, JSON validates through `jq`, and no maintenance action runs by default. The report separated ten unreadable preference files from valid readable files and surfaced four missing OneDrive launch-job executable paths without unloading or deleting anything.
- **Optimization safety regressions:** parser fixtures cover mounted images, memory, swap, and CPU; executor fixtures prove exact Quick Look action scope, mounted-image revalidation before detach, and rejection of a non-`/Volumes` target without running a command.
- **Optimize terminal UI:** the installed menu layout includes `[m] Optimize & check`; a real PTY showed the eight-step spinner, report, return-to-menu flow, and clean alternate-screen restoration.
- **User verification:** the user confirmed that the updated installed AppSleuth runs successfully in their terminal after the Calculator-scan fix.
- **Permission diagnostics:** structured human and JSON output verified.
- **Local installer:** verified using a project-local temporary prefix and the fixed build installed at `/opt/homebrew/bin/appsleuth` with a matching SHA-256.
- **Interactive terminal:** home screen, help navigation, read-only scan, return-to-menu, and quit exercised in a real PTY.
- **Interactive arrow navigation:** Up and Down escape sequences move the highlighted action in a real PTY; shortcut quit restores the terminal normally.
- **Centered dashboard:** final installed build reached the complete overview within three seconds in a real PTY and showed 68 third-party bundles, a clearly marked ≥53.06 GB lower bound from 63 indexed bundles, nine active user jobs, arrow-capable navigation, and clean terminal restoration.
- **Progressive dashboard:** the installed build rendered the home menu immediately, then visibly transitioned through all-loading, names/count discovered, disk complete, app sizes complete, and jobs complete states. The final real-session result showed 68 third-party bundles, two application-name previews plus 66 more, a ≥53.06 GB lower bound from 63 indexed bundles, and ten currently active third-party user jobs.
- **Large-logo home layout:** the installed release displayed the centered six-line logo, live overview, and every menu action together in a 24-row PTY. The compact two-column menu did not scroll; Down moved the highlight and shortcut `q` restored the terminal cleanly.
- **Cached application browser:** `l` immediately opened a nine-row keyboard browser over 151 cached bundles; Down changed the highlighted app and its name/version/size/scope/ID/path details, while `q` returned home without rerunning discovery.
- **Active service inventory:** normal macOS session reported nine running third-party current-user jobs under seven likely owners after an initial test exposed and fixed Apple namespace leakage; restricted sessions now show `Unavailable` instead of a misleading zero.
- **Application inventory:** production binary listed 151 application bundles across `user`, `shared`, and `system` scopes on the verification Mac, including 74 non-system bundles; compact human, verbose, and JSON output exercised.
- **Application sizes:** real-Mac `list --no-system` displayed indexed sizes for 68 of 74 non-system bundles, including Maccy at 7.8 MB, Google Chrome at 1.47 GB, and Xcode at 8.55 GB; six unavailable results were displayed as `—`.
- **Expanded artifact coverage:** fixtures verify web data, frameworks, fonts, profiles, command-line/shell integration, package-manager records, extensions, embedded XPC/plug-in/framework content, and Mac App Store receipts.
- **Permanent purge fixture:** app bundle, cache, preference, and opted-in Application Support data were permanently removed; a Group Container was kept and no restore vault was created.
- **Permanent purge fail-closed test:** a crafted plan attempting to select a system-level path was rejected by the execution service independently of the planner.
- **Permission preflight regressions:** a non-app permission blocker stops before deleting the app; simulated administrator cancellation leaves both app and user data untouched; successful simulated authorization is used only for the application bundle.
- **Parsec namespace regression:** `com.apple.parsecd` and `com.apple.siri.parsec.*` are rejected as evidence for the third-party `tv.parsec.www` app, while exact `tv.parsec.www` evidence remains valid.
- **Installed Parsec preview:** the updated release finds only `/Applications/Parsec.app` and its two protected receipts, reports the root-owned bundle as `ADMIN REQUIRED`, and changes nothing. The unrelated Apple findings fell from ten to zero.
- **Real-app purge preview:** Maccy dry-run produced three eligible roots, marked its embedded Sparkle framework as covered by the app bundle, and kept its Homebrew Caskroom record protected; nothing was changed.
- **Permanent purge terminal selector:** `x` opened the red 68-app selector in a real PTY, Down moved the highlight, `q` cancelled back to the home menu, and a second `q` restored the terminal cleanly.
- **Artifact documentation:** launchd/background-item statements cross-checked against Apple launchd, Service Management, and Login Items documentation.
- **Leftover fixtures:** installed-vendor exclusion, Team-ID normalization, Apple exclusion, multi-category scoring, broken launch-agent evidence, active-process blocking, system opt-in, exact-ID selection, reversible move, and restore verified.
- **Inspection timeout:** child-command timeout kills stalled inspection safely; regression test completes a forced timeout in under two seconds.
- **Real-Mac leftover audit:** completed in approximately two seconds under restricted process/launchd visibility; candidate count fell from 155 to 72 after false-positive hardening and Apple/Workflow exclusion, grouped under 14 likely owners, with unavailable visibility reported as coverage warnings.
- **Leftover CLI plans:** invalid IDs fail closed; an exact user candidate previews as `MOVE`; a system launch agent remains `KEEP` even with `--include-system` because its service domain is not safely controlled.
- **Alias migration:** isolated installer test created `appsl -> appsleuth`, removed only an AppSleuth-owned retired `aps` symlink, and preserved the canonical executable.
- **Current installed build:** `/opt/homebrew/bin/appsl -> appsleuth` remains the previously verified local `0.1.0` build. It was deliberately not overwritten during open-source preparation; the validated source/release build is `0.1.0-beta.1`.
- **Previous source archive:** `outputs/AppSleuth-v0.1.0-source.zip` is a superseded local snapshot, not a public release artifact. The first distributable beta must be built from its immutable Git tag by GitHub Actions.
- **Workflow files:** CI, release, Dependabot, and issue-template YAML parsed successfully. The release shell logic correctly marks hyphenated versions as prereleases.
- **Action provenance:** `actions/checkout` is pinned to the official `v6.0.2` commit `de0fac2e4500dabe0009e67214ff5f5447ce83dd`; `actions/attest` is pinned to the official `v4.2.1` commit `508db95dd578ae2727ebd6217d5ba78e4fbda05d`.
- **Shell installers:** syntax checked and marked executable. An isolated `/private/tmp` install produced `appsleuth 0.1.0-beta.1`, created `appsl -> appsleuth`, and the uninstall helper removed only those two test entries after confirmation.
- **Release smoke checks:** version, help, non-interactive usage, read-only doctor JSON, executable architecture, and SHA-256 completed successfully. A stale CI text assertion was found and corrected before commit.
- **Secret-pattern check:** no common token, access-key, or private-key patterns were found in the public project files.

## Deliberately unresolved

- GitHub owner: username or organization not chosen/provided.
- Final public repository URL.
- Named maintainer identity and private contact method.
- GitHub CLI installation/authentication and first push.
- Developer ID signing and Apple notarization.
- Published `v0.1.0-beta.1` GitHub prerelease.
- Separate `homebrew-tap` repository and real formula checksum.
- Whether and when to pursue acceptance into `homebrew/core`.
- External modern Background Task Management modification.
- Privileged helper design for reviewed system-level operations.
- Supported Homebrew/App Store/vendor uninstaller orchestration for package-manager records and shared components.
- Supported Keychain, privacy-grant, handler-registration, and Background Task Management cleanup workflows.
- Secure erasure or a guarantee that snapshots, backups, managed state, or external services retain no trace; this is outside the product promise.

## Current distribution reality

- From this source tree, users can run `./scripts/install.sh` and then call `appsleuth` or its `appsl` symlink when the selected install directory is in `PATH`.
- The repository contains a release workflow, but it cannot publish until an online GitHub repository and tag exist.
- The Homebrew formula in `docs/DISTRIBUTION.md` is a template with placeholders. It must not be advertised as a working formula until the GitHub URL, immutable release, and SHA-256 are real.
- Unqualified `brew install appsleuth` is a long-term goal, not a current capability.

## Resolved issue: Calculator scan appeared stuck

- **Root cause:** process inspection waited for `ps` to exit before draining its output pipe. On a busy Mac, `ps` could fill the pipe buffer and block forever, preventing exit.
- **Fix:** drain command output concurrently with child progress by reading the pipe before waiting for termination.
- **UX fix:** the default spinner now changes its message to the current approved location instead of displaying one fixed “Scanning” label.
- **Permission behavior:** `appsleuth doctor` reports readable roots, process visibility, and a conservative Full Disk Access probe. Scan warnings now disclose unavailable process inspection.
- **macOS constraint:** AppSleuth cannot grant itself Full Disk Access. The user must enable their terminal host in System Settings. Full Disk Access is not required for a Calculator scan.

## Resolved issue: Parsec purge partially completed before a permission failure

- **Observed failure:** the earlier permanent-purge implementation deleted three selected user roots, then failed to recursively remove `/Applications/Parsec.app`; permanent mode had no rollback vault, so AppSleuth cannot restore those three roots.
- **Root cause:** Parsec is installed as `root:wheel`; its bundle and `Contents` directory are mode `755`. The normal user can discover the app and may move its top-level entry, but cannot recursively erase administrator-owned bundle contents.
- **Safety fix:** preflight the complete selected trees before mutation. Non-app blockers fail closed; administrator authentication for an eligible app occurs before any selected item is deleted.
- **Privilege boundary:** only the exact revalidated application bundle under `/Applications` can be passed to administrator-authorized removal. AppSleuth, scanning, matching, and user-data deletion stay unprivileged.
- **Matching fix:** Apple-owned `com.apple.parsec.*` components are no longer shown as evidence for the third-party Parsec app.

## Immediate next action

**Ask which GitHub username or organization should own AppSleuth. Install and authenticate GitHub CLI before creating the public remote. After the owner is chosen, replace `YOUR-USERNAME`, name the maintainer/security contact, create the public repository, enable the documented ruleset and private vulnerability reporting, and push `main`.** Do not tag or publish `v0.1.0-beta.1`, create a Homebrew tap, execute a real maintenance/purge action, switch languages, add automatic clean-all/optimize-all behavior, kill/unload services, or broaden permanent deletion into shared, system, startup, package-manager, or privileged categories without the required review and authorization.

## Update protocol

When work resumes:

1. Read this file before making project changes.
2. Confirm that the newest user request agrees with the recorded product and safety decisions.
3. Record new decisions as decisions, not assumptions.
4. Record implemented work only after proportionate verification.
5. Add unresolved dependencies or user choices to the unresolved section.
6. Update the immediate next action before ending a material project turn.
