import Foundation

public final class BackupStore {
    public let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        root: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.root = root ?? homeDirectory
            .appendingPathComponent(".local/share/appsleuth/backups", isDirectory: true)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func newManifest(for app: ApplicationIdentity, findings: [Finding]) throws -> BackupManifest {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let id = "\(timestamp)-\(UUID().uuidString.lowercased().prefix(8))"
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let payload = directory.appendingPathComponent("payload", isDirectory: true)
        let items = findings.map { finding in
            BackupItem(
                findingID: finding.id,
                originalPath: finding.path,
                backupPath: payloadPath(for: finding.path, payloadRoot: payload).path,
                kind: finding.kind,
                scope: finding.scope,
                status: .pending,
                note: nil
            )
        }
        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        let manifest = BackupManifest(
            schemaVersion: 1,
            id: id,
            createdAt: Date(),
            application: app,
            status: .preparing,
            items: items
        )
        try save(manifest)
        return manifest
    }

    public func save(_ manifest: BackupManifest) throws {
        let directory = root.appendingPathComponent(manifest.id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    public func load(id: String) throws -> BackupManifest {
        guard isValidIdentifier(id) else {
            throw AppSleuthError.backupNotFound(id)
        }
        let url = root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw AppSleuthError.backupNotFound(id)
        }
        return try decoder.decode(BackupManifest.self, from: data)
    }

    public func validateBackupPath(_ path: String, manifestID: String) -> Bool {
        let payload = root.appendingPathComponent(manifestID, isDirectory: true)
            .appendingPathComponent("payload", isDirectory: true)
            .standardizedFileURL.path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        guard candidate.path.hasPrefix(payload + "/") else { return false }
        let resolvedPayload = URL(fileURLWithPath: payload).resolvingSymlinksInPath().path
        let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath().path
        return resolvedParent == resolvedPayload || resolvedParent.hasPrefix(resolvedPayload + "/")
    }

    private func payloadPath(for originalPath: String, payloadRoot: URL) -> URL {
        let components = URL(fileURLWithPath: originalPath).standardizedFileURL.pathComponents
            .filter { $0 != "/" && $0 != "." && $0 != ".." }
        return components.reduce(payloadRoot) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
    }
}
