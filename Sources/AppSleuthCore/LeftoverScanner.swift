import Foundation

private struct LeftoverDraft {
    let url: URL
    let location: SearchLocation
    let identifier: String
    let serviceLabel: String?
    let brokenExecutable: String?
}

public struct LeftoverScanner {
    private let fileManager: FileManager
    private let locations: [SearchLocation]
    private let inspectRuntime: Bool

    public init(
        fileManager: FileManager = .default,
        locations: [SearchLocation]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        inspectRuntime: Bool = true
    ) {
        self.fileManager = fileManager
        self.locations = locations ?? PathCatalog.defaultLocations(homeDirectory: homeDirectory)
        self.inspectRuntime = inspectRuntime
    }

    public func scan(
        installedApplications: [InstalledApplication],
        onProgress: ((String) -> Void)? = nil
    ) -> LeftoverReport {
        let installedIdentifiers = Set(installedApplications.map(\.application.bundleIdentifier))
        let installedNamespaces = Set(installedIdentifiers.compactMap(vendorNamespace))
        var drafts: [LeftoverDraft] = []
        var warnings: [String] = []

        for location in locations where location.kind != .receipt {
            guard fileManager.fileExists(atPath: location.root.path) else { continue }
            onProgress?("Inspecting \(location.root.path)")
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: location.root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                warnings.append("Could not inspect \(location.root.path): \(error.localizedDescription)")
                continue
            }

            for child in children {
                let service = serviceMetadata(at: child, kind: location.kind)
                guard let identifier = service.label ?? identifier(from: child, kind: location.kind) else {
                    continue
                }
                guard looksLikeBundleIdentifier(identifier) else { continue }
                guard !isAppleIdentifier(identifier) else { continue }
                guard !hasInstalledOwner(
                    identifier,
                    installedIdentifiers: installedIdentifiers,
                    installedNamespaces: installedNamespaces
                ) else { continue }
                drafts.append(LeftoverDraft(
                    url: child,
                    location: location,
                    identifier: identifier,
                    serviceLabel: (location.kind == .launchAgent || location.kind == .launchDaemon)
                        ? (service.label ?? identifier)
                        : nil,
                    brokenExecutable: service.brokenExecutable
                ))
            }
        }

        let evidenceCounts = Dictionary(grouping: drafts, by: {
            vendorNamespace($0.identifier) ?? $0.identifier.lowercased()
        }).mapValues { values in
            Set(values.map(\.location.kind)).count
        }
        let launchdInspection = inspectRuntime
            ? launchdLabels(warnings: &warnings)
            : (labels: Set<String>(), available: false)
        let significantDrafts = drafts.filter { draft in
            let evidenceKey = vendorNamespace(draft.identifier) ?? draft.identifier.lowercased()
            let evidenceCount = evidenceCounts[evidenceKey] ?? 1
            return draft.brokenExecutable != nil
                || draft.location.kind == .launchAgent
                || draft.location.kind == .launchDaemon
                || draft.location.kind == .privilegedHelper
                || evidenceCount >= 2
        }
        var candidates = significantDrafts.map { draft in
            let evidenceKey = vendorNamespace(draft.identifier) ?? draft.identifier.lowercased()
            return makeCandidate(
                from: draft,
                evidenceCount: evidenceCounts[evidenceKey] ?? 1,
                loadedLabels: launchdInspection.labels,
                serviceInspectionAvailable: launchdInspection.available
            )
        }

        if inspectRuntime {
            onProgress?("Checking processes whose application bundle is missing")
            let inspection = missingApplicationProcesses()
            candidates.append(contentsOf: inspection.candidates)
            if let warning = inspection.warning { warnings.append(warning) }
            warnings.append(
                "Loaded-service visibility is limited to the current user's launchd domain; system-domain and modern background registrations may require separate review."
            )
        }

