import Foundation

/// Hard limits for optional document-icon themes. They mirror
/// `LIMITS` in design/document-icon-themes/build.py; a catalogue that declares
/// different limits is still held to these.
public enum ThemeLimits {
    public static let catalogBytes = 1 << 20
    public static let packBytes = 16 << 20
    public static let previewBytes = 2 << 20
    public static let fileBytes = 2 << 20
    public static let manifestBytes = 256 << 10
    public static let files = 256
    public static let themes = 128
    public static let installedBytes = 16 << 20
    public static let textLength = 600
}

/// The 11 document icons Arkiv ships, in display order. Names match the
/// bundled `Arkiv-<name>.icns` resources and `Resources/Info.plist`.
public enum DocumentIconName: String, CaseIterable, Sendable, Codable {
    case zip = "ZIP", sevenZip = "7z", tar = "TAR", rar = "RAR", gzip = "GZIP", bzip2 = "BZIP2"
    case xz = "XZ", zstd = "ZSTD", tgz = "TGZ", tbz2 = "TBZ2", txz = "TXZ"

    /// Finder types a file by its last extension, so `name.tar.gz` gets GZIP.
    /// Arkiv's own UI follows the same mapping as Info.plist.
    public static func forFileName(_ name: String) -> DocumentIconName? {
        switch (name as NSString).pathExtension.lowercased() {
        case "zip": return .zip
        case "7z": return .sevenZip
        case "tar": return .tar
        case "rar": return .rar
        case "gz": return .gzip
        case "bz2": return .bzip2
        case "xz": return .xz
        case "zst", "tzst": return .zstd
        case "tgz": return .tgz
        case "tbz2", "tbz": return .tbz2
        case "txz": return .txz
        default: return nil
        }
    }
    public var label: String { rawValue == "7z" ? "7Z" : rawValue }
}

/// Artwork kept for future consumers (a Quick Look thumbnail provider):
/// double-suffix TAR labels, TZST and volume artwork. Never used for Finder.
public let documentIconExtraNames: Set<String> = ["TAR.GZ", "TAR.BZ2", "TAR.XZ", "TAR.ZST", "TZST",
                                                   "7z-volume", "RAR-volume-future", "ZIP-volume-future"]

/// The ten macOS iconset representations.
public struct IconRepresentation: Hashable, Sendable {
    public let points: Int
    public let scale: Int
    public var pixels: Int { points * scale }
    public var fileName: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
    public static let all: [IconRepresentation] = [16, 32, 128, 256, 512].flatMap { [IconRepresentation(points: $0, scale: 1), IconRepresentation(points: $0, scale: 2)] }
    public static func named(_ name: String) -> IconRepresentation? { all.first { $0.fileName == name } }
    /// The smallest artwork tier that covers `points` (16 and 32 pt have dedicated artwork).
    public static func tier(for points: CGFloat) -> Int {
        [16, 32, 128, 256, 512].first { CGFloat($0) >= points } ?? 512
    }
}

public enum ThemeKind: String, Codable, Sendable {
    case family, concept, surface, candidate, reproduction, variation
    public var displayName: String {
        switch self {
        case .family: return "Family"
        case .concept: return "Original concept"
        case .surface: return "Surface study"
        case .candidate: return "Candidate"
        case .reproduction: return "Reproduction"
        case .variation: return "Variation"
        }
    }
}

public struct ThemeProvenance: Codable, Equatable, Sendable {
    public let type: String
    public let archive: String?
    public let commit: String?
    public let archives: [String]?
    public let file: String?
    public let variant: String?
    public let parent: String?
    public let direction: String?
    public let theme: String?
}

public struct ThemeAsset: Codable, Equatable, Sendable {
    public let url: URL
    public let size: Int
    public let sha256: String
    public let installedSize: Int?
    public let files: Int?
}

public struct ThemePreviewFile: Codable, Equatable, Sendable {
    public let name: String
    public let size: Int
    public let sha256: String
    public let width: Int
    public let height: Int
}

public struct ThemePreview: Codable, Equatable, Sendable {
    public let url: URL
    public let size: Int
    public let sha256: String
    public let files: [ThemePreviewFile]
}

public struct ThemeVariation: Codable, Equatable, Sendable {
    public let changes: [String]
}

/// One downloadable theme, as listed by a verified catalogue.
public struct CatalogTheme: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: Int
    public let name: String
    public let family: String
    public let familyName: String
    public let kind: ThemeKind
    public let summary: String
    public let variantOf: String?
    public let coverage: [String]
    public let extras: [String]
    public let minimumAppBuild: Int
    public let licence: String
    public let provenance: ThemeProvenance
    public let pack: ThemeAsset
    public let preview: ThemePreview
    public let variation: ThemeVariation?
    /// Themes that existed only for some formats (Classic) leave the rest to the system icon.
    public var isPartial: Bool { coverage.count < DocumentIconName.allCases.count }
}

public struct ThemeCatalog: Codable, Equatable, Sendable {
    public let schema: Int
    public let catalogVersion: Int
    public let defaultTheme: String
    public let themes: [CatalogTheme]
}

/// `theme.json` inside a pack. Every representation of every icon maps to a
/// stored file; byte-identical representations share one file.
public struct ThemeManifest: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int
        public let sha256: String
        public let width: Int
        public let height: Int
        public let pixels: String?
    }
    public let schema: Int
    public let id: String
    public let version: Int
    public let name: String
    public let icons: [String: [String: String]]
    public let extras: [String: [String: String]]
    public let files: [File]
    public let licence: String?
}

public enum ThemeError: Error, LocalizedError, Equatable {
    case notConfigured
    case catalogRejected(String)
    case rollback(cached: Int, received: Int)
    case download(String)
    case tooLarge
    case checksumMismatch
    case packRejected(String)
    case cancelled
    case busy
    case notInstalled
    case requiresNewerArkiv

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Theme downloads are not configured in this build."
        case .catalogRejected(let reason): return "The theme catalogue was rejected: \(reason)"
        case .rollback(let cached, let received): return "The theme catalogue is older than the one already verified (\(received) < \(cached)) and was rejected."
        case .download(let reason): return "The download failed: \(reason)"
        case .tooLarge: return "The download is larger than declared and was stopped."
        case .checksumMismatch: return "The downloaded theme does not match its signed checksum and was discarded."
        case .packRejected(let reason): return "The theme pack was rejected: \(reason)"
        case .cancelled: return "Download cancelled."
        case .busy: return "This theme is already being changed."
        case .notInstalled: return "This theme is not installed."
        case .requiresNewerArkiv: return "This theme requires a newer version of Arkiv."
        }
    }
}

enum ThemeText {
    static let idPattern = try! NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
    static func validID(_ id: String) -> Bool {
        id.utf8.count <= 64 && idPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
    }
    static func validHex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    /// Displayed text: bounded and free of control characters.
    static func validText(_ value: String, allowEmpty: Bool = false) -> Bool {
        (allowEmpty || !value.isEmpty) && value.count <= ThemeLimits.textLength
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }
    }
}
