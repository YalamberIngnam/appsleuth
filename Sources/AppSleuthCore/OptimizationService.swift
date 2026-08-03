import Foundation

public enum OptimizationCheckStatus: String, Codable, Sendable {
    case healthy
    case attention
    case information
    case unavailable
}

public struct OptimizationSystemSnapshot: Codable, Equatable, Sendable {
    public let totalMemoryBytes: UInt64?
    public let usedMemoryBytes: UInt64?
    public let swapUsedBytes: UInt64?
    public let totalDiskBytes: UInt64?
    public let usedDiskBytes: UInt64?
    public let availableDiskBytes: UInt64?
    public let uptimeSeconds: TimeInterval

    public init(
        totalMemoryBytes: UInt64?,
        usedMemoryBytes: UInt64?,
        swapUsedBytes: UInt64?,
        totalDiskBytes: UInt64?,
        usedDiskBytes: UInt64?,
        availableDiskBytes: UInt64?,
        uptimeSeconds: TimeInterval
    ) {
        self.totalMemoryBytes = totalMemoryBytes
        self.usedMemoryBytes = usedMemoryBytes
        self.swapUsedBytes = swapUsedBytes
        self.totalDiskBytes = totalDiskBytes
        self.usedDiskBytes = usedDiskBytes
        self.availableDiskBytes = availableDiskBytes
        self.uptimeSeconds = uptimeSeconds
    }
}

public struct OptimizationCheck: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: OptimizationCheckStatus
    public let summary: String
    public let details: [String]

    public init(
        id: String,
        title: String,
        status: OptimizationCheckStatus,
        summary: String,
        details: [String] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.summary = summary
        self.details = details
    }
}

public enum OptimizationActionRisk: String, Codable, Sendable {
    case low
    case disruptive
}

public enum OptimizationActionKind: String, Codable, Sendable {
    case refreshQuickLookCache = "refresh-quicklook-cache"
    case restartDock = "restart-dock"
    case detachDiskImage = "detach-disk-image"
}

public struct OptimizationAction: Codable, Equatable, Sendable {
    public let id: String
    public let kind: OptimizationActionKind
    public let title: String
    public let summary: String
    public let risk: OptimizationActionRisk
    public let target: String?
    public let reason: String

    public init(
        id: String,
        kind: OptimizationActionKind,
        title: String,
        summary: String,
        risk: OptimizationActionRisk,
        target: String? = nil,
        reason: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.risk = risk
        self.target = target
        self.reason = reason
    }
}

public struct OptimizationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let system: OptimizationSystemSnapshot
    public let checks: [OptimizationCheck]
    public let actions: [OptimizationAction]
    public let warnings: [String]

    public init(
        system: OptimizationSystemSnapshot,
        checks: [OptimizationCheck],
        actions: [OptimizationAction],
        warnings: [String] = []
    ) {
        self.schemaVersion = 1
        self.generatedAt = Date()
        self.system = system
        self.checks = checks
        self.actions = actions
        self.warnings = warnings
    }
}

public enum OptimizationOutcomeStatus: String, Codable, Sendable {
    case applied
    case failed
}

public struct OptimizationOutcome: Codable, Equatable, Sendable {
    public let actionID: String
    public let title: String
    public let status: OptimizationOutcomeStatus
    public let detail: String

    public init(
        actionID: String,
        title: String,
        status: OptimizationOutcomeStatus,
        detail: String
    ) {
        self.actionID = actionID
        self.title = title
        self.status = status
        self.detail = detail
    }
}

protocol OptimizationCommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval?) throws -> CommandResult
}

extension CommandRunner: OptimizationCommandRunning {}

struct MountedDiskImage: Equatable {
    let imagePath: String
    let mountPoint: String
}

