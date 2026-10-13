import Foundation
import CArkiv

/// One extracted copy. Editing it never updates the archive.
public struct ArchiveOpenedFile: Sendable {
    public let url: URL
    fileprivate let attempt: String
    fileprivate let relativePath: String
    fileprivate let source: URL
    fileprivate let stamp: SourceStamp
}

/// Keeps opened copies alive until the archive window/session ends. No passwords
/// are retained: extraction uses the caller's existing (possibly unlocked) snapshot.
/// prepare/discard are serialized; close cancels immediately and cleans after any
/// in-flight extraction has stopped. A locked private directory protects live
/// sessions from another process's stale-data sweep.
public final class ArchiveOpenSession: @unchecked Sendable {
    private let operation = NSLock()
    private let state = NSLock()
    private var closed = false
    private var active: ArchiveCancellation?
    private var workspace: OpaquePointer?
    private var attempts = Set<String>()
    private let temporaryParent: URL

    public init() { temporaryParent = Self.systemTemporaryParent }
    init(temporaryParent: URL) { self.temporaryParent = temporaryParent }
    deinit { if let workspace { arkiv_open_workspace_free(workspace) } }

    private static var systemTemporaryParent: URL {
        var url = FileManager.default.temporaryDirectory.standardizedFileURL
        #if os(macOS)
        // Only the standard system aliases, never arbitrary caller-provided links.
        if url.path == "/tmp" || url.path.hasPrefix("/tmp/") || url.path == "/var" || url.path.hasPrefix("/var/") {
            url = URL(fileURLWithPath: "/private" + url.path, isDirectory: true)
        }
        #endif
        return url
    }
    public static func cleanStaleTemporaryData() { arkiv_open_sweep(systemTemporaryParent.path) }
    static func cleanStaleTemporaryData(in parent: URL) { arkiv_open_sweep(parent.path) }

    /// Ambiguous duplicate names and folder/file collisions cannot be opened.
    public static func regularEntry(in snapshot: ArchiveSnapshot, path: String) -> ArchiveEntry? {
        let matches = snapshot.entries.filter { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path }
        guard matches.count == 1, let entry = matches.first, entry.kind == .file,
              entry.path == path, !path.isEmpty, !path.hasPrefix("/"), !path.utf8.contains(0),
              path.split(separator: "/", omittingEmptySubsequences: false).count <= 64,
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !snapshot.entries.contains(where: { $0.path.hasPrefix(path + "/") }) else { return nil }
        return entry
    }
    private func check(_ token: ArchiveCancellation) throws {
        state.lock(); let ended = closed; state.unlock()
        if ended || token.isCancelled { throw ArchiveFailure.cancelled }
    }
    public func prepare(_ snapshot: ArchiveSnapshot, path: String, cancellation token: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> ArchiveOpenedFile {
        operation.lock(); defer { operation.unlock() }
        state.lock(); active = token; state.unlock()
        defer { state.lock(); active = nil; state.unlock() }
        try check(token)
        guard let entry = Self.regularEntry(in: snapshot, path: path) else {
            throw ArchiveFailure.message("Select exactly one regular file to open.")
        }
        if workspace == nil { workspace = arkiv_open_workspace_new(temporaryParent.path, "session-" + UUID().uuidString) }
        guard let workspace else { throw ArchiveFailure.message("Cannot create a safe temporary workspace for Open.") }
        let attempt = "file-" + UUID().uuidString
        guard arkiv_open_workspace_attempt(workspace, attempt) == 0 else {
            throw ArchiveFailure.message("Cannot create a temporary file workspace.")
        }
        let root = URL(fileURLWithPath: String(cString: arkiv_open_workspace_path(workspace)), isDirectory: true)
        do {
            let report = try LibArchiveEngine().extractReporting(snapshot, ids: [entry.id],
                into: root.appendingPathComponent(attempt, isDirectory: true), cancellation: token, progress: progress)
            try check(token)
            let relative = attempt + "/" + report.url.lastPathComponent + "/" + entry.path
            guard report.warnings.isEmpty, arkiv_open_workspace_regular(workspace, relative) != 0 else {
                throw ArchiveFailure.message("The selected file could not be safely opened.")
            }
            attempts.insert(attempt)
            return ArchiveOpenedFile(url: root.appendingPathComponent(relative), attempt: attempt,
                                     relativePath: relative, source: snapshot.url, stamp: snapshot.stamp)
        } catch {
            arkiv_open_workspace_discard(workspace, attempt)
            throw error
        }
    }
    /// Recheck immediately before handing the URL to the default application.
    public func validateForLaunch(_ file: ArchiveOpenedFile, cancellation: ArchiveCancellation) throws {
        operation.lock(); defer { operation.unlock() }
        try check(cancellation)
        guard let workspace, attempts.contains(file.attempt),
              arkiv_open_workspace_regular(workspace, file.relativePath) != 0 else {
            throw ArchiveFailure.message("The temporary file is no longer available.")
        }
        guard try SourceStamp(file.source) == file.stamp else {
            throw ArchiveFailure.message("Archive changed since it was opened. Reopen it.")
        }
    }
    public func discard(_ file: ArchiveOpenedFile) {
        operation.lock(); defer { operation.unlock() }
        if attempts.remove(file.attempt) != nil, let workspace { arkiv_open_workspace_discard(workspace, file.attempt) }
    }
    public func close() {
        state.lock(); closed = true; active?.cancel(); state.unlock()
        if operation.try() { cleanup(); operation.unlock() }
        else {
            DispatchQueue.global(qos: .utility).async { [self] in
                operation.lock(); defer { operation.unlock() }
                cleanup()
            }
        }
    }
    private func cleanup() {
        if let workspace { arkiv_open_workspace_free(workspace) }
        workspace = nil; attempts.removeAll()
    }
}
