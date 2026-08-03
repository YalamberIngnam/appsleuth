import Foundation

public enum DiagnosticStatus: String, Codable, Equatable, Sendable {
    case pass
    case limited
    case unavailable
    case unknown

    public var label: String { rawValue.uppercased() }
}

public struct DiagnosticCheck: Codable, Equatable, Sendable {
    public let name: String
    public let status: DiagnosticStatus
    public let message: String
    public let resolution: String?

    public init(name: String, status: DiagnosticStatus, message: String, resolution: String? = nil) {
        self.name = name
        self.status = status
        self.message = message
        self.resolution = resolution
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let checks: [DiagnosticCheck]
    public let needsAttention: Bool

    public init(checks: [DiagnosticCheck]) {
        self.schemaVersion = 1
        self.generatedAt = Date()
        self.checks = checks
        self.needsAttention = checks.contains { $0.status == .limited || $0.status == .unavailable }
    }
}

public struct PermissionInspector {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let locations: [SearchLocation]

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        locations: [SearchLocation]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.locations = locations ?? PathCatalog.defaultLocations(homeDirectory: homeDirectory)
    }

    public func inspect() -> DiagnosticReport {
        DiagnosticReport(checks: [
            directoryCheck(name: "User cleanup locations", scope: .user),
            directoryCheck(name: "System cleanup locations", scope: .system),
            processCheck(),
            fullDiskAccessCheck()
        ])
    }

    private func directoryCheck(name: String, scope: FindingScope) -> DiagnosticCheck {
        let roots = locations.filter { $0.scope == scope && fileManager.fileExists(atPath: $0.root.path) }
        var denied: [String] = []
        for location in roots {
            do {
                _ = try fileManager.contentsOfDirectory(atPath: location.root.path)
            } catch {
                denied.append(location.root.path)
            }
        }
        if denied.isEmpty {
            return DiagnosticCheck(
                name: name,
                status: .pass,
                message: "\(roots.count) existing approved location(s) are readable."
            )
        }
        return DiagnosticCheck(
            name: name,
            status: .limited,
            message: "Could not read \(denied.count) of \(roots.count) existing approved location(s): \(denied.joined(separator: ", "))",
            resolution: fullDiskAccessGuidance
        )
    }

    private func processCheck() -> DiagnosticCheck {
        guard let result = try? CommandRunner().run(executable: "/bin/ps", arguments: ["-axo", "pid=,comm="]) else {
            return DiagnosticCheck(
                name: "Process inspection",
                status: .unavailable,
                message: "Could not start the read-only process inventory.",
                resolution: "Check terminal restrictions or endpoint-security policy, then run appsleuth doctor again."
            )
        }
        guard result.terminationStatus == 0 else {
            return DiagnosticCheck(
                name: "Process inspection",
                status: .limited,
                message: "macOS denied or restricted the read-only process inventory.",
                resolution: fullDiskAccessGuidance
            )
        }
        return DiagnosticCheck(
            name: "Process inspection",
            status: .pass,
            message: "Running processes can be inspected."
        )
    }

    private func fullDiskAccessCheck() -> DiagnosticCheck {
        let candidates = ["Library/Mail", "Library/Messages", "Library/Safari"]
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
        guard let probe = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return DiagnosticCheck(
                name: "Full Disk Access",
                status: .unknown,
                message: "No standard protected-data directory was available for a read-only permission probe.",
                resolution: "Full Disk Access is optional for basic scans but recommended for comprehensive third-party app discovery. \(fullDiskAccessGuidance)"
            )
        }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: probe.path)
            return DiagnosticCheck(
                name: "Full Disk Access",
                status: .pass,
                message: "The terminal session can read a standard protected-data location."
            )
        } catch {
            return DiagnosticCheck(
                name: "Full Disk Access",
                status: .limited,
                message: "The terminal session cannot read \(probe.path). Basic scans still work, but some app data may be omitted.",
                resolution: fullDiskAccessGuidance
            )
        }
    }

    private var fullDiskAccessGuidance: String {
        "Open System Settings > Privacy & Security > Full Disk Access, enable the terminal app you use, then quit and reopen that terminal. macOS does not allow AppSleuth to grant this permission to itself."
    }
}
