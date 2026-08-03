import Darwin
import Foundation

public struct PurgeOptions: Sendable {
    public let includeUserData: Bool

    public init(includeUserData: Bool = false) {
        self.includeUserData = includeUserData
    }
}

public struct PermanentPurgePlanner {
    private let userDataKinds: Set<FindingKind> = [
        .applicationSupport,
        .preference,
        .savedState,
        .webData,
        .container,
        .applicationScript
    ]

    public init() {}

    public func makePlan(
        from report: ScanReport,
        options: PurgeOptions = PurgeOptions()
    ) -> UninstallPlan {
        let items = report.findings.map { finding -> PlannedFinding in
            if finding.kind == .applicationBundle {
                return PlannedFinding(
                    finding: finding,
                    selected: finding.removable,
                    decision: finding.removable
                        ? "selected application bundle"
                        : "protected application bundle"
                )
            }
            if finding.path.hasPrefix(report.application.path + "/") {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "embedded item is deleted with the selected application bundle"
                )
            }
            guard finding.removable else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "discovery-only, shared, or protected category"
                )
            }
            guard finding.scope == .user else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "permanent purge does not delete system-level artifacts"
                )
            }
            guard finding.confidence >= 92 else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "ownership confidence below permanent-deletion threshold"
                )
            }
            guard finding.risk <= .review else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "shared, startup, extension, or high-risk category"
                )
            }
            if finding.risk == .safe {
                return PlannedFinding(
                    finding: finding,
                    selected: true,
                    decision: "high-confidence disposable app data"
                )
            }
            guard userDataKinds.contains(finding.kind) else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "category is not eligible for permanent deletion"
                )
            }
            guard options.includeUserData else {
                return PlannedFinding(
                    finding: finding,
                    selected: false,
                    decision: "app-specific settings or user data require --include-user-data"
                )
            }
            return PlannedFinding(
                finding: finding,
                selected: true,
                decision: "high-confidence app-specific user data explicitly included"
            )
        }
        return UninstallPlan(application: report.application, items: items)
    }
}

public struct PurgePreflightIssue: Codable, Equatable, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct PurgePreflight: Codable, Equatable, Sendable {
    public let selectedCount: Int
    public let administratorRequiredPaths: [String]
    public let blockers: [PurgePreflightIssue]

    public init(
        selectedCount: Int,
        administratorRequiredPaths: [String] = [],
        blockers: [PurgePreflightIssue] = []
    ) {
        self.selectedCount = selectedCount
        self.administratorRequiredPaths = administratorRequiredPaths
        self.blockers = blockers
    }
}

public protocol PrivilegedApplicationRemoving {
    func authorize() throws
    func removeApplication(atPath path: String) throws
}

public struct SudoApplicationRemover: PrivilegedApplicationRemoving {
    public init() {}

    public func authorize() throws {
        try withCanonicalTerminalInput {
            try runSudo(
                arguments: [
                    "-p", "AppSleuth needs administrator permission to remove the selected application: ",
                    "-v"
                ],
                failureMessage: "Administrator authorization failed. Nothing was deleted."
            )
        }
    }

    public func removeApplication(atPath path: String) throws {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized == path,
              path.hasPrefix("/Applications/"),
              path.hasSuffix(".app")
        else {
            throw AppSleuthError.unsafeOperation(
                "Privileged removal is limited to validated application bundles in /Applications."
            )
        }
        let relative = String(path.dropFirst("/Applications/".count))
        guard (1...2).contains(relative.split(separator: "/").count) else {
            throw AppSleuthError.unsafeOperation(
                "Privileged removal rejected an application outside the approved layout."
            )
        }
        try runSudo(
            arguments: ["-n", "/bin/rm", "-rf", "--", path],
            failureMessage: "Administrator-authorized application removal failed: \(path)"
        )
    }

    private func runSudo(arguments: [String], failureMessage: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw AppSleuthError.unsafeOperation("\(failureMessage) \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            throw AppSleuthError.unsafeOperation(failureMessage)
        }
    }

    private func withCanonicalTerminalInput<T>(_ operation: () throws -> T) throws -> T {
        var original = termios()
        guard isatty(STDIN_FILENO) == 1,
              tcgetattr(STDIN_FILENO, &original) == 0
        else {
            return try operation()
        }
        var canonical = original
        canonical.c_lflag |= tcflag_t(ICANON | ISIG)
        canonical.c_iflag |= tcflag_t(ICRNL | IXON)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &canonical) == 0 else {
            return try operation()
        }
        defer {
            var restored = original
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored)
        }
        return try operation()
    }
}

public final class PermanentPurgeService {
    private let fileManager: FileManager
    private let safetyPolicy: SafetyPolicy
    private let privilegedApplicationRemover: (any PrivilegedApplicationRemoving)?
    private let privilegedApplicationRoots: [URL]
    private let permanentlyAllowedKinds: Set<FindingKind> = [
        .applicationSupport,
        .preference,
        .cache,
        .log,
        .savedState,
        .webData,
        .container,
        .applicationScript
    ]

    public init(
        fileManager: FileManager = .default,
        safetyPolicy: SafetyPolicy = SafetyPolicy(),
        privilegedApplicationRemover: (any PrivilegedApplicationRemoving)? = SudoApplicationRemover(),
        privilegedApplicationRoots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
    ) {
        self.fileManager = fileManager
        self.safetyPolicy = safetyPolicy
        self.privilegedApplicationRemover = privilegedApplicationRemover
        self.privilegedApplicationRoots = privilegedApplicationRoots
    }

