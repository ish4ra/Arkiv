import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ArkivCore

enum ThemeHash {
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// Streams a file so a pack is never held in memory twice.
    static func sha256(file url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Strict PNG acceptance: 8-bit RGBA, non-interlaced, only IHDR/IDAT/IEND
/// chunks with valid CRCs, exact dimensions, and a successful ImageIO decode.
enum ThemePNG {
    static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func validate(_ data: Data, width: Int, height: Int) throws {
        func reject(_ reason: String) -> ThemeError { .packRejected("an image \(reason).") }
        guard data.count > 8 + 25 + 12, data.prefix(8) == signature else { throw reject("is not a PNG") }
        let bytes = [UInt8](data)
        var offset = 8, kinds: [String] = [], idat = Data()
        while offset < bytes.count {
            guard offset + 12 <= bytes.count else { throw reject("is truncated") }
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length <= bytes.count - offset - 12 else { throw reject("is truncated") }
            let kindBytes = bytes[(offset + 4)..<(offset + 8)]
            let kind = String(decoding: kindBytes, as: UTF8.self)
            let crcStart = offset + 8 + length
            let stored = UInt32(bytes[crcStart]) << 24 | UInt32(bytes[crcStart + 1]) << 16 | UInt32(bytes[crcStart + 2]) << 8 | UInt32(bytes[crcStart + 3])
            guard crc32(bytes[(offset + 4)..<crcStart]) == stored else { throw reject("has a damaged chunk") }
            if kind == "IHDR" {
                guard kinds.isEmpty, length == 13 else { throw reject("has an invalid header") }
                let h = bytes[(offset + 8)..<(offset + 21)].map { $0 }
                let w = Int(h[0]) << 24 | Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
                let ht = Int(h[4]) << 24 | Int(h[5]) << 16 | Int(h[6]) << 8 | Int(h[7])
                guard w == width, ht == height else { throw reject("has unexpected dimensions") }
                guard h[8] == 8, h[9] == 6, h[10] == 0, h[11] == 0, h[12] == 0 else { throw reject("is not 8-bit RGBA") }
            } else if kind == "IDAT" {
                guard kinds.last == "IHDR" || kinds.last == "IDAT" else { throw reject("has misplaced data") }
                idat.append(contentsOf: bytes[(offset + 8)..<crcStart])
            } else if kind == "IEND" {
                guard length == 0, kinds.last == "IDAT", crcStart + 4 == bytes.count else { throw reject("has data after its end") }
            } else {
                throw reject("contains unexpected chunk \(kind.debugDescription)")
            }
            kinds.append(kind)
            offset = crcStart + 4
        }
        guard kinds.last == "IEND" else { throw reject("is truncated") }
        // ImageIO quietly fills in damaged compressed data, so inflate and check
        // the image stream itself: exact length, valid row filters, Adler-32.
        try checkImageData(idat, width: width, height: height)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier, CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              image.width == width, image.height == height, image.bitsPerComponent == 8,
              ![CGImageAlphaInfo.none, CGImageAlphaInfo.noneSkipLast, CGImageAlphaInfo.noneSkipFirst].contains(image.alphaInfo) else {
            throw reject("could not be decoded")
        }
        // Force a full decode so damaged compressed data is caught now.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw reject("could not be decoded")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func checkImageData(_ stream: Data, width: Int, height: Int) throws {
        func reject() -> ThemeError { .packRejected("an image has damaged image data.") }
        let bytes = [UInt8](stream)
        guard bytes.count > 6, (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) % 31 == 0, bytes[0] & 0x0F == 8, bytes[1] & 0x20 == 0 else { throw reject() }
        let raw = Data(bytes[2..<(bytes.count - 4)])
        guard let inflated = try? (raw as NSData).decompressed(using: .zlib) as Data,
              inflated.count == (width * 4 + 1) * height else { throw reject() }
        var a: UInt32 = 1, b: UInt32 = 0, valid = true
        let stride = width * 4 + 1
        inflated.withUnsafeBytes { buffer in
            var index = 0
            while index < buffer.count {
                let end = min(index + 5552, buffer.count)
                while index < end {
                    let byte = buffer[index]
                    if index % stride == 0, byte > 4 { valid = false }
                    a &+= UInt32(byte); b &+= a; index += 1
                }
                a %= 65521; b %= 65521
            }
        }
        let n = bytes.count
        let stored = UInt32(bytes[n - 4]) << 24 | UInt32(bytes[n - 3]) << 16 | UInt32(bytes[n - 2]) << 8 | UInt32(bytes[n - 1])
        guard valid, stored == (b << 16 | a) else { throw reject() }
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

/// Accepts a downloaded pack only if every rule holds. Content is read through
/// Arkiv's hardened extraction engine (no links, no unsafe paths, bounded
/// sizes) after the entry list has been checked against a strict allowlist,
/// and the extracted tree is checked again before anything is published.
struct ThemePackValidator: Sendable {
    enum Mode {
        case theme(CatalogTheme)
        case preview(CatalogTheme)
    }
    let engine = LibArchiveEngine()

    static func allowedPath(_ path: String, coverage: Set<String>, extras: Set<String>) -> Bool {
        if path == "theme.json" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let (folder, file): (String, String)
        if parts.count == 2 { (folder, file) = (parts[0], parts[1]) }
        else if parts.count == 3, parts[0] == "extras" { (folder, file) = (parts[1], parts[2]) }
        else { return false }
        guard folder.hasPrefix("Arkiv-"), folder.hasSuffix(".iconset"), IconRepresentation.named(file) != nil else { return false }
        let name = String(folder.dropFirst(6).dropLast(8))
        return parts.count == 2 ? coverage.contains(name) : extras.contains(name)
    }

    /// `pack` has already passed the size and SHA-256 checks against the signed
    /// catalogue. Returns a fully validated directory inside `staging`.
    func validate(pack: URL, mode: Mode, staging: URL, cancellation: ArchiveCancellation) throws -> URL {
        func reject(_ reason: String) -> ThemeError { .packRejected(reason) }
        let header = try FileHandle(forReadingFrom: pack)
        let magic = try header.read(upToCount: 4)
        try header.close()
        guard magic == Data([0x50, 0x4B, 0x03, 0x04]) else { throw reject("it is not a ZIP pack.") }

        let theme: CatalogTheme, expected: [String: (size: Int, sha: String, width: Int, height: Int)]?
        switch mode {
        case .theme(let t): theme = t; expected = nil
        case .preview(let t):
            theme = t
            expected = Dictionary(uniqueKeysWithValues: t.preview.files.map { ($0.name, (size: $0.size, sha: $0.sha256, width: $0.width, height: $0.height)) })
        }
        let coverage = Set(theme.coverage), extras = Set(theme.extras)
        let snapshot: ArchiveSnapshot
        do { snapshot = try engine.inspect(pack, cancellation: cancellation) }
        catch ArchiveFailure.cancelled { throw ThemeError.cancelled }
        catch { throw reject("it could not be read.") }

        // 1. Entry list: exact allowlist, regular files only, no duplicates
        //    (also case-insensitively, as on APFS), no executables, bounded sizes.
        let limit = expected == nil ? ThemeLimits.files : theme.preview.files.count
        guard !snapshot.entries.isEmpty, snapshot.entries.count <= limit else { throw reject("it has an unexpected number of files.") }
        var seen = Set<String>(), folded = Set<String>(), total = 0
        for entry in snapshot.entries {
            let path = entry.path
            guard entry.kind == .file else { throw reject("it contains a link, folder or special file (\(path)).") }
            let allowed = expected == nil ? Self.allowedPath(path, coverage: coverage, extras: extras) : expected?[path] != nil
            guard allowed else { throw reject("it contains an unexpected file (\(path)).") }
            guard seen.insert(path).inserted, folded.insert(path.lowercased()).inserted else { throw reject("it contains a duplicate path (\(path)).") }
            guard entry.size >= 0, entry.size <= Int64(path == "theme.json" ? ThemeLimits.manifestBytes : ThemeLimits.fileBytes) else { throw reject("a file is too large.") }
            if let mode = entry.metadata.posixMode, mode & 0o7111 != 0 { throw reject("it contains an executable file (\(path)).") }
            if entry.metadata.encrypted == true { throw reject("it contains an encrypted file.") }
            total += Int(entry.size)
        }
        guard total <= ThemeLimits.installedBytes else { throw reject("it expands beyond the size limit.") }
        if expected == nil { guard seen.contains("theme.json") else { throw reject("it has no manifest.") } }
        if cancellation.isCancelled { throw ThemeError.cancelled }

        // 2. Hardened extraction into the staging directory.
        let extracted: URL
        do { extracted = try engine.extract(snapshot, ids: nil, into: staging, cancellation: cancellation, progress: { _ in }) }
        catch ArchiveFailure.cancelled { throw ThemeError.cancelled }
        catch { throw reject("it could not be extracted safely.") }

        // 3. The extracted tree must be exactly the checked entries.
        let files = try Self.regularFiles(in: extracted)
        guard Set(files.keys) == seen else { throw reject("its extracted contents differ from its listing.") }
        // ZIP metadata does not always surface POSIX modes, so check what was written.
        for file in files.keys {
            let mode = (try FileManager.default.attributesOfItem(atPath: extracted.appendingPathComponent(file).path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard mode & 0o7111 == 0 else { throw reject("it contains an executable file (\(file)).") }
        }

        if let expected {
            for (name, info) in expected {
                let data = try Self.read(extracted.appendingPathComponent(name), limit: ThemeLimits.fileBytes)
                guard data.count == info.size, ThemeHash.sha256(data) == info.sha else { throw ThemeError.checksumMismatch }
                try ThemePNG.validate(data, width: info.width, height: info.height)
            }
            try Self.seal(extracted, files: Array(files.keys))
            return extracted
        }

        // 4. Manifest: identity, every representation of the covered icons, exact file list.
        let manifestData = try Self.read(extracted.appendingPathComponent("theme.json"), limit: ThemeLimits.manifestBytes)
        guard let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: manifestData) else { throw reject("its manifest is malformed.") }
        try Self.check(manifest, against: theme)
        guard Set(manifest.files.map(\.path)).union(["theme.json"]) == seen else { throw reject("its manifest does not list its files exactly.") }
        var installed = manifestData.count
        for file in manifest.files {
            let data = try Self.read(extracted.appendingPathComponent(file.path), limit: ThemeLimits.fileBytes)
            guard data.count == file.size, ThemeHash.sha256(data) == file.sha256 else { throw ThemeError.checksumMismatch }
            try ThemePNG.validate(data, width: file.width, height: file.height)
            installed += data.count
            if cancellation.isCancelled { throw ThemeError.cancelled }
        }
        guard installed == theme.pack.installedSize else { throw reject("its installed size differs from the catalogue.") }
        try Self.seal(extracted, files: Array(files.keys))
        return extracted
    }

    /// Structural rules shared by installation and loading an installed theme.
    static func check(_ manifest: ThemeManifest, against theme: CatalogTheme?) throws {
        func reject(_ reason: String) -> ThemeError { .packRejected(reason) }
        guard manifest.schema == 1, ThemeText.validID(manifest.id), ThemeText.validText(manifest.name) else { throw reject("its manifest is invalid.") }
        if let theme {
            guard manifest.id == theme.id, manifest.version == theme.version else { throw reject("it is not the theme the catalogue describes.") }
            guard Set(manifest.icons.keys) == Set(theme.coverage), Set(manifest.extras.keys) == Set(theme.extras) else {
                throw reject("its coverage differs from the catalogue.")
            }
        }
        guard !manifest.icons.isEmpty, Set(manifest.icons.keys).isSubset(of: Set(DocumentIconName.allCases.map(\.rawValue))),
              Set(manifest.extras.keys).isSubset(of: documentIconExtraNames), manifest.files.count < ThemeLimits.files else {
            throw reject("its manifest lists unknown artwork.")
        }
        var byPath = [String: ThemeManifest.File]()
        for file in manifest.files {
            guard byPath.updateValue(file, forKey: file.path) == nil, ThemeText.validHex(file.sha256),
                  allowedPath(file.path, coverage: Set(manifest.icons.keys), extras: Set(manifest.extras.keys)), file.path != "theme.json",
                  (1...ThemeLimits.fileBytes).contains(file.size) else { throw reject("its manifest lists an invalid file.") }
        }
        for (name, reps) in manifest.icons.merging(manifest.extras, uniquingKeysWith: { a, _ in a }) {
            guard Set(reps.keys) == Set(IconRepresentation.all.map(\.fileName)) else { throw reject("\(name) is missing representations.") }
            for (repName, path) in reps {
                guard let rep = IconRepresentation.named(repName), let file = byPath[path],
                      file.width == rep.pixels, file.height == rep.pixels else { throw reject("\(name) has an image with unexpected dimensions.") }
            }
        }
    }

    /// Regular files below `root`, by relative path. Any link or special file rejects the tree.
    static func regularFiles(in root: URL) throws -> [String: Int] {
        var result = [String: Int]()
        let manager = FileManager.default
        func walk(_ directory: URL, _ prefix: String, depth: Int) throws {
            guard depth <= 3 else { throw ThemeError.packRejected("it nests folders too deeply.") }
            for name in try manager.contentsOfDirectory(atPath: directory.path) {
                let url = directory.appendingPathComponent(name)
                let attributes = try manager.attributesOfItem(atPath: url.path)
                let relative = prefix.isEmpty ? name : prefix + "/" + name
                switch attributes[.type] as? FileAttributeType {
                case .typeRegular?: result[relative] = (attributes[.size] as? NSNumber)?.intValue ?? -1
                case .typeDirectory?: try walk(url, relative, depth: depth + 1)
                default: throw ThemeError.packRejected("it contains a link or special file.")
                }
            }
        }
        try walk(root, "", depth: 0)
        return result
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= limit else {
            throw ThemeError.packRejected("a file is not a regular file or is too large.")
        }
        return try Data(contentsOf: url, options: .uncached)
    }

    /// Validated themes are read-only to Arkiv's own logic.
    static func seal(_ root: URL, files: [String]) throws {
        for file in files {
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: root.appendingPathComponent(file).path)
        }
    }
}
