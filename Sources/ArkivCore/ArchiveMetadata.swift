import Foundation

/// Evidence captured while inspecting the original archive, never its plaintext spool.
public struct ArchiveMetadata: Sendable {
    public let url: URL
    public let format: String?
    public let physicalSize: UInt64
    public let unpackedSize: UInt64?
    public let fileCount: Int
    public let folderCount: Int
    public let compressionMethods: String?
    public let solid: Bool?
    public let dataEncrypted: Bool?
    public let headersEncrypted: Bool?
    public let multipart: Bool?
    /// Whole-container size / regular-file bytes, including archive overhead.
    public var sizeRatio: Double? {
        guard let unpackedSize, unpackedSize > 0 else { return nil }
        return Double(physicalSize) / Double(unpackedSize)
    }
    init(url: URL, physicalSize: UInt64, entries: [ArchiveEntry], format: String?, methods: String? = nil,
         solid: Bool? = nil, dataEncrypted: Bool? = nil, headersEncrypted: Bool? = nil) {
        self.url = url; self.physicalSize = physicalSize; self.format = format
        self.compressionMethods = methods; self.solid = solid
        self.dataEncrypted = dataEncrypted; self.headersEncrypted = headersEncrypted; multipart = nil
        fileCount = entries.filter { $0.kind == .file }.count
        folderCount = entries.filter { $0.kind == .directory }.count
        var total: UInt64 = 0
        var valid = true
        for entry in entries where entry.kind != .directory {
            guard entry.kind == .file, entry.size >= 0 else { valid = false; continue }
            let sum = total.addingReportingOverflow(UInt64(entry.size))
            if sum.overflow { valid = false } else { total = sum.partialValue }
        }
        unpackedSize = valid ? total : nil
    }
}
