import Foundation

/// Creation presets only. Existing archive edits retain their current encoding policy.
public enum CompressionPreset: String, CaseIterable, Sendable {
    case store, fastest, fast, normal, maximum, ultra
    public var title: String { rawValue.capitalized }
    public static func available(for format: ArchiveFormat) -> [CompressionPreset] {
        format == .zip ? [.store, .fastest, .fast, .normal, .maximum] : [.fastest, .fast, .normal, .maximum, .ultra]
    }
    public enum Backend: Equatable, Sendable {
        case zipStore
        case zipDeflate(level: Int32)
        case sevenLZMA2(level: Int32)
        var level: Int32 {
            switch self { case .zipStore: return 0; case .zipDeflate(let n), .sevenLZMA2(let n): return n }
        }
    }
    public func backend(for format: ArchiveFormat) throws -> Backend {
        switch (format, self) {
        case (.zip, .store): return .zipStore
        case (.zip, .fastest): return .zipDeflate(level: 1)
        case (.zip, .fast): return .zipDeflate(level: 3)
        case (.zip, .normal): return .zipDeflate(level: 6)
        case (.zip, .maximum): return .zipDeflate(level: 9)
        case (.sevenZip, .fastest): return .sevenLZMA2(level: 1)
        case (.sevenZip, .fast): return .sevenLZMA2(level: 3)
        case (.sevenZip, .normal): return .sevenLZMA2(level: 5)
        case (.sevenZip, .maximum): return .sevenLZMA2(level: 7)
        case (.sevenZip, .ultra): return .sevenLZMA2(level: 9)
        default: throw ArchiveFailure.message("This compression preset is not supported by the selected archive format.")
        }
    }
}
