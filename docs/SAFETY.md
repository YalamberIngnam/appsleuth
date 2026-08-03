# Safety and matching model

## Threat model

AppSleuth assumes that filenames can be misleading, vendors can share directories across products, filesystem state can change between scan and execution, symlinks can escape an expected tree, permissions can fail halfway through an operation, and users can accidentally select the wrong application.

The design therefore treats scanner output as untrusted evidence. A match is not permission to move or permanently delete a file.

## Risk levels

| Level | Meaning | Default plan |
|---|---|---|
| `SAFE` | Strong app-specific evidence in a disposable category such as a user cache or log | Selected if confidence is at least 85 |
| `REVIEW` | Strong evidence, but the item can contain user settings/data or is the app bundle itself | Kept unless it is the selected app bundle or `--include-review` is used |
| `HIGH` | Shared-container/startup/system implications, or weak evidence | Kept; requires strong evidence and explicit review opt-in; fuzzy matches remain non-removable |
| `PROTECTED` | Audit evidence or OS-managed data AppSleuth must not move | Never selected |

System-level associated items additionally require `--include-system`. The selected app bundle is treated specially: `/Applications/Foo.app` can be planned without opting into unrelated `/Library` artifacts. One non-symlinked containing folder below an application root is allowed for layouts such as Adobe Photoshop. Apps below `/System/Applications`, and explicit bundle paths outside `/Applications` or `~/Applications`, are protected.

## Matching strategy

Evidence is scored in this order:

1. filename stem exactly equals the app bundle identifier: **100**;
2. launch/preference plist declares the exact bundle identifier or launches inside the selected bundle: **100**;
3. filename contains the complete, boundary-delimited bundle identifier: **94–96**;
4. normalized filename exactly equals the app display name: **92**;
5. plist references the exact application executable name: **88**;
6. filename contains every distinctive product-name token: **80**.

Scores below 75 are not reported. Scores from 75 through 84 are discovery-only and forcibly raised to `HIGH`; they cannot be selected, even with opt-in flags. Vendor-only names do not satisfy product-token matching: `Adobe Photoshop` may correlate with Photoshop, while `Adobe` alone does not.

Property-list inspection looks only at structured fields such as `Label`, `BundleIdentifier`, `Program`, `ProgramArguments`, and `AssociatedBundleIdentifiers`. AppSleuth does not grep arbitrary file contents.

## Shared dependencies

- Group Containers are always `HIGH` because several apps can share them.
- Package receipts are always `PROTECTED` and retained as audit evidence.
- A vendor-wide Application Support folder is not matched from vendor name alone.
- Creative Cloud, license managers, update services, runtimes, and fonts are not attributed to Photoshop merely because they share the Adobe brand.
- Future vendor recipes may establish stronger relationships, but a recipe cannot override protected paths or point-of-action validation.

## Bounded discovery

The scanner enumerates only direct children of explicit roots. It does not recursively traverse home directories, documents, cloud storage, mounted volumes, or arbitrary paths. It does not follow symlinks while searching.

The bounded-root approach limits both false positives and scan cost. Deeper product layouts will be added as explicit, testable catalog entries or recipes rather than by enabling general recursive search.

Every app scan records a coverage ledger. A missing catalog root is `not-present`; a successfully enumerated root is `inspected`; a permission or command failure is `unavailable`. The latter never means empty. The report also names macOS-managed or external state outside filename discovery. This makes incompleteness visible but does not turn a finite catalog into a guarantee that every vendor-created trace was found.

## Optimize & Check safety

Health inspection is read-only and offline by default. Single CPU samples are labeled snapshots, unreadable property lists are separated from malformed ones, and any denied or timed-out command becomes `unavailable` rather than a passing result.

Maintenance execution has no “all” selection. The user supplies exact current action IDs, reviews targets and risk, adds `--execute`, and types `OPTIMIZE <count> ACTIONS`. The initial executor accepts only three fixed kinds: Quick Look cache refresh, current-user Dock restart, and detach of one exact `/Volumes/...` path currently proven by `hdiutil` to belong to a mounted disk image. Arguments are passed directly without shell evaluation. No action uses administrator privileges.

AppSleuth intentionally excludes generic permission repair, database rewriting, memory purge, Bluetooth or network-stack resets, job unloading, LaunchServices rebuilding, and undocumented system changes. These operations can be disruptive, misleading, version-dependent, or impossible to reverse safely without a symptom-specific workflow.

## Suspected-leftover policy

The whole-Mac leftover audit is intentionally more conservative than an app-specific scan. A direct child is considered only when it has a reverse-DNS-style identifier, is not Apple-owned, and no inventoried application shares its exact identifier, parent/child identifier relationship, or vendor namespace. Plain vendor folders are ignored. Confidence increases when the same identifier appears in multiple artifact categories or when a launchd plist points to a missing absolute executable.

