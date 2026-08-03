# Troubleshooting

## A scan appears stuck

Current builds continuously update the spinner with the approved location being inspected:

```bash
appsleuth scan Calculator
```

For a persistent line-by-line trace, use:

```bash
appsleuth scan Calculator --verbose
```

If progress stops, record the last numbered location or check. That line is the most useful first detail in a bug report.

The final scan coverage section distinguishes `Checked`, `Not present`, and `Unavailable`. A location that is not present was successfully considered and had no directory to enumerate. An unavailable location could not be inspected and must not be interpreted as empty.

AppSleuth previously had a process-inspection deadlock when `ps` produced more data than the operating-system pipe buffer. The child process output is now drained before AppSleuth waits for termination, and a regression test sends more than 300 KB through that path.

The whole-Mac leftover audit also puts time limits around `launchctl` and `ps` inspection. If either check cannot complete, AppSleuth stops that child check, prints a coverage warning, and keeps affected services report-only instead of assuming they are inactive.

## Optimize & Check reports unavailable or attention

Run the diagnosis with a persistent check-by-check trace:

```bash
appsl optimize --verbose
```

`Unavailable` means the current terminal session or macOS denied, timed out, or did not expose that measurement. It is not a failed health result. In preference and launch-job checks, unreadable files are reported separately from files that were actually parsed and found malformed.

`Attention` is evidence to review, not permission to repair. A missing absolute launch-job executable can be a stale uninstall leftover, but AppSleuth does not unload or delete the job from the optimize command. Low disk space is based on a conservative threshold and should be addressed through reviewed cleanup, not blind cache deletion.

The available maintenance action IDs are symptom-specific. Preview one with `appsl optimize <action-id> --dry-run`. Execution requires the same exact ID plus `--execute`; there is no optimize-all command and no AppSleuth restore vault for these small system-maintenance actions.

## Check permissions

Run the read-only diagnostic:

```bash
appsleuth doctor
```

The report distinguishes:

- readable user cleanup locations;
- readable system cleanup locations;
- process-inventory availability;
- a conservative Full Disk Access probe.

Basic scans such as Calculator do not require Full Disk Access. Protected third-party application data may be omitted without it.

To open the relevant settings pane:

```bash
appsleuth doctor --open-settings
```

Enable the terminal host you actually use under **System Settings → Privacy & Security → Full Disk Access**, then quit and reopen that terminal. AppSleuth cannot grant this permission to itself.

## Process inspection is unavailable

When macOS or an endpoint-security policy prevents `ps` access, the scan continues and prints a warning instead of hanging or treating the check as successful. `appsleuth doctor` provides the same capability result independently.

The absence of process information matters before an executed uninstall because AppSleuth normally uses it to block removal while the selected app is running. Review the warning and quit the target app manually.

## Some application sizes show `—`

The application list asks Spotlight metadata for each bundle's indexed size. A dash means macOS did not return that metadata within the bounded inspection time; it does not mean the app is empty. AppSleuth does not recursively walk the bundle as a fallback because doing that for every installed application can make the list appear stuck.

If most or all sizes are unavailable, run AppSleuth from your normal Terminal or iTerm session rather than a restricted automation or sandbox. Rebuilding the Spotlight index is a system-wide action and is not performed automatically.

## Permanent purge keeps some discovered files

This is expected. `appsl purge "Application Name"` checks more categories than it is allowed to permanently delete. Shared containers, system files, startup/background jobs, privileged helpers, plug-ins, extensions, receipts, package-manager records, and uncertain matches remain marked `KEEP`. Embedded components are marked `COVERED` because removing the selected `.app` bundle removes them with it.

Use `--include-user-data` only when you also want high-confidence app-specific settings and data included. Permanent purge has no AppSleuth restore vault. It is ordinary filesystem deletion—not secure erasure—and cannot remove APFS snapshots, Time Machine copies, Keychain items, privacy records, or vendor-cloud data.

## Permanent purge says `ADMIN REQUIRED`

Installer packages sometimes create `/Applications/App.app` as `root:wheel`. Your account may be allowed to move the bundle entry while still lacking permission to recursively erase its administrator-owned contents. AppSleuth checks the complete selected trees before mutation and marks an eligible root-owned application bundle `ADMIN REQUIRED`.

If you continue with `--execute` and type the exact phrase, the standard `sudo` password prompt appears before anything is deleted. Cancelling or failing that prompt changes nothing. Elevation is limited to the exact revalidated `.app` bundle under `/Applications`; AppSleuth does not run its scan or user-data deletion as root. Full Disk Access is different from administrator authentication and still must be granted to the terminal host through System Settings when needed.

## `appsleuth: command not found`

Find the installed executable:

```bash
command -v appsleuth
```

Reinstall from the project directory if necessary:

```bash
./scripts/install.sh
```

The installer uses `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`. If it chooses `~/.local/bin`, add the printed `PATH` line to `~/.zprofile`, open a new terminal, and try again.

Refresh the current shell's command lookup after reinstalling:

```bash
hash -r
```

The shorter `appsl` command is a symlink to the same executable. Check it with:

```bash
command -v appsl
appsl version
```

## Confirm which build is running

```bash
command -v appsleuth
appsleuth version
```

During local development, `.build/release/appsleuth` may be newer than the installed command. Run `./scripts/install.sh` again after rebuilding to replace the installed copy.

## The alternate terminal screen looks damaged

Press `q` to exit normally. AppSleuth restores the previous terminal screen and settings when it exits through the menu.

If the process was forcibly terminated and the shell no longer echoes input correctly, type:

```bash
reset
```

and press Return.

## Collect safe diagnostic output

Machine-readable permission report:

```bash
appsleuth doctor --json
```

Verbose read-only scan:

```bash
appsleuth scan "Application Name" --verbose
```

Before sharing output, remove usernames, personal filesystem paths, backup identifiers, bundle data that identifies private software, and any secrets. Use private vulnerability reporting for any behavior that could move unrelated data or bypass the safety policy.
