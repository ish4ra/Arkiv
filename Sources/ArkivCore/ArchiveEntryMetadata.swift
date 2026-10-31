import Foundation

/// Optional backend evidence. A missing value is never inferred from extension,
/// archive-wide compression, or an unlocked plaintext spool.
public struct ArchiveEntryMetadata: Equatable, Sendable {
    public let packedSize: UInt64?
    public let modificationTime: Date?
    public let compressionMethod: String?
    public let encrypted: Bool?
    public init(packedSize: UInt64? = nil, modificationTime: Date? = nil,
                compressionMethod: String? = nil, encrypted: Bool? = nil) {
        self.packedSize = packedSize; self.modificationTime = modificationTime
        self.compressionMethod = compressionMethod; self.encrypted = encrypted
    }
    /// Packed / unpacked bytes. Not defined for empty files or non-regular entries.
    public func ratio(unpackedSize: Int64, kind: ArchiveEntry.Kind) -> Double? {
        guard kind == .file, unpackedSize > 0, let packedSize else { return nil }
        return Double(packedSize) / Double(unpackedSize)
    }
}
