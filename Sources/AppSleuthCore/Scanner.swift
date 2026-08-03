import Darwin
import Foundation

struct CommandResult {
    let terminationStatus: Int32
    let standardOutput: Data
    let timedOut: Bool
}

private final class CommandTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct CommandRunner {
    func run(executable: String, arguments: [String], timeout: TimeInterval? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let timeoutState = CommandTimeoutState()
        var timeoutWorkItem: DispatchWorkItem?
        if let timeout {
            let workItem = DispatchWorkItem {
                guard process.isRunning else { return }
                timeoutState.markTimedOut()
                kill(process.processIdentifier, SIGKILL)
            }
            timeoutWorkItem = workItem
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: workItem)
        }

        // Drain before waiting. Waiting first can deadlock when a child fills the
        // pipe buffer and blocks before it gets a chance to exit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem?.cancel()
        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: data,
            timedOut: timeoutState.timedOut
        )
    }
}

public struct ProcessInspector {
    public init() {}

    public func findings(for app: ApplicationIdentity) -> [Finding] {
        inspect(for: app).findings
    }

    func inspect(for app: ApplicationIdentity) -> (findings: [Finding], warning: String?) {
        let result: CommandResult
        do {
            result = try CommandRunner().run(
                executable: "/bin/ps",
                arguments: ["-axo", "pid=,comm=,args="],
                timeout: 5
            )
        } catch {
            return ([], "Could not inspect running processes: \(error.localizedDescription)")
        }
        guard !result.timedOut else {
            return ([], "Running-process inspection timed out and was stopped safely.")
        }
        guard result.terminationStatus == 0 else {
            return ([], "Running-process inspection was denied or restricted by macOS.")
        }
        guard let text = String(data: result.standardOutput, encoding: .utf8) else {
            return ([], "Running-process output was not valid UTF-8 and was skipped.")
        }

        let findings = text.split(separator: "\n").compactMap { line -> Finding? in
            let value = String(line).trimmingCharacters(in: .whitespaces)
            guard let firstSpace = value.firstIndex(where: { $0.isWhitespace }) else { return nil }
            let pid = String(value[..<firstSpace])
            let details = String(value[firstSpace...]).trimmingCharacters(in: .whitespaces)
            guard details.hasPrefix(app.path + "/") else { return nil }
            let display = "pid:\(pid) \(details)"
            return Finding(
                id: stableIdentifier(for: "process:\(display)"),
                path: display,
                kind: .process,
                scope: .runtime,
                risk: .review,
                confidence: 100,
                reasons: ["running process command references an executable inside the application bundle"],
                removable: false,
                byteSize: nil,
                isDirectory: false,
                expectedFileID: nil,
                expectedDeviceID: nil
            )
        }
        return (findings, nil)
    }
}

