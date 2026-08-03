import Foundation

public struct ActiveApplicationService: Codable, Equatable, Sendable {
    public let label: String
    public let processIdentifier: Int
    public let likelyOwner: String
    public let matchingApplications: [String]

    public init(
        label: String,
        processIdentifier: Int,
        likelyOwner: String,
        matchingApplications: [String]
    ) {
        self.label = label
        self.processIdentifier = processIdentifier
        self.likelyOwner = likelyOwner
        self.matchingApplications = matchingApplications
    }
}

public struct ApplicationServiceReport: Codable, Equatable, Sendable {
    public let services: [ActiveApplicationService]
    public let inspectionAvailable: Bool
    public let warnings: [String]

    public init(
        services: [ActiveApplicationService],
        inspectionAvailable: Bool = true,
        warnings: [String] = []
    ) {
        self.services = services
        self.inspectionAvailable = inspectionAvailable
        self.warnings = warnings
    }
}

public struct DiskSpaceReport: Equatable, Sendable {
    public let totalBytes: UInt64?
    public let usedBytes: UInt64?
    public let availableBytes: UInt64?
    public let warning: String?

    public init(
        totalBytes: UInt64?,
        usedBytes: UInt64?,
        availableBytes: UInt64?,
        warning: String? = nil
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.warning = warning
    }
}

public struct ApplicationBundleSpaceReport: Equatable, Sendable {
    public let byteSize: UInt64?
    public let indexedApplicationCount: Int
    public let externalApplicationCount: Int
    public let warning: String?

    public init(
        byteSize: UInt64?,
        indexedApplicationCount: Int,
        externalApplicationCount: Int,
        warning: String? = nil
    ) {
        self.byteSize = byteSize
        self.indexedApplicationCount = indexedApplicationCount
        self.externalApplicationCount = externalApplicationCount
        self.warning = warning
    }
}

public struct SystemOverview: Codable, Equatable, Sendable {
    public let totalDiskBytes: UInt64?
    public let usedDiskBytes: UInt64?
    public let availableDiskBytes: UInt64?
    public let installedApplicationBytes: UInt64?
    public let indexedApplicationCount: Int
    public let externalApplicationCount: Int
    public let activeUserServices: [ActiveApplicationService]
    public let activeServiceInspectionAvailable: Bool
    public let warnings: [String]

    public init(
        totalDiskBytes: UInt64?,
        usedDiskBytes: UInt64?,
        availableDiskBytes: UInt64?,
        installedApplicationBytes: UInt64?,
        indexedApplicationCount: Int,
        externalApplicationCount: Int,
        activeUserServices: [ActiveApplicationService],
        activeServiceInspectionAvailable: Bool,
        warnings: [String] = []
    ) {
        self.totalDiskBytes = totalDiskBytes
        self.usedDiskBytes = usedDiskBytes
        self.availableDiskBytes = availableDiskBytes
        self.installedApplicationBytes = installedApplicationBytes
        self.indexedApplicationCount = indexedApplicationCount
        self.externalApplicationCount = externalApplicationCount
        self.activeUserServices = activeUserServices
        self.activeServiceInspectionAvailable = activeServiceInspectionAvailable
        self.warnings = warnings
    }
}

public struct ApplicationSizeInspector {
    public init() {}

    public func enrich(_ applications: [InstalledApplication]) -> [InstalledApplication] {
        let missing = applications.enumerated().filter { $0.element.bundleByteSize == nil }
        guard !missing.isEmpty else { return applications }

        let result: CommandResult
        do {
            result = try CommandRunner().run(
                executable: "/usr/bin/mdls",
                arguments: ["-raw", "-name", "kMDItemFSSize"] + missing.map(\.element.application.path),
                timeout: 3
            )
        } catch {
            return applications
        }
        guard !result.timedOut,
              result.terminationStatus == 0,
              let output = String(data: result.standardOutput, encoding: .utf8)
        else { return applications }

        let sizes = indexedSizeEntries(from: output, expectedCount: missing.count)
        guard sizes.count == missing.count else { return applications }
        var resultApplications = applications
        for (offset, entry) in missing.enumerated() {
            resultApplications[entry.offset] = InstalledApplication(
                application: entry.element.application,
                scope: entry.element.scope,
                bundleByteSize: sizes[offset]
            )
        }
        return resultApplications
    }

