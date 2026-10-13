import Foundation
import CArkiv

private final class ZIPAdditionProgress {
    let callback: @Sendable (ArchiveProgress) -> Void
    init(_ callback: @escaping @Sendable (ArchiveProgress) -> Void) { self.callback = callback }
}

/// Adds, deletes or renames items without recompressing retained entry data.
/// ZIP64, encrypted, multipart, and ambiguous metadata/layouts remain read-only.
public struct ArchiveZIPUpdater: Sendable {
    public init() {}
    private func canonical(_ url: URL) -> URL {
        let url = url.standardizedFileURL
        #if os(macOS)
        if url.path.hasPrefix("/var/") || url.path.hasPrefix("/tmp/") {
            return URL(fileURLWithPath: "/private" + url.path)
        }
        #endif
        return url
    }
    public func canAdd(to snapshot: ArchiveSnapshot) -> Bool {
        guard snapshot.unlocked == nil, snapshot.entries.allSatisfy({ $0.kind == .file || $0.kind == .directory }), (try? SourceStamp(snapshot.url)) == snapshot.stamp else { return false }
        var error = [CChar](repeating: 0, count: 256)
        guard let transaction = arkiv_zip_begin(canonical(snapshot.url).path, &error, error.count) else { return false }
        arkiv_zip_end(transaction)
        return true
    }
    private func deletionPlan(_ snapshot: ArchiveSnapshot, paths: Set<String>) throws -> [UInt8] {
        let index = snapshot.index
        guard !paths.isEmpty, paths.allSatisfy({ index.row(at: $0) != nil }),
              snapshot.entries.enumerated().allSatisfy({ $0.element.id == Int64($0.offset) }) else {
            throw ArchiveFailure.message("Choose archive items to delete.")
        }
        return snapshot.entries.map { entry in
            let path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return paths.contains { selected in
                path == selected || (index.row(at: selected)?.isDirectory == true && path.hasPrefix(selected + "/"))
            } ? 0 : 1
        }
    }
    /// Renames one row within its existing parent, including every directory descendant.
    @discardableResult
    public func rename(path: String, to name: String, in snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let row = snapshot.index.row(at: path),
              snapshot.entries.enumerated().allSatisfy({ $0.element.id == Int64($0.offset) }) else {
            throw ArchiveFailure.message("Choose one archive item and enter a valid name without separators or control characters.")
        }
        var seen = Set<String>()
        let index = snapshot.index
        for entry in snapshot.entries {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            let normalized = parts.joined(separator: "/")
            guard entry.path == normalized || (entry.kind == .directory && entry.path == normalized + "/"),
                  seen.insert(normalized).inserted,
                  parts.dropLast().indices.allSatisfy({ index.row(at: parts.prefix($0 + 1).joined(separator: "/"))?.isDirectory == true }) else {
                throw ArchiveFailure.message("Ambiguous archive paths cannot safely be renamed.")
            }
        }
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        func key(_ value: String) -> String {
            value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        guard !snapshot.index.children(of: parent).contains(where: { $0.path != path && key($0.name) == key(name) }) else {
            throw ArchiveFailure.message("An item named ‘\(name)’ already exists in this archive folder.")
        }
        let destination = parent.isEmpty ? name : parent + "/" + name
        let names: [String?] = snapshot.entries.map { entry in
            let normalized = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard normalized == path || (row.isDirectory && normalized.hasPrefix(path + "/")) else { return nil }
            return destination + String(entry.path.dropFirst(path.count))
        }
        guard names.contains(where: { $0 != nil }), names.compactMap({ $0 }).allSatisfy({ $0.utf8.count <= 65535 }) else {
            throw ArchiveFailure.message("The renamed path is too long or the selection is invalid.")
        }
        return try update(sources: [], snapshot: snapshot, folder: "", plan: nil, renameNames: names, cancellation: cancellation, progress: progress)
    }
    @discardableResult
    public func delete(paths: Set<String>, from snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try update(sources: [], snapshot: snapshot, folder: "", plan: deletionPlan(snapshot, paths: paths), cancellation: cancellation, progress: progress)
    }
    @discardableResult
    public func add(sources: [URL], to snapshot: ArchiveSnapshot, folder: String = "", cancellation: ArchiveCancellation,
                    progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try update(sources: sources, snapshot: snapshot, folder: folder, plan: nil, cancellation: cancellation, progress: progress)
    }
    private func update(sources: [URL], snapshot: ArchiveSnapshot, folder: String, plan: [UInt8]?, renameNames: [String?]? = nil, cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        guard snapshot.unlocked == nil, snapshot.entries.allSatisfy({ $0.kind == .file || $0.kind == .directory }), try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed since it was opened. Reopen it.")
        }
        let archive = canonical(snapshot.url)
        var error = [CChar](repeating: 0, count: 256)
        guard let transaction = arkiv_zip_begin(archive.path, &error, error.count) else {
            throw ArchiveFailure.message(String(cString: error))
        }
        defer { arkiv_zip_end(transaction) }
        // Recheck after pinning the source descriptor, before any source work.
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed since it was opened. Reopen it.")
        }
        func key(_ value: String) -> String {
            value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let components = folder.split(separator: "/", omittingEmptySubsequences: false)
        guard folder.isEmpty || (components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }
            && snapshot.index.row(at: folder)?.isDirectory == true) else {
            throw ArchiveFailure.message("Choose an existing archive folder.")
        }
        var roots = Set(snapshot.index.children(of: folder).map { key($0.name) })
        for sourceURL in sources {
            let source = canonical(sourceURL)
            guard roots.insert(key(source.lastPathComponent)).inserted else {
                throw ArchiveFailure.message("An item named ‘\(source.lastPathComponent)’ already exists in the destination archive folder. Rename the source item before adding it.")
            }
            guard canonical(source) != archive, (try? SourceStamp(source).inode) != snapshot.stamp.inode else {
                throw ArchiveFailure.message("An archive cannot be added to itself.")
            }
        }
        let manager = FileManager.default
        let stage = archive.deletingLastPathComponent().appendingPathComponent(".arkiv-add-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        let additions = try plan == nil && renameNames == nil ? ArchiveCreator().create(ArchiveCreationRequest(sources: sources, destination: stage, name: "additions"),
                                                    archiveFolder: folder, cancellation: cancellation, progress: progress) : nil
        let receiver = ZIPAdditionProgress(progress)
        let retained = Unmanaged.passRetained(receiver)
        defer { retained.release() }
        let callback: arkiv_progress_callback = { context, files, bytes in
            guard let context else { return }
            Unmanaged<ZIPAdditionProgress>.fromOpaque(context).takeUnretainedValue().callback(ArchiveProgress(files: files, bytes: bytes))
        }
        let result: Int32
        if let renameNames {
            let old = snapshot.entries.map { strdup($0.path) }
            let renamed = renameNames.map { $0.flatMap { strdup($0) } }
            defer { old.forEach { free($0) }; renamed.forEach { free($0) } }
            guard old.allSatisfy({ $0 != nil }), zip(renameNames, renamed).allSatisfy({ $0.0 == nil || $0.1 != nil }) else {
                throw ArchiveFailure.message("Not enough memory to prepare the ZIP rename. Original archive unchanged.")
            }
            let oldPointers = old.map { $0.map { UnsafePointer<CChar>($0) } }
            let newPointers = renamed.map { $0.map { UnsafePointer<CChar>($0) } }
            result = arkiv_zip_prepare_rename(transaction, oldPointers, newPointers, renameNames.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else if let plan {
            result = arkiv_zip_prepare_delete(transaction, plan, plan.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else {
            result = arkiv_zip_prepare(transaction, additions!.path, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        }
        func check(_ result: Int32) throws {
            if result == 2 { throw ArchiveFailure.cancelled }
            if result != 0 { throw ArchiveFailure.message(String(cString: error)) }
        }
        try check(result)
        #if os(macOS)
        var coordinationError: NSError?
        var commitResult: Int32 = 1
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: archive, options: .forReplacing, error: &coordinationError) { coordinated in
            guard canonical(coordinated) == archive else { return }
            commitResult = arkiv_zip_commit(transaction, cancellation.pointer, &error, error.count)
        }
        // Once rename succeeds, late cancellation/coordination errors cannot undo success.
        if commitResult != 0 {
            if let coordinationError { throw coordinationError }
            try check(commitResult)
        }
        #else
        try check(arkiv_zip_commit(transaction, cancellation.pointer, &error, error.count))
        #endif
        return snapshot.url
    }
}
