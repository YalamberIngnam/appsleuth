# AppSleuth

AppSleuth is an evidence-first, open-source macOS application uninstaller for the terminal. It discovers an application and its related files, explains every match, assigns a risk level, and changes nothing unless the user explicitly requests and confirms an operation.

> **Project status:** working prerelease MVP (`0.1.0-beta.1`). Sized app inventory, coverage-ledger app scans, grouped suspected-leftover audits, active user-service inspection, diagnosis-first Optimize & Check, reversible uninstall/restore, and a separately guarded permanent purge are implemented. Beta means the safety model is implemented and tested locally, but the project still needs independent review and real-world feedback before a stable release. Review every plan: this is intentionally not a one-command “delete everything with a similar name” tool.

## Why AppSleuth?

Dragging an app to Trash removes its bundle but often leaves preferences, caches, state, helpers, and launch configuration behind. Aggressive cleaners solve the opposite problem: a fuzzy match can remove shared vendor data or files owned by another product.

AppSleuth treats uninstalling as an evidence problem:

- read-only `scan` and `explain` commands;
- read-only installed-app and suspected-leftover audits, with a separate exact-ID cleanup command;
- dry-run uninstall and restore by default;
- bundle identifier and plist evidence ahead of loose filename matching;
- `SAFE`, `REVIEW`, `HIGH`, and `PROTECTED` risk levels;
- clear `user`, `system`, and `runtime` scopes;
- a numbered scan ledger that distinguishes checked, absent, unavailable, and explicitly unsupported state;
- read-only Mac health diagnosis plus exact-ID maintenance actions—never an optimize-all button;
- exact, app-specific confirmation before any mutation;
- transactional moves to a private restore vault for normal uninstall and cleanup;
- a separate, red-labeled `purge` workflow for explicitly requested permanent local deletion;
- file identity and approved-root checks immediately before every move;
- conservative handling of shared containers, receipts, vendor suites, and running processes.

## Install from source

Requirements: Apple Silicon Mac, macOS 13 or newer, and the Swift toolchain from Xcode Command Line Tools.

```bash
git clone https://github.com/YalamberIngnam/appsleuth.git
cd appsleuth
./scripts/install.sh
appsleuth
```

The installer builds an optimized binary and installs it into `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, depending on what is available and writable. It prints a one-line `PATH` instruction when necessary. It does not modify shell configuration automatically.

It also creates `appsl` as a short **command alias** implemented with a symbolic link (symlink) to the same `appsleuth` executable. Both commands therefore run identical code:

```bash
appsleuth version
appsl version
```

The installer will not overwrite an unrelated command named `appsl`. The earlier provisional `aps` alias was retired after an ecosystem collision check found other CLIs using that command; `as` is also unavailable because macOS already provides Apple's assembler under that name.

You can also use:

```bash
make test
make install
make uninstall
```

Once installed, use `appsleuth` or `appsl` directly—`.build/release/appsleuth` is only the development-build path.

Homebrew installation will become available after the repository has an online home and its first immutable tagged release:

```bash
brew install YalamberIngnam/tap/appsleuth
appsleuth
```

See the [distribution guide](docs/DISTRIBUTION.md) for the tap formula and the path toward an eventual unqualified `brew install appsleuth` command.

The package has no third-party runtime dependencies. Intel macOS is not the primary MVP target, but the code contains no deliberate architecture lock. Installing the binary does not grant Full Disk Access or administrator privileges.

## Interactive terminal home

Run AppSleuth without arguments:

```bash
appsleuth
```

It opens a centered, dedicated alternate-screen terminal dashboard with a large six-line AppSleuth logo. The large logo is shown on ordinary 22-row-or-taller terminal windows; only physically smaller windows use the compact fallback. A two-column menu keeps the full home screen visible beneath it without scrolling. The dashboard appears immediately: Disk, Apps, and Jobs each show their own loading state until that inspection finishes, then update in place. The overview shows used and available disk space, the fast Spotlight-indexed approximate size of non-system, non-Apple `.app` bundles, recognizable application-name previews, the number of third-party app bundles, and the number of visible active third-party user jobs. App-bundle size excludes support data and leftovers; when metadata is incomplete it is marked as a lower bound with an indexed-bundle count. Service visibility does not include system daemons or every modern background registration.

Move through the menu with `↑` and `↓`, then press `Return`; direct shortcut keys such as `l`, `o`, `a`, `s`, `e`, `u`, `x`, `r`, `p`, `m`, `h`, and `q` also work. Press `l` to browse the already-loaded application inventory with `↑`/`↓`; the highlighted app shows its name, version, size, scope, bundle ID, and path, and `q` returns home. Press `m` for the read-only Optimize & Check report. The red permanent-purge section provides a separate scrollable, keyboard-driven third-party application selector, scans the selected app, shows the complete plan, and requires two decisions plus the exact bundle-ID confirmation before execution.

## Commands

```bash
# List application bundles in user, shared, and Apple system locations
appsleuth list