        return LeftoverReport(
            installedApplicationCount: installedApplications.count,
            candidates: candidates.sorted { lhs, rhs in
                let left = lhs.finding
                let right = rhs.finding
                if lhs.active != rhs.active { return lhs.active && !rhs.active }
                if left.scope != right.scope { return left.scope.rawValue < right.scope.rawValue }
                if left.risk != right.risk { return left.risk > right.risk }
                return left.path.localizedStandardCompare(right.path) == .orderedAscending
            },
            warnings: warnings
        )
    }

    private func makeCandidate(
        from draft: LeftoverDraft,
        evidenceCount: Int,
        loadedLabels: Set<String>,
        serviceInspectionAvailable: Bool
    ) -> LeftoverCandidate {
        let active = draft.serviceLabel.map(loadedLabels.contains) ?? false
        let launchdItem = draft.location.kind == .launchAgent || draft.location.kind == .launchDaemon
        let serviceStateUnknown = launchdItem
            && (!serviceInspectionAvailable || draft.location.scope == .system)
        let metadata = fileMetadata(at: draft.url)
        let confidence: Int
        if draft.brokenExecutable != nil {
            confidence = 95
        } else if evidenceCount >= 2 {
            confidence = 90
        } else {
            confidence = 75
        }

        var reasons = [
            "reverse-DNS identifier: \(draft.identifier)",
            "no installed application uses the same identifier or vendor namespace"
        ]
        if evidenceCount >= 2 {
            reasons.append("the same identifier appears in \(evidenceCount) artifact categories")
        } else {
            reasons.append("single-location evidence; manual review is required")
        }
        if let executable = draft.brokenExecutable {
            reasons.append("launchd program path no longer exists: \(executable)")
        }
        if active {
            reasons.append("launchd reports this job loaded in the current user domain")
        }
        if serviceStateUnknown {
            reasons.append("service state is not safely known in the required launchd domain; report only")
        }
        if draft.location.kind == .privilegedHelper {
            reasons.append("privileged helpers are report-only until their owning daemon and signature can be verified")
        }
        if draft.location.kind == .groupContainer {
            reasons.append("group containers may be shared by products that are not application bundles")
        }
        if draft.location.scope == .system {
            reasons.append("system-level item; administrator permission and extra review are required")
        }

        let removable = draft.location.removable
            && !active
            && !serviceStateUnknown
            && draft.location.kind != .privilegedHelper
        let risk: RiskLevel = active || draft.location.scope == .system || draft.location.baseRisk >= .high
            ? .high
            : .review
        let finding = Finding(
            id: stableIdentifier(for: "leftover:\(draft.location.kind.rawValue):\(draft.url.standardizedFileURL.path)"),
            path: draft.url.standardizedFileURL.path,
            kind: draft.location.kind,
            scope: draft.location.scope,
            risk: risk,
            confidence: confidence,
            reasons: reasons,
            removable: removable,
            byteSize: metadata.size,
            isDirectory: metadata.isDirectory,
            expectedFileID: metadata.fileID,
            expectedDeviceID: metadata.deviceID
        )
        return LeftoverCandidate(
            finding: finding,
            suspectedIdentifier: draft.identifier,
            suspectedName: suspectedDisplayName(draft.identifier),
            vendorNamespace: vendorNamespace(draft.identifier),
            active: active
        )
    }

    private func identifier(from url: URL, kind: FindingKind) -> String? {
        var name = url.lastPathComponent
        if kind == .preference || kind == .launchAgent || kind == .launchDaemon {
            if name.lowercased().hasSuffix(".plist") { name.removeLast(6) }
        }
        if kind == .savedState, name.lowercased().hasSuffix(".savedstate") {
            name.removeLast(".savedState".count)
        }
        return name
    }

    private func serviceMetadata(at url: URL, kind: FindingKind) -> (label: String?, brokenExecutable: String?) {
        guard kind == .launchAgent || kind == .launchDaemon else { return (nil, nil) }
        guard
            let data = try? Data(contentsOf: url),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let plist = object as? [String: Any]
        else { return (nil, nil) }

        let label = plist["Label"] as? String
        let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first
        let broken: String?
        if let program, program.hasPrefix("/"), !fileManager.fileExists(atPath: program) {
            broken = program
        } else {
            broken = nil
        }
        return (label, broken)
    }

    private func looksLikeBundleIdentifier(_ value: String) -> Bool {
        guard let normalized = canonicalIdentifier(value) else { return false }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
                    .contains($0)
            }
        }
    }

    private func isAppleIdentifier(_ value: String) -> Bool {
        guard let normalized = canonicalIdentifier(value) else { return false }
        return normalized == "com.apple"
            || normalized.hasPrefix("com.apple.")
            || normalized == "is.workflow"
            || normalized.hasPrefix("is.workflow.")
    }

    private func hasInstalledOwner(
        _ candidate: String,
        installedIdentifiers: Set<String>,
        installedNamespaces: Set<String>
    ) -> Bool {
        guard let normalized = canonicalIdentifier(candidate) else { return false }
        if installedIdentifiers.contains(normalized) { return true }
        if installedIdentifiers.contains(where: {
            normalized.hasPrefix($0 + ".") || $0.hasPrefix(normalized + ".")
        }) { return true }
        guard let namespace = vendorNamespace(normalized) else { return false }
        return installedNamespaces.contains(namespace)
    }

    private func vendorNamespace(_ identifier: String) -> String? {
        guard let canonical = canonicalIdentifier(identifier) else { return nil }
        let parts = canonical.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".").lowercased()
    }

    private func canonicalIdentifier(_ identifier: String) -> String? {
        let domainPrefixes: Set<String> = ["com", "org", "net", "io", "dev", "app", "ai", "co", "me", "is", "us"]
        let parts = identifier.split(separator: ".").map(String.init)
        guard let start = parts.firstIndex(where: { domainPrefixes.contains($0.lowercased()) }) else {
            return nil
        }
        let canonical = parts[start...].joined(separator: ".")
        return canonical.split(separator: ".").count >= 3 ? canonical : nil
    }

    private func suspectedDisplayName(_ identifier: String) -> String? {
        guard let canonical = canonicalIdentifier(identifier) else { return nil }
        let parts = canonical.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        let vendor = humanizedIdentifierToken(parts[1])
        let noise: Set<String> = [
            "app", "agent", "daemon", "engine", "group", "helper", "loginitem",
            "mac", "osx", "service", "services", "shared", "update", "updater", "xpc"
        ]
        let product = parts.dropFirst(2).first {
            !noise.contains($0.lowercased()) && !$0.allSatisfy(\.isNumber)
        }.map(humanizedIdentifierToken)
        guard let product, product.caseInsensitiveCompare(vendor) != .orderedSame else {
            return vendor
        }
        return "\(product) · \(vendor)"
    }

    private func humanizedIdentifierToken(_ value: String) -> String {
        let separated = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = separated.first else { return separated }
        return String(first).uppercased() + separated.dropFirst()
    }

    private func launchdLabels(warnings: inout [String]) -> (labels: Set<String>, available: Bool) {
        let result: CommandResult
        do {
            result = try CommandRunner().run(
                executable: "/bin/launchctl",
                arguments: ["list"],
                timeout: 3
            )
        } catch {
            warnings.append("Could not inspect loaded launchd jobs: \(error.localizedDescription)")
            return ([], false)
        }
        guard !result.timedOut else {
            warnings.append("Loaded launchd job inspection timed out after 3 seconds and was stopped safely.")
            return ([], false)
        }
        guard result.terminationStatus == 0,
              let text = String(data: result.standardOutput, encoding: .utf8)
        else {
            warnings.append("Loaded launchd jobs were unavailable in this terminal session.")
            return ([], false)
        }
        let labels = Set(text.split(separator: "\n").compactMap { line in
            line.split(whereSeparator: { $0.isWhitespace }).last.map(String.init)
        })
        return (labels, true)
    }

    private func missingApplicationProcesses() -> (candidates: [LeftoverCandidate], warning: String?) {
        let result: CommandResult
        do {
            result = try CommandRunner().run(
                executable: "/bin/ps",
                arguments: ["-axo", "pid=,comm="],
                timeout: 5
            )
        } catch {
            return ([], "Could not inspect running processes for missing application bundles: \(error.localizedDescription)")
        }
        guard !result.timedOut else {
            return ([], "Running-process inspection timed out after 5 seconds and was stopped safely.")
        }
        guard result.terminationStatus == 0,
              let text = String(data: result.standardOutput, encoding: .utf8)
        else {
            return ([], "Running-process inspection was denied or restricted by macOS.")
        }

        let candidates = text.split(separator: "\n").compactMap { line -> LeftoverCandidate? in
            let value = String(line).trimmingCharacters(in: .whitespaces)
            guard let separator = value.firstIndex(where: { $0.isWhitespace }) else { return nil }
            let pid = String(value[..<separator])
            let command = String(value[separator...]).trimmingCharacters(in: .whitespaces)
            guard let appPath = missingApplicationBundle(in: command) else { return nil }
            let display = "pid:\(pid) \(command)"
            let finding = Finding(
                id: stableIdentifier(for: "leftover-process:\(display)"),
                path: display,
                kind: .process,
                scope: .runtime,
                risk: .high,
                confidence: 95,
                reasons: [
                    "running executable points inside an application bundle that no longer exists",
                    "missing application bundle: \(appPath)",
                    "processes are reported only; AppSleuth never kills them automatically"
                ],
                removable: false,
                byteSize: nil,
                isDirectory: false,
                expectedFileID: nil,
                expectedDeviceID: nil
            )
            let missingName = URL(fileURLWithPath: appPath)
                .deletingPathExtension()
                .lastPathComponent
            return LeftoverCandidate(
                finding: finding,
                suspectedIdentifier: nil,
                suspectedName: missingName.isEmpty ? nil : missingName,
                vendorNamespace: nil,
                active: true
            )
        }
        return (candidates, nil)
    }

    private func missingApplicationBundle(in command: String) -> String? {
        guard let marker = command.range(of: ".app/Contents/") else { return nil }
        let prefix = command[..<marker.lowerBound]
        guard let slash = prefix.firstIndex(of: "/") else { return nil }
        let bundle = String(command[slash..<marker.lowerBound]) + ".app"
        return fileManager.fileExists(atPath: bundle) ? nil : bundle
    }

    private func fileMetadata(at url: URL) -> (isDirectory: Bool, size: UInt64?, fileID: UInt64?, deviceID: UInt64?) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return (false, nil, nil, nil)
        }
        let type = attributes[.type] as? FileAttributeType
        return (
            type == .typeDirectory,
            (attributes[.size] as? NSNumber)?.uint64Value,
            (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

public struct LeftoverCleanupPlanner {
    public init() {}

    public func makePlan(
        from report: LeftoverReport,
        selectedIDs: Set<String>,
        includeSystem: Bool = false
    ) -> LeftoverCleanupPlan {
        LeftoverCleanupPlan(items: report.candidates.map { candidate in
            let finding = candidate.finding
            guard selectedIDs.contains(finding.id) else {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "not explicitly selected by finding ID"
                )
            }
            guard !candidate.active, finding.kind != .process else {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "active services and processes are report-only"
                )
            }
            if finding.kind == .launchAgent || finding.kind == .launchDaemon {
                guard finding.removable else {
                    return PlannedLeftover(
                        candidate: candidate,
                        selected: false,
                        decision: "launchd service state is unknown or requires another domain; report only"
                    )
                }
            }
            if finding.kind == .privilegedHelper {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "privileged helper ownership and daemon state require verification; report only"
                )
            }
            guard finding.removable, finding.risk != .protected else {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "protected or discovery-only item"
                )
            }
            guard finding.confidence >= 75 else {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "insufficient orphan evidence"
                )
            }
            guard finding.scope != .system || includeSystem else {
                return PlannedLeftover(
                    candidate: candidate,
                    selected: false,
                    decision: "system item requires --include-system"
                )
            }
            return PlannedLeftover(
                candidate: candidate,
                selected: true,
                decision: "exact finding ID selected; move remains reversible"
            )
        })
    }
}

public final class LeftoverCleanupService {
    private let uninstallService: UninstallService

    public init(uninstallService: UninstallService = UninstallService()) {
        self.uninstallService = uninstallService
    }

    public func execute(_ plan: LeftoverCleanupPlan) throws -> OperationResult {
        let selectedIDs = Set(plan.selected.map(\.id))
        let items = plan.items.compactMap { item -> PlannedFinding? in
            guard item.candidate.finding.kind != .process else { return nil }
            return PlannedFinding(
                finding: item.candidate.finding,
                selected: selectedIDs.contains(item.candidate.finding.id),
                decision: item.decision
            )
        }
        let identity = ApplicationIdentity(
            path: "/Applications",
            name: "AppSleuth leftover cleanup",
            bundleIdentifier: "dev.appsleuth.leftover-cleanup",
            executableName: nil,
            version: nil
        )
        return try uninstallService.execute(UninstallPlan(application: identity, items: items))
    }
}
