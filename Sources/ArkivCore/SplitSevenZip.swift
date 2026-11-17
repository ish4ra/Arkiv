import Foundation
import CArkiv

struct VolumeFailure: LocalizedError {
    let code: Int32
    let detail: String
    var errorDescription: String? { detail }
}
/// Owns validated descriptors plus the private reconstructed input, not passwords.
/// The existing 7z backend performs all header/data decoding and verification.
final class SplitSevenZip: @unchecked Sendable {
    static let maximumPhysicalSize: UInt64 = 4 << 30
    let spool: UnlockedArchive
    let physicalSize: UInt64
    private let volumes: OpaquePointer
    private let lock = NSLock()
    static func matches(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        guard let range = name.range(of: ".7z.", options:.backwards) else { return false }
        let suffix = name[range.upperBound...]
        return !suffix.isEmpty && suffix.allSatisfy { $0.isASCII && $0.isNumber }
    }
    init(_ url: URL, cancellation: ArchiveCancellation, progress: @escaping @Sendable (ArchiveProgress) -> Void) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost", url.query == nil, url.fragment == nil else {
            throw ArchiveFailure.message("Choose local split 7z volumes.")
        }
        spool = try UnlockedArchive(filename:"reconstructed.7z")
        var source = url.standardizedFileURL
        #if os(macOS)
        if source.path.hasPrefix("/var/") || source.path.hasPrefix("/tmp/") { source = URL(fileURLWithPath:"/private" + source.path) }
        #endif
        let receiver = VolumeProgress(progress)
        var pointer: OpaquePointer?
        var error = [CChar](repeating:0,count:1024)
        let result = arkiv_volumes_reconstruct(source.path,spool.url.path,Self.maximumPhysicalSize,cancellation.pointer,{ context, files, bytes in
            guard let context else { return }
            Unmanaged<VolumeProgress>.fromOpaque(context).takeUnretainedValue().callback(.init(files:files,bytes:bytes))
        },Unmanaged.passUnretained(receiver).toOpaque(),&pointer,&error,error.count)
        if result == 2 { throw ArchiveFailure.cancelled }
        guard result == 0, let pointer else { throw VolumeFailure(code:result,detail:String(cString:error).isEmpty ? "Unsupported or unreadable split 7z volumes." : String(cString:error)) }
        volumes = pointer; physicalSize = arkiv_volumes_size(pointer)
    }
    func validate(_ cancellation: ArchiveCancellation) throws {
        lock.lock(); defer { lock.unlock() }
        var error = [CChar](repeating:0,count:1024)
        let code = arkiv_volumes_validate(volumes,cancellation.pointer,&error,error.count)
        if code == 2 { throw ArchiveFailure.cancelled }
        guard code == 0 else { throw VolumeFailure(code:code,detail:String(cString:error)) }
    }
    deinit { arkiv_volumes_free(volumes) }
}
private final class VolumeProgress {
    let callback: @Sendable (ArchiveProgress) -> Void
    init(_ callback: @escaping @Sendable (ArchiveProgress) -> Void) { self.callback = callback }
}