    public func preflight(_ plan: UninstallPlan) throws -> PurgePreflight {
        let running = plan.items.filter { $0.finding.kind == .process }
        guard running.isEmpty else {
            throw AppSleuthError.unsafeOperation(
                "The application still has \(running.count) running process(es). Quit it and scan again."
            )
        }
        guard !plan.selected.isEmpty else {
            throw AppSleuthError.unsafeOperation("The permanent-purge plan contains no eligible items.")
        }

        var administratorRequiredPaths: [String] = []
        var blockers: [PurgePreflightIssue] = []
        for finding in plan.selected {
            guard permanentlyEligible(finding, for: plan.application) else {
                throw AppSleuthError.unsafeOperation(
                    "The plan selected a category that permanent purge is forbidden to delete: \(finding.path)"
                )
            }
            try safetyPolicy.validate(finding, for: plan.application)
            if let reason = recursiveDeletionBlocker(atPath: finding.path) {
                if finding.kind == .applicationBundle,
                   isInsidePrivilegedApplicationRoot(finding.path) {
                    administratorRequiredPaths.append(finding.path)
                } else {
                    blockers.append(PurgePreflightIssue(path: finding.path, reason: reason))
                }
            }
        }

        return PurgePreflight(
            selectedCount: plan.selected.count,
            administratorRequiredPaths: administratorRequiredPaths.sorted(),
            blockers: blockers.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )
    }

    public func execute(_ plan: UninstallPlan) throws -> PurgeResult {
        let preflight = try preflight(plan)
        guard preflight.blockers.isEmpty else {
            let details = preflight.blockers
                .map { "\($0.path): \($0.reason)" }
                .joined(separator: "; ")
            throw AppSleuthError.unsafeOperation(
                "Permanent purge preflight failed before deleting anything. \(details)"
            )
        }
        if !preflight.administratorRequiredPaths.isEmpty {
            guard let privilegedApplicationRemover else {
                throw AppSleuthError.unsafeOperation(
                    "The selected application requires administrator authorization. Nothing was deleted."
                )
            }
            // Authenticate before the first mutation so a cancelled or failed
            // password prompt cannot leave a partially deleted plan.
            try privilegedApplicationRemover.authorize()
        }

        // Delete the application bundle last. If an earlier deletion fails, the
        // main application remains available, but already deleted data is not restored.
        let ordered = plan.selected.sorted { lhs, rhs in
            if lhs.kind == .applicationBundle { return false }
            if rhs.kind == .applicationBundle { return true }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        let administratorPaths = Set(preflight.administratorRequiredPaths)
        var deleted: [String] = []
        for finding in ordered {
            do {
                try safetyPolicy.validate(finding, for: plan.application)
                if administratorPaths.contains(finding.path) {
                    guard let privilegedApplicationRemover else {
                        throw AppSleuthError.unsafeOperation(
                            "Administrator authorization became unavailable."
                        )
                    }
                    try privilegedApplicationRemover.removeApplication(atPath: finding.path)
                } else {
                    try fileManager.removeItem(atPath: finding.path)
                }
                deleted.append(finding.path)
            } catch {
                throw AppSleuthError.unsafeOperation(
                    "Permanent purge stopped after deleting \(deleted.count) item(s). " +
                    "No rollback was attempted. Failed at \(finding.path): \(error)"
                )
            }
        }
        return PurgeResult(application: plan.application, deleted: deleted)
    }

    private func recursiveDeletionBlocker(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let parentPath = url.deletingLastPathComponent().path
        guard Darwin.access(parentPath, W_OK | X_OK) == 0 else {
            return "the containing directory is not writable"
        }
        if hasBlockingFlags(atPath: path) {
            return "the item has an immutable or append-only filesystem flag"
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "the item disappeared during permission preflight"
        }
        guard isDirectory.boolValue else { return nil }
        guard Darwin.access(path, W_OK | X_OK) == 0 else {
            return "the directory contents are not writable by the current user"
        }

        var traversalError: Error?
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            return "the directory contents could not be inspected"
        }
        for case let child as URL in enumerator {
            if hasBlockingFlags(atPath: child.path) {
                return "a descendant has an immutable or append-only filesystem flag"
            }
            guard let values = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ) else {
                return "a descendant's permissions could not be inspected"
            }
            if values.isDirectory == true,
               values.isSymbolicLink != true,
               Darwin.access(child.path, W_OK | X_OK) != 0 {
                return "a descendant directory is not writable by the current user"
            }
        }
        if let traversalError {
            return "the directory tree could not be fully inspected: \(traversalError.localizedDescription)"
        }
        return nil
    }

    private func hasBlockingFlags(atPath path: String) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return true
        }
        return (attributes[.immutable] as? NSNumber)?.boolValue == true
            || (attributes[.appendOnly] as? NSNumber)?.boolValue == true
    }

    private func isInsidePrivilegedApplicationRoot(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard standardized.path == path, path.hasSuffix(".app") else { return false }
        return privilegedApplicationRoots.contains { root in
            let rootPath = root.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { return false }
            let relative = String(path.dropFirst(rootPath.count + 1))
            return (1...2).contains(relative.split(separator: "/").count)
        }
    }

    private func permanentlyEligible(
        _ finding: Finding,
        for application: ApplicationIdentity
    ) -> Bool {
        if finding.kind == .applicationBundle {
            return finding.path == application.path && finding.removable
        }
        return finding.scope == .user
            && finding.removable
            && finding.confidence >= 92
            && finding.risk <= .review
            && permanentlyAllowedKinds.contains(finding.kind)
    }
}