public struct OptimizationInspector {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let commandRunner: any OptimizationCommandRunning

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.commandRunner = CommandRunner()
    }

    init(
        fileManager: FileManager,
        homeDirectory: URL,
        commandRunner: any OptimizationCommandRunning
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.commandRunner = commandRunner
    }

    public func inspect(onProgress: ((String) -> Void)? = nil) -> OptimizationReport {
        let totalChecks = 8
        var step = 0
        func progress(_ title: String) {
            step += 1
            onProgress?("[\(step)/\(totalChecks)] \(title)")
        }

        progress("Reading memory, disk, swap, and uptime")
        let system = inspectSystemSnapshot()
        let resourceCheck = resourceCheck(for: system)

        progress("Taking a high-CPU process snapshot")
        let performanceCheck = inspectPerformance()

        progress("Inspecting mounted disk images")
        let imageInspection = inspectMountedDiskImages()

        progress("Checking preference property lists")
        let preferenceCheck = inspectPreferencePropertyLists()

        progress("Checking launch agents and daemons")
        let launchJobCheck = inspectLaunchJobs()

        progress("Checking active VPN connections")
        let vpnCheck = inspectVPN()

        progress("Checking DNS resolver configuration")
        let dnsCheck = inspectDNS()

        progress("Checking Homebrew availability")
        let brewCheck = inspectHomebrew()

        var actions = standardActions()
        actions.append(contentsOf: imageInspection.images.map { image in
            OptimizationAction(
                id: "detach-\(stableIdentifier(for: image.mountPoint))",
                kind: .detachDiskImage,
                title: "Detach \(URL(fileURLWithPath: image.mountPoint).lastPathComponent)",
                summary: "Unmount this exact disk-image volume without deleting its .dmg file.",
                risk: .disruptive,
                target: image.mountPoint,
                reason: "The volume is currently mounted from \(image.imagePath). Detaching can interrupt an app or file still in use."
            )
        })

        return OptimizationReport(
            system: system,
            checks: [
                resourceCheck,
                performanceCheck,
                imageInspection.check,
                preferenceCheck,
                launchJobCheck,
                vpnCheck,
                dnsCheck,
                brewCheck
            ],
            actions: actions,
            warnings: [
                "This is a point-in-time health check, not a benchmark or proof that a Mac is fully healthy.",
                "AppSleuth does not rewrite databases, reset Bluetooth/network hardware, repair permissions, unload jobs, or run undocumented cleanup commands as a general optimization."
            ]
        )
    }

    private func inspectSystemSnapshot() -> OptimizationSystemSnapshot {
        let disk = SystemOverviewInspector(fileManager: fileManager).inspectDiskSpace()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = commandOutput(
            executable: "/usr/bin/vm_stat",
            arguments: [],
            timeout: 3
        ).flatMap { parseUsedMemory(vmStat: $0, totalMemoryBytes: totalMemory) }
        let swapUsed = commandOutput(
            executable: "/usr/sbin/sysctl",
            arguments: ["-n", "vm.swapusage"],
            timeout: 3
        ).flatMap(parseSwapUsed)

        return OptimizationSystemSnapshot(
            totalMemoryBytes: totalMemory,
            usedMemoryBytes: usedMemory,
            swapUsedBytes: swapUsed,
            totalDiskBytes: disk.totalBytes,
            usedDiskBytes: disk.usedBytes,
            availableDiskBytes: disk.availableBytes,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    private func resourceCheck(for snapshot: OptimizationSystemSnapshot) -> OptimizationCheck {
        var attention: [String] = []
        var details: [String] = []
        if let available = snapshot.availableDiskBytes,
           let total = snapshot.totalDiskBytes,
           total > 0 {
            let ratio = Double(available) / Double(total)
            if available < 30_000_000_000 || ratio < 0.10 {
                attention.append("startup disk space is low")
            }
            details.append("Disk available: \(formatBytes(available)) of \(formatBytes(total))")
        } else {
            details.append("Disk capacity is unavailable in this terminal session")
        }
        if let used = snapshot.usedMemoryBytes, let total = snapshot.totalMemoryBytes {
            details.append("Memory in use: approximately \(formatBytes(used)) of \(formatBytes(total))")
        } else if let total = snapshot.totalMemoryBytes {
            details.append("Physical memory: \(formatBytes(total)); current use unavailable")
        }
        if let swap = snapshot.swapUsedBytes {
            details.append("Swap in use: \(formatBytes(swap))")
            if swap > 4_000_000_000 { attention.append("swap use is elevated") }
        }
        details.append("Uptime: \(formatUptime(snapshot.uptimeSeconds))")

        return OptimizationCheck(
            id: "system-resources",
            title: "System resources",
            status: attention.isEmpty ? .healthy : .attention,
            summary: attention.isEmpty
                ? "No resource threshold currently needs attention."
                : attention.joined(separator: "; ").capitalized + ".",
            details: details
        )
    }

    private func inspectPerformance() -> OptimizationCheck {
        guard let output = commandOutput(
            executable: "/bin/ps",
            arguments: ["-A", "-o", "%cpu=,pid=,comm="],
            timeout: 4
        ) else {
            return OptimizationCheck(
                id: "performance-snapshot",
                title: "Performance snapshot",
                status: .unavailable,
                summary: "Running-process CPU data is unavailable in this terminal session."
            )
        }
        let hot = parseHighCPUProcesses(output, threshold: 80)
        return OptimizationCheck(
            id: "performance-snapshot",
            title: "Performance snapshot",
            status: hot.isEmpty ? .healthy : .attention,
            summary: hot.isEmpty
                ? "No process exceeded 80% CPU in this single snapshot."
                : "\(hot.count) process(es) exceeded 80% CPU in this snapshot.",
            details: hot
        )
    }

    private func inspectMountedDiskImages() -> (check: OptimizationCheck, images: [MountedDiskImage]) {
        guard let output = commandData(
            executable: "/usr/bin/hdiutil",
            arguments: ["info", "-plist"],
            timeout: 5
        ) else {
            return (
                OptimizationCheck(
                    id: "mounted-images",
                    title: "Mounted disk images",
                    status: .unavailable,
                    summary: "Mounted disk images could not be inspected."
                ),
                []
            )
        }
        let images = parseMountedDiskImages(plistData: output)
        return (
            OptimizationCheck(
                id: "mounted-images",
                title: "Mounted disk images",
                status: images.isEmpty ? .healthy : .attention,
                summary: images.isEmpty
                    ? "No mounted disk-image volumes were found."
                    : "\(images.count) mounted disk-image volume(s) can be reviewed.",
                details: images.map { "\($0.mountPoint) ← \($0.imagePath)" }
            ),
            images
        )
    }

    private func inspectPreferencePropertyLists() -> OptimizationCheck {
        let roots = [
            homeDirectory.appendingPathComponent("Library/Preferences", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Preferences/ByHost", isDirectory: true),
            URL(fileURLWithPath: "/Library/Preferences", isDirectory: true)
        ]
        var checked = 0
        var invalid: [String] = []
        var unavailable: [String] = []
        var presentRoots = 0
        for root in roots where fileManager.fileExists(atPath: root.path) {
            presentRoots += 1
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: []
                )
            } catch {
                unavailable.append(root.path)
                continue
            }
            for child in children where child.pathExtension.lowercased() == "plist" {
                do {
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { continue }
                    guard (values.fileSize ?? 0) <= 5_000_000 else {
                        unavailable.append("\(child.path) (larger than the 5 MB validation limit)")
                        continue
                    }
                    let data = try Data(contentsOf: child, options: [.mappedIfSafe])
                    do {
                        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                        checked += 1
                    } catch {
                        invalid.append(child.path)
                    }
                } catch {
                    unavailable.append(child.path)
                }
            }
        }
        let status: OptimizationCheckStatus = !invalid.isEmpty
            ? .attention
            : (unavailable.isEmpty ? .healthy : .information)
        var details = invalid.prefix(10).map { "Invalid property list: \($0)" }
        details.append("Checked \(checked) direct .plist file(s) across \(presentRoots) present preference root(s).")
        if !unavailable.isEmpty {
            details.append("Skipped or could not read \(unavailable.count) item(s); they were not called healthy.")
            details.append(contentsOf: unavailable.prefix(5).map { "Unavailable: \($0)" })
        }
        return OptimizationCheck(
            id: "preference-integrity",
            title: "Preference files",
            status: status,
            summary: invalid.isEmpty
                ? (unavailable.isEmpty
                    ? "No invalid property list was found in the bounded preference roots."
                    : "Readable preference files were valid; \(unavailable.count) item(s) were unavailable.")
                : "\(invalid.count) invalid preference file(s) need review.",
            details: details
        )
    }

    private func inspectLaunchJobs() -> OptimizationCheck {
        let roots = [
            homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
        ]
        var checked = 0
        var problems: [String] = []
        var unavailableRoots = 0
        var unavailableItems: [String] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            } catch {
                unavailableRoots += 1
                continue
            }
            for child in children where child.pathExtension.lowercased() == "plist" {
                checked += 1
                do {
                    let data = try Data(contentsOf: child, options: [.mappedIfSafe])
                    let plist: [String: Any]
                    do {
                        guard let decoded = try PropertyListSerialization.propertyList(
                            from: data,
                            options: [],
                            format: nil
                        ) as? [String: Any] else {
                            problems.append("Invalid launch job: \(child.path)")
                            continue
                        }
                        plist = decoded
                    } catch {
                        problems.append("Invalid launch job: \(child.path)")
                        continue
                    }
                    let program = (plist["Program"] as? String)
                        ?? (plist["ProgramArguments"] as? [String])?.first
                    if let program,
                       program.hasPrefix("/"),
                       !fileManager.fileExists(atPath: program) {
                        problems.append("Missing executable: \(child.lastPathComponent) → \(program)")
                    }
                } catch {
                    unavailableItems.append(child.path)
                }
            }
        }
        var details = Array(problems.prefix(10))
        details.append("Checked \(checked) launch agent/daemon property list(s).")
        if unavailableRoots > 0 {
            details.append("\(unavailableRoots) launch-job root(s) were unavailable and were not called healthy.")
        }
        if !unavailableItems.isEmpty {
            details.append("Could not read \(unavailableItems.count) launch job(s); they were not called healthy.")
            details.append(contentsOf: unavailableItems.prefix(5).map { "Unavailable: \($0)" })
        }
        let status: OptimizationCheckStatus = !problems.isEmpty
            ? .attention
            : ((unavailableRoots > 0 || !unavailableItems.isEmpty) ? .information : .healthy)
        return OptimizationCheck(
            id: "launch-job-integrity",
            title: "Launch agents and daemons",
            status: status,
            summary: problems.isEmpty
                ? ((unavailableRoots == 0 && unavailableItems.isEmpty)
                    ? "No invalid job or missing absolute executable was found."
                    : "Readable launch jobs passed; some job data was unavailable.")
                : "\(problems.count) launch job problem(s) need review; nothing was unloaded or deleted.",
            details: details
        )
    }

    private func inspectVPN() -> OptimizationCheck {
        guard let output = commandOutput(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "list"],
            timeout: 3
        ) else {
            return OptimizationCheck(
                id: "vpn",
                title: "VPN connections",
                status: .unavailable,
                summary: "VPN connection state is unavailable."
            )
        }
        let connected = output.split(separator: "\n").map(String.init).filter {
            $0.localizedCaseInsensitiveContains("(Connected)")
        }
        return OptimizationCheck(
            id: "vpn",
            title: "VPN connections",
            status: connected.isEmpty ? .healthy : .information,
            summary: connected.isEmpty
                ? "No active Network Configuration VPN was reported."
                : "An active VPN is present; network-reset actions should be avoided.",
            details: connected
        )
    }

    private func inspectDNS() -> OptimizationCheck {
        guard let output = commandOutput(
            executable: "/usr/sbin/scutil",
            arguments: ["--dns"],
            timeout: 3
        ) else {
            return OptimizationCheck(
                id: "dns",
                title: "DNS resolver",
                status: .unavailable,
                summary: "DNS resolver configuration is unavailable."
            )
        }
        let hasResolver = output.contains("resolver #") || output.contains("nameserver[")
        return OptimizationCheck(
            id: "dns",
            title: "DNS resolver",
            status: hasResolver ? .healthy : .attention,
            summary: hasResolver
                ? "macOS reports an active DNS resolver configuration."
                : "No active DNS resolver was visible; AppSleuth did not flush or restart anything."
        )
    }

    private func inspectHomebrew() -> OptimizationCheck {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return OptimizationCheck(
                id: "homebrew",
                title: "Homebrew",
                status: .information,
                summary: "Homebrew was not detected in the standard Apple Silicon or Intel prefix."
            )
        }
        return OptimizationCheck(
            id: "homebrew",
            title: "Homebrew",
            status: .healthy,
            summary: "Homebrew is installed and executable.",
            details: [
                "Path: \(brew)",
                "Package update checks are intentionally not run during the default offline health check."
            ]
        )
    }

    private func standardActions() -> [OptimizationAction] {
        var actions: [OptimizationAction] = []
        if fileManager.isExecutableFile(atPath: "/usr/bin/qlmanage") {
            actions.append(OptimizationAction(
                id: "quicklook-cache",
                kind: .refreshQuickLookCache,
                title: "Refresh Quick Look cache",
                summary: "Ask macOS to discard and rebuild Quick Look thumbnail cache data.",
                risk: .low,
                reason: "Useful only when Finder previews or thumbnails are stale; regenerated thumbnails may briefly load more slowly."
            ))
        }
        if fileManager.isExecutableFile(atPath: "/usr/bin/killall") {
            actions.append(OptimizationAction(
                id: "restart-dock",
                kind: .restartDock,
                title: "Restart Dock",
                summary: "Restart the current user's Dock process; macOS normally launches it again.",
                risk: .disruptive,
                reason: "Useful only for a stuck Dock or stale icons; the Dock briefly disappears."
            ))
        }
        return actions
    }

    func parseMountedDiskImages(plistData: Data) -> [MountedDiskImage] {
        guard let root = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any],
        let images = root["images"] as? [[String: Any]]
        else { return [] }

        return images.flatMap { image -> [MountedDiskImage] in
            guard let imagePath = image["image-path"] as? String,
                  let entities = image["system-entities"] as? [[String: Any]]
            else { return [] }
            return entities.compactMap { entity in
                guard let mountPoint = entity["mount-point"] as? String,
                      mountPoint.hasPrefix("/Volumes/")
                else { return nil }
                return MountedDiskImage(imagePath: imagePath, mountPoint: mountPoint)
            }
        }.sorted { $0.mountPoint.localizedStandardCompare($1.mountPoint) == .orderedAscending }
    }

    func parseUsedMemory(vmStat: String, totalMemoryBytes: UInt64) -> UInt64? {
        guard let pageSizeMatch = vmStat.range(of: #"page size of [0-9]+ bytes"#, options: .regularExpression),
              let pageSize = UInt64(vmStat[pageSizeMatch].split(separator: " ")[3])
        else { return nil }
        var freePages = UInt64(0)
        for line in vmStat.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("pages free:") || lower.hasPrefix("pages speculative:") else { continue }
            let digits = line.filter(\.isNumber)
            if let value = UInt64(digits) { freePages += value }
        }
        let freeBytesResult = freePages.multipliedReportingOverflow(by: pageSize)
        guard !freeBytesResult.overflow else { return nil }
        return totalMemoryBytes > freeBytesResult.partialValue
            ? totalMemoryBytes - freeBytesResult.partialValue
            : 0
    }

    func parseSwapUsed(_ output: String) -> UInt64? {
        guard let range = output.range(
            of: #"used = [0-9]+(?:\.[0-9]+)?[MG]"#,
            options: .regularExpression
        ) else { return nil }
        let token = output[range].split(separator: " ").last.map(String.init) ?? ""
        guard let suffix = token.last,
              let value = Double(token.dropLast())
        else { return nil }
        let multiplier = suffix == "G" ? 1_073_741_824.0 : 1_048_576.0
        return UInt64(value * multiplier)
    }

    func parseHighCPUProcesses(_ output: String, threshold: Double) -> [String] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let cpu = Double(fields[0]),
                  cpu >= threshold
            else { return nil }
            return "\(fields[2]) · pid \(fields[1]) · \(String(format: "%.1f", cpu))% CPU"
        }
    }

    private func commandOutput(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        commandData(executable: executable, arguments: arguments, timeout: timeout)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    private func commandData(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> Data? {
        guard fileManager.isExecutableFile(atPath: executable),
              let result = try? commandRunner.run(
                executable: executable,
                arguments: arguments,
                timeout: timeout
              ),
              !result.timedOut,
              result.terminationStatus == 0
        else { return nil }
        return result.standardOutput
    }

    private func formatBytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useTB, .useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}

public struct OptimizationExecutor {
    private let fileManager: FileManager
    private let commandRunner: any OptimizationCommandRunning

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.commandRunner = CommandRunner()
    }

    init(fileManager: FileManager, commandRunner: any OptimizationCommandRunning) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func execute(_ actions: [OptimizationAction]) throws -> [OptimizationOutcome] {
        guard !actions.isEmpty else {
            throw AppSleuthError.unsafeOperation("No exact optimization action was selected.")
        }
        return actions.map(execute)
    }

    private func execute(_ action: OptimizationAction) -> OptimizationOutcome {
        let command: (String, [String])
        switch action.kind {
        case .refreshQuickLookCache:
            guard action.id == "quicklook-cache" else {
                return failed(action, "Action identity failed validation; nothing was run.")
            }
            command = ("/usr/bin/qlmanage", ["-r", "cache"])
        case .restartDock:
            guard action.id == "restart-dock" else {
                return failed(action, "Action identity failed validation; nothing was run.")
            }
            command = ("/usr/bin/killall", ["Dock"])
        case .detachDiskImage:
            guard let target = action.target,
                  target.hasPrefix("/Volumes/"),
                  URL(fileURLWithPath: target).standardizedFileURL.path == target,
                  action.id == "detach-\(stableIdentifier(for: target))",
                  currentlyMountedImagePaths().contains(target)
            else {
                return failed(action, "The exact disk-image mount is no longer present or failed revalidation.")
            }
            command = ("/usr/bin/hdiutil", ["detach", target])
        }

        guard fileManager.isExecutableFile(atPath: command.0) else {
            return failed(action, "Required macOS command is unavailable; nothing was run.")
        }
        do {
            let result = try commandRunner.run(
                executable: command.0,
                arguments: command.1,
                timeout: 20
            )
            guard !result.timedOut, result.terminationStatus == 0 else {
                let detail = result.timedOut
                    ? "Action timed out and was stopped."
                    : "macOS declined the action (exit \(result.terminationStatus))."
                return failed(action, detail)
            }
            return OptimizationOutcome(
                actionID: action.id,
                title: action.title,
                status: .applied,
                detail: "Applied the exact reviewed action."
            )
        } catch {
            return failed(action, error.localizedDescription)
        }
    }

    private func currentlyMountedImagePaths() -> Set<String> {
        guard fileManager.isExecutableFile(atPath: "/usr/bin/hdiutil"),
              let result = try? commandRunner.run(
                executable: "/usr/bin/hdiutil",
                arguments: ["info", "-plist"],
                timeout: 5
              ),
              !result.timedOut,
              result.terminationStatus == 0
        else { return [] }
        return Set(OptimizationInspector().parseMountedDiskImages(
            plistData: result.standardOutput
        ).map(\.mountPoint))
    }

    private func failed(_ action: OptimizationAction, _ detail: String) -> OptimizationOutcome {
        OptimizationOutcome(
            actionID: action.id,
            title: action.title,
            status: .failed,
            detail: detail
        )
    }
}