public struct Scanner {
    private let fileManager: FileManager
    private let locations: [SearchLocation]
    private let applicationRoots: [URL]
    private let matcher: Matcher
    private let inspectProcesses: Bool
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        locations: [SearchLocation]? = nil,
        applicationRoots: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        inspectProcesses: Bool = true
    ) {
        self.fileManager = fileManager
        self.locations = locations ?? PathCatalog.defaultLocations(homeDirectory: homeDirectory)
        self.applicationRoots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        self.matcher = Matcher()
        self.inspectProcesses = inspectProcesses
        self.homeDirectory = homeDirectory
    }

    public func scan(_ app: ApplicationIdentity, onProgress: ((String) -> Void)? = nil) -> ScanReport {
        var findings: [Finding] = [applicationFinding(app)]
        var warnings: [String] = []
        var coverage: [ScanLocationInspection] = []
        let embeddedRoots = embeddedSearchRoots(in: app)
        let totalSteps = embeddedRoots.count + locations.count + (inspectProcesses ? 1 : 0)
        var currentStep = 0

        for (root, kind) in embeddedRoots {
            currentStep += 1
            onProgress?(progressMessage(
                step: currentStep,
                total: totalSteps,
                kind: kind,
                scope: app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system,
                path: root.path
            ))
            guard fileManager.fileExists(atPath: root.path) else {
                coverage.append(ScanLocationInspection(
                    path: root.path,
                    kind: kind,
                    scope: app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system,
                    status: .notPresent
                ))
                continue
            }
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: []
                )
                let embedded = children.map { embeddedFinding(at: $0, kind: kind, app: app) }
                findings.append(contentsOf: embedded)
                coverage.append(ScanLocationInspection(
                    path: root.path,
                    kind: kind,
                    scope: app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system,
                    status: .inspected,
                    matchedItemCount: embedded.count
                ))
            } catch {
                let message = "Could not inspect \(root.path): \(error.localizedDescription)"
                warnings.append(message)
                coverage.append(ScanLocationInspection(
                    path: root.path,
                    kind: kind,
                    scope: app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system,
                    status: .unavailable,
                    note: error.localizedDescription
                ))
            }
        }

        for location in locations {
            currentStep += 1
            onProgress?(progressMessage(
                step: currentStep,
                total: totalSteps,
                kind: location.kind,
                scope: location.scope,
                path: location.root.path
            ))
            guard fileManager.fileExists(atPath: location.root.path) else {
                coverage.append(ScanLocationInspection(
                    path: location.root.path,
                    kind: location.kind,
                    scope: location.scope,
                    status: .notPresent
                ))
                continue
            }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: location.root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: []
                )
            } catch {
                let message = "Could not inspect \(location.root.path): \(error.localizedDescription)"
                warnings.append(message)
                coverage.append(ScanLocationInspection(
                    path: location.root.path,
                    kind: location.kind,
                    scope: location.scope,
                    status: .unavailable,
                    note: error.localizedDescription
                ))
                continue
            }
            var matchedItemCount = 0
            for child in children {
                guard let evidence = matcher.evidence(for: child, app: app, kind: location.kind) else { continue }
                findings.append(makeFinding(at: child, location: location, evidence: evidence))
                matchedItemCount += 1
            }
            coverage.append(ScanLocationInspection(
                path: location.root.path,
                kind: location.kind,
                scope: location.scope,
                status: .inspected,
                matchedItemCount: matchedItemCount
            ))
        }

        if inspectProcesses {
            currentStep += 1
            onProgress?("[\(currentStep)/\(totalSteps)] process · runtime · running process table")
            let inspection = ProcessInspector().inspect(for: app)
            findings.append(contentsOf: inspection.findings)
            if let warning = inspection.warning {
                warnings.append(warning)
                coverage.append(ScanLocationInspection(
                    path: "running process table",
                    kind: .process,
                    scope: .runtime,
                    status: .unavailable,
                    note: warning
                ))
            } else {
                coverage.append(ScanLocationInspection(
                    path: "running process table",
                    kind: .process,
                    scope: .runtime,
                    status: .inspected,
                    matchedItemCount: inspection.findings.count
                ))
            }
        }
        let unsupportedState = [
            "Keychain items and certificates",
            "privacy grants in macOS TCC databases",
            "file-handler registrations managed by LaunchServices",
            "modern Background Task Management registrations",
            "APFS snapshots, Time Machine copies, and vendor cloud/server data"
        ]
        warnings.append(
            "Keychain items, certificates, privacy grants, file-handler registrations, and modern Background Task Management records are macOS-managed state. AppSleuth does not enumerate or delete them from filename evidence."
        )
        warnings.append(
            "Package-manager records, command-line tools, shared frameworks, fonts, profiles, and low-level extensions are discovery-only unless a supported owner-specific removal workflow is available."
        )

        let deduplicated = Dictionary(grouping: findings, by: \.path).compactMap { _, values in
            values.max { lhs, rhs in lhs.confidence < rhs.confidence }
        }
        return ScanReport(
            application: app,
            findings: deduplicated.sorted { lhs, rhs in
                if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
                if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            },
            coverage: ScanCoverage(
                locations: coverage,
                unsupportedState: unsupportedState
            ),
            warnings: warnings
        )
    }

    private func progressMessage(
        step: Int,
        total: Int,
        kind: FindingKind,
        scope: FindingScope,
        path: String
    ) -> String {
        "[\(step)/\(total)] \(kind.rawValue) · \(scope.rawValue) · \(path)"
    }

    private func applicationFinding(_ app: ApplicationIdentity) -> Finding {
        let url = URL(fileURLWithPath: app.path)
        let metadata = fileMetadata(at: url)
        let approvedRoot = applicationRoots.contains { isApplication(url, inside: $0) }
        let isSystemProtected = app.path == "/System/Applications" || app.path.hasPrefix("/System/Applications/")
        let removable = approvedRoot && !isSystemProtected
        let scope: FindingScope = app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system
        var reasons = ["exact application bundle selected by the user", "bundle identifier: \(app.bundleIdentifier)"]
        if !approvedRoot {
            reasons.append("bundle is outside approved installed-application roots")
        }
        return Finding(
            id: stableIdentifier(for: "application:\(app.path)"),
            path: app.path,
            kind: .applicationBundle,
            scope: scope,
            risk: removable ? .review : .protected,
            confidence: 100,
            reasons: reasons,
            removable: removable,
            byteSize: metadata.size,
            isDirectory: metadata.isDirectory,
            expectedFileID: metadata.fileID,
            expectedDeviceID: metadata.deviceID
        )
    }

    private func isApplication(_ application: URL, inside root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let appPath = application.standardizedFileURL.path
        guard appPath.hasPrefix(rootPath + "/") else { return false }
        let relative = String(appPath.dropFirst(rootPath.count + 1))
        return relative.split(separator: "/").count <= 2
    }

    private func makeFinding(at url: URL, location: SearchLocation, evidence: MatchEvidence) -> Finding {
        let metadata = fileMetadata(at: url)
        var risk = location.baseRisk
        var removable = location.removable
        var reasons = evidence.reasons
        if evidence.confidence < 85 {
            risk = .high
            removable = false
            reasons.append("fuzzy name-only match; discovery only")
        }
        if location.kind == .groupContainer {
            reasons.append("group containers can be shared by several applications")
        }
        if location.kind == .receipt {
            reasons.append("package receipts are system records and are never removed by AppSleuth")
        }
        if [.framework, .font, .colorProfile].contains(location.kind) {
            reasons.append("this category may be shared by several applications and is discovery-only")
        }
        if [.commandLineTool, .shellIntegration, .packageManagerRecord].contains(location.kind) {
            reasons.append("external package-manager or command-line state is reported but never removed directly")
        }
        if [.systemExtension, .driverExtension].contains(location.kind) {
            reasons.append("low-level extensions require their vendor or a supported macOS deactivation workflow")
        }
        if location.scope == .system {
            reasons.append("system-level item; administrator permission may be required")
        }
        return Finding(
            id: stableIdentifier(for: "\(location.kind.rawValue):\(url.standardizedFileURL.path)"),
            path: url.standardizedFileURL.path,
            kind: location.kind,
            scope: location.scope,
            risk: risk,
            confidence: evidence.confidence,
            reasons: reasons,
            removable: removable,
            byteSize: metadata.size,
            isDirectory: metadata.isDirectory,
            expectedFileID: metadata.fileID,
            expectedDeviceID: metadata.deviceID
        )
    }

    private func embeddedSearchRoots(in app: ApplicationIdentity) -> [(URL, FindingKind)] {
        let bundle = URL(fileURLWithPath: app.path, isDirectory: true)
        let roots: [(String, FindingKind)] = [
            ("Contents/Library/LoginItems", .loginItem),
            ("Contents/Library/LaunchServices", .backgroundHelper),
            ("Contents/Library/SystemExtensions", .systemExtension),
            ("Contents/XPCServices", .backgroundHelper),
            ("Contents/PlugIns", .plugin),
            ("Contents/Frameworks", .framework),
            ("Contents/Library/QuickLook", .plugin),
            ("Contents/Library/Spotlight", .plugin),
            ("Contents/_MASReceipt", .receipt)
        ]
        return roots.map { relativePath, kind in
            (bundle.appendingPathComponent(relativePath, isDirectory: true), kind)
        }
    }

    private func embeddedFinding(
        at child: URL,
        kind: FindingKind,
        app: ApplicationIdentity
    ) -> Finding {
        let scope: FindingScope = app.path.hasPrefix(homeDirectory.path + "/") ? .user : .system
        let metadata = fileMetadata(at: child)
        return Finding(
            id: stableIdentifier(for: "\(kind.rawValue):\(child.standardizedFileURL.path)"),
            path: child.standardizedFileURL.path,
            kind: kind,
            scope: scope,
            risk: .review,
            confidence: 100,
            reasons: [
                "item is embedded inside the exact selected application bundle",
                "covered by the parent application move and never moved separately"
            ],
            removable: false,
            byteSize: metadata.size,
            isDirectory: metadata.isDirectory,
            expectedFileID: metadata.fileID,
            expectedDeviceID: metadata.deviceID
        )
    }

    private func fileMetadata(at url: URL) -> (isDirectory: Bool, size: UInt64?, fileID: UInt64?, deviceID: UInt64?) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return (false, nil, nil, nil)
        }
        let type = attributes[.type] as? FileAttributeType
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let deviceID = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        return (type == .typeDirectory, type == .typeRegular ? size : nil, fileID, deviceID)
    }
}
