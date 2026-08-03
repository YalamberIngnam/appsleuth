import Foundation

public enum AppSleuthError: Error, CustomStringConvertible {
    case appNotFound(String)
    case ambiguousApp(String, [String])
    case invalidApplication(String)
    case invalidArguments(String)
    case unsafeOperation(String)
    case backupNotFound(String)
    case restoreConflict(String)

    public var description: String {
        switch self {
        case let .appNotFound(query):
            return "No installed application matched '\(query)'. Try an absolute .app path."
        case let .ambiguousApp(query, paths):
            return "'\(query)' matched more than one application:\n" + paths.map { "  \($0)" }.joined(separator: "\n")
        case let .invalidApplication(reason), let .invalidArguments(reason),
             let .unsafeOperation(reason), let .restoreConflict(reason):
            return reason
        case let .backupNotFound(identifier):
            return "Backup '\(identifier)' was not found."
        }
    }
}

public struct ApplicationIdentity: Codable, Equatable, Sendable {
    public let path: String
    public let name: String
    public let bundleIdentifier: String
    public let executableName: String?
    public let version: String?

    public init(path: String, name: String, bundleIdentifier: String, executableName: String?, version: String?) {
        self.path = path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.version = version
    }
}

public enum ApplicationInstallScope: String, Codable, Sendable {
    case user
    case shared
    case system
}

public struct InstalledApplication: Codable, Equatable, Sendable {
    public let application: ApplicationIdentity
    public let scope: ApplicationInstallScope
    public let bundleByteSize: UInt64?

    public init(
        application: ApplicationIdentity,
        scope: ApplicationInstallScope,
        bundleByteSize: UInt64? = nil
    ) {
        self.application = application
        self.scope = scope
        self.bundleByteSize = bundleByteSize
    }
}

public enum FindingKind: String, Codable, CaseIterable, Hashable, Sendable {
    case applicationBundle = "application"
    case applicationSupport = "application-support"
    case preference
    case cache
    case log
    case savedState = "saved-state"
    case webData = "web-data"
    case container
    case groupContainer = "group-container"
    case applicationScript = "application-script"
    case launchAgent = "launch-agent"
    case launchDaemon = "launch-daemon"
    case startupItem = "startup-item"
    case privilegedHelper = "privileged-helper"
    case loginItem = "login-item"
    case backgroundHelper = "background-helper"
    case systemExtension = "system-extension"
    case driverExtension = "driver-extension"
    case plugin
    case framework
    case font
    case colorProfile = "color-profile"
    case commandLineTool = "command-line-tool"
    case shellIntegration = "shell-integration"
    case packageManagerRecord = "package-manager-record"
    case receipt
    case process
}

public enum FindingScope: String, Codable, Sendable {
    case user
    case system
    case runtime
}

public enum RiskLevel: String, Codable, Comparable, Sendable {
    case safe
    case review
    case high
    case protected

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .high: return 2
        case .protected: return 3
        }
    }

    public var label: String {
        switch self {
        case .safe: return "SAFE"
        case .review: return "REVIEW"
        case .high: return "HIGH"
        case .protected: return "PROTECTED"
        }
    }
}

public struct Finding: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let kind: FindingKind
    public let scope: FindingScope
    public let risk: RiskLevel
    public let confidence: Int
    public let reasons: [String]
    public let removable: Bool
    public let byteSize: UInt64?
    public let isDirectory: Bool
    public let expectedFileID: UInt64?
    public let expectedDeviceID: UInt64?

    public init(
        id: String,
        path: String,
        kind: FindingKind,
        scope: FindingScope,
        risk: RiskLevel,
        confidence: Int,
        reasons: [String],
        removable: Bool,
        byteSize: UInt64?,
        isDirectory: Bool,
        expectedFileID: UInt64?,
        expectedDeviceID: UInt64?
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.scope = scope
        self.risk = risk
        self.confidence = confidence
        self.reasons = reasons
        self.removable = removable
        self.byteSize = byteSize
        self.isDirectory = isDirectory
        self.expectedFileID = expectedFileID
        self.expectedDeviceID = expectedDeviceID
    }
}

public enum ScanLocationStatus: String, Codable, Sendable {
    case inspected
    case notPresent = "not-present"
    case unavailable
}

public struct ScanLocationInspection: Codable, Equatable, Sendable {
    public let path: String
    public let kind: FindingKind
    public let scope: FindingScope
    public let status: ScanLocationStatus
    public let matchedItemCount: Int
    public let note: String?

