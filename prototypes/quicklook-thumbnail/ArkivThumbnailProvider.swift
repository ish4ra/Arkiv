// PROTOTYPE — not built into Arkiv.app. See README.md in this folder.
//
// A Quick Look thumbnail extension that draws Arkiv's document icon artwork
// for archive files in Finder icon views, Quick Look and other thumbnail
// clients. It reads, never writes:
//   * the selected theme from Arkiv's preferences (read-only exception), and
//   * the installed theme from ~/Library/Application Support/Arkiv/
//     DocumentIconThemes (read-only exception), verifying every file's size
//     and SHA-256 against the theme's manifest, as the app does;
//   * otherwise the bundled Seal Dark icons in the containing Arkiv.app.
// It never touches the archive's contents: only the file name is used.
import AppKit
import CryptoKit
import QuickLookThumbnailing

final class ArkivThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        guard let artwork = Artwork(fileName: request.fileURL.lastPathComponent),
              let image = ThemeArtwork.image(for: artwork, pixels: Int(max(request.maximumSize.width, request.maximumSize.height) * request.scale)) else {
            handler(nil, nil) // Let macOS draw its own icon.
            return
        }
        // Document icons are square; fit them in the requested box.
        let side = min(request.maximumSize.width, request.maximumSize.height)
        let size = CGSize(width: side, height: side)
        handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
            image.draw(in: CGRect(origin: .zero, size: size))
            return true
        }), nil)
    }
}

/// Mirrors DocumentIconArtwork in ArkivThemes: longest suffix first, split 7z
/// volumes by exactly `.7z.` + digits. Only names macOS routes here (by the
/// content types in Info.plist) ever arrive, so `.001` is never claimed.
enum Artwork: Equatable {
    case icon(String)    // ZIP, 7z, TAR, RAR, GZIP, BZIP2, XZ, ZSTD, TGZ, TBZ2, TXZ
    case extra(String)   // TAR.GZ, TAR.BZ2, TAR.XZ, TAR.ZST, TZST, 7z-volume

    init?(fileName: String) {
        let lower = fileName.lowercased()
        if let range = lower.range(of: ".7z.", options: .backwards), !lower[range.upperBound...].isEmpty,
           lower[range.upperBound...].allSatisfy({ $0.isASCII && $0.isNumber }) { self = .extra("7z-volume"); return }
        for (suffix, name) in [(".tar.gz", "TAR.GZ"), (".tar.bz2", "TAR.BZ2"), (".tar.xz", "TAR.XZ"), (".tar.zst", "TAR.ZST"), (".tzst", "TZST")]
            where lower.hasSuffix(suffix) && lower.count > suffix.count { self = .extra(name); return }
        let map = ["zip": "ZIP", "7z": "7z", "tar": "TAR", "rar": "RAR", "gz": "GZIP", "bz2": "BZIP2", "xz": "XZ",
                   "zst": "ZSTD", "tgz": "TGZ", "tbz2": "TBZ2", "tbz": "TBZ2", "txz": "TXZ"]
        guard let name = map[(lower as NSString).pathExtension] else { return nil }
        self = .icon(name)
    }
    /// The family icon used when a theme has no dedicated extra.
    var fallback: Artwork? {
        guard case .extra(let name) = self else { return nil }
        return .icon(["TAR.GZ": "TGZ", "TAR.BZ2": "TBZ2", "TAR.XZ": "TXZ", "TAR.ZST": "ZSTD", "TZST": "ZSTD", "7z-volume": "7z"][name] ?? "ZIP")
    }
}

enum ThemeArtwork {
    static let appDomain = "xyz.isharalakshan.arkiv"
    /// Arkiv.app/Contents/PlugIns/ArkivThumbnail.appex → Arkiv.app/Contents/Resources
    static var appResources: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    }
    static var themeRoot: URL {
        // Inside the sandbox, NSHomeDirectory() is the container; the
        // read-only exception is relative to the real home folder.
        let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) } ?? URL(fileURLWithPath: NSHomeDirectory())
        return home.appendingPathComponent("Library/Application Support/Arkiv/DocumentIconThemes", isDirectory: true)
    }

    static func image(for artwork: Artwork, pixels: Int) -> NSImage? {
        if let selection = UserDefaults(suiteName: appDomain)?.dictionary(forKey: "Arkiv.DocumentIconTheme"),
           let id = selection["id"] as? String, let version = selection["version"] as? Int,
           let image = installed(id: id, version: version, artwork: artwork, pixels: pixels)
                ?? artwork.fallback.flatMap({ installed(id: id, version: version, artwork: $0, pixels: pixels) }) {
            return image
        }
        return bundled(artwork, pixels: pixels) ?? artwork.fallback.flatMap { bundled($0, pixels: pixels) }
    }

    private struct Manifest: Decodable {
        struct File: Decodable { let path: String; let size: Int; let sha256: String }
        let id: String; let version: Int
        let icons: [String: [String: String]]; let extras: [String: [String: String]]; let files: [File]
    }

    /// The smallest representation at least `pixels` wide, verified.
    private static func installed(id: String, version: Int, artwork: Artwork, pixels: Int) -> NSImage? {
        guard id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil, version > 0 else { return nil }
        let directory = themeRoot.appendingPathComponent(id).appendingPathComponent(String(version))
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("theme.json")), data.count < 256 << 10,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.id == id, manifest.version == version else { return nil }
        let reps: [String: String]?
        switch artwork { case .icon(let name): reps = manifest.icons[name]; case .extra(let name): reps = manifest.extras[name] }
        guard let reps else { return nil }
        let files = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        for (points, scale) in representations(atLeast: pixels) {
            let key = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            guard let path = reps[key], let file = files[path], !path.contains(".."),
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(path)), bytes.count == file.size,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == file.sha256,
                  let image = NSImage(data: bytes) else { continue }
            return image
        }
        return nil
    }

    private static func bundled(_ artwork: Artwork, pixels: Int) -> NSImage? {
        switch artwork {
        case .icon(let name):
            return NSImage(contentsOf: appResources.appendingPathComponent("Arkiv-\(name).icns"))
        case .extra(let name):
            // Bundled extras have 16 and 128 pt tiers.
            let tier = pixels <= 32 ? "icon_16x16@2x.png" : "icon_128x128@2x.png"
            return NSImage(contentsOf: appResources.appendingPathComponent("DocumentIconsInApp/Arkiv-\(name)/\(tier)"))
        }
    }

    private static func representations(atLeast pixels: Int) -> [(Int, Int)] {
        let all = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }.sorted { $0.0 * $0.1 < $1.0 * $1.1 }
        return all.filter { $0.0 * $0.1 >= pixels } + all.reversed()
    }
}
