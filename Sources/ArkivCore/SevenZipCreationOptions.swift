import Foundation
import CArkiv

public struct SevenZipCreationOptions: Equatable, Sendable {
    public let dictionaryBytes: UInt64?
    public let threads: Int?
    public init(dictionaryBytes: UInt64? = nil, threads: Int? = nil) {
        self.dictionaryBytes = dictionaryBytes; self.threads = threads
    }
    public static let supportedDictionaryBytes: [UInt64] = [1,2,4,8,16,32,64].map { $0 * 1024 * 1024 }
    public static let memoryCeiling: UInt64 = 2 * 1024 * 1024 * 1024
    public static func supportedThreads(processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> [Int] {
        Array(1...min(4,max(2,processorCount)))
    }
    public struct Resolved: Sendable {
        /// Zero leaves the upstream preset-derived dictionary unset (Auto).
        public let dictionaryBytes: UInt32
        public let threads: UInt32
        public let estimatedMemoryBytes: UInt64
    }
    public func resolve(preset: CompressionPreset, inputBytes: UInt64? = nil,
                        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) throws -> Resolved {
        let backend = try preset.backend(for:.sevenZip)
        let count = threads ?? 2
        guard Self.supportedThreads(processorCount:processorCount).contains(count),
              dictionaryBytes == nil || Self.supportedDictionaryBytes.contains(dictionaryBytes!) else {
            throw ArchiveFailure.message("Unsupported 7z dictionary or thread count.")
        }
        let dictionary = UInt32(dictionaryBytes ?? 0)
        let memory = arkiv_seven_creation_memory(UInt32(backend.level),dictionary,UInt32(count),inputBytes ?? UInt64.max)
        guard memory > 0 else { throw ArchiveFailure.message("Cannot estimate this 7z configuration safely.") }
        guard memory <= Self.memoryCeiling else {
            throw ArchiveFailure.message("Approximate compression memory exceeds Arkiv’s 2 GiB ceiling. Choose a smaller dictionary or fewer threads.")
        }
        return Resolved(dictionaryBytes:dictionary,threads:UInt32(count),estimatedMemoryBytes:memory)
    }
    /// Metadata-only estimate. Creation repeats this check against the staged bytes
    /// in the backend, so changed inputs cannot bypass the memory ceiling.
    public static func inputSize(sources: [URL], cancellation: ArchiveCancellation) throws -> UInt64 {
        let manager = FileManager.default
        var total: UInt64 = 0, entries = 0
        func inspect(_ url: URL) throws -> Bool {
            if cancellation.isCancelled { throw ArchiveFailure.cancelled }
            entries += 1
            guard entries <= 100_000, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost", url.query == nil, url.fragment == nil else { throw ArchiveFailure.message("Too many source entries or unsupported source URL.") }
            let attributes = try manager.attributesOfItem(atPath:url.path)
            let kind = attributes[.type] as? FileAttributeType
            guard kind == .typeRegular || kind == .typeDirectory else { throw ArchiveFailure.message("Links and special files cannot be archived.") }
            if kind == .typeRegular {
                guard let size = attributes[.size] as? NSNumber, size.int64Value >= 0,
                      size.uint64Value <= 20 * 1024 * 1024 * 1024 - total else { throw ArchiveFailure.message("Source size exceeds the creation limit.") }
                total += size.uint64Value
            }
            return kind == .typeDirectory
        }
        for root in sources {
            if try inspect(root) {
                var enumerationError: Error?
                guard let enumerator = manager.enumerator(at:root,includingPropertiesForKeys:nil,errorHandler:{ _,error in enumerationError=error;return false }) else {
                    throw ArchiveFailure.message("Cannot inspect the source folder.")
                }
                for case let url as URL in enumerator { _ = try inspect(url) }
                if let enumerationError { throw enumerationError }
            }
        }
        return total
    }
}
