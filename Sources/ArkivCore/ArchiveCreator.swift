import Foundation
import CArkiv

public enum ZIPCompression: Sendable { case store, deflate }
public struct ArchiveCreationRequest: Sendable {
    public let sources: [URL]
    public let destination: URL
    public let name: String
    public let compression: ZIPCompression
    public init(sources: [URL], destination: URL, name: String, compression: ZIPCompression = .deflate) {
        self.sources = sources; self.destination = destination; self.name = name; self.compression = compression
    }
}
private final class CreationProgress {
    let callback: @Sendable (ArchiveProgress) -> Void
    init(_ callback: @escaping @Sendable (ArchiveProgress) -> Void) { self.callback = callback }
}
public struct ArchiveCreator: Sendable {
    public init() {}
    public func create(_ request: ArchiveCreationRequest, cancellation: ArchiveCancellation,
                       progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        func local(_ url: URL) -> Bool {
            url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost") && url.query == nil && url.fragment == nil
        }
        func component(_ name: String) -> Bool {
            !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 240 &&
            !name.unicodeScalars.contains { $0.value < 32 || "/\\:".unicodeScalars.contains($0) }
        }
        guard !request.sources.isEmpty, request.sources.count <= 100_000, local(request.destination), component(request.name) else {
            throw ArchiveFailure.message("Choose local source items, a destination folder, and a valid archive name.")
        }
        func canonicalSystemURL(_ url: URL) -> URL {
            let url = url.standardizedFileURL
            #if os(macOS)
            // macOS exposes trusted system aliases for its temporary folders.
            if url.path == "/var" || url.path.hasPrefix("/var/") || url.path == "/tmp" || url.path.hasPrefix("/tmp/") {
                return URL(fileURLWithPath: "/private" + url.path)
            }
            #endif
            return url
        }
        let manager = FileManager.default
        let destination = canonicalSystemURL(request.destination)
        var paths: [String] = [], names = Set<String>()
        for source in request.sources {
            guard local(source) else { throw ArchiveFailure.message("Choose local source items.") }
            let url = canonicalSystemURL(source)
            guard component(url.lastPathComponent), names.insert(url.lastPathComponent.lowercased()).inserted else {
                throw ArchiveFailure.message("Source items must have distinct safe names.")
            }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard let kind = attributes[.type] as? FileAttributeType, kind == .typeRegular || kind == .typeDirectory else {
                throw ArchiveFailure.message("Links and special files cannot be archived.")
            }
            guard !paths.contains(where: { $0 == url.path || $0.hasPrefix(url.path + "/") || url.path.hasPrefix($0 + "/") }) else {
                throw ArchiveFailure.message("Choose distinct source items without overlapping folders.")
            }
            if kind == .typeDirectory {
                let folder = url.resolvingSymlinksInPath().path
                let target = destination.resolvingSymlinksInPath().path
                guard target != folder && !target.hasPrefix(folder + "/") else {
                    throw ArchiveFailure.message("Choose a destination outside the source folders.")
                }
            }
            paths.append(url.path)
        }
        let receiver = CreationProgress(progress)
        let retained = Unmanaged.passRetained(receiver)
        defer { retained.release() }
        let context = retained.toOpaque()
        let callback: arkiv_progress_callback = { context, files, bytes in
            guard let context else { return }
            Unmanaged<CreationProgress>.fromOpaque(context).takeUnretainedValue().callback(ArchiveProgress(files: files, bytes: bytes))
        }
        let strings = paths.map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = strings.map { UnsafePointer($0) }
        do {
            let stage = destination.appendingPathComponent(".arkiv-create-" + UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: stage) }
            let filename = request.name + ".zip"
            var published = [CChar](repeating: 0, count: 512)
            var error = [CChar](repeating: 0, count: 256)
            let result = pointers.withUnsafeBufferPointer { buffer in
                arkiv_create_zip(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                    filename, &published, published.count, request.compression == .store ? 0 : 1,
                    arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                    cancellation.pointer, callback, context, &error, error.count)
            }
            if result == 0 { return destination.appendingPathComponent(String(cString: published)) }
            if result == 3 { throw ArchiveFailure.message("No unused archive name was available.") }
            if result == 2 { throw ArchiveFailure.cancelled }
            throw ArchiveFailure.message(String(cString: error))
        }
    }
}
