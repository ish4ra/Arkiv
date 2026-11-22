import Foundation

/// Decimal preset units; actual encoded size is admitted again before publication.
public struct SevenZipSplitOptions: Sendable, Equatable {
    public static let presets: [UInt64] = [100_000_000,650_000_000,700_000_000,1_000_000_000,2_000_000_000,4_000_000_000]
    public static let maximumPhysicalBytes: UInt64 = 4 << 30
    public let volumeBytes: UInt64
    public init(volumeBytes: UInt64) { self.volumeBytes = volumeBytes }
    public func validate() throws {
        guard volumeBytes >= 32, volumeBytes < Self.maximumPhysicalBytes else {
            throw ArchiveFailure.message("Split size must be at least 32 bytes and less than 4 GiB. At least two parts are required.")
        }
    }
    public func volumeCount(archiveBytes: UInt64) throws -> Int {
        try validate()
        guard archiveBytes > volumeBytes, archiveBytes <= Self.maximumPhysicalBytes else {
            throw ArchiveFailure.message("The encoded 7z must exceed the split size and fit within 4 GiB. Choose a smaller split size or no splitting.")
        }
        let count = (archiveBytes - 1) / volumeBytes + 1
        guard count <= 128 else { throw ArchiveFailure.message("This split size would exceed 128 volumes. Choose a larger size.") }
        return Int(count)
    }
}
