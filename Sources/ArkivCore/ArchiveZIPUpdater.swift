import Foundation
import CArkiv

private final class ZIPAdditionProgress {
    let callback: @Sendable (ArchiveProgress) -> Void
    init(_ callback: @escaping @Sendable (ArchiveProgress) -> Void) { self.callback = callback }
}

/// Adds, deletes, renames or replaces items without recompressing unrelated entry data.
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
    /// Adds an explicit empty ZIP directory through the existing Add transaction.
    @discardableResult
    public func createFolder(named name: String, in snapshot: ArchiveSnapshot, folder: String = "",
                             cancellation: ArchiveCancellation,
                             progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ArchiveFailure.message("Enter a valid folder name without separators or control characters.")
        }
        return try update(sources: [], snapshot: snapshot, folder: folder, plan: nil, newFolder: name,
                          cancellation: cancellation, progress: progress)
    }
    /// Strict same-basename replacements in one archive folder, committed together.
    @discardableResult
    public func updateSelectedFiles(paths: Set<String>, from directory: URL, in snapshot: ArchiveSnapshot,
                                    cancellation: ArchiveCancellation,
                                    progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        let entries = snapshot.entries.filter { paths.contains($0.path) }
        let parents = Set(paths.map { $0.split(separator: "/").dropLast().joined(separator: "/") })
        guard paths.count >= 2, entries.count == paths.count, parents.count == 1,
              entries.allSatisfy({ $0.kind == .file }),
              snapshot.entries.enumerated().allSatisfy({ $0.element.id == Int64($0.offset) }),
              directory.isFileURL, (directory.host == nil || directory.host == "" || directory.host == "localhost"),
              directory.query == nil, directory.fragment == nil,
              try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw ArchiveFailure.message("Select at least two regular files in one archive folder and choose a local source folder.")
        }
        let candidates = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        func key(_ name: String) -> String {
            name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let sources = try entries.map { entry -> URL in
            let name = String(entry.path.split(separator: "/").last!)
            let matches = candidates.filter { key($0.lastPathComponent) == key(name) }
            guard matches.count == 1, let source = matches.first, source.lastPathComponent == name,
                  try FileManager.default.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType == .typeRegular else {
                throw ArchiveFailure.message("‘\(name)’ needs exactly one regular source file with the same name. No files were updated.")
            }
            return source
        }
        return try update(sources: sources, snapshot: snapshot, folder: "", plan: nil, selectedReplacements: entries,
                          cancellation: cancellation, progress: progress)
    }
    /// Replace one directory subtree without changing its archive path.
    @discardableResult
    public func replaceFolder(path: String, with source: URL, in snapshot: ArchiveSnapshot,
                              cancellation: ArchiveCancellation,
                              progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try editFolder(path: path, with: source, in: snapshot, merge: false, cancellation: cancellation, progress: progress)
    }
    @discardableResult
    public func updateFolder(path: String, with source: URL, in snapshot: ArchiveSnapshot,
                             cancellation: ArchiveCancellation,
                             progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try editFolder(path: path, with: source, in: snapshot, merge: true, cancellation: cancellation, progress: progress)
    }
    private func editFolder(path: String, with source: URL, in snapshot: ArchiveSnapshot, merge: Bool,
                            cancellation: ArchiveCancellation,
                            progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        guard snapshot.index.row(at: path)?.isDirectory == true,
              source.isFileURL, (source.host == nil || source.host == "" || source.host == "localhost"),
              source.query == nil, source.fragment == nil,
              (try FileManager.default.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType) == .typeDirectory else {
            throw ArchiveFailure.message("Choose one archive folder and one local folder.")
        }
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        var keep = try deletionPlan(snapshot, paths: [path])
        for (i, entry) in snapshot.entries.enumerated() where entry.kind == .directory && entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path {
            keep[i] = 1 // Preserve the explicit root directory record and all its metadata.
        }
        return try update(sources: [source], snapshot: snapshot, folder: "", plan: keep,
                          folderReplacement: path, folderMerge: merge, cancellation: cancellation, progress: progress)
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
        try renameItem(path: path, to: name, in: snapshot, seven: false, cancellation: cancellation, progress: progress)
    }
    private func renameItem(path: String, to name: String, in snapshot: ArchiveSnapshot, seven: Bool, password: String? = nil,
                            cancellation: ArchiveCancellation, progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
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
        if seven {
            let entries = zip(snapshot.entries, names).map { entry, name in
                ArchiveEntry(id: entry.id, path: name ?? entry.path, size: entry.size, kind: entry.kind)
            }
            let proposed = ArchiveSnapshot(url: snapshot.url, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
            try ArchiveAdditionUpdater.validateSevenPaths(proposed)
        }
        return try update(sources: [], snapshot: snapshot, folder: "", plan: nil, renameNames: names, seven: seven, password: password, cancellation: cancellation, progress: progress)
    }
    /// Replaces exactly one regular file while retaining its archive name and metadata.
    @discardableResult
    public func replace(path: String, with source: URL, in snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void = { _ in }) throws -> URL {
        try replaceItem(path: path, with: source, in: snapshot, seven: false, cancellation: cancellation, progress: progress)
    }
    @discardableResult
    func replaceSeven(path: String, with source: URL, in snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                      progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        return try replaceItem(path: path, with: source, in: snapshot, seven: true, password: password, cancellation: cancellation, progress: progress)
    }
    private func replaceItem(path: String, with source: URL, in snapshot: ArchiveSnapshot, seven: Bool, password: String? = nil,
                             cancellation: ArchiveCancellation, progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        guard let entry = snapshot.entries.first(where: { $0.path == path }), entry.kind == .file,
              snapshot.entries.filter({ $0.path == path }).count == 1,
              snapshot.entries.enumerated().allSatisfy({ $0.element.id == Int64($0.offset) }),
              snapshot.index.row(at: path)?.isDirectory == false,
              !snapshot.entries.contains(where: { $0.path.hasPrefix(path + "/") }),
              try FileManager.default.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType == .typeRegular else {
            throw ArchiveFailure.message("Choose one regular archive file and one regular replacement file.")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.dropLast().indices.allSatisfy({ snapshot.index.row(at: components.prefix($0 + 1).joined(separator: "/"))?.isDirectory == true }) else {
            throw ArchiveFailure.message("Ambiguous archive paths cannot safely be replaced.")
        }
        return try update(sources: [source], snapshot: snapshot, folder: "", plan: nil, replacement: entry, seven: seven, password: password, cancellation: cancellation, progress: progress)
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
    @discardableResult
    func addSeven(sources: [URL], to snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                  progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        return try update(sources: sources, snapshot: snapshot, folder: "", plan: nil, seven: true, password: password, cancellation: cancellation, progress: progress)
    }
    @discardableResult
    func deleteSeven(paths: Set<String>, from snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                     progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        return try update(sources: [], snapshot: snapshot, folder: "", plan: deletionPlan(snapshot, paths: paths), seven: true, password: password, cancellation: cancellation, progress: progress)
    }
    @discardableResult
    func renameSeven(path: String, to name: String, in snapshot: ArchiveSnapshot, password: String? = nil, cancellation: ArchiveCancellation,
                     progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        try ArchiveAdditionUpdater.validateSevenPaths(snapshot)
        return try renameItem(path: path, to: name, in: snapshot, seven: true, password: password, cancellation: cancellation, progress: progress)
    }
    private func update(sources: [URL], snapshot: ArchiveSnapshot, folder: String, plan: [UInt8]?, renameNames: [String?]? = nil, replacement: ArchiveEntry? = nil, newFolder: String? = nil, folderReplacement: String? = nil, folderMerge: Bool = false, selectedReplacements: [ArchiveEntry]? = nil, seven: Bool = false, password: String? = nil, cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        guard (seven || snapshot.unlocked == nil), snapshot.entries.allSatisfy({ $0.kind == .file || $0.kind == .directory }), try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed since it was opened. Reopen it.")
        }
        let archive = canonical(snapshot.url)
        var error = [CChar](repeating: 0, count: 256)
        let encryptedOperations = (plan != nil ? 1 : 0) + (renameNames != nil ? 1 : 0) + (!sources.isEmpty ? 1 : 0)
        if password != nil && (!seven || encryptedOperations != 1 || (replacement != nil && sources.count != 1)) {
            throw ArchiveFailure.message("Choose one supported encrypted archive edit.")
        }
        guard let transaction = password != nil ? arkiv_seven_encrypted_begin(archive.path, password, cancellation.pointer, &error, error.count) :
            seven ? arkiv_seven_begin(archive.path, &error, error.count) : arkiv_zip_begin(archive.path, &error, error.count) else {
            if cancellation.isCancelled { throw ArchiveFailure.cancelled }
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
        if let newFolder {
            guard !seven, password == nil, roots.insert(key(newFolder)).inserted else {
                throw ArchiveFailure.message("A folder or file with that name already exists in this archive directory.")
            }
        }
        for sourceURL in sources {
            let source = canonical(sourceURL)
            guard selectedReplacements != nil || replacement != nil || folderReplacement != nil || roots.insert(key(source.lastPathComponent)).inserted else {
                throw ArchiveFailure.message("An item named ‘\(source.lastPathComponent)’ already exists in the destination archive folder. Rename the source item before adding it.")
            }
            guard canonical(source) != archive, (try? SourceStamp(source).inode) != snapshot.stamp.inode else {
                throw ArchiveFailure.message("An archive cannot be added to itself.")
            }
        }
        var sourcePins = [OpaquePointer]()
        defer { sourcePins.forEach { arkiv_file_pin_end($0) } }
        var fileMethods: [Int32]? = nil
        if let selectedReplacements {
            guard !seven, selectedReplacements.count == sources.count else { throw ArchiveFailure.message("Invalid selected-file update.") }
            fileMethods = try zip(selectedReplacements, sources).map { entry, source in
                let method = arkiv_zip_replacement_method(transaction, Int(entry.id), snapshot.entries.count, entry.path)
                guard (method == 0 || method == 8), let pin = arkiv_file_pin_begin(canonical(source).path) else {
                    throw ArchiveFailure.message("A selected file or source cannot safely be updated.")
                }
                sourcePins.append(pin)
                return method
            }
        }
        func validateSources() throws {
            guard sourcePins.allSatisfy({ arkiv_file_pin_valid($0) != 0 }) else {
                throw ArchiveFailure.message("A source file changed during the update. Original archive unchanged.")
            }
        }
        let manager = FileManager.default
        let stage = archive.deletingLastPathComponent().appendingPathComponent(".arkiv-add-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        var sources = sources
        if let newFolder {
            let inputs = stage.appendingPathComponent("input", isDirectory: true)
            try manager.createDirectory(at: inputs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let empty = inputs.appendingPathComponent(newFolder, isDirectory: true)
            try manager.createDirectory(at: empty, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            sources = [empty]
        }
        var compression: ZIPCompression = .deflate
        if let replacement, !seven {
            let method = arkiv_zip_replacement_method(transaction, Int(replacement.id), snapshot.entries.count, replacement.path)
            guard method == 0 || method == 8 else { throw ArchiveFailure.message("This entry cannot safely be replaced.") }
            compression = method == 0 ? .store : .deflate
        }
        let additions = try (plan == nil || folderReplacement != nil) && renameNames == nil ? ArchiveCreator().create(ArchiveCreationRequest(sources: sources, destination: stage, name: "additions", compression: compression),
                                                    archiveFolder: folder, replacementRoot: folderReplacement, omitReplacementRoot: folderReplacement.map { path in snapshot.entries.contains { $0.kind == .directory && $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path } } ?? false, fileMethods: fileMethods, cancellation: cancellation, progress: progress) : nil
        if seven || folderReplacement != nil, let additions {
            // Check every staged descendant, including implicit directories and
            // Unicode/case aliases, before handing the new manifest to 7-Zip.
            let incoming = try LibArchiveEngine().inspect(additions, cancellation: cancellation)
            try ArchiveAdditionUpdater.validateSevenPaths(incoming)
        }
        let receiver = ZIPAdditionProgress(progress)
        let retained = Unmanaged.passRetained(receiver)
        defer { retained.release() }
        let callback: arkiv_progress_callback = { context, files, bytes in
            guard let context else { return }
            Unmanaged<ZIPAdditionProgress>.fromOpaque(context).takeUnretainedValue().callback(ArchiveProgress(files: files, bytes: bytes))
        }
        let result: Int32
        if let selectedReplacements, let additions {
            try validateSources()
            let incoming = try LibArchiveEngine().inspect(additions, cancellation: cancellation)
            guard incoming.entries.count == selectedReplacements.count else { throw ArchiveFailure.message("Replacement manifest changed.") }
            var updates = [Int64](repeating: -1, count: snapshot.entries.count)
            for entry in selectedReplacements {
                let name = String(entry.path.split(separator: "/").last!)
                let matches = incoming.entries.filter { $0.kind == .file && $0.path == name }
                guard matches.count == 1 else { throw ArchiveFailure.message("Replacement source is missing or ambiguous.") }
                updates[Int(entry.id)] = matches[0].id
            }
            result = arkiv_zip_prepare_selected(transaction, additions.path, updates, updates.count, incoming.entries.count,
                                                stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else if folderMerge, let additions {
            let incoming = try LibArchiveEngine().inspect(additions, cancellation: cancellation)
            func normalized(_ path: String) -> String { path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            struct Node { let path: String; let directory: Bool; var ordinal: Int? }
            var nodes = [String: Node]()
            for (i, entry) in snapshot.entries.enumerated() {
                let parts = normalized(entry.path).split(separator: "/")
                for n in 1...parts.count {
                    let path = parts.prefix(n).joined(separator: "/")
                    let explicit = n == parts.count
                    var node = nodes[key(path)] ?? Node(path: path, directory: !explicit || entry.kind == .directory, ordinal: nil)
                    if explicit { node.ordinal = i }
                    nodes[key(path)] = node
                }
            }
            var updates = [Int64](repeating: -1, count: snapshot.entries.count)
            var append = [UInt8](repeating: 1, count: incoming.entries.count)
            for (i, entry) in incoming.entries.enumerated() {
                let path = normalized(entry.path)
                guard let old = nodes[key(path)] else { continue }
                guard old.path == path, old.directory == (entry.kind == .directory) else {
                    throw ArchiveFailure.message("A file/folder conflict or case-only alias prevents this folder update.")
                }
                if let ordinal = old.ordinal {
                    append[i] = 0
                    if entry.kind == .file { updates[ordinal] = Int64(i) }
                }
            }
            let combined = snapshot.entries + incoming.entries.enumerated().filter { append[$0.offset] != 0 }.map(\.element)
            try ArchiveAdditionUpdater.validateSevenPaths(ArchiveSnapshot(url: snapshot.url, entries: combined, stamp: snapshot.stamp, unlocked: nil))
            result = arkiv_zip_prepare_merge(transaction, additions.path, updates, updates.count, append, append.count,
                                             stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else if folderReplacement != nil, let plan, let additions {
            result = arkiv_zip_prepare_subtree(transaction, additions.path, plan, plan.count, stage.path,
                                              cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else if let replacement {
            if seven {
                let names = snapshot.entries.map { strdup($0.path) }
                defer { names.forEach { free($0) } }
                guard names.allSatisfy({ $0 != nil }) else { throw ArchiveFailure.message("Not enough memory to prepare the edit.") }
                let pointers = names.map { $0.map { UnsafePointer<CChar>($0) } }
                if let password {
                    result = arkiv_seven_prepare_replace_encrypted(transaction, additions!.path, pointers, snapshot.entries.count, Int(replacement.id), stage.path, password, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
                } else {
                result = arkiv_seven_prepare_replace(transaction, additions!.path, pointers, snapshot.entries.count, Int(replacement.id), stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
                }
            } else {
            result = arkiv_zip_prepare_replace(transaction, additions!.path, Int(replacement.id), snapshot.entries.count, replacement.path, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
            }
        } else if let renameNames {
            let old = snapshot.entries.map { strdup($0.path) }
            let renamed = renameNames.map { $0.flatMap { strdup($0) } }
            defer { old.forEach { free($0) }; renamed.forEach { free($0) } }
            guard old.allSatisfy({ $0 != nil }), zip(renameNames, renamed).allSatisfy({ $0.0 == nil || $0.1 != nil }) else {
                throw ArchiveFailure.message("Not enough memory to prepare the ZIP rename. Original archive unchanged.")
            }
            let oldPointers = old.map { $0.map { UnsafePointer<CChar>($0) } }
            let newPointers = renamed.map { $0.map { UnsafePointer<CChar>($0) } }
            if let password {
                result = arkiv_seven_prepare_rename_encrypted(transaction, oldPointers, newPointers, renameNames.count, stage.path, password, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
            } else {
                result = seven
                    ? arkiv_seven_prepare_rename(transaction, oldPointers, newPointers, renameNames.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
                    : arkiv_zip_prepare_rename(transaction, oldPointers, newPointers, renameNames.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
            }
        } else if let plan {
            if seven {
                let names = snapshot.entries.map { strdup($0.path) }
                defer { names.forEach { free($0) } }
                guard names.allSatisfy({ $0 != nil }) else { throw ArchiveFailure.message("Not enough memory to prepare the edit.") }
                let pointers = names.map { $0.map { UnsafePointer<CChar>($0) } }
                if let password {
                    result = arkiv_seven_prepare_delete_encrypted(transaction, pointers, plan, plan.count, stage.path, password, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
                } else {
                    result = arkiv_seven_prepare_delete(transaction, pointers, plan, plan.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
                }
            } else {
                result = arkiv_zip_prepare_delete(transaction, plan, plan.count, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
            }
        } else if seven, let password {
            result = arkiv_seven_prepare_add_encrypted(transaction, additions!.path, stage.path, password, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else if seven {
            result = arkiv_seven_prepare(transaction, additions!.path, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        } else {
            result = arkiv_zip_prepare(transaction, additions!.path, stage.path, cancellation.pointer, callback, retained.toOpaque(), &error, error.count)
        }
        func check(_ result: Int32) throws {
            if result == 2 { throw ArchiveFailure.cancelled }
            if result != 0 { throw ArchiveFailure.message(String(cString: error)) }
        }
        try check(result)
        try validateSources()
        #if os(macOS)
        var coordinationError: NSError?
        var commitResult: Int32 = 1
        var sourceError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: archive, options: .forReplacing, error: &coordinationError) { coordinated in
            guard canonical(coordinated) == archive else { return }
            do { try validateSources() } catch { sourceError = error; return }
            commitResult = arkiv_zip_commit(transaction, cancellation.pointer, &error, error.count)
        }
        // Once rename succeeds, late cancellation/coordination errors cannot undo success.
        if commitResult != 0 {
            if let sourceError { throw sourceError }
            if let coordinationError { throw coordinationError }
            try check(commitResult)
        }
        #else
        try check(arkiv_zip_commit(transaction, cancellation.pointer, &error, error.count))
        #endif
        return snapshot.url
    }
}
