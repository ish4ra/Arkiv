import Foundation
import CArkiv

public final class ArchiveCancellation: @unchecked Sendable {
    let pointer: OpaquePointer
    public init() { pointer = arkiv_cancel_new()! }
    deinit { arkiv_cancel_free(pointer) }
    public func cancel() { arkiv_cancel_set(pointer) }
    public var isCancelled: Bool { arkiv_cancel_is_set(pointer) != 0 }
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
    public internal(set) var sevenEncryptionPolicy: SevenZipEncryptionPolicy? = nil
    public internal(set) var metadata: ArchiveMetadata? = nil
    var sourceLease: ArchiveOpenedFileLease? = nil
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
        url = directory.appendingPathComponent("contents.tar")
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
    func test(_ url: URL, cancellation: ArchiveCancellation, password: String?,
              progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> ArchiveIntegrityResult
    func inspect(_ url: URL, cancellation: ArchiveCancellation) throws -> ArchiveSnapshot
    func extract(_ snapshot: ArchiveSnapshot, ids: [Int64]?, into parent: URL,
                 cancellation: ArchiveCancellation,
                 progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL
}
private final class EntryCollector {
    var entries: [ArchiveEntry] = []
}
public struct ArchiveExtractionWarning: Equatable, Sendable {
    public let path: String
    public let reason: String
}
public struct ArchiveExtractionReport: Sendable {
    public let url: URL
    public let warnings: [ArchiveExtractionWarning]
}
private final class ProgressReceiver {
    var warnings: [ArchiveExtractionWarning] = []
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
    /// Content recognition only. Recognized but malformed containers still need
    /// inspection, and must not silently fall back to a default archive app.
    public func isArchiveCandidate(_ url: URL, cancellation: ArchiveCancellation) throws -> Bool {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        _ = try SourceStamp(url)
        let result = arkiv_archive_candidate(url.path)
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        guard result >= 0 else { throw ArchiveFailure.message("Cannot read the temporary file.") }
        return result != 0
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
        var detectedFormat = [CChar](repeating:0,count:128)
        let result = arkiv_list_metadata(backing.path, limits, cancellation.pointer, { context, id, path, size, kind in
            guard let context, let path, let name = String(validatingUTF8: path) else { return 1 }
            let collector = Unmanaged<EntryCollector>.fromOpaque(context).takeUnretainedValue()
            collector.entries.append(ArchiveEntry(id: id, path: name, size: size,
                kind: kind == 1 ? .file : kind == 2 ? .directory : kind == 3 ? .symbolicLink : kind == 4 ? .hardLink : .unsupported))
            return 0
        }, context, &error, error.count, &detectedFormat, detectedFormat.count)
        try check(result, error)
        guard try SourceStamp(url) == stamp else { throw ArchiveFailure.message("Archive changed while reading. Reopen it.") }
        var snapshot = ArchiveSnapshot(url: url, entries: collector.entries, stamp: stamp, unlocked: unlocked)
        if unlocked != nil, password != nil {
            // Non-secret UI eligibility only. Every edit still asks for a fresh
            // password and validates the pinned original; never retain it here.
            snapshot.sevenEncryptionPolicy = try? SevenZipPolicyInspector().inspect(snapshot, password: password, cancellation: cancellation)
            if cancellation.isCancelled { throw ArchiveFailure.cancelled }
            guard try SourceStamp(url) == stamp else { throw ArchiveFailure.message("Archive changed while inspecting encryption policy.") }
        }
        var methods: String?, solid: Bool?, dataEncrypted: Bool?, headersEncrypted: Bool?
        if unlocked != nil {
            let handle = try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            var flags: UInt32 = 0
            var summary = [CChar](repeating:0,count:2048)
            if arkiv_seven_metadata(handle.fileDescriptor,password,&flags,&summary,summary.count) == 0 {
                let text = String(cString:summary); methods = text.isEmpty ? nil : text
                solid = flags & 32 != 0; dataEncrypted = flags & 1 != 0; headersEncrypted = flags & 2 != 0
            }
        }
        let formatName = String(cString:detectedFormat)
        snapshot.metadata = ArchiveMetadata(url:url,physicalSize:stamp.size,entries:collector.entries,
            format:unlocked != nil ? "7z" : (formatName.isEmpty ? nil : formatName),methods:methods,
            solid:solid,dataEncrypted:dataEncrypted,headersEncrypted:headersEncrypted)
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        guard try SourceStamp(url) == stamp else { throw ArchiveFailure.message("Archive changed while reading metadata. Reopen it.") }
        return snapshot
    }
    public func extract(_ snapshot: ArchiveSnapshot, ids: [Int64]?, into parent: URL,
                        cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        try extractReporting(snapshot, ids: ids, into: parent, cancellation: cancellation, progress: progress).url
    }
    public func extractReporting(_ snapshot: ArchiveSnapshot, ids: [Int64]?, into parent: URL,
                                 includeHardlinkDependencies: Bool = false,
                                 cancellation: ArchiveCancellation,
                                 progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> ArchiveExtractionReport {
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
        let warning: arkiv_warning_callback = { context, path, reason in
            guard let context, let path, let reason else { return }
            Unmanaged<ProgressReceiver>.fromOpaque(context).takeUnretainedValue().warnings.append(
                ArchiveExtractionWarning(path: String(cString: path), reason: String(cString: reason)))
        }
        let result: Int32
        if let ids {
            result = ids.sorted().withUnsafeBufferPointer { buffer in
                let extract = includeHardlinkDependencies ? arkiv_extract_promised : arkiv_extract_with_warnings
                return extract(snapshot.backingURL.path, staging.path, buffer.baseAddress, buffer.count,
                    limits, cancellation.pointer, callback, warning, context, &error, error.count)
            }
        } else {
            result = arkiv_extract_with_warnings(snapshot.backingURL.path, staging.path, nil, 0,
                limits, cancellation.pointer, callback, warning, context, &error, error.count)
        }
        try check(result, error)
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed during extraction. Output discarded.")
        }
        let destination = parent.appendingPathComponent("Arkiv Extracted " + UUID().uuidString, isDirectory: true)
        try manager.moveItem(at: staging, to: destination)
        return ArchiveExtractionReport(url: destination, warnings: receiver.warnings)
    }
}

public enum SevenZipBackend {
    public static var loadedLibraryURL: URL { URL(fileURLWithPath: String(cString: arkiv_seven_loaded_library())) }
}

public enum ArchiveIntegrityState: String, Sendable {
    case ok = "OK", warning = "Warning", corrupt = "Corrupt", crcError = "CRC Error"
    case wrongPassword = "Wrong Password", unsupportedMethod = "Unsupported Method"
}
public struct ArchiveIntegrityResult: Sendable {
    public let state: ArchiveIntegrityState
    public let detail: String
}
extension LibArchiveEngine {
    /// Verifies the original archive, including encrypted data, without extraction or publication.
    public func test(_ url: URL, cancellation: ArchiveCancellation, password: String? = nil,
                     progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> ArchiveIntegrityResult {
        try validateArchivePassword(password)
        let stamp = try SourceStamp(url)
        let receiver = ProgressReceiver(progress)
        let retained = Unmanaged.passRetained(receiver)
        defer { retained.release() }
        var error = [CChar](repeating: 0, count: 256)
        var source = url.standardizedFileURL
        #if os(macOS)
        if source.path.hasPrefix("/var/") || source.path.hasPrefix("/tmp/") { source = URL(fileURLWithPath: "/private" + source.path) }
        #endif
        let code = arkiv_test(source.path, password, limits, cancellation.pointer, { context, files, bytes in
            guard let context else { return }
            Unmanaged<ProgressReceiver>.fromOpaque(context).takeUnretainedValue().callback(ArchiveProgress(files: files, bytes: bytes))
        }, retained.toOpaque(), &error, error.count)
        guard try SourceStamp(url) == stamp else { throw ArchiveFailure.message("Archive changed during testing.") }
        let state: ArchiveIntegrityState
        let detail: String
        switch code {
        case 0: state = .ok; detail = "All archive entries were decoded and their available checksums verified."
        case 9: state = .warning; detail = "TAR structure and all payload bytes are readable. TAR has no payload checksum; content integrity cannot be confirmed."
        case 6: state = .corrupt; detail = "Archive structure or data is damaged."
        case 7: state = .crcError; detail = "An archive checksum does not match the decoded data."
        case 8: state = .unsupportedMethod; detail = "The compression or encryption method is unsupported."
        case 5: throw ArchiveFailure.wrongPassword
        default: try check(code, error); throw ArchiveFailure.message("Unexpected integrity result.")
        }
        return ArchiveIntegrityResult(state: state, detail: detail)
    }
}
