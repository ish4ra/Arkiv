import Foundation
import CArkiv

/// Add is deliberately separate from ZIP-only Delete, Rename, Replace and drag-in.
public enum ArchiveAdditionCapability: Equatable, Sendable {
    case zip, sevenZip, readOnly(String)
    public var isAvailable: Bool {
        switch self { case .zip, .sevenZip: return true; case .readOnly: return false }
    }
    public var reason: String? {
        if case .readOnly(let reason) = self { return reason }; return nil
    }
}

public struct ArchiveAdditionUpdater: Sendable {
    public init() {}
    public func capability(for snapshot: ArchiveSnapshot) -> ArchiveAdditionCapability {
        if ArchiveZIPUpdater().canAdd(to: snapshot) { return .zip }
        guard (try? SourceStamp(snapshot.url)) == snapshot.stamp else {
            return .readOnly("Archive changed since it was opened. Reopen it.")
        }
        guard (try? Self.validateSevenPaths(snapshot)) != nil else {
            return .readOnly("Ambiguous or unsupported archive paths cannot safely be updated.")
        }
        var url = snapshot.url.standardizedFileURL
        #if os(macOS)
        if url.path.hasPrefix("/var/") || url.path.hasPrefix("/tmp/") {
            url = URL(fileURLWithPath: "/private" + url.path)
        }
        #endif
        var error = [CChar](repeating: 0, count: 256)
        guard let transaction = arkiv_seven_begin(url.path, &error, error.count) else {
            return .readOnly("Add supports ordinary ZIP and plain, non-solid single 7z archives. Encrypted, multipart and unusual archives remain read-only.")
        }
        arkiv_zip_end(transaction)
        return .sevenZip
    }
    /// Adds at the archive root for 7z. ZIP retains its existing folder-aware API.
    @discardableResult
    public func add(sources: [URL], to snapshot: ArchiveSnapshot, folder: String = "", cancellation: ArchiveCancellation,
                    progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        switch capability(for: snapshot) {
        case .zip:
            return try ArchiveZIPUpdater().add(sources: sources, to: snapshot, folder: folder, cancellation: cancellation, progress: progress)
        case .sevenZip:
            guard folder.isEmpty else { throw ArchiveFailure.message("7z additions are supported only at the archive root.") }
            return try ArchiveZIPUpdater().addSeven(sources: sources, to: snapshot, cancellation: cancellation, progress: progress)
        case .readOnly(let reason): throw ArchiveFailure.message(reason)
        }
    }
    // Include implicit directories, and compare raw spellings by UTF-8 bytes:
    // Swift String equality intentionally equates NFC and NFD representations.
    static func validateSevenPaths(_ snapshot: ArchiveSnapshot) throws {
        struct Node { let spelling: [UInt8]; let directory: Bool; var explicit: Bool }
        var nodes: [String: Node] = [:]
        for entry in snapshot.entries {
            guard entry.kind == .file || entry.kind == .directory else {
                throw ArchiveFailure.message("Unsupported 7z entry type.")
            }
            var path = entry.path
            if entry.kind == .directory && path.hasSuffix("/") { path.removeLast() }
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, path.utf8.count <= 4096, parts.count <= 256,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
                throw ArchiveFailure.message("Unsafe 7z entry path.")
            }
            for n in 1...parts.count {
                let spelling = parts.prefix(n).joined(separator: "/")
                let key = spelling.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                let explicit = n == parts.count
                let directory = !explicit || entry.kind == .directory
                if var old = nodes[key] {
                    guard old.spelling == Array(spelling.utf8), old.directory == directory, !(old.explicit && explicit) else {
                        throw ArchiveFailure.message("Ambiguous 7z entry paths.")
                    }
                    old.explicit = old.explicit || explicit; nodes[key] = old
                } else { nodes[key] = Node(spelling: Array(spelling.utf8), directory: directory, explicit: explicit) }
            }
        }
    }
}
