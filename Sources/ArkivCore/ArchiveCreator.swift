import Foundation
import CArkiv

public enum ArchiveFormat: Sendable, CaseIterable {
    case zip, sevenZip, tar, tarGzip, tgz, tarBzip2, tbz2, tarXZ, txz, gzip, bzip2, xz
    public var fileExtension: String {
        switch self {
        case .zip: return ".zip"
        case .sevenZip: return ".7z"
        case .tar: return ".tar"
        case .tarGzip: return ".tar.gz"
        case .tgz: return ".tgz"
        case .tarBzip2: return ".tar.bz2"
        case .tbz2: return ".tbz2"
        case .tarXZ: return ".tar.xz"
        case .txz: return ".txz"
        case .gzip: return ".gz"
        case .bzip2: return ".bz2"
        case .xz: return ".xz"
        }
    }
    public var title: String {
        let name: String
        switch self {
        case .zip: name = "ZIP"
        case .sevenZip: name = "7z"
        case .tar: name = "TAR"
        case .tarGzip, .tgz: name = "TAR + gzip"
        case .tarBzip2, .tbz2: name = "TAR + bzip2"
        case .tarXZ, .txz: name = "TAR + XZ"
        case .gzip: name = "GZIP (single file)"
        case .bzip2: name = "BZIP2 (single file)"
        case .xz: name = "XZ (single file)"
        }
        return "\(name) (\(fileExtension))"
    }
    var tarCodec: Int32? {
        switch self {
        case .zip, .sevenZip, .gzip, .bzip2, .xz: return nil
        case .tar: return 0
        case .tarGzip, .tgz: return 1
        case .tarBzip2, .tbz2: return 2
        case .tarXZ, .txz: return 3
        }
    }
    public var isStandalone: Bool { streamCodec != nil }
    var streamCodec: Int32? {
        switch self { case .gzip: return 1; case .bzip2: return 2; case .xz: return 3; default: return nil }
    }
    public var compressionDescription: String {
        switch self {
        case .zip: return "Store or Deflate"
        case .sevenZip: return "LZMA2"
        case .tar: return "None (uncompressed)"
        case .tarGzip, .tgz, .gzip: return "gzip · level 6"
        case .tarBzip2, .tbz2, .bzip2: return "bzip2 · level 9"
        case .tarXZ, .txz, .xz: return "XZ · LZMA2 level 6"
        }
    }
}
public enum ZIPCompression: Sendable { case store, deflate }
public struct ArchiveCreationRequest: Sendable {
    public let format: ArchiveFormat
    public let password: String?
    public let encryptFilenames: Bool
    public let sources: [URL]
    public let destination: URL
    public let name: String
    public let sevenZipOptions: SevenZipCreationOptions?
    public let preset: CompressionPreset
    public let compression: ZIPCompression
    public init(sources: [URL], destination: URL, name: String, compression: ZIPCompression? = nil,
                format: ArchiveFormat = .zip, password: String? = nil, encryptFilenames: Bool = true, preset: CompressionPreset? = nil, sevenZipOptions: SevenZipCreationOptions? = nil) {
        self.sevenZipOptions = sevenZipOptions
        self.format = format; self.password = password; self.encryptFilenames = encryptFilenames
        self.sources = sources; self.destination = destination; self.name = name
        self.preset = preset ?? (compression == .store ? .store : .normal)
        self.compression = compression ?? (preset == .store ? .store : .deflate)
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
        try create(request, archiveFolder: "", cancellation: cancellation, progress: progress)
    }
    func create(_ request: ArchiveCreationRequest, archiveFolder: String, replacementRoot: String? = nil, omitReplacementRoot: Bool = false, fileMethods: [Int32]? = nil, cancellation: ArchiveCancellation,
                progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        let backend = try request.preset.backend(for: request.format)
        guard request.format == .sevenZip || request.sevenZipOptions == nil else {
            throw ArchiveFailure.message("Advanced compression options are available for 7z creation only.")
        }
        let advanced: SevenZipCreationOptions.Resolved?
        if request.format == .sevenZip {
            let bytes = try SevenZipCreationOptions.inputSize(sources:request.sources,cancellation:cancellation)
            advanced = try (request.sevenZipOptions ?? .init()).resolve(preset:request.preset,inputBytes:bytes)
        } else { advanced = nil }
        guard (request.compression == .store) == (request.preset == .store) else {
            throw ArchiveFailure.message("Conflicting compression method and preset.")
        }
        // Internal ZIP edit staging APIs retain their existing Normal/Store policy.
        if !archiveFolder.isEmpty || replacementRoot != nil || fileMethods != nil {
            guard request.format == .zip, request.preset == .normal || request.preset == .store else {
                throw ArchiveFailure.message("Creation presets are not supported for archive edit staging.")
            }
        }
        if let fileMethods {
            guard request.format == .zip, replacementRoot == nil, archiveFolder.isEmpty,
                  fileMethods.count == request.sources.count else { throw ArchiveFailure.message("Invalid replacement compression plan.") }
        }
        try validateArchivePassword(request.password)
        if request.format != .sevenZip, request.password != nil {
            throw ArchiveFailure.message("Password protection is available for 7z archives only.")
        }
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
        if request.format.isStandalone {
            guard request.sources.count == 1,
                  try manager.attributesOfItem(atPath: request.sources[0].path)[.type] as? FileAttributeType == .typeRegular else {
                throw ArchiveFailure.message("Standalone compression requires exactly one regular file. Choose a TAR-based format for folders or multiple files.")
            }
        }
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
            let filename = request.name + request.format.fileExtension
            var published = [CChar](repeating: 0, count: 512)
            var error = [CChar](repeating: 0, count: 256)
            let result = pointers.withUnsafeBufferPointer { buffer in
                if let codec = request.format.streamCodec {
                    return arkiv_create_stream(buffer[0], destination.path, stage.lastPathComponent,
                        filename, &published, published.count, codec,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count)
                }
                if let codec = request.format.tarCodec {
                    return arkiv_create_tar(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                        filename, &published, published.count, codec,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count)
                }
                if let fileMethods {
                    return arkiv_create_zip_files(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                        filename, &published, published.count, fileMethods,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count)
                }
                if let replacementRoot {
                    return arkiv_create_zip_folder(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                        filename, &published, published.count, request.compression == .store ? 0 : 1,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count, replacementRoot, omitReplacementRoot ? 1 : 0)
                }
                if !archiveFolder.isEmpty {
                    return arkiv_create_zip_at(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                        filename, &published, published.count, request.compression == .store ? 0 : 1,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count, archiveFolder)
                }
                if let advanced {
                    return arkiv_create_archive_solid(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                        filename, &published, published.count, 1,
                        arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                        cancellation.pointer, callback, context, &error, error.count,
                        1, request.password, request.encryptFilenames ? 1 : 0, backend.level, advanced.dictionaryBytes, advanced.threads, advanced.solid.enabled ? 1 : 0, advanced.solid.blockBytes ?? 0)
                }
                return arkiv_create_archive_preset(buffer.baseAddress, buffer.count, destination.path, stage.lastPathComponent,
                    filename, &published, published.count, request.compression == .store ? 0 : 1,
                    arkiv_limits(max_entries: 100_000, max_bytes: 20 * 1024 * 1024 * 1024),
                    cancellation.pointer, callback, context, &error, error.count,
                    request.format == .sevenZip ? 1 : 0, request.password, request.encryptFilenames ? 1 : 0, backend.level)
            }
            if result == 0 { return destination.appendingPathComponent(String(cString: published)) }
            if result == 3 { throw ArchiveFailure.message("No unused archive name was available.") }
            if result == 2 { throw ArchiveFailure.cancelled }
            throw ArchiveFailure.message(String(cString: error))
        }
    }
}
