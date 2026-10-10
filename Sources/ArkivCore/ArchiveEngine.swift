import Foundation
import CArkiv

public final class ArchiveCancellation: @unchecked Sendable {
    let pointer: OpaquePointer
    public init() { pointer = arkiv_cancel_new()! }
    deinit { arkiv_cancel_free(pointer) }
    public func cancel() { arkiv_cancel_set(pointer) }
}
public struct ArchiveProgress: Sendable {
    public let files: UInt64
    public let bytes: UInt64
}
public enum ArchiveFailure: Error, LocalizedError {
    case message(String), cancelled, passwordRequired, wrongPassword
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .passwordRequired: return "Enter the archive password."
        case .wrongPassword: return "The password is incorrect or the encrypted archive is damaged."
        case .cancelled: return "Operation cancelled."
        }
    }
}
public struct ArchiveSnapshot: Sendable {
    public let url: URL
    public let entries: [ArchiveEntry]
    let stamp: SourceStamp
    let unlocked: UnlockedArchive?
    var backingURL: URL { unlocked?.url ?? url }
    public var index: ArchiveIndex { ArchiveIndex(entries: entries) }
}
func validateArchivePassword(_ password: String?) throws {
    if let password, password.isEmpty || password.utf8.count > 1024 || password.utf8.contains(0) {
        throw ArchiveFailure.message("Use a password of 1–1024 UTF-8 bytes without null characters.")
    }
}
/// The private plaintext spool is retained only by live snapshots, never the password.
final class UnlockedArchive: @unchecked Sendable {
    let directory: URL
    let url: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("arkiv-unlocked-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("contents.zip")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
struct SourceStamp: Equatable, Sendable {
    let size: UInt64
    let modified: Date
    let inode: UInt64
    init(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw ArchiveFailure.message("Choose a regular archive file.")
        }
        self.size = size.uint64Value; modified = date; self.inode = inode.uint64Value
    }
}
public protocol ArchiveEngine: Sendable {
    func inspect(_ url: URL, cancellation: ArchiveCancellation) throws -> ArchiveSnapshot
    func extract(_ snapshot: ArchiveSnapshot, ids: [Int64]?, into parent: URL,
                 cancellation: ArchiveCancellation,
                 progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL
}
private final class EntryCollector {
    var entries: [ArchiveEntry] = []
}
private final class ProgressReceiver {
    let callback: @Sendable (ArchiveProgress) -> Void
    init(_ callback: @escaping @Sendable (ArchiveProgress) -> Void) { self.callback = callback }
}
public struct LibArchiveEngine: ArchiveEngine {
    public init() {}
    public static var version: String { String(cString: arkiv_backend_version()) }
    // Conservative initial safety budgets. No silent unlimited mode.
    private var limits: arkiv_limits { arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024) }
    private func check(_ result: Int32, _ error: [CChar]) throws {
        if result == 4 { throw ArchiveFailure.passwordRequired }
        if result == 5 { throw ArchiveFailure.wrongPassword }
        if result == 2 { throw ArchiveFailure.cancelled }
        if result != 0 { throw ArchiveFailure.message(String(cString: error)) }
    }
    public func inspect(_ url: URL, cancellation: ArchiveCancellation) throws -> ArchiveSnapshot {
        try inspect(url, cancellation: cancellation, password: nil)
    }
    public func inspect(_ url: URL, cancellation: ArchiveCancellation, password: String?) throws -> ArchiveSnapshot {
        try validateArchivePassword(password)
        let stamp = try SourceStamp(url)
        var unlocked: UnlockedArchive?
        var sevenURL = url.standardizedFileURL
        #if os(macOS)
        // Match creation's trusted system aliases without resolving arbitrary links.
        if sevenURL.path == "/var" || sevenURL.path.hasPrefix("/var/") || sevenURL.path == "/tmp" || sevenURL.path.hasPrefix("/tmp/") {
            sevenURL = URL(fileURLWithPath: "/private" + sevenURL.path)
        }
        #endif
        if arkiv_is_seven(sevenURL.path) != 0 {
            let session = try UnlockedArchive()
            let result = arkiv_unlock_seven(sevenURL.path, session.url.path, password, cancellation.pointer)
            try check(result, Array("Cannot safely read the 7z archive.\0".utf8).map { CChar(bitPattern: $0) })
            unlocked = session
        }
        let backing = unlocked?.url ?? url
        let collector = EntryCollector()
        let context = Unmanaged.passUnretained(collector).toOpaque()
        var error = [CChar](repeating: 0, count: 256)
        let result = arkiv_list(backing.path, limits, cancellation.pointer, { context, id, path, size, kind in
            guard let context, let path, let name = String(validatingUTF8: path) else { return 1 }
            let collector = Unmanaged<EntryCollector>.fromOpaque(context).takeUnretainedValue()
            collector.entries.append(ArchiveEntry(id: id, path: name, size: size,
                kind: kind == 1 ? .file : kind == 2 ? .directory : .unsupported))
            return 0
        }, context, &error, error.count)
        try check(result, error)
        guard try SourceStamp(url) == stamp else { throw ArchiveFailure.message("Archive changed while reading. Reopen it.") }
        return ArchiveSnapshot(url: url, entries: collector.entries, stamp: stamp, unlocked: unlocked)
    }
    public func extract(_ snapshot: ArchiveSnapshot, ids: [Int64]?, into parent: URL,
                        cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        if let ids, ids.isEmpty { throw ArchiveFailure.message("Select an entry to extract.") }
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed since it was opened. Reopen it.")
        }
        let fresh = try inspect(snapshot.backingURL, cancellation: cancellation)
        guard fresh.entries == snapshot.entries else {
            throw ArchiveFailure.message("Archive contents changed. Reopen it.")
        }
        let manager = FileManager.default
        let staging = parent.appendingPathComponent(".arkiv-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        let receiver = ProgressReceiver(progress)
        let retainedReceiver = Unmanaged.passRetained(receiver)
        defer { retainedReceiver.release() }
        let context = retainedReceiver.toOpaque()
        var error = [CChar](repeating: 0, count: 256)
        let callback: arkiv_progress_callback = { context, files, bytes in
            guard let context else { return }
            Unmanaged<ProgressReceiver>.fromOpaque(context).takeUnretainedValue()
                .callback(ArchiveProgress(files: files, bytes: bytes))
        }
        let result: Int32
        if let ids {
            result = ids.sorted().withUnsafeBufferPointer { buffer in
                arkiv_extract(snapshot.backingURL.path, staging.path, buffer.baseAddress, buffer.count,
                    limits, cancellation.pointer, callback, context, &error, error.count)
            }
        } else {
            result = arkiv_extract(snapshot.backingURL.path, staging.path, nil, 0,
                limits, cancellation.pointer, callback, context, &error, error.count)
        }
        try check(result, error)
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed during extraction. Output discarded.")
        }
        let destination = parent.appendingPathComponent("Arkiv Extracted " + UUID().uuidString, isDirectory: true)
        try manager.moveItem(at: staging, to: destination)
        return destination
    }
}

public enum SevenZipBackend {
    public static var loadedLibraryURL: URL { URL(fileURLWithPath: String(cString: arkiv_seven_loaded_library())) }
}
