import Foundation

public final class UninstallService {
    private let fileManager: FileManager
    private let safetyPolicy: SafetyPolicy
    private let backupStore: BackupStore

    public init(
        fileManager: FileManager = .default,
        safetyPolicy: SafetyPolicy = SafetyPolicy(),
        backupStore: BackupStore = BackupStore()
    ) {
        self.fileManager = fileManager
        self.safetyPolicy = safetyPolicy
        self.backupStore = backupStore
    }

    public func execute(_ plan: UninstallPlan) throws -> OperationResult {
        let running = plan.items.filter { $0.finding.kind == .process }
        guard running.isEmpty else {
            throw AppSleuthError.unsafeOperation(
                "The application still has \(running.count) running process(es). Quit it and run the command again."
            )
        }
        let selected = plan.selected
        guard !selected.isEmpty else {
            throw AppSleuthError.unsafeOperation("The plan contains no eligible items.")
        }
        for finding in selected {
            try safetyPolicy.validate(finding, for: plan.application)
        }

        var manifest = try backupStore.newManifest(for: plan.application, findings: selected)
        var movedIndices: [Int] = []
        do {
            for index in manifest.items.indices {
                let finding = selected[index]
                try safetyPolicy.validate(finding, for: plan.application)
                let item = manifest.items[index]
                let destination = URL(fileURLWithPath: item.backupPath)
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw AppSleuthError.unsafeOperation("Backup destination already exists: \(destination.path)")
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(atPath: item.originalPath, toPath: item.backupPath)
                manifest.items[index].status = .moved
                movedIndices.append(index)
                try backupStore.save(manifest)
            }
            manifest.status = .complete
            try backupStore.save(manifest)
            return OperationResult(
                backupID: manifest.id,
                moved: manifest.items.filter { $0.status == .moved }.map(\.originalPath),
                skipped: []
            )
        } catch {
            for index in movedIndices.reversed() {
                let item = manifest.items[index]
                do {
                    if !fileManager.fileExists(atPath: item.originalPath) {
                        try fileManager.createDirectory(
                            at: URL(fileURLWithPath: item.originalPath).deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try fileManager.moveItem(atPath: item.backupPath, toPath: item.originalPath)
                        manifest.items[index].status = .restored
                        manifest.items[index].note = "automatically rolled back after a later move failed"
                    }
                } catch let rollbackError {
                    manifest.items[index].note = "rollback failed: \(rollbackError.localizedDescription)"
                }
            }
            manifest.status = .partial
            try? backupStore.save(manifest)
            throw AppSleuthError.unsafeOperation(
                "Uninstall stopped safely: \(String(describing: error)). Audit backup: \(manifest.id)"
            )
        }
    }

    public func restorePreview(id: String) throws -> BackupManifest {
        try backupStore.load(id: id)
    }

    public func restore(id: String) throws -> OperationResult {
        var manifest = try backupStore.load(id: id)
        let candidates = manifest.items.indices.filter { manifest.items[$0].status == .moved }
        guard !candidates.isEmpty else {
            throw AppSleuthError.unsafeOperation("Backup has no moved items left to restore.")
        }

        var restored: [String] = []
        var skipped: [String] = []
        for index in candidates {
            let item = manifest.items[index]
            guard backupStore.validateBackupPath(item.backupPath, manifestID: manifest.id) else {
                throw AppSleuthError.unsafeOperation("Manifest contains a backup path outside its vault.")
            }
            try safetyPolicy.validateRestoreDestination(
                path: item.originalPath,
                kind: item.kind,
                scope: item.scope
            )
            guard fileManager.fileExists(atPath: item.backupPath) else {
                manifest.items[index].status = .skipped
                manifest.items[index].note = "backup payload is missing"
                skipped.append(item.originalPath)
                continue
            }
            guard !fileManager.fileExists(atPath: item.originalPath) else {
                manifest.items[index].note = "restore conflict: original path already exists"
                skipped.append(item.originalPath)
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: URL(fileURLWithPath: item.originalPath).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(atPath: item.backupPath, toPath: item.originalPath)
                manifest.items[index].status = .restored
                restored.append(item.originalPath)
            } catch {
                manifest.items[index].note = "restore failed: \(error.localizedDescription)"
                skipped.append(item.originalPath)
            }
            try backupStore.save(manifest)
        }
        manifest.status = manifest.items.allSatisfy { $0.status == .restored } ? .restored : .partial
        try backupStore.save(manifest)
        return OperationResult(backupID: manifest.id, moved: restored, skipped: skipped)
    }
}
