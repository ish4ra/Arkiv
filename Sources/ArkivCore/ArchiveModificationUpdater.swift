import Foundation

/// Transactional item edits. Finder drag-in remains ZIP-only.
public struct ArchiveModificationUpdater: Sendable {
    public init() {}
    public func capability(for snapshot: ArchiveSnapshot) -> ArchiveAdditionCapability {
        ArchiveAdditionUpdater().capability(for: snapshot)
    }
    @discardableResult
    public func replace(path: String, with source: URL, in snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        switch capability(for: snapshot) {
        case .zip: return try ArchiveZIPUpdater().replace(path: path, with: source, in: snapshot, cancellation: cancellation, progress: progress)
        case .sevenZip: return try ArchiveZIPUpdater().replaceSeven(path: path, with: source, in: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }
    public func canDeleteEncrypted(_ snapshot: ArchiveSnapshot) -> Bool {
        snapshot.sevenEncryptionPolicy?.eligibleForEncryptedDeletion == true &&
            (try? SourceStamp(snapshot.url)) == snapshot.stamp
    }
    @discardableResult
    public func delete(paths: Set<String>, from snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        if canDeleteEncrypted(snapshot) {
            guard let password else { throw ArchiveFailure.passwordRequired }
            let policy = try SevenZipPolicyInspector().inspect(snapshot, password: password, cancellation: cancellation)
            guard policy.eligibleForEncryptedDeletion else {
                throw ArchiveFailure.message(policy.readOnlyReason)
            }
            return try ArchiveZIPUpdater().deleteSeven(paths: paths, from: snapshot, password: password, cancellation: cancellation, progress: progress)
        }
        switch capability(for: snapshot) {
        case .zip: return try ArchiveZIPUpdater().delete(paths: paths, from: snapshot, cancellation: cancellation, progress: progress)
        case .sevenZip: return try ArchiveZIPUpdater().deleteSeven(paths: paths, from: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }
    public func canRenameEncrypted(_ snapshot: ArchiveSnapshot) -> Bool {
        snapshot.sevenEncryptionPolicy?.eligibleForEncryptedRenaming == true &&
            (try? SourceStamp(snapshot.url)) == snapshot.stamp
    }
    @discardableResult
    public func rename(path: String, to name: String, in snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        if canRenameEncrypted(snapshot) {
            guard let password else { throw ArchiveFailure.passwordRequired }
            let policy = try SevenZipPolicyInspector().inspect(snapshot, password: password, cancellation: cancellation)
            guard policy.eligibleForEncryptedRenaming else { throw ArchiveFailure.message(policy.readOnlyReason) }
            return try ArchiveZIPUpdater().renameSeven(path: path, to: name, in: snapshot, password: password, cancellation: cancellation, progress: progress)
        }
        switch capability(for: snapshot) {
        case .zip: return try ArchiveZIPUpdater().rename(path: path, to: name, in: snapshot, cancellation: cancellation, progress: progress)
        case .sevenZip: return try ArchiveZIPUpdater().renameSeven(path: path, to: name, in: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }

}
