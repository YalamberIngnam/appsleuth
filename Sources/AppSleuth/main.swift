import AppSleuthCore
import Darwin
import Foundation

private let version = "0.1.0-beta.1"

private struct CLI {
    let arguments: [String]

    func run() throws {
        guard let command = arguments.first else {
            try interactiveHome()
            return
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "list", "apps":
            try listApplications(rest)
        case "leftovers", "orphans":
            try leftovers(rest)
        case "services":
            try services(rest)
        case "scan":
            try scan(rest)
        case "explain":
            try explain(rest)
        case "uninstall":
            try uninstall(rest)
        case "purge":
            try purge(rest)
        case "restore":
            try restore(rest)
        case "doctor":
            try doctor(rest)
        case "optimize", "optimise", "health":
            try optimize(rest)
        case "version", "--version", "-v":
            print("appsleuth \(version)")
        case "help", "--help", "-h":
            printUsage()
        default:
            throw AppSleuthError.invalidArguments("Unknown command '\(command)'. Run 'appsleuth help'.")
        }
    }

    private func listApplications(_ args: [String]) throws {
        let parsed = try parse(args, allowedFlags: ["--no-system", "--json", "--quiet", "--verbose"])
        guard parsed.positionals.isEmpty else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth list [--no-system] [--json]")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let discovered = reporter.activity("Listing installed applications") {
            ApplicationLocator().installedApplications(
                includeSystem: !parsed.flags.contains("--no-system")
            ) { message in reporter.detail(message) }
        }
        let applications = reporter.activity("Reading indexed application sizes") {
            ApplicationSizeInspector().enrich(discovered)
        }
        reporter.success("Found \(applications.count) installed application(s)")
        if parsed.flags.contains("--json") {
            try printJSON(applications)
        } else {
            printInstalledApplications(applications, verbose: parsed.flags.contains("--verbose"))
        }
    }

    private func leftovers(_ args: [String]) throws {
        if args.first == "clean" {
            try cleanLeftovers(Array(args.dropFirst()))
            return
        }
        let scanArgs = args.first == "scan" ? Array(args.dropFirst()) : args
        let parsed = try parse(scanArgs, allowedFlags: ["--json", "--quiet", "--verbose"])
        guard parsed.positionals.isEmpty else {
            throw AppSleuthError.invalidArguments(
                "Usage: appsleuth leftovers [scan] [--json]"
            )
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let report = makeLeftoverReport(reporter: reporter)
        if parsed.flags.contains("--json") {
            try printJSON(report)
        } else {
            printLeftoverReport(report, verbose: parsed.flags.contains("--verbose"))
        }
    }

    private func cleanLeftovers(_ args: [String]) throws {
        let parsed = try parse(
            args,
            allowedFlags: [
                "--dry-run", "--execute", "--include-system", "--json", "--quiet", "--verbose"
            ]
        )
        guard !parsed.positionals.isEmpty else {
            throw AppSleuthError.invalidArguments(
                "Usage: appsleuth leftovers clean <finding-id>... [--dry-run|--execute] [--include-system]"
            )
        }
        guard !(parsed.flags.contains("--dry-run") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("Choose either --dry-run or --execute, not both.")
        }
        guard !(parsed.flags.contains("--json") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("--json cannot be combined with --execute because execution is interactive.")
        }

        let reporter = try makeReporter(flags: parsed.flags)
        let report = makeLeftoverReport(reporter: reporter)
        let requestedIDs = Set(parsed.positionals)
        let availableIDs = Set(report.candidates.map(\.finding.id))
        let missingIDs = requestedIDs.subtracting(availableIDs).sorted()
        guard missingIDs.isEmpty else {
            throw AppSleuthError.invalidArguments(
                "No current leftover finding matched: \(missingIDs.joined(separator: ", ")). Run 'appsleuth leftovers' again."
            )
        }
        let plan = LeftoverCleanupPlanner().makePlan(
            from: report,
            selectedIDs: requestedIDs,
            includeSystem: parsed.flags.contains("--include-system")
        )
        if parsed.flags.contains("--json") {
            try printJSON(plan)
        } else {
            printLeftoverPlan(plan, requestedIDs: requestedIDs)
        }
        guard parsed.flags.contains("--execute") else {
            if !parsed.flags.contains("--json") {
                print("Dry run only. Nothing was changed. Add --execute only after reviewing every selected path.")
            }
            return
        }

        guard !plan.selected.isEmpty else {
            throw AppSleuthError.unsafeOperation("No requested leftover is currently eligible to move.")
        }
        let phrase = "CLEAN \(plan.selected.count) LEFTOVERS"
        print("\nThis will move \(plan.selected.count) selected item(s) into AppSleuth's restore vault.")
        print("Type exactly: \(phrase)")
        print("> ", terminator: "")
        guard readLine() == phrase else {
            throw AppSleuthError.unsafeOperation("Confirmation did not match. Nothing was changed.")
        }
        let result = try reporter.activity("Moving selected leftovers into the restore vault") {
            try LeftoverCleanupService().execute(plan)
        }
        reporter.success("Reversible leftover cleanup completed")
        print("Moved \(result.moved.count) item(s) into backup \(result.backupID).")
        print("Restore with: appsl restore \(result.backupID) --execute")
    }

    private func services(_ args: [String]) throws {
        let parsed = try parse(args, allowedFlags: ["--json", "--quiet", "--verbose"])
        guard parsed.positionals.isEmpty else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth services [--json]")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let installed = reporter.activity("Inventorying third-party applications") {
            ApplicationLocator().installedApplications(includeSystem: false) { message in
                reporter.detail(message)
            }
        }
        let report = reporter.activity("Inspecting active user services") {
            SystemOverviewInspector().inspectActiveUserServices(installedApplications: installed)
        }
        reporter.success("Found \(report.services.count) active third-party user service(s)")
        if parsed.flags.contains("--json") {
            try printJSON(report)
        } else {
            printServiceReport(report, verbose: parsed.flags.contains("--verbose"))
        }
    }

    private func makeLeftoverReport(reporter: ProgressReporter) -> LeftoverReport {
        let installed = reporter.activity("Inventorying installed applications") {
            ApplicationLocator().installedApplications { message in reporter.detail(message) }
        }
        let report = reporter.activity("Auditing approved macOS locations for leftovers") {
            LeftoverScanner().scan(installedApplications: installed) { message in reporter.detail(message) }
        }
        reporter.success("Leftover audit complete: \(report.candidates.count) candidate(s)")
        return report
    }

    private func scan(_ args: [String]) throws {
        let parsed = try parse(args, allowedFlags: ["--json", "--quiet", "--verbose"])
        guard parsed.positionals.count == 1 else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth scan <app-name-or-path> [--json]")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let report = try makeReport(query: parsed.positionals[0], reporter: reporter)
        if parsed.flags.contains("--json") {
            try printJSON(report)
        } else {
            printScan(report, verbose: parsed.flags.contains("--verbose"))
        }
    }

    private func explain(_ args: [String]) throws {
        let parsed = try parse(args, allowedFlags: ["--json", "--quiet", "--verbose"])
        guard (1...2).contains(parsed.positionals.count) else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth explain <app-name-or-path> [finding-id-or-path] [--json]")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let report = try makeReport(query: parsed.positionals[0], reporter: reporter)
        let filtered: [Finding]
        if parsed.positionals.count == 2 {
            let selector = NSString(string: parsed.positionals[1]).expandingTildeInPath
            filtered = report.findings.filter { $0.id == selector || $0.path == selector }
            guard !filtered.isEmpty else {
                throw AppSleuthError.invalidArguments("No finding matched '\(parsed.positionals[1])'.")
            }
        } else {
            filtered = report.findings
        }
        if parsed.flags.contains("--json") {
            try printJSON(filtered)
        } else {
            print("Evidence for \(report.application.name) [\(report.application.bundleIdentifier)]\n")
            for finding in filtered {
                print("[\(finding.risk.label)] \(finding.kind.rawValue) · \(finding.scope.rawValue) · \(finding.confidence)%")
                print("  ID:   \(finding.id)")
                print("  Path: \(finding.path)")
                for reason in finding.reasons { print("  Why:  \(reason)") }
                print("  Move: \(finding.removable ? "eligible after policy checks" : "never selected")\n")
            }
        }
    }

    private func uninstall(_ args: [String]) throws {
        let parsed = try parse(
            args,
            allowedFlags: [
                "--dry-run", "--execute", "--include-review", "--include-system",
                "--json", "--quiet", "--verbose"
            ]
        )
        guard parsed.positionals.count == 1 else {
            throw AppSleuthError.invalidArguments(
                "Usage: appsleuth uninstall <app-name-or-path> [--dry-run|--execute] [--include-review] [--include-system]"
            )
        }
        guard !(parsed.flags.contains("--dry-run") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("Choose either --dry-run or --execute, not both.")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let report = try makeReport(query: parsed.positionals[0], reporter: reporter)
        let options = PlanOptions(
            includeReview: parsed.flags.contains("--include-review"),
            includeSystem: parsed.flags.contains("--include-system")
        )
        let plan = UninstallPlanner().makePlan(from: report, options: options)

        if parsed.flags.contains("--json") {
            try printJSON(plan)
        } else {
            printPlan(plan)
        }
        guard parsed.flags.contains("--execute") else {
            if !parsed.flags.contains("--json") {
                print("Dry run only. Nothing was changed. Add --execute to request a confirmed, reversible uninstall.")
            }
            return
        }

        guard !parsed.flags.contains("--json") else {
            throw AppSleuthError.invalidArguments("--json cannot be combined with --execute because execution is interactive.")
        }
        let phrase = "UNINSTALL \(report.application.bundleIdentifier)"
        print("\nThis will move \(plan.selected.count) item(s) into AppSleuth's restore vault.")
        print("Type exactly: \(phrase)")
        print("> ", terminator: "")
        guard readLine() == phrase else {
            throw AppSleuthError.unsafeOperation("Confirmation did not match. Nothing was changed.")
        }
        let result = try reporter.activity("Moving selected items into the restore vault") {
            try UninstallService().execute(plan)
        }
        reporter.success("Reversible uninstall completed")
        print("Moved \(result.moved.count) item(s) into backup \(result.backupID).")
        print("Restore with: appsleuth restore \(result.backupID) --execute")
    }

    private func purge(
        _ args: [String],
        confirmation: ((String) -> Bool)? = nil
    ) throws {
        let parsed = try parse(
            args,
            allowedFlags: [
                "--dry-run", "--execute", "--include-user-data",
                "--json", "--quiet", "--verbose"
            ]
        )
        guard parsed.positionals.count == 1 else {
            throw AppSleuthError.invalidArguments(
                "Usage: appsleuth purge <app-name-or-path> [--dry-run|--execute] [--include-user-data]"
            )
        }
        guard !(parsed.flags.contains("--dry-run") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("Choose either --dry-run or --execute, not both.")
        }
        guard !(parsed.flags.contains("--json") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments(
                "--json cannot be combined with --execute because permanent deletion requires interactive confirmation."
            )
        }

        let reporter = try makeReporter(flags: parsed.flags)
        let report = try makeReport(query: parsed.positionals[0], reporter: reporter)
        let plan = PermanentPurgePlanner().makePlan(
            from: report,
            options: PurgeOptions(
                includeUserData: parsed.flags.contains("--include-user-data")
            )
        )
        let purgeService = PermanentPurgeService()
        let preflight = plan.selected.isEmpty
            ? PurgePreflight(selectedCount: 0)
            : try reporter.activity("Checking deletion permissions") {
                try purgeService.preflight(plan)
            }
        if parsed.flags.contains("--json") {
            try printJSON(plan)
        } else {
            printPurgePlan(plan, includesUserData: parsed.flags.contains("--include-user-data"))
            printScanCoverage(report.coverage, verbose: false)
            if !report.warnings.isEmpty {
                print("\nCoverage notes:")
                report.warnings.forEach { print("  - \($0)") }
            }
            printPurgePreflight(preflight)
        }
        guard parsed.flags.contains("--execute") else {
            if !parsed.flags.contains("--json") {
                print("Dry run only. Nothing was changed.")
                print("Add --execute only if you accept permanent deletion with no AppSleuth rollback.")
            }
            return
        }
        guard !plan.selected.isEmpty else {
            throw AppSleuthError.unsafeOperation("No item is eligible for permanent deletion.")
        }
        guard preflight.blockers.isEmpty else {
            throw AppSleuthError.unsafeOperation(
                "Permission preflight found blockers. Nothing was deleted. Review the paths above."
            )
        }

        let phrase = "PERMANENTLY DELETE \(report.application.bundleIdentifier)"
        print("\n\(styled("IRREVERSIBLE:", code: "1;31")) \(plan.selected.count) item(s) will be deleted without a restore vault.")
        print("APFS snapshots, Time Machine, vendor servers, and macOS-managed records may still retain copies.")
        if !preflight.administratorRequiredPaths.isEmpty {
            print("Administrator authentication will occur before any selected item is deleted.")
        }
        print("Type exactly: \(phrase)")
        let confirmed: Bool
        if let confirmation {
            confirmed = confirmation(phrase)
        } else {
            print("> ", terminator: "")
            confirmed = readLine() == phrase
        }
        guard confirmed else {
            throw AppSleuthError.unsafeOperation("Confirmation did not match. Nothing was changed.")
        }

        let result: PurgeResult
        if preflight.administratorRequiredPaths.isEmpty {
            result = try reporter.activity("Permanently deleting selected items") {
                try purgeService.execute(plan)
            }
        } else {
            print("\nRequesting administrator permission for the approved application bundle…")
            result = try purgeService.execute(plan)
        }
        reporter.success("Permanent purge completed")
        print("Permanently deleted \(result.deleted.count) local item(s) for \(result.application.name).")
        print("No AppSleuth backup or rollback was created.")
    }

    private func printPurgePreflight(_ preflight: PurgePreflight) {
        print("\nPermission preflight:")
        let readyCount = preflight.selectedCount
            - preflight.administratorRequiredPaths.count
            - preflight.blockers.count
        if readyCount > 0 {
            print("  \(styled("[READY]", code: "1;32")) \(readyCount) selected root(s) are removable by the current user.")
        }
        for path in preflight.administratorRequiredPaths {
            print("  \(styled("[ADMIN REQUIRED]", code: "1;33")) \(path)")
            print("    ↳ root-owned bundle contents require narrowly scoped administrator removal")
        }
        for blocker in preflight.blockers {
            print("  \(styled("[BLOCKED]", code: "1;31")) \(blocker.path)")
            print("    ↳ \(blocker.reason)")
        }
        if preflight.selectedCount == 0 {
            print("  No roots are selected for permanent deletion.")
        }
    }

    private func restore(_ args: [String]) throws {
        let parsed = try parse(
            args,
            allowedFlags: ["--dry-run", "--execute", "--json", "--quiet", "--verbose"]
        )
        guard parsed.positionals.count == 1 else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth restore <backup-id> [--dry-run|--execute] [--json]")
        }
        guard !(parsed.flags.contains("--dry-run") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("Choose either --dry-run or --execute, not both.")
        }
        let id = parsed.positionals[0]
        let reporter = try makeReporter(flags: parsed.flags)
        let service = UninstallService()
        let manifest = try reporter.activity("Loading backup manifest") {
            try service.restorePreview(id: id)
        }
        if parsed.flags.contains("--json") {
            try printJSON(manifest)
        } else {
            print("Restore preview: \(manifest.id)")
            print("Application: \(manifest.application.name)")
            for item in manifest.items where item.status == .moved {
                print("  [RESTORE] \(item.originalPath)")
            }
        }
        guard parsed.flags.contains("--execute") else {
            if !parsed.flags.contains("--json") { print("Dry run only. Nothing was changed.") }
            return
        }
        guard !parsed.flags.contains("--json") else {
            throw AppSleuthError.invalidArguments("--json cannot be combined with --execute because execution is interactive.")
        }
        let phrase = "RESTORE \(id)"
        print("Type exactly: \(phrase)")
        print("> ", terminator: "")
        guard readLine() == phrase else {
            throw AppSleuthError.unsafeOperation("Confirmation did not match. Nothing was changed.")
        }
        let result = try reporter.activity("Restoring non-conflicting items") {
            try service.restore(id: id)
        }
        reporter.success("Restore operation completed")
        print("Restored \(result.moved.count) item(s); skipped \(result.skipped.count).")
    }

    private func doctor(_ args: [String]) throws {
        let parsed = try parse(
            args,
            allowedFlags: ["--json", "--quiet", "--verbose", "--open-settings"]
        )
        guard parsed.positionals.isEmpty else {
            throw AppSleuthError.invalidArguments("Usage: appsleuth doctor [--json] [--open-settings]")
        }
        guard !(parsed.flags.contains("--json") && parsed.flags.contains("--open-settings")) else {
            throw AppSleuthError.invalidArguments("--json cannot be combined with --open-settings.")
        }
        let reporter = try makeReporter(flags: parsed.flags)
        let report = reporter.activity("Checking macOS access and scan capabilities") {
            PermissionInspector().inspect()
        }
        if parsed.flags.contains("--json") {
            try printJSON(report)
        } else {
            printDiagnosticReport(report)
        }
        if parsed.flags.contains("--open-settings") {
            try openPrivacySettings()
        }
    }

    private func optimize(_ args: [String]) throws {
        let parsed = try parse(
            args,
            allowedFlags: ["--dry-run", "--execute", "--json", "--quiet", "--verbose"]
        )
        guard !(parsed.flags.contains("--dry-run") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments("Choose either --dry-run or --execute, not both.")
        }
        guard !(parsed.flags.contains("--json") && parsed.flags.contains("--execute")) else {
            throw AppSleuthError.invalidArguments(
                "--json cannot be combined with --execute because maintenance execution is interactive."
            )
        }

        let reporter = try makeReporter(flags: parsed.flags)
        let report = reporter.activity("Running read-only Mac health checks") {
            OptimizationInspector().inspect { message in reporter.detail(message) }
        }
        reporter.success("Health check complete: \(report.checks.count) check(s)")

        let requestedIDs = Set(parsed.positionals)
        let availableIDs = Set(report.actions.map(\.id))
        let missingIDs = requestedIDs.subtracting(availableIDs).sorted()
        guard missingIDs.isEmpty else {
            throw AppSleuthError.invalidArguments(
                "No current optimization action matched: \(missingIDs.joined(separator: ", ")). Run 'appsl optimize' again."
            )
        }
        let selected = report.actions.filter { requestedIDs.contains($0.id) }

        if parsed.flags.contains("--json") {
            try printJSON(report)
        } else {
            printOptimizationReport(report, selectedIDs: requestedIDs)
        }

        guard parsed.flags.contains("--execute") else {
            if !parsed.flags.contains("--json") {
                if selected.isEmpty {
                    print("\nDiagnosis only. Nothing was changed.")
                    print("Preview one exact action with: appsl optimize <action-id> --dry-run")
                } else {
                    print("\nDry run only. \(selected.count) exact action(s) would run; nothing was changed.")
                    print("Add --execute only after reviewing each action's risk and target.")
                }
            }
            return
        }

        guard !selected.isEmpty else {
            throw AppSleuthError.unsafeOperation(
                "Execution requires at least one exact action ID. AppSleuth has no optimize-all mode."
            )
        }
        let phrase = "OPTIMIZE \(selected.count) ACTIONS"
        print("\nOnly the \(selected.count) exact action(s) marked RUN will be attempted.")
        print("These maintenance actions do not have an AppSleuth restore vault.")
        print("Type exactly: \(phrase)")
        print("> ", terminator: "")
        guard readLine() == phrase else {
            throw AppSleuthError.unsafeOperation("Confirmation did not match. Nothing was changed.")
        }

        let outcomes = try reporter.activity("Applying reviewed maintenance actions") {
            try OptimizationExecutor().execute(selected)
        }
        print("\nOptimization outcomes")
        for outcome in outcomes {
            let marker = outcome.status == .applied ? "APPLIED" : "FAILED"
            let color = outcome.status == .applied ? "1;32" : "1;31"
            print("  \(styled("[\(marker)]", code: color)) \(outcome.title)")
            print("    ↳ \(outcome.detail)")
        }
        let applied = outcomes.filter { $0.status == .applied }.count
        let failed = outcomes.count - applied
        print("Applied \(applied); failed \(failed). No unselected action was run.")
    }

    private func makeReport(query: String, reporter: ProgressReporter) throws -> ScanReport {
        let app = try reporter.activity("Locating \(query)") {
            try ApplicationLocator().locate(query)
        }
        reporter.detail("Found \(app.path)")
        let report = reporter.activity("Scanning approved macOS locations") {
            Scanner().scan(app) { message in reporter.detail(message) }
        }
        reporter.success(
            "Scan complete: \(report.findings.count) item(s) found across \(report.coverage.inspectedLocationCount) inspected location(s)"
        )
        return report
    }

    private func makeReporter(flags: Set<String>) throws -> ProgressReporter {
        guard !(flags.contains("--quiet") && flags.contains("--verbose")) else {
            throw AppSleuthError.invalidArguments("Choose either --quiet or --verbose, not both.")
        }
        return ProgressReporter(
            quiet: flags.contains("--quiet") || flags.contains("--json"),
            verbose: flags.contains("--verbose")
        )
    }

    private func parse(_ args: [String], allowedFlags: Set<String>) throws -> (positionals: [String], flags: Set<String>) {
        var positionals: [String] = []
        var flags: Set<String> = []
        for argument in args {
            if argument.hasPrefix("--") {
                guard allowedFlags.contains(argument) else {
                    throw AppSleuthError.invalidArguments("Unknown option '\(argument)'.")
                }
                flags.insert(argument)
            } else {
                positionals.append(argument)
            }
        }
        return (positionals, flags)
    }

    private func printOptimizationReport(
        _ report: OptimizationReport,
        selectedIDs: Set<String>
    ) {
        print("Optimize & Check")
        print("Read-only diagnosis by default · selective maintenance only\n")

        let usedMemory = compactSize(report.system.usedMemoryBytes)
        let totalMemory = compactSize(report.system.totalMemoryBytes)
        let usedDisk = compactSize(report.system.usedDiskBytes)
        let totalDisk = compactSize(report.system.totalDiskBytes)
        print(
            "System  \(usedMemory)/\(totalMemory) memory · \(usedDisk)/\(totalDisk) disk · uptime \(compactUptime(report.system.uptimeSeconds))"
        )

        print("\nHealth checks")
        for check in report.checks {
            let (symbol, color): (String, String)
            switch check.status {
            case .healthy: (symbol, color) = ("✓", "1;32")
            case .attention: (symbol, color) = ("!", "1;33")
            case .information: (symbol, color) = ("•", "1;36")
            case .unavailable: (symbol, color) = ("?", "1;31")
            }
            print("  \(styled(symbol, code: color)) \(check.title) — \(check.summary)")
            for detail in check.details { print("      \(detail)") }
        }

        print("\nReviewed maintenance actions")
        if report.actions.isEmpty {
            print("  No supported action is available on this Mac.")
        }
        for action in report.actions {
            let selected = selectedIDs.contains(action.id)
            let marker = selected ? "RUN" : "AVAILABLE"
            let color = selected ? "1;33" : "1;36"
            print("  \(styled("[\(marker)]", code: color)) \(action.title) · \(action.risk.rawValue.uppercased())")
            print("      ID: \(action.id)")
            if let target = action.target { print("      Target: \(target)") }
            print("      \(action.summary)")
            print("      Why/risk: \(action.reason)")
        }
        print("\nSafety notes:")
        report.warnings.forEach { print("  - \($0)") }
        print("  - No action is recommended merely because it exists; use one only for the symptom it names.")
    }

    private func compactUptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }

    private func printScan(_ report: ScanReport, verbose: Bool) {
        print("AppSleuth scan (read-only)")
        print("Application: \(report.application.name)")
        print("Bundle ID:   \(report.application.bundleIdentifier)")
        if let version = report.application.version { print("Version:     \(version)") }
        print("Path:        \(report.application.path)\n")
        for finding in report.findings {
            print("[\(finding.risk.label)] [\(finding.scope.rawValue)] \(finding.kind.rawValue) \(finding.confidence)%")
            print("  \(finding.path)")
            print("  ↳ \(finding.reasons.joined(separator: "; "))")
        }
        printScanCoverage(report.coverage, verbose: verbose)
        if !report.warnings.isEmpty {
            print("\nWarnings:")
            report.warnings.forEach { print("  - \($0)") }
        }
        print("\nFound \(report.findings.count) item(s). Nothing was changed.")
    }

    private func printScanCoverage(_ coverage: ScanCoverage, verbose: Bool) {
        print("\nScan coverage")
        print(
            "  Checked \(coverage.inspectedLocationCount) · Not present \(coverage.notPresentLocationCount) · Unavailable \(coverage.unavailableLocationCount) · Matched \(coverage.matchedLocationCount)"
        )
        let categories = coverage.supportedKinds.map {
            $0.rawValue.replacingOccurrences(of: "-", with: " ")
        }.joined(separator: ", ")
        if !categories.isEmpty {
            print("  Categories: \(categories)")
        }

        let unavailable = coverage.locations.filter { $0.status == .unavailable }
        if !unavailable.isEmpty {
            print("  Unavailable locations:")
            for location in unavailable {
                print("    ! \(location.path)")
                if let note = location.note { print("      \(note)") }
            }
        }

        if verbose {
            print("  Location ledger:")
            for location in coverage.locations {
                let marker: String
                switch location.status {
                case .inspected: marker = "CHECKED"
                case .notPresent: marker = "ABSENT"
                case .unavailable: marker = "UNAVAILABLE"
                }
                print("    [\(marker)] [\(location.scope.rawValue)] \(location.kind.rawValue) · \(location.path)")
                if location.matchedItemCount > 0 {
                    print("      ↳ \(location.matchedItemCount) matching item(s)")
                }
            }
        }

        if !coverage.unsupportedState.isEmpty {
            print("  Outside filename-based coverage:")
            for item in coverage.unsupportedState { print("    - \(item)") }
        }
        print("  Coverage is explicit and bounded; it is not a guarantee that every vendor-created trace is visible.")
    }

    private func printInstalledApplications(_ applications: [InstalledApplication], verbose: Bool) {
        print("Installed Applications")
        print("\(applications.count) application bundles found · read-only\n")

        let scopes: [(ApplicationInstallScope, String, String)] = [
            (.user, "Your Applications", "~/Applications"),
            (.shared, "Shared Applications", "/Applications"),
            (.system, "Apple System Applications", "/System")
        ]
        var row = 1
        for (scope, title, location) in scopes {
            let values = applications.filter { $0.scope == scope }
            guard !values.isEmpty else { continue }
            print("\(title) — \(values.count)  [\(location)]")
            print("  #    \(paddedColumn("Application", width: 34)) \(paddedColumn("Version", width: 14)) Size")
            print("  ───  \(String(repeating: "─", count: 34))  \(String(repeating: "─", count: 14))  ──────────")
            for item in values {
                let app = item.application
                let number = String(row) + "."
                print("  \(paddedColumn(number, width: 4)) \(paddedColumn(app.name, width: 34)) \(paddedColumn(compactVersion(app.version), width: 14)) \(compactSize(item.bundleByteSize))")
                if verbose {
                    print("       ID:   \(app.bundleIdentifier)")
                    print("       Path: \(app.path)")
                }
                row += 1
            }
            print("")
        }
        print("Nothing was changed.")
        print("Tip: run 'appsl list --verbose' for bundle IDs and full paths.")
        print("     run 'appsl scan \"Application Name\"' to inspect one app.")
        print("     run 'appsl purge \"Application Name\"' to preview permanent cleanup.")
    }

    private func printLeftoverReport(_ report: LeftoverReport, verbose: Bool) {
        let grouped = Dictionary(grouping: report.candidates, by: leftoverGroupKey)
            .map { key, candidates in
                (key: key, title: leftoverGroupTitle(key: key, candidates: candidates), candidates: candidates)
            }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        print(styled("SUSPECTED LEFTOVERS", code: "1;36"))
        print("\(report.candidates.count) findings grouped under \(grouped.count) likely owner(s)")
        print("Ownership was checked against \(report.installedApplicationCount) installed applications · audit only\n")
        if report.candidates.isEmpty {
            print("No conservative leftover candidates were found in the approved locations.")
        }
        for (groupIndex, group) in grouped.enumerated() {
            let reviewable = group.candidates.filter { $0.finding.removable && !$0.active }.count
            let kinds = Dictionary(grouping: group.candidates, by: \.finding.kind)
                .map { kind, values in "\(values.count) \(kind.rawValue)" }
                .sorted()
                .joined(separator: ", ")
            print(styled(
                "\(groupIndex + 1). LIKELY OWNER: \(group.title)",
                code: "1;38;5;45"
            ))
            print("   \(group.candidates.count) item(s) · \(reviewable) reviewable · \(group.candidates.count - reviewable) report-only")
            print("   Types: \(kinds)")

            let sortedCandidates = group.candidates.sorted { lhs, rhs in
                if lhs.active != rhs.active { return !lhs.active && rhs.active }
                if lhs.finding.removable != rhs.finding.removable {
                    return lhs.finding.removable && !rhs.finding.removable
                }
                if lhs.finding.kind != rhs.finding.kind {
                    return lhs.finding.kind.rawValue < rhs.finding.kind.rawValue
                }
                return lhs.finding.path.localizedStandardCompare(rhs.finding.path) == .orderedAscending
            }
            for candidate in sortedCandidates {
                let finding = candidate.finding
                let state = candidate.active
                    ? "ACTIVE · REPORT ONLY"
                    : (finding.removable ? "REVIEWABLE" : "REPORT ONLY")
                let stateCode = candidate.active ? "1;31" : (finding.removable ? "1;32" : "1;33")
                print("\n   \(styled("[\(state)]", code: stateCode)) \(styled("[\(finding.risk.label)]", code: riskCode(finding.risk))) \(finding.kind.rawValue) · \(finding.scope.rawValue) · \(finding.confidence)%")
                if let identifier = candidate.suspectedIdentifier {
                    print("      Identifier: \(identifier)")
                }
                print("      Path: \(finding.path)")
                print("      ID:   \(finding.id)")
                if verbose {
                    for reason in finding.reasons { print("      Why:  \(reason)") }
                } else if let reason = finding.reasons.last {
                    print("      Why:  \(reason)")
                }
            }
            print("")
        }
        if !report.warnings.isEmpty {
            print("Coverage notes:")
            report.warnings.forEach { print("  - \($0)") }
            print("")
        }
        print(styled("Nothing was changed.", code: "1"), "A likely owner is a heuristic label, not proof of ownership.")
        print("Preview whether one or more exact IDs can be moved safely:")
        print("  appsl leftovers clean <finding-id> [more-finding-ids]")
        if !verbose { print("Use --verbose to show every evidence reason.") }
    }

    private func printLeftoverPlan(_ plan: LeftoverCleanupPlan, requestedIDs: Set<String>) {
        print(styled("LEFTOVER CLEANUP PLAN", code: "1;36") + "\n")
        for item in plan.items where requestedIDs.contains(item.candidate.finding.id) {
            let finding = item.candidate.finding
            let marker = item.selected ? "MOVE" : "KEEP"
            let markerCode = item.selected ? "1;32" : "1;33"
            print("\(styled("[\(marker)]", code: markerCode)) \(styled("[\(finding.risk.label)]", code: riskCode(finding.risk))) \(finding.path)")
            print("  ID: \(finding.id)")
            print("  ↳ \(item.decision)\n")
        }
        print("Selected \(plan.selected.count) of \(requestedIDs.count) requested item(s).")
    }

    private func printServiceReport(_ report: ApplicationServiceReport, verbose: Bool) {
        print(styled("ACTIVE THIRD-PARTY USER SERVICES", code: "1;36"))
        let countText = report.inspectionAvailable ? String(report.services.count) : "Unavailable"
        print("\(countText) running launchd job(s) matched to installed non-system applications · read-only\n")

        let groups = Dictionary(grouping: report.services, by: \.likelyOwner).sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
        if groups.isEmpty {
            print("No matching active user services were visible in this terminal session.\n")
        }
        for (index, group) in groups.enumerated() {
            print(styled("\(index + 1). LIKELY OWNER: \(group.key)", code: "1;38;5;45"))
            for service in group.value {
                print("   \(styled("[RUNNING]", code: "1;32")) PID \(service.processIdentifier) · \(service.label)")
                if verbose, service.matchingApplications.count > 1 {
                    print("      Matching installed apps: \(service.matchingApplications.joined(separator: ", "))")
                }
            }
            print("")
        }
        if !report.warnings.isEmpty {
            print("Coverage notes:")
            report.warnings.forEach { print("  - \($0)") }
        }
    }

    private func leftoverGroupKey(_ candidate: LeftoverCandidate) -> String {
        candidate.vendorNamespace
            ?? candidate.suspectedIdentifier?.lowercased()
            ?? candidate.suspectedName?.lowercased()
            ?? "unidentified-runtime"
    }

    private func leftoverGroupTitle(key: String, candidates: [LeftoverCandidate]) -> String {
        let names = Array(Set(candidates.compactMap(\.suspectedName))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        if names.count == 1 { return names[0] }
        if names.count > 1 {
            let vendor = humanizedVendorNamespace(candidates.first?.vendorNamespace ?? key)
            return "\(vendor) family"
        }
        return key == "unidentified-runtime" ? "Unidentified missing application" : humanizedVendorNamespace(key)
    }

    private func humanizedVendorNamespace(_ namespace: String) -> String {
        let value = namespace.split(separator: ".").last.map(String.init) ?? namespace
        let separated = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = separated.first else { return separated }
        return String(first).uppercased() + separated.dropFirst()
    }

    private func styled(_ value: String, code: String) -> String {
        guard isatty(STDOUT_FILENO) == 1 else { return value }
        return "\u{001B}[\(code)m\(value)\u{001B}[0m"
    }

    private func riskCode(_ risk: RiskLevel) -> String {
        switch risk {
        case .safe: return "1;32"
        case .review: return "1;33"
        case .high: return "1;31"
        case .protected: return "1;35"
        }
    }

    private func paddedColumn(_ value: String, width: Int) -> String {
        let shortened: String
        if value.count > width {
            shortened = String(value.prefix(max(1, width - 1))) + "…"
        } else {
            shortened = value
        }
        return shortened + String(repeating: " ", count: max(0, width - shortened.count))
    }

    private func compactVersion(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.count > 14 ? String(value.prefix(13)) + "…" : value
    }

    private func compactSize(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    private func printPlan(_ plan: UninstallPlan) {
        print("Uninstall plan for \(plan.application.name) [\(plan.application.bundleIdentifier)]\n")
        for item in plan.items {
            let marker = item.selected ? "MOVE" : "KEEP"
            print("[\(marker)] [\(item.finding.risk.label)] \(item.finding.path)")
            print("  ↳ \(item.decision)")
        }
        print("\nSelected \(plan.selected.count) of \(plan.items.count) discovered item(s).")
    }

    private func printPurgePlan(_ plan: UninstallPlan, includesUserData: Bool) {
        print(styled("PERMANENT PURGE PREVIEW", code: "1;31"))
        print("Application: \(plan.application.name) [\(plan.application.bundleIdentifier)]")
        print("Mode: \(includesUserData ? "app bundle + disposable data + high-confidence app-specific user data" : "app bundle + high-confidence disposable data")\n")
        for item in plan.items {
            let covered = !item.selected && item.finding.path.hasPrefix(plan.application.path + "/")
            let marker = item.selected ? "DELETE" : (covered ? "COVERED" : "KEEP")
            let code = item.selected ? "1;31" : (covered ? "1;36" : "1;33")
            print("\(styled("[\(marker)]", code: code)) [\(item.finding.risk.label)] \(item.finding.kind.rawValue)")
            print("  \(item.finding.path)")
            print("  ↳ \(item.decision)")
        }
        print("\nPermanent filesystem roots: \(plan.selected.count) of \(plan.items.count) discovered item(s).")
        if !includesUserData {
            print("App-specific preferences, containers, saved state, and support data are kept.")
            print("Use --include-user-data to include high-confidence, non-shared user data.")
        }
        print("Shared containers, startup jobs, system files, receipts, extensions, and uncertain matches are always kept.")
    }

    private func printDiagnosticReport(_ report: DiagnosticReport) {
        print("AppSleuth doctor (read-only)\n")
        for check in report.checks {
            print("[\(check.status.label)] \(check.name)")
            print("  \(check.message)")
            if let resolution = check.resolution { print("  Fix: \(resolution)") }
        }
        print("\nFull Disk Access is not required for Calculator or other basic scans.")
        print("It can improve discovery for protected third-party application data.")
        print("Run 'appsleuth doctor --open-settings' to open the relevant System Settings pane.")
    }

    private func openPrivacySettings() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppSleuthError.invalidArguments(
                "Could not open System Settings. Open Privacy & Security > Full Disk Access manually."
            )
        }
        print("Opened System Settings. Enable the terminal app you use, then quit and reopen it.")
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else { return }
        print(text)
    }

    private func printUsage() {
        print("""
        AppSleuth \(version) — evidence-first macOS application cleanup

        Usage:
          appsleuth                                  Open the interactive terminal menu
          appsleuth list [--no-system] [--json]
          appsleuth services [--json]
          appsleuth leftovers [scan] [--json]
          appsleuth leftovers clean <finding-id>... [--dry-run|--execute]
                                      [--include-system] [--json]
          appsleuth scan <app-name-or-path> [--json]
          appsleuth explain <app-name-or-path> [finding-id-or-path] [--json]
          appsleuth uninstall <app-name-or-path> [--dry-run|--execute]
                             [--include-review] [--include-system] [--json]
          appsleuth purge <app-name-or-path> [--dry-run|--execute]
                         [--include-user-data] [--json]
          appsleuth restore <backup-id> [--dry-run|--execute] [--json]
          appsleuth doctor [--json] [--open-settings]
          appsleuth optimize [action-id...] [--dry-run|--execute] [--json]

        Output controls:
          --quiet       Hide progress while keeping command results
          --verbose     Show every location as it is inspected
          --json        Emit machine-readable output without progress

        Safety defaults:
          • scan and explain are always read-only
          • uninstall, leftover cleanup, purge, and restore are dry-run unless --execute is present
          • leftover cleanup requires exact finding IDs; there is no clean-all option
          • execution requires typing an app-specific confirmation phrase
          • uninstall and leftover cleanup move files to a restorable vault
          • purge is the explicit exception: it deletes only its eligible plan with no rollback
          • optimize diagnoses only by default; execution requires exact action IDs and confirmation
          • optimize has no run-all mode and does not perform undocumented reset/repair routines
        """)
    }

    private func interactiveHome() throws {
        guard TerminalUI.isAvailable else {
            printUsage()
            return
        }
        let terminal = TerminalUI()
        terminal.enter()
        defer { terminal.leave() }
        let actions = TerminalMenuAction.allCases
        var selectedIndex = 0
        var installedApplications: [InstalledApplication] = []
        var applicationNames: [String] = []
        var externalApplicationCount = 0
        var diskReport: DiskSpaceReport?
        var applicationSpaceReport: ApplicationBundleSpaceReport?
        var serviceReport: ApplicationServiceReport?

        func dashboardOverview() -> SystemOverview {
            var warnings = [diskReport?.warning, applicationSpaceReport?.warning]
                .compactMap { $0 }
            warnings.append(contentsOf: serviceReport?.warnings ?? [])
            return SystemOverview(
                totalDiskBytes: diskReport?.totalBytes,
                usedDiskBytes: diskReport?.usedBytes,
                availableDiskBytes: diskReport?.availableBytes,
                installedApplicationBytes: applicationSpaceReport?.byteSize,
                indexedApplicationCount: applicationSpaceReport?.indexedApplicationCount ?? 0,
                externalApplicationCount: applicationSpaceReport?.externalApplicationCount
                    ?? externalApplicationCount,
                activeUserServices: serviceReport?.services ?? [],
                activeServiceInspectionAvailable: serviceReport?.inspectionAvailable ?? false,
                warnings: warnings
            )
        }

        let allLoading: Set<HomeOverviewSection> = [.disk, .applications, .jobs]
        terminal.renderHome(
            version: version,
            selectedIndex: selectedIndex,
            overview: dashboardOverview(),
            loadingSections: allLoading,
            applicationNames: applicationNames
        )

        let discoveredApplications = ApplicationLocator().installedApplications()
        let externalApplications = discoveredApplications.filter(isThirdPartyApplication)
        externalApplicationCount = externalApplications.count
        applicationNames = Array(Set(externalApplications.map(\.application.name))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        terminal.renderHome(
            version: version,
            selectedIndex: selectedIndex,
            overview: dashboardOverview(),
            loadingSections: allLoading,
            applicationNames: applicationNames
        )

        let overviewInspector = SystemOverviewInspector()
        diskReport = overviewInspector.inspectDiskSpace()
        terminal.renderHome(
            version: version,
            selectedIndex: selectedIndex,
            overview: dashboardOverview(),
            loadingSections: [.applications, .jobs],
            applicationNames: applicationNames
        )

        installedApplications = ApplicationSizeInspector().enrich(discoveredApplications)
        applicationSpaceReport = overviewInspector.summarizeApplicationSpace(
            installedApplications: installedApplications
        )
        terminal.renderHome(
            version: version,
            selectedIndex: selectedIndex,
            overview: dashboardOverview(),
            loadingSections: [.jobs],
            applicationNames: applicationNames
        )

        serviceReport = overviewInspector.inspectActiveUserServices(
            installedApplications: installedApplications
        )
        let overview = dashboardOverview()

        while true {
            terminal.renderHome(
                version: version,
                selectedIndex: selectedIndex,
                overview: overview,
                applicationNames: applicationNames
            )
            let action: TerminalMenuAction
            switch terminal.readInput() {
            case .up:
                selectedIndex = (selectedIndex - 1 + actions.count) % actions.count
                continue
            case .down:
                selectedIndex = (selectedIndex + 1) % actions.count
                continue
            case .enter:
                action = actions[selectedIndex]
            case let .character(character):
                let shortcut = Character(character.lowercased())
                guard let selected = actions.first(where: { $0.shortcut == shortcut }) else { continue }
                action = selected
                selectedIndex = actions.firstIndex(of: selected) ?? selectedIndex
            case .escape:
                continue
            case .endOfInput:
                return
            }

            switch action {
            case .list:
                terminal.browseApplications(installedApplications)
            case .leftovers:
                runInteractive(title: "Suspected leftovers", terminal: terminal) {
                    try leftovers([])
                }
            case .services:
                runInteractive(title: "Active third-party user services", terminal: terminal) {
                    printServiceReport(
                        ApplicationServiceReport(
                            services: overview.activeUserServices,
                            inspectionAvailable: overview.activeServiceInspectionAvailable,
                            warnings: overview.warnings.filter { $0.localizedCaseInsensitiveContains("service") }
                        ),
                        verbose: false
                    )
                }
            case .scan:
                guard let query = terminal.prompt("Application name or absolute .app path:"), !query.isEmpty else { continue }
                runInteractive(title: "Read-only scan", terminal: terminal) {
                    try scan([query])
                }
            case .explain:
                guard let query = terminal.prompt("Application to explain:"), !query.isEmpty else { continue }
                runInteractive(title: "Matching evidence", terminal: terminal) {
                    try explain([query])
                }
            case .uninstall:
                guard let query = terminal.prompt("Application to preview uninstalling:"), !query.isEmpty else { continue }
                let review = terminal.prompt("Include settings and other REVIEW/HIGH findings? [y/N]")
                var options = [query, "--dry-run"]
                if review?.lowercased() == "y" { options.append("--include-review") }
                runInteractive(title: "Uninstall preview", terminal: terminal) {
                    try uninstall(options)
                }
            case .purge:
                let choices = installedApplications.filter(isThirdPartyApplication)
                guard let selected = terminal.selectApplication(
                    choices,
                    title: "PERMANENT APPLICATION PURGE"
                ) else { continue }
                let includeData = terminal.prompt(
                    "Also permanently delete high-confidence app-specific settings and user data? [y/N]"
                )
                let execute = terminal.prompt(
                    "Permanently delete now after reviewing the full plan? [y/N]"
                )
                var options = [
                    selected.application.path,
                    execute?.lowercased() == "y" ? "--execute" : "--dry-run"
                ]
                if includeData?.lowercased() == "y" {
                    options.append("--include-user-data")
                }
                runInteractive(title: "Permanent purge", terminal: terminal) {
                    try purge(options) { phrase in
                        terminal.promptInline("Enter the exact phrase shown above:")
                            == phrase
                    }
                }
            case .restore:
                guard let identifier = terminal.prompt("Backup ID to preview:"), !identifier.isEmpty else { continue }
                runInteractive(title: "Restore preview", terminal: terminal) {
                    try restore([identifier, "--dry-run"])
                }
            case .doctor:
                runInteractive(title: "Permission diagnostics", terminal: terminal) {
                    try doctor([])
                }
            case .optimize:
                runInteractive(title: "Optimize & Check", terminal: terminal) {
                    try optimize([])
                }
            case .help:
                runInteractive(title: "Command-line help", terminal: terminal) {
                    printUsage()
                }
            case .quit:
                return
            }
        }
    }

    private func runInteractive(title: String, terminal: TerminalUI, operation: () throws -> Void) {
        terminal.prepareOutput(title)
        do {
            try operation()
        } catch {
            terminal.showError(error)
        }
        terminal.waitForKey()
    }

    private func isThirdPartyApplication(_ installed: InstalledApplication) -> Bool {
        guard installed.scope != .system else { return false }
        let identifier = installed.application.bundleIdentifier.lowercased()
        return identifier != "com.apple"
            && !identifier.hasPrefix("com.apple.")
            && identifier != "is.workflow"
            && !identifier.hasPrefix("is.workflow.")
    }
}

do {
    try CLI(arguments: Array(CommandLine.arguments.dropFirst())).run()
} catch {
    let message = "appsleuth: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