These matches remain suspected—not proven—orphans. Human output extracts a likely product/vendor name from structured identifiers and groups it under a **likely owner** heading only to make review and sorting easier; this label never raises confidence or deletion eligibility. Cleanup has no select-all mode and accepts only stable finding IDs from the current audit. Active jobs, running processes, privileged helpers, and launchd items whose required domain state cannot be inspected are report-only; unknown state never means inactive. Other system-scope candidates require `--include-system`. Selected paths still pass the same approved-root, symlink, identity, transactional-vault, rollback, and restore checks as an app-specific uninstall.

## Point-of-action validation

Immediately before each move, AppSleuth checks:

- the finding is removable and not protected;
- the path is absolute and unchanged by standardization;
- the path still exists;
- it is not beneath `/System`, `/usr`, `/bin`, `/sbin`, `/private`, or `/var`;
- non-app findings are direct children of the approved root for their category/scope;
- the resolved parent is still the approved root (symlink-escape defense);
- filesystem device and file identifiers still match the scan snapshot;
- an application finding is exactly the originally selected `.app` path.

This is a fail-closed policy. Any failed check stops the operation.

## Permanent purge policy

`purge` is dry-run by default and is not an `uninstall` flag. The permanent planner uses stricter rules than reversible uninstall:

- the selected application bundle must be inside an approved application root;
- disposable user caches/logs need at least 92% ownership confidence;
- Application Support, preferences, saved state, web data, sandbox containers, and Application Scripts additionally require `--include-user-data`;
- Group Containers, startup/launch jobs, active processes, plug-ins, frameworks, fonts, profiles, extensions, package-manager records, receipts, all system-level related artifacts, and fuzzy matches are never selected;
- embedded helpers/frameworks/receipts are marked `COVERED` because deleting the parent app bundle removes them without a second filesystem operation.

Before deleting, the service validates every selected root and recursively checks whether the current user can remove the complete tree. Non-app permission failures are blockers and stop the plan before mutation. A root-owned application under the approved `/Applications` layout is instead marked `ADMIN REQUIRED`. After the exact phrase, AppSleuth runs `sudo -v` before deleting anything; a failed or cancelled authorization therefore leaves the whole plan untouched. Only the revalidated application-bundle path is passed as a separate argument to a non-interactive, administrator-authorized `/bin/rm` operation. Scanning, matching, user-data deletion, and AppSleuth itself remain unprivileged.

The service then revalidates each item, processes related data first, and deletes the application bundle last. A later filesystem failure still stops immediately; already deleted data is not recreated. There is no vault, rollback, Trash move, or secure erase. APFS snapshots, Time Machine, Keychain, privacy databases, package managers, vendor services, and other external/macOS-managed state can retain records or copies.

## Confirmation and recovery

`uninstall`, leftover cleanup, `restore`, and `purge` are previews unless `--execute` is present. Execution then requires typing `UNINSTALL <bundle-id>`, `CLEAN <count> LEFTOVERS`, `RESTORE <backup-id>`, or `PERMANENTLY DELETE <bundle-id>` exactly. There is intentionally no non-interactive `--yes` option in the MVP.

Reversible operations move items rather than deleting them. Their backup payload mirrors absolute paths and is journaled in `manifest.json`. Restore treats the user-writable manifest as untrusted: it validates that payload sources remain inside the vault and that original destinations remain direct children of approved app/data roots. It will not overwrite an existing path. A partial uninstall attempts rollback and preserves its manifest even if rollback cannot fully complete. `purge` is the explicitly labeled exception described above.

## Processes and startup state

The scanner reports a process only when the process command begins inside the selected application bundle. Any reported process blocks execution; AppSleuth does not send signals automatically. Embedded `LoginItems`, `LaunchServices` helpers, and `SystemExtensions` are reported with exact parent-bundle evidence but never moved separately because moving the containing app already covers them.

LaunchAgent/LaunchDaemon plist files can be discovered, but moving a file does not unload an already loaded launchd job. Modern Background Task Management/login-item records are outside the MVP. A later release should inspect and modify them using supported Apple APIs, with a separate preview and confirmation.

## Permissions

AppSleuth does not bypass SIP, TCC, Full Disk Access, ACLs, or ordinary filesystem permissions. Read failures and unavailable process inspection become scan warnings. `appsleuth doctor` performs a read-only access preflight, while `appsleuth doctor --open-settings` opens the Full Disk Access pane. Apple requires the person using the Mac to grant Full Disk Access in System Settings; AppSleuth cannot grant it in code. Basic scans such as Calculator do not require it, but comprehensive third-party app discovery can benefit from it. Administrator authentication in permanent purge is a separate, narrow capability for one approved application bundle; it does not grant Full Disk Access or authorize shared/system artifact deletion. Reversible system moves can still fail without permission, and their transactional service attempts rollback rather than continuing with a partial plan.