    public init(
        path: String,
        kind: FindingKind,
        scope: FindingScope,
        status: ScanLocationStatus,
        matchedItemCount: Int = 0,
        note: String? = nil
    ) {
        self.path = path
        self.kind = kind
        self.scope = scope
        self.status = status
        self.matchedItemCount = matchedItemCount
        self.note = note
    }
}

public struct ScanCoverage: Codable, Equatable, Sendable {
    public let locations: [ScanLocationInspection]
    public let unsupportedState: [String]

    public init(
        locations: [ScanLocationInspection] = [],
        unsupportedState: [String] = []
    ) {
        self.locations = locations
        self.unsupportedState = unsupportedState
    }

    public var inspectedLocationCount: Int {
        locations.filter { $0.status == .inspected }.count
    }

    public var notPresentLocationCount: Int {
        locations.filter { $0.status == .notPresent }.count
    }

    public var unavailableLocationCount: Int {
        locations.filter { $0.status == .unavailable }.count
    }

    public var matchedLocationCount: Int {
        locations.filter { $0.matchedItemCount > 0 }.count
    }

    public var supportedKinds: [FindingKind] {
        Array(Set(locations.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
    }
}

public struct ScanReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let application: ApplicationIdentity
    public let findings: [Finding]
    public let coverage: ScanCoverage
    public let warnings: [String]

    public init(
        application: ApplicationIdentity,
        findings: [Finding],
        coverage: ScanCoverage = ScanCoverage(),
        warnings: [String] = []
    ) {
        self.schemaVersion = 2
        self.generatedAt = Date()
        self.application = application
        self.findings = findings
        self.coverage = coverage
        self.warnings = warnings
    }
}

public struct LeftoverCandidate: Codable, Equatable, Sendable {
    public let finding: Finding
    public let suspectedIdentifier: String?
    public let suspectedName: String?
    public let vendorNamespace: String?
    public let active: Bool

    public init(
        finding: Finding,
        suspectedIdentifier: String?,
        suspectedName: String? = nil,
        vendorNamespace: String? = nil,
        active: Bool
    ) {
        self.finding = finding
        self.suspectedIdentifier = suspectedIdentifier
        self.suspectedName = suspectedName
        self.vendorNamespace = vendorNamespace
        self.active = active
    }
}

public struct LeftoverReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let installedApplicationCount: Int
    public let candidates: [LeftoverCandidate]
    public let warnings: [String]

    public init(
        installedApplicationCount: Int,
        candidates: [LeftoverCandidate],
        warnings: [String] = []
    ) {
        self.schemaVersion = 1
        self.generatedAt = Date()
        self.installedApplicationCount = installedApplicationCount
        self.candidates = candidates
        self.warnings = warnings
    }
}

public struct PlannedLeftover: Codable, Equatable, Sendable {
    public let candidate: LeftoverCandidate
    public let selected: Bool
    public let decision: String

    public init(candidate: LeftoverCandidate, selected: Bool, decision: String) {
        self.candidate = candidate
        self.selected = selected
        self.decision = decision
    }
}

public struct LeftoverCleanupPlan: Codable, Equatable, Sendable {
    public let items: [PlannedLeftover]

    public init(items: [PlannedLeftover]) {
        self.items = items
    }

    public var selected: [Finding] {
        items.filter(\.selected).map(\.candidate.finding)
    }
}

public struct PlannedFinding: Codable, Equatable, Sendable {
    public let finding: Finding
    public let selected: Bool
    public let decision: String
}

public struct UninstallPlan: Codable, Equatable, Sendable {
    public let application: ApplicationIdentity
    public let items: [PlannedFinding]

    public var selected: [Finding] { items.filter(\.selected).map(\.finding) }
}

public enum BackupItemStatus: String, Codable, Sendable {
    case pending
    case moved
    case restored
    case skipped
}

public struct BackupItem: Codable, Equatable, Sendable {
    public let findingID: String
    public let originalPath: String
    public let backupPath: String
    public let kind: FindingKind
    public let scope: FindingScope
    public var status: BackupItemStatus
    public var note: String?
}

public enum BackupStatus: String, Codable, Sendable {
    case preparing
    case complete
    case partial
    case restored
}

public struct BackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let createdAt: Date
    public let application: ApplicationIdentity
    public var status: BackupStatus
    public var items: [BackupItem]
}

public struct OperationResult: Codable, Equatable, Sendable {
    public let backupID: String
    public let moved: [String]
    public let skipped: [String]
}

public struct PurgeResult: Codable, Equatable, Sendable {
    public let application: ApplicationIdentity
    public let deleted: [String]

    public init(application: ApplicationIdentity, deleted: [String]) {
        self.application = application
        self.deleted = deleted
    }
}

public func stableIdentifier(for value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}