    func indexedSizeEntries(from output: String, expectedCount: Int) -> [UInt64?] {
        var values = output.components(separatedBy: "\0")
        if values.last == "" { values.removeLast() }
        guard values.count == expectedCount else { return [] }
        return values.map { value in
            UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public struct SystemOverviewInspector {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(installedApplications: [InstalledApplication]) -> SystemOverview {
        let externalApplications = installedApplications.filter {
            $0.scope != .system && !isAppleIdentifier($0.application.bundleIdentifier)
        }
        var warnings: [String] = []

        let disk = inspectDiskSpace()
        if let warning = disk.warning { warnings.append(warning) }

        let enrichedApplications = ApplicationSizeInspector().enrich(externalApplications)
        let applicationSize = summarizeApplicationSpace(
            installedApplications: enrichedApplications
        )
        if let warning = applicationSize.warning { warnings.append(warning) }

        let serviceReport = inspectActiveUserServices(installedApplications: externalApplications)
        warnings.append(contentsOf: serviceReport.warnings)

        return SystemOverview(
            totalDiskBytes: disk.totalBytes,
            usedDiskBytes: disk.usedBytes,
            availableDiskBytes: disk.availableBytes,
            installedApplicationBytes: applicationSize.byteSize,
            indexedApplicationCount: applicationSize.indexedApplicationCount,
            externalApplicationCount: applicationSize.externalApplicationCount,
            activeUserServices: serviceReport.services,
            activeServiceInspectionAvailable: serviceReport.inspectionAvailable,
            warnings: warnings
        )
    }

    public func inspectDiskSpace() -> DiskSpaceReport {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: "/")
            let total = (attributes[.systemSize] as? NSNumber)?.uint64Value
            let available = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value
            let used: UInt64?
            if let total, let available, total >= available {
                used = total - available
            } else {
                used = nil
            }
            return DiskSpaceReport(
                totalBytes: total,
                usedBytes: used,
                availableBytes: available
            )
        } catch {
            return DiskSpaceReport(
                totalBytes: nil,
                usedBytes: nil,
                availableBytes: nil,
                warning: "Disk-space information is unavailable: \(error.localizedDescription)"
            )
        }
    }

    public func summarizeApplicationSpace(
        installedApplications: [InstalledApplication]
    ) -> ApplicationBundleSpaceReport {
        let externalApplications = installedApplications.filter {
            $0.scope != .system && !isAppleIdentifier($0.application.bundleIdentifier)
        }
        guard !externalApplications.isEmpty else {
            return ApplicationBundleSpaceReport(
                byteSize: 0,
                indexedApplicationCount: 0,
                externalApplicationCount: 0
            )
        }
        let values = externalApplications.compactMap(\.bundleByteSize)
        guard !values.isEmpty else {
            return ApplicationBundleSpaceReport(
                byteSize: nil,
                indexedApplicationCount: 0,
                externalApplicationCount: externalApplications.count,
                warning: "Indexed app-bundle sizes were unavailable in this terminal session."
            )
        }
        var total = UInt64(0)
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else {
                return ApplicationBundleSpaceReport(
                    byteSize: nil,
                    indexedApplicationCount: 0,
                    externalApplicationCount: externalApplications.count,
                    warning: "Indexed app-bundle sizes exceeded the supported total."
                )
            }
            total = addition.partialValue
        }
        let warning = values.count == externalApplications.count
            ? nil
            : "App-bundle space is a lower bound: Spotlight supplied sizes for \(values.count) of \(externalApplications.count) third-party bundles."
        return ApplicationBundleSpaceReport(
            byteSize: total,
            indexedApplicationCount: values.count,
            externalApplicationCount: externalApplications.count,
            warning: warning
        )
    }