# Exclude Apple system applications, or request structured output
appsleuth list --no-system
appsleuth list --json

# List running user launchd jobs that likely belong to installed third-party apps
appsl services
appsl services --verbose

# Audit the Mac for suspected leftovers; always read-only
appsl leftovers
appsl leftovers --verbose

# Preview selected finding IDs, then execute only after exact confirmation
appsl leftovers clean <finding-id> [more-finding-ids]
appsl leftovers clean <finding-id> --execute

# Always read-only
appsleuth scan "Pixelmator Pro"
appsleuth scan /Applications/Pixelmator\ Pro.app --json

# Read-only Mac health diagnosis; verbose streams every check as it begins
appsl optimize
appsl optimize --verbose

# Preview or execute one exact reviewed maintenance action
appsl optimize quicklook-cache --dry-run
appsl optimize quicklook-cache --execute

# Show evidence for all findings, or one finding by ID/path
appsleuth explain "Pixelmator Pro"
appsleuth explain "Pixelmator Pro" 442c19c2ab12d86f

# Dry-run is the default; these two are equivalent
appsleuth uninstall "Pixelmator Pro"
appsleuth uninstall "Pixelmator Pro" --dry-run

# Include user data/configuration that requires review in the plan
appsleuth uninstall "Pixelmator Pro" --include-review

# Also consider exact system-level matches (may require elevated permission)
appsleuth uninstall "Pixelmator Pro" --include-review --include-system

# Execute only after an app-specific phrase is typed
appsleuth uninstall "Pixelmator Pro" --include-review --execute

# Preview permanent deletion; the app bundle and high-confidence caches/logs are selected
appsl purge "Pixelmator Pro"

# Also include high-confidence, non-shared settings and user data
appsl purge "Pixelmator Pro" --include-user-data

# Permanently delete the eligible plan after an exact confirmation; no rollback vault
appsl purge "Pixelmator Pro" --include-user-data --execute

