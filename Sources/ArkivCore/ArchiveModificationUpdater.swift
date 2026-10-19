import Foundation

/// Transactional item edits. Replace and Finder drag-in remain ZIP-only APIs.
public struct ArchiveModificationUpdater: Sendable {
    public init() {}
    public func capability(for snapshot: ArchiveSnapshot) -> ArchiveAdditionCapability {
        ArchiveAdditionUpdater().capability(for: snapshot)
    }
    @discardableResult
    public func delete(paths: Set<String>, from snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        switch capability(for: snapshot) {
        case .zip: return try ArchiveZIPUpdater().delete(paths: paths, from: snapshot, cancellation: cancellation, progress: progress)
        case .sevenZip: return try ArchiveZIPUpdater().deleteSeven(paths: paths, from: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }
    @discardableResult
    public func rename(path: String, to name: String, in snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        switch capability(for: snapshot) {
        case .zip: return try ArchiveZIPUpdater().rename(path: path, to: name, in: snapshot, cancellation: cancellation, progress: progress)
        case .sevenZip: return try ArchiveZIPUpdater().renameSeven(path: path, to: name, in: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }

}
