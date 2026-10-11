import Foundation
import CArkiv

public struct ArchiveDragItem: Equatable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
}

/// One drag owns its snapshot (and decrypted spool), until the last promise is released.
/// Call write serially. Merely constructing a session does no extraction or disk writes.
public final class ArchiveDragSession {
    public let items: [ArchiveDragItem]
    private var snapshot: ArchiveSnapshot?
    private let cancellation = ArchiveCancellation()
    private var staging: URL?
    private var extracted: URL?
    private var completed = Set<String>()
    private var failure: Error?
    private let lock = NSRecursiveLock()
    private var expiry: DispatchWorkItem?
    private var expiryGeneration = 0
    var idleTimeout: TimeInterval = 300
    private var warnings: [ArchiveExtractionWarning] = []

    public init(snapshot: ArchiveSnapshot, paths: Set<String>) throws {
        let index = snapshot.index
        let rows = paths.sorted().compactMap { index.row(at: $0) }
        items = rows.filter { row in
            !rows.contains { $0.isDirectory && row.path.hasPrefix($0.path + "/") }
        }.map { ArchiveDragItem(path: $0.path, name: $0.name, isDirectory: $0.isDirectory) }
        guard !items.isEmpty else { throw ArchiveFailure.message("Select an entry to drag.") }
        self.snapshot = snapshot
    }
    deinit { expiry?.cancel(); cleanup() }
    public func requestCancellation() { cancellation.cancel() }
    public func cancel() {
        cancellation.cancel()
        if lock.try() {
            cleanup(); lock.unlock()
        } else {
            DispatchQueue.global(qos: .utility).async { [self] in
                lock.lock(); defer { lock.unlock() }
                cleanup()
            }
        }
    }
    private func invalidateExpiry() {
        expiryGeneration += 1
        expiry?.cancel(); expiry = nil
    }
    private func expireStaging() {
        invalidateExpiry()
        let generation = expiryGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.expiryGeneration == generation, self.completed.count < self.items.count else { return }
            self.failure = ArchiveFailure.message("The file promise expired. Drag the remaining items again.")
            self.cancellation.cancel()
            self.cleanup()
        }
        expiry = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }
    private func cleanup() {
        invalidateExpiry()
        if let staging { try? FileManager.default.removeItem(at: staging) }
        staging = nil; extracted = nil; snapshot = nil
    }
    public func write(item: ArchiveDragItem, to destination: URL) throws -> ArchiveExtractionReport {
        lock.lock(); defer { lock.unlock() }
        guard items.contains(item), !completed.contains(item.path) else {
            throw ArchiveFailure.message("The file promise is invalid or already fulfilled.")
        }
        if let failure { throw failure }
        invalidateExpiry()
        do {
            guard destination.isFileURL, destination.host == nil || destination.host == "" || destination.host == "localhost",
                  destination.query == nil, destination.fragment == nil else {
                throw ArchiveFailure.message("Choose a local destination.")
            }
            var parent = destination.deletingLastPathComponent().standardizedFileURL
            #if os(macOS)
            if parent.path == "/tmp" || parent.path.hasPrefix("/tmp/") || parent.path == "/var" || parent.path.hasPrefix("/var/") {
                parent = URL(fileURLWithPath: "/private" + parent.path, isDirectory: true)
            }
            #endif
            if extracted == nil {
                guard let snapshot else { throw ArchiveFailure.cancelled }
                let privateRoot = parent.appendingPathComponent(".arkiv-drag-" + UUID().uuidString, isDirectory: true)
                var error = [CChar](repeating: 0, count: 256)
                guard arkiv_prepare_promise_staging(parent.path, privateRoot.lastPathComponent, &error, error.count) == 0 else {
                    throw ArchiveFailure.message(String(cString: error))
                }
                staging = privateRoot
                let report = try LibArchiveEngine().extractReporting(snapshot,
                    ids: snapshot.index.entryIDs(for: Set(items.filter { !completed.contains($0.path) }.map(\.path))), into: privateRoot, includeHardlinkDependencies: true,
                    cancellation: cancellation, progress: { _ in })
                extracted = report.url; warnings = report.warnings
            }
            guard let extracted else { throw ArchiveFailure.message("Extracted output is unavailable.") }
            var error = [CChar](repeating: 0, count: 256)
            let result = arkiv_publish_promised(extracted.path, item.path, parent.path,
                destination.lastPathComponent, cancellation.pointer, &error, error.count)
            if result == 2 { throw ArchiveFailure.cancelled }
            guard result == 0 else { throw ArchiveFailure.message(String(cString: error)) }
            completed.insert(item.path)
            let report = ArchiveExtractionReport(url: destination, warnings: warnings)
            warnings = []
            if completed.count == items.count { cleanup() } else { expireStaging() }
            return report
        } catch {
            failure = error; cleanup(); throw error
        }
    }
}