# Preview or execute a restore
appsleuth restore <backup-id>
appsleuth restore <backup-id> --execute
```

`appsleuth list` is a compact, grouped, read-only application inventory. It lists each app's Spotlight-indexed bundle size alongside its name and version. Bundles with unavailable metadata show `—`. It searches `/Applications`, `~/Applications`, `/System/Applications`, and `/System/Library/CoreServices/Applications`, including apps one folder below those roots. `--no-system` excludes Apple's protected system locations while retaining both personal and shared applications. Use `--verbose` when bundle identifiers and full paths are needed.

`appsl services` is also read-only. It groups running jobs visible through the current user's `launchd` domain under a **likely owner**, using the job label's reverse-DNS vendor namespace and installed non-system, non-Apple bundle identifiers. The list can include a running application's own launch job as well as its helpers. A likely owner is a sorting aid, not proof that one exact application owns the service. System daemons and some modern background registrations require separate inspection.

## Permanent safe purge

`appsl purge <app>` is a deliberately separate workflow. It is dry-run by default and never changes the behavior of `uninstall`, leftover cleanup, or restore.

The default permanent plan selects the approved application bundle plus high-confidence disposable user caches and logs. `--include-user-data` additionally permits high-confidence, non-shared user Application Support, preferences, saved state, web data, sandbox containers, and Application Scripts. It always keeps:

- Group Containers and other potentially shared dependencies;
- launch agents, launch daemons, startup jobs, privileged helpers, and active processes;
- all system-level findings outside the selected application bundle;
- frameworks, fonts, profiles, command-line/package-manager records, receipts, and low-level extensions;
- fuzzy matches and anything below the permanent ownership threshold.

Before execution, AppSleuth recursively preflights permissions for every selected root. A blocker stops the entire operation before anything is deleted. When an approved `.app` under `/Applications` contains administrator-owned files, the preview marks only that exact bundle `ADMIN REQUIRED`. After the exact permanent-deletion phrase, AppSleuth asks `sudo` to authenticate **before the first mutation**; cancellation or failed authentication leaves every selected root untouched. The elevated command is limited to removing the revalidated application bundle—AppSleuth itself, user data, shared items, and the scan never run as root.

Execution still revalidates every selected path and deletes the application bundle last. It creates no AppSleuth backup and performs no rollback. “Without any trace” cannot be guaranteed on modern macOS: APFS snapshots, Time Machine backups, package-manager databases, Keychain, privacy databases, vendor cloud services, and other macOS-managed registrations may retain records or copies. Permanent deletion is ordinary filesystem removal, not secure erasure of SSD blocks.

## Whole-Mac leftover audit

`appsl leftovers` compares reverse-DNS-style artifact identifiers—such as `org.example.product`—with every application bundle AppSleuth can inventory. It checks the approved user and system roots for support data, preferences, caches, logs, saved state, containers, scripts, launchd plists, privileged helpers, plug-ins, and related categories. It also reports launchd candidates that appear loaded in the current user domain and processes whose executable still points inside a missing `.app` bundle.

The results are deliberately called **suspected leftovers**. The absence of a matching `.app` is not proof that a file is unused: command-line software, plug-ins, shared vendor components, and externally managed services may have no main application bundle. The audit groups results alphabetically under colored **likely owner** headings, but names extracted from identifiers are heuristic labels rather than verified product ownership. AppSleuth therefore:

- ignores plain vendor-name folders and Apple-owned identifiers;
- suppresses candidates when an installed app shares their vendor namespace;
- raises confidence when one identifier appears in several artifact categories or a launchd executable path is broken;
- never provides a “clean all” command;
- requires exact finding IDs for a cleanup plan;
- keeps active jobs, privileged helpers, processes, and services with unknown domain state report-only;
- requires `--include-system` for selected system items;
- moves confirmed items to the restore vault instead of permanently deleting them.

The audit itself is read-only so that broad discovery cannot become broad deletion. Deletion is not forbidden: `appsl leftovers clean <finding-id>` previews an exact candidate, and `--execute` moves eligible items into the restore vault after confirmation. Items that are active, shared, privileged, protected, or whose service state cannot be verified remain report-only. Re-run the audit immediately before selecting IDs because findings are snapshots of filesystem state.

`--json` is available for application inventories, read-only scans, leftover audits, explanations, plans, and restore previews. It is deliberately incompatible with `--execute`, because MVP execution always requires an interactive confirmation phrase.

Progress is animated automatically in an interactive terminal. A scan numbers every catalog, embedded, and runtime step. Use `--quiet` to hide progress or `--verbose` to preserve each location as a line while it is inspected:

```bash
appsleuth scan "Pixelmator Pro" --quiet
appsleuth scan "Pixelmator Pro" --verbose
```

Every completed scan also prints a coverage ledger summary: locations checked, expected locations that were not present, locations macOS did not allow AppSleuth to read, categories covered, and state outside filename-based discovery. With `--verbose`, the final report includes the complete per-location ledger. “Not present” is a successful check with nothing at that location; “unavailable” is unknown, not empty. AppSleuth cannot honestly promise that a bounded scan sees every file a vendor could create, so the report makes that limit visible instead of hiding it.

## Optimize & Check

`appsl optimize` is diagnosis-only by default. It displays a loading spinner in a normal terminal, while `--verbose` streams all eight checks: memory/disk/swap/uptime, a point-in-time CPU snapshot, mounted disk images, bounded preference-plist validity, launch-agent/daemon integrity, active VPN state, DNS resolver visibility, and local Homebrew availability. Default checks do not contact package servers or change the Mac.

The initial reviewed action catalog is intentionally small:

- `quicklook-cache` asks macOS to rebuild the disposable Quick Look thumbnail cache;
- `restart-dock` briefly restarts the current user's Dock process;
- one dynamic `detach-…` action appears for each exact mounted disk-image volume.

Actions are never selected merely because they are available. Preview an exact ID first, then add `--execute` and type the displayed confirmation phrase. There is no select-all or optimize-all command. Each disk-image target is rechecked immediately before detach. These maintenance actions do not have an AppSleuth restore vault, so they are kept separate from reversible app uninstallation.

AppSleuth does not claim that generic cache resets improve a healthy Mac. It deliberately omits blanket permission repair, database rewriting, Bluetooth/network-stack resets, launch-service rebuilding, job unloading, memory purging, and undocumented system modifications. A check marked unavailable stays unknown; it is never silently converted into a green result.

## Permissions and diagnostics

Basic scans—including Calculator—do not require Full Disk Access. Some protected third-party application data can be omitted when the terminal host lacks that permission.

Run the read-only diagnostic:

```bash
appsleuth doctor
```

To open the relevant settings pane:

```bash
appsleuth doctor --open-settings
```

macOS does not allow a CLI to grant itself Full Disk Access. In **System Settings → Privacy & Security → Full Disk Access**, enable the terminal application you use, such as Terminal or iTerm, then quit and reopen that terminal. AppSleuth reports inaccessible scan roots and unavailable process inspection instead of silently treating them as empty.

## What macOS software can leave behind

An application is usually a directory ending in `.app`, called an **application bundle**. Dragging that bundle to Trash normally moves only that directory. A vendor installer—or the app itself while running—may have created data and registered services elsewhere.

The correct spelling is **launch agent**, not “lunch agent.” Both launch agents and launch daemons are jobs managed by macOS's `launchd` service: agents run in a user's login session, while daemons usually provide system-wide background work without a graphical login.

### Common ways software is installed

The installation method affects which records and extra files may exist:

| Installation method | What it does | Typical extra evidence |
|---|---|---|
| Drag from a downloaded `.dmg` or `.zip` | Copies an `.app` bundle into `/Applications` or `~/Applications` | Usually no package receipt, although the app can create support data, helpers, login items, and services when first launched. |
| Apple Installer package (`.pkg`) | Runs a signed installer that can place files in several approved user or system locations | Package receipts/BOMs, shared support files, launch jobs, privileged helpers, frameworks, command-line tools, or extensions. |
| Mac App Store | Installs and updates a signed, normally sandboxed app through Apple | App bundle, sandbox container, group containers, application scripts, preferences, and App Store receipt metadata. |
| Homebrew Cask | Downloads and installs a macOS app, often by copying or linking its bundle and running declared installer/uninstall steps | Homebrew cask records plus whatever the vendor's app or package creates. |
| Homebrew Formula | Installs command-line software into the Homebrew prefix rather than as a normal `.app` | Binaries, libraries, configuration, background services, and Homebrew's installation metadata. |
| App-managed installer or updater | The app installs components during first launch, updates itself, or downloads suite components | Update agents, background helpers, vendor support folders, privileged tools, and login/background registrations. |

AppSleuth inventories `.app` bundles directly. It uses package receipts and service metadata as evidence, but it does not yet replace Homebrew, App Store, or a vendor's supported uninstaller database.

No finite list can cover every installer because software with administrator permission can write to many locations. These are the important macOS categories AppSleuth must reason about:

| Artifact | Common locations | Purpose | What happens when the `.app` is dragged to Trash? |
|---|---|---|---|
| Application bundle | `/Applications/App.app`, `~/Applications/App.app` | Main executable, resources, embedded frameworks, and metadata | This is the item moved to Trash. |
| User Application Support | `~/Library/Application Support/<app or vendor>` | Databases, downloaded resources, indexes, user data, and app state | Usually remains. It may contain valuable user data. |
| Shared Application Support | `/Library/Application Support/<app or vendor>` | Machine-wide assets, licensing data, shared services, and suite components | Remains; it may be shared by several products. |
| Preferences | `~/Library/Preferences/*.plist`, `/Library/Preferences/*.plist` | User or machine-wide settings | Usually remains. |
| Caches and temporary data | `~/Library/Caches`, `/Library/Caches`, `~/Library/HTTPStorages` | Rebuildable performance data, downloaded responses, and network caches | Usually remains; not every cache is safe to identify by name alone. |
| Logs and crash reports | `~/Library/Logs`, `/Library/Logs`, `~/Library/Logs/DiagnosticReports` | Diagnostics, audit history, and crash information | Usually remains. |
| Saved application state | `~/Library/Saved Application State` | Windows and documents restored when an app reopens | Usually remains. |
| Sandbox container | `~/Library/Containers/<bundle-id>` | A sandboxed app's private data, preferences, caches, and documents | Usually remains and can include user-created data. |
| Group container | `~/Library/Group Containers/<group-id>` | Data shared by a family of apps and extensions | Usually remains; deleting it can break other apps from the same vendor. |
| Application Scripts | `~/Library/Application Scripts/<bundle-or-group-id>` | User-approved scripts for sandboxed apps and extensions | Usually remains. |
| Web data | `~/Library/WebKit`, `~/Library/Cookies`, `~/Library/HTTPStorages` | Embedded-browser storage, cookies, sessions, and website data | Usually remains and may contain signed-in sessions. |
| Launch agent | `~/Library/LaunchAgents`, `/Library/LaunchAgents` | Starts a per-user helper at login or on demand | Its plist remains. A separately installed helper may continue running or relaunching. |
| Launch daemon | `/Library/LaunchDaemons` | Starts a system-wide or privileged background service, often at boot | Remains and may stay loaded if its executable also remains. |
| Login item or background item | Inside the app, `/Applications`, `~/Applications`, vendor support folders, plus macOS-managed registration | Starts a helper after login or permits background activity | Embedded files move with the bundle; separate helpers and registrations may remain. Modern items must be managed through supported macOS APIs or System Settings. |
| Privileged helper tool | `/Library/PrivilegedHelperTools` | Performs narrowly authorized operations as `root` for an app | Remains unless the vendor uninstaller removes it. It is commonly paired with a launch daemon. |
| Startup item (legacy) | `/Library/StartupItems` | Old pre-`launchd` boot-time service | Remains on systems where one exists. |
| XPC service or helper | Inside `App.app/Contents/XPCServices`, `LoginItems`, or `Library/LaunchServices`; sometimes installed separately | Isolates helper work, login behavior, updates, or interprocess communication | Embedded helpers move with the app; separately installed helpers remain. |
| Plug-in or extension | `~/Library` or `/Library` locations for Quick Look, Internet Plug-Ins, Spotlight, audio plug-ins, preference panes, and services | Extends Finder, browsers, media apps, Spotlight, System Settings, or other hosts | Separately installed items remain and can still be loaded by their host. |
| System, network, driver, or kernel extension | App bundle, `/Library/SystemExtensions`, `/Library/Extensions`, or macOS-managed registrations | Adds security, networking, hardware, VPN, or low-level capabilities | May remain active or registered. These require vendor or Apple-supported deactivation workflows—not blind file deletion. |
| Shared framework or library | `/Library/Frameworks`, `/usr/local/lib`, `/opt/homebrew/lib`, vendor support folders | Code shared by one or more products | Remains and must be treated as shared unless ownership is proven. |
| Command-line tool or shell integration | `/usr/local/bin`, `/opt/homebrew/bin`, shell configuration, completion directories | Adds terminal commands, PATH entries, aliases, or completions | Remains because it lives outside the app bundle. |
| Font, color profile, audio component, or device support | `~/Library` or `/Library` subdirectories such as `Fonts`, `ColorSync`, and `Audio/Plug-Ins` | Adds content or hardware/media capabilities to the system | Remains and may be shared with other software. |
| Package receipt and BOM | `/var/db/receipts/*.plist`, `/var/db/receipts/*.bom` | Records that a signed installer package installed files and which payload it contained | Remains. A receipt is evidence, not proof that every recorded file is still exclusively owned. |
| Keychain item, certificate, privacy grant, or system registration | macOS-managed databases and Keychain | Stores credentials, trust, permissions, handlers, and registrations | Usually remains; these must be changed through supported APIs, Keychain, or System Settings. |
| Running process | Memory/runtime state rather than one leftover file | The app, updater, sync engine, or helper currently executing | Can continue until it exits. A launch job may restart it if its external executable and registration remain. |

This is why “the icon is gone” does not always mean “the software is completely uninstalled.” It is also why AppSleuth shows evidence and risk instead of deleting every path containing a vendor name.

Apple references: [Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html), [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice), and [Login Items & Extensions settings](https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac).

### What AppSleuth currently discovers

The MVP checks the selected `.app` bundle and direct children of these locations:

| Scope | Categories |
|---|---|
| User | Application Support, Preferences, Caches, Logs/crash reports, Saved Application State, WebKit/HTTP/cookie data, Containers, Group Containers, Application Scripts, LaunchAgents, LaunchServices, Internet/QuickLook/Spotlight/audio plug-ins, preference panes, services, screen savers, frameworks, fonts, and color profiles |
| System | Application Support, Preferences, Caches, Logs/crash reports, LaunchAgents, LaunchDaemons, LaunchServices, PrivilegedHelperTools, StartupItems, plug-ins, audio components, frameworks, fonts, profiles, SystemExtensions, and legacy driver/kernel extensions |
| External/protected evidence | `/usr/local` and Homebrew command-line tools, shell completions, Caskroom/Cellar records, and installer receipts under `/var/db/receipts` |
| Runtime | Processes whose executable command begins inside the selected app bundle |
| Embedded | LoginItems, LaunchServices helpers, XPC services, plug-ins, frameworks, QuickLook/Spotlight importers, SystemExtensions, and Mac App Store receipt data inside the selected app bundle |
| Explicit coverage limits | Keychain items, certificates, privacy grants, handler registrations, and modern Background Task Management records are disclosed as macOS-managed rather than guessed or blindly deleted |

Direct-child scanning is intentional. AppSleuth does not recursively crawl arbitrary folders or follow symlinks while searching.
An explicit `.app` path outside `/Applications` or `~/Applications` can be inspected, but its bundle is marked `PROTECTED` and cannot be moved.
Application lookup accepts bundles directly inside those roots or one containing folder below them, covering layouts such as `/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app` without recursive search.

## Complex suites such as Adobe

AppSleuth is designed to expose complex suite artifacts without assuming every vendor file belongs to one product. For a Photoshop-style app, exact identifiers such as `com.adobe.Photoshop` can qualify as strong evidence. A shared folder named only `Adobe`, Creative Cloud services, shared group containers, licensing components, and package receipts are not silently selected.

Vendor-specific uninstall recipes and code-signing Team ID correlation are planned, but recipes will add evidence—not bypass the central safety policy.

## Restore vault

Executed uninstalls move selected items to:

```text
~/.local/share/appsleuth/backups/<backup-id>/
├── manifest.json
└── payload/
```

The manifest records original and backup paths, item kind/scope, and per-item state. Restore revalidates both sides of every move, refuses destinations outside approved roots, refuses to overwrite an existing original path, and keeps the backup for manual resolution. If an uninstall move fails partway through, AppSleuth attempts to roll back earlier moves and retains the manifest as an audit record.

## Current boundaries

The MVP does **not**:

- securely erase SSD blocks, delete APFS/Time Machine history, or promise that no external trace exists;
- permanently delete shared, system-level, startup, privileged, extension, package-manager, receipt, or uncertain findings through `purge`;
- automatically kill processes, unload launchd jobs, or alter external modern Background Task Management records (embedded login/background helpers are reported read-only);
- remove package receipts with `pkgutil --forget`;
- delete fuzzy name-only matches or vendor-wide shared directories;
- bypass SIP, TCC, Full Disk Access, or filesystem permissions;
- claim that every third-party installer convention is already known.

These are safety boundaries, not hidden failures. Missing permission locations appear as scan warnings.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Safety and matching model](docs/SAFETY.md)
- [MVP plan and roadmap](docs/ROADMAP.md)
- [Distribution and Homebrew](docs/DISTRIBUTION.md)
- [Open-source operations](docs/OPEN_SOURCE.md)
- [Release process](docs/RELEASING.md)
- [Swift versus Python](docs/LANGUAGE.md)
- [Current project status](PROJECT_STATUS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security policy](SECURITY.md)

## License

AppSleuth is available under the [MIT License](LICENSE).
