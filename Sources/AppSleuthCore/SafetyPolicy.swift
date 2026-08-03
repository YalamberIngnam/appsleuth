import Foundation

public struct SafetyPolicy {
    private let fileManager: FileManager
    private let locations: [SearchLocation]
    private let applicationRoots: [URL]

    public init(
        fileManager: FileManager = .default,
        locations: [SearchLocation]? = nil,
        applicationRoots: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.locations = locations ?? PathCatalog.defaultLocations(homeDirectory: homeDirectory)
        self.applicationRoots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public func validate(_ finding: Finding, for app: ApplicationIdentity) throws {
        guard finding.removable, finding.risk != .protected else {
            throw AppSleuthError.unsafeOperation("Protected or discovery-only item cannot be moved: \(finding.path)")
        }
        guard finding.kind != .process, finding.kind != .receipt else {
            throw AppSleuthError.unsafeOperation("Runtime processes and package receipts are never moved.")
        }
        _ = try validateDestination(path: finding.path, kind: finding.kind, scope: finding.scope)
        guard fileManager.fileExists(atPath: finding.path) else {
            throw AppSleuthError.unsafeOperation("Item disappeared after the scan: \(finding.path)")
        }

        if finding.kind == .applicationBundle {
            guard finding.path == app.path, finding.path.hasSuffix(".app") else {
                throw AppSleuthError.unsafeOperation("Application bundle no longer matches the selected app.")
            }
        }

        let attributes = try fileManager.attributesOfItem(atPath: finding.path)
        if let expected = finding.expectedFileID,
           let current = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
           current != expected {
            throw AppSleuthError.unsafeOperation("Item identity changed after the scan: \(finding.path)")
        }
        if let expected = finding.expectedDeviceID,
           let current = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
           current != expected {
            throw AppSleuthError.unsafeOperation("Item moved to a different filesystem after the scan: \(finding.path)")
        }
    }

    public func validateRestoreDestination(path: String, kind: FindingKind, scope: FindingScope) throws {
        _ = try validateDestination(path: path, kind: kind, scope: scope)
    }

    private func validateDestination(path: String, kind: FindingKind, scope: FindingScope) throws -> URL {
        guard path.hasPrefix("/") else {
            throw AppSleuthError.unsafeOperation("Only absolute paths can be moved: \(path)")
        }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard standardized.path == path else {
            throw AppSleuthError.unsafeOperation("Path changed after normalization: \(path)")
        }
        let forbidden = ["/System", "/usr", "/bin", "/sbin", "/private", "/var"]
        if forbidden.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            throw AppSleuthError.unsafeOperation("Path is inside a protected operating-system location: \(path)")
        }

        let root: URL
        if kind == .applicationBundle {
            guard path.hasSuffix(".app"), let matched = applicationRoots.first(where: {
                isApplication(standardized, inside: $0)
            }) else {
                throw AppSleuthError.unsafeOperation("Application is outside an approved installation root: \(path)")
            }
            root = matched
        } else {
            guard scope != .runtime, let matched = locations.first(where: {
                $0.kind == kind
                    && $0.scope == scope
                    && standardized.deletingLastPathComponent().path == $0.root.standardizedFileURL.path
            }) else {
                throw AppSleuthError.unsafeOperation("Path is not a direct child of an approved discovery root: \(path)")
            }
            root = matched.root
        }

        let standardizedRoot = root.standardizedFileURL
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath().path
        guard resolvedRoot == standardizedRoot.path else {
            throw AppSleuthError.unsafeOperation("Approved root unexpectedly resolves through a symlink: \(root.path)")
        }
        let resolvedParent = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        let parentIsApproved: Bool
        if kind == .applicationBundle, resolvedParent.hasPrefix(resolvedRoot + "/") {
            let relativeParent = String(resolvedParent.dropFirst(resolvedRoot.count + 1))
            parentIsApproved = relativeParent.split(separator: "/").count == 1
        } else {
            parentIsApproved = resolvedParent == resolvedRoot
        }
        guard parentIsApproved else {
            throw AppSleuthError.unsafeOperation("Parent directory resolves outside its approved root: \(path)")
        }
        return standardized
    }

    private func isApplication(_ application: URL, inside root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let appPath = application.standardizedFileURL.path
        guard appPath.hasPrefix(rootPath + "/") else { return false }
        let relative = String(appPath.dropFirst(rootPath.count + 1))
        return relative.split(separator: "/").count <= 2
    }
}

public struct PlanOptions: Sendable {
    public let includeReview: Bool
    public let includeSystem: Bool

    public init(includeReview: Bool = false, includeSystem: Bool = false) {
        self.includeReview = includeReview
        self.includeSystem = includeSystem
    }
}

public struct UninstallPlanner {
    public init() {}

    public func makePlan(from report: ScanReport, options: PlanOptions = PlanOptions()) -> UninstallPlan {
        let items = report.findings.map { finding -> PlannedFinding in
            if finding.kind == .applicationBundle {
                if finding.removable {
                    return PlannedFinding(finding: finding, selected: true, decision: "selected application bundle")
                }
                return PlannedFinding(finding: finding, selected: false, decision: "protected system application")
            }
            guard finding.removable else {
                return PlannedFinding(finding: finding, selected: false, decision: "discovery-only or protected")
            }
            guard finding.confidence >= 85 else {
                return PlannedFinding(finding: finding, selected: false, decision: "confidence below deletion threshold")
            }
            if finding.scope == .system && !options.includeSystem {
                return PlannedFinding(finding: finding, selected: false, decision: "system item requires --include-system")
            }
            if finding.risk >= .review && !options.includeReview {
                return PlannedFinding(finding: finding, selected: false, decision: "risk requires --include-review")
            }
            return PlannedFinding(finding: finding, selected: true, decision: "selected by safety policy")
        }
        return UninstallPlan(application: report.application, items: items)
    }
}
