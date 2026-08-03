import Foundation

public struct ApplicationSearchLocation: Sendable {
    public let directory: URL
    public let scope: ApplicationInstallScope

    public init(directory: URL, scope: ApplicationInstallScope) {
        self.directory = directory
        self.scope = scope
    }
}

public struct ApplicationLocator {
    private let fileManager: FileManager
    private let searchLocations: [ApplicationSearchLocation]

    public init(
        fileManager: FileManager = .default,
        searchDirectories: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        if let searchDirectories {
            self.searchLocations = searchDirectories.map {
                ApplicationSearchLocation(
                    directory: $0,
                    scope: Self.inferredScope(for: $0, homeDirectory: homeDirectory)
                )
            }
        } else {
            self.searchLocations = [
                ApplicationSearchLocation(
                    directory: URL(fileURLWithPath: "/Applications", isDirectory: true),
                    scope: .shared
                ),
                ApplicationSearchLocation(
                    directory: homeDirectory.appendingPathComponent("Applications", isDirectory: true),
                    scope: .user
                ),
                ApplicationSearchLocation(
                    directory: URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                    scope: .system
                ),
                ApplicationSearchLocation(
                    directory: URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
                    scope: .system
                )
            ]
        }
    }

    public init(
        fileManager: FileManager = .default,
        searchLocations: [ApplicationSearchLocation]
    ) {
        self.fileManager = fileManager
        self.searchLocations = searchLocations
    }

    public func installedApplications(
        includeSystem: Bool = true,
        onProgress: ((String) -> Void)? = nil
    ) -> [InstalledApplication] {
        var applications: [InstalledApplication] = []
        var seenPaths = Set<String>()

        for location in searchLocations where fileManager.fileExists(atPath: location.directory.path) {
            let directory = location.directory
            let scope = location.scope
            guard includeSystem || scope != .system else { continue }
            onProgress?("Inspecting \(directory.path)")

            for candidate in applicationCandidates(in: directory) {
                guard
                    let identity = try? readIdentity(at: candidate),
                    seenPaths.insert(identity.path).inserted
                else { continue }
                applications.append(InstalledApplication(application: identity, scope: scope))
            }
        }

        return applications.sorted {
            let nameOrder = $0.application.name.localizedCaseInsensitiveCompare($1.application.name)
            if nameOrder == .orderedSame {
                return $0.application.path.localizedCaseInsensitiveCompare($1.application.path) == .orderedAscending
            }
            return nameOrder == .orderedAscending
        }
    }

    public func locate(_ query: String) throws -> ApplicationIdentity {
        let expanded = NSString(string: query).expandingTildeInPath
        if query.contains("/") {
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard fileManager.fileExists(atPath: url.path) else {
                throw AppSleuthError.appNotFound(query)
            }
            return try readIdentity(at: url)
        }

        let searchedName = query.lowercased().hasSuffix(".app") ? String(query.dropLast(4)) : query
        var exact: [ApplicationIdentity] = []
        var bundleMatches: [ApplicationIdentity] = []
        for location in searchLocations where fileManager.fileExists(atPath: location.directory.path) {
            let directory = location.directory
            for child in applicationCandidates(in: directory) {
                guard let identity = try? readIdentity(at: child) else { continue }
                let names = [identity.name, child.deletingPathExtension().lastPathComponent]
                if names.contains(where: { $0.caseInsensitiveCompare(searchedName) == .orderedSame }) {
                    exact.append(identity)
                } else if identity.bundleIdentifier.caseInsensitiveCompare(query) == .orderedSame {
                    bundleMatches.append(identity)
                }
            }
        }

        let matches = exact.isEmpty ? bundleMatches : exact
        guard !matches.isEmpty else { throw AppSleuthError.appNotFound(query) }
        guard matches.count == 1 else {
            throw AppSleuthError.ambiguousApp(query, matches.map(\.path).sorted())
        }
        return matches[0]
    }

    private func applicationCandidates(in directory: URL) -> [URL] {
        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var candidates = children.filter { $0.pathExtension.lowercased() == "app" }
        for child in children where child.pathExtension.lowercased() != "app" {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let grandchildren = (try? fileManager.contentsOfDirectory(
                at: child,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates.append(contentsOf: grandchildren.filter { $0.pathExtension.lowercased() == "app" })
        }
        return candidates
    }

    private static func inferredScope(for directory: URL, homeDirectory: URL) -> ApplicationInstallScope {
        let path = directory.standardizedFileURL.path
        let userApplications = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path
        if path == userApplications || path.hasPrefix(userApplications + "/") {
            return .user
        }
        if path == "/System" || path.hasPrefix("/System/") {
            return .system
        }
        return .shared
    }

    public func readIdentity(at applicationURL: URL) throws -> ApplicationIdentity {
        guard applicationURL.pathExtension.lowercased() == "app" else {
            throw AppSleuthError.invalidApplication("Expected a .app bundle, got: \(applicationURL.path)")
        }
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let info = object as? [String: Any]
        else {
            throw AppSleuthError.invalidApplication("Could not read bundle metadata at \(infoURL.path)")
        }
        guard let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw AppSleuthError.invalidApplication("Application has no CFBundleIdentifier: \(applicationURL.path)")
        }
        let fileName = applicationURL.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? fileName
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        return ApplicationIdentity(
            path: applicationURL.standardizedFileURL.path,
            name: name,
            bundleIdentifier: bundleID,
            executableName: info["CFBundleExecutable"] as? String,
            version: version
        )
    }
}