    public func inspectActiveUserServices(
        installedApplications: [InstalledApplication]
    ) -> ApplicationServiceReport {
        let externalApplications = installedApplications.filter {
            $0.scope != .system && !isAppleIdentifier($0.application.bundleIdentifier)
        }
        let groupedApplications = Dictionary(grouping: externalApplications) {
            vendorNamespace(for: $0.application.bundleIdentifier)
        }
        let applicationNamespaces = Dictionary(
            uniqueKeysWithValues: groupedApplications.compactMap { namespace, applications in
                namespace.map { ($0, applications) }
            }
        )

        let result: CommandResult
        do {
            result = try CommandRunner().run(
                executable: "/bin/launchctl",
                arguments: ["list"],
                timeout: 3
            )
        } catch {
            return ApplicationServiceReport(
                services: [],
                inspectionAvailable: false,
                warnings: ["Active user services could not be inspected: \(error.localizedDescription)"]
            )
        }
        guard !result.timedOut else {
            return ApplicationServiceReport(
                services: [],
                inspectionAvailable: false,
                warnings: ["Active user-service inspection timed out after 3 seconds."]
            )
        }
        guard result.terminationStatus == 0,
              let output = String(data: result.standardOutput, encoding: .utf8)
        else {
            return ApplicationServiceReport(
                services: [],
                inspectionAvailable: false,
                warnings: ["Active user services are unavailable in this terminal session."]
            )
        }

        let services = output.split(separator: "\n").compactMap { line -> ActiveApplicationService? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 3,
                  let processIdentifier = Int(fields[0]),
                  processIdentifier > 0
            else { return nil }
            let label = String(fields.last!)
            guard let namespace = vendorNamespace(for: label),
                  let applications = applicationNamespaces[namespace]
            else { return nil }

            let names = Array(Set(applications.map(\.application.name))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let likelyOwner = names.count == 1
                ? names[0]
                : "\(humanizedVendor(namespace)) family (\(names.count) installed apps)"
            return ActiveApplicationService(
                label: label,
                processIdentifier: processIdentifier,
                likelyOwner: likelyOwner,
                matchingApplications: names
            )
        }.sorted {
            let ownerOrder = $0.likelyOwner.localizedCaseInsensitiveCompare($1.likelyOwner)
            if ownerOrder == .orderedSame {
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            return ownerOrder == .orderedAscending
        }

        return ApplicationServiceReport(
            services: services,
            warnings: [
                "Service coverage is limited to running jobs in the current user's launchd domain; system daemons and modern background registrations need separate inspection."
            ]
        )
    }

    func vendorNamespace(for identifier: String) -> String? {
        let domainPrefixes: Set<String> = [
            "com", "org", "net", "io", "dev", "app", "ai", "co", "me", "is", "us"
        ]
        let parts = identifier.split(separator: ".").map(String.init)
        guard let start = parts.firstIndex(where: { domainPrefixes.contains($0.lowercased()) }),
              parts.count - start >= 2
        else { return nil }
        return parts[start...].prefix(2).joined(separator: ".").lowercased()
    }

    func isAppleIdentifier(_ identifier: String) -> Bool {
        guard let namespace = vendorNamespace(for: identifier) else { return false }
        return namespace == "com.apple" || namespace == "is.workflow"
    }

    func indexedSizeValues(from output: String) -> [UInt64] {
        output.split(whereSeparator: { !$0.isNumber }).compactMap { UInt64($0) }
    }

    private func humanizedVendor(_ namespace: String) -> String {
        let vendor = namespace.split(separator: ".").last.map(String.init) ?? namespace
        let separated = vendor
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = separated.first else { return separated }
        return String(first).uppercased() + separated.dropFirst()
    }
}
