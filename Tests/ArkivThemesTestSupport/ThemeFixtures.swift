import CryptoKit
import Foundation
import ArkivThemes

/// Local fixtures for the document-icon theme tests: strict PNGs, Store ZIP
/// packs (including hostile ones), signed catalogues made with isolated,
/// ephemeral keys, and a mocked network. Nothing here touches real servers.
public enum ThemeFixtures {
    // MARK: PNG

    /// An 8-bit RGBA, non-interlaced PNG with only IHDR/IDAT/IEND.
    public static func png(width: Int, height: Int, rgba: (UInt8, UInt8, UInt8, UInt8) = (120, 60, 90, 255),
                           bitDepth: UInt8 = 8, colorType: UInt8 = 6, interlace: UInt8 = 0,
                           extraChunks: [(String, Data)] = [], corruptCRC: Bool = false, trailing: Data = Data(),
                           idatOverride: Data? = nil) -> Data {
        var raw = Data(capacity: (width * 4 + 1) * height)
        let row = [UInt8](repeating: 0, count: 1) + (0..<width).flatMap { x -> [UInt8] in
            // A little structure so images are not all identical.
            [rgba.0 &+ UInt8(x % 7), rgba.1, rgba.2, x == 0 ? 0 : rgba.3]
        }
        for _ in 0..<height { raw.append(contentsOf: row) }
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(be32(UInt32(width))); header.append(be32(UInt32(height)))
        header.append(contentsOf: [bitDepth, colorType, 0, 0, interlace])
        out.append(chunk("IHDR", header))
        for (kind, body) in extraChunks { out.append(chunk(kind, body)) }
        var idat = chunk("IDAT", idatOverride ?? zlib(raw))
        if corruptCRC { idat[idat.count - 1] ^= 0xFF }
        out.append(idat)
        out.append(chunk("IEND", Data()))
        out.append(trailing)
        return out
    }

    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buffer in for b in buffer { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFFFFFF
    }
    /// Installed files are read-only; restore permissions before deleting.
    public static func removeTree(_ url: URL) {
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.appendingPathComponent(item).path) }
        }
        try? FileManager.default.removeItem(at: url)
    }
    static func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
    static func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)]) }

    static func chunk(_ kind: String, _ body: Data) -> Data {
        var data = be32(UInt32(body.count))
        let typed = Data(kind.utf8) + body
        data.append(typed)
        data.append(be32(crc32(typed)))
        return data
    }

    /// zlib stream: header, raw DEFLATE from Foundation, Adler-32.
    static func zlib(_ data: Data) -> Data {
        let deflated = (try? (data as NSData).compressed(using: .zlib) as Data) ?? Data()
        var a: UInt32 = 1, b: UInt32 = 0
        data.withUnsafeBytes { buffer in
            var index = 0
            while index < buffer.count {
                // 5552 bytes keep the sums below 2^32 between reductions.
                let end = min(index + 5552, buffer.count)
                while index < end { a &+= UInt32(buffer[index]); b &+= a; index += 1 }
                a %= 65521; b %= 65521
            }
        }
        return Data([0x78, 0x9C]) + deflated + be32(b << 16 | a)
    }

    // MARK: ZIP

    public struct Entry {
        public var name: String
        public var data: Data
        public var mode: UInt32 = 0o100444
        public var flags: Int = 0
        public init(_ name: String, _ data: Data, mode: UInt32 = 0o100444, flags: Int = 0) {
            self.name = name; self.data = data; self.mode = mode; self.flags = flags
        }
    }

    /// Store-method ZIP with full control over names and attributes.
    public static func zip(_ entries: [Entry]) -> Data {
        var body = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(body.count)
            var local = le32(0x04034b50) + le16(20) + le16(entry.flags) + le16(0) + le16(0) + le16(0x21)
            local += le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count)) + le16(name.count) + le16(0)
            body += local + name + entry.data
            var record = le32(0x02014b50) + le16(3 << 8 | 20) + le16(20) + le16(entry.flags) + le16(0) + le16(0) + le16(0x21)
            record += le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count)) + le16(name.count)
            record += le16(0) + le16(0) + le16(0) + le16(0) + le32(entry.mode << 16) + le32(offset)
            central += record + name
        }
        let end = le32(0x06054b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
            + le32(UInt32(central.count)) + le32(UInt32(body.count)) + le16(0)
        return body + central + end
    }

    // MARK: Packs

    public struct Pack {
        public var id: String
        public var version: Int
        public var coverage: [DocumentIconName]
        public var extras: [DocumentIconExtra] = []
        public var entries: [Entry]
        public var manifest: [String: Any]
        public var data: Data { ThemeFixtures.zip(entries) }
        public var installedSize: Int { entries.reduce(0) { $0 + $1.data.count } }
        public var previewFiles: [(name: String, data: Data)]
    }

    /// A complete, valid pack: every representation of every covered icon,
    /// with the pipeline's deduplication (128 pt @2x = 256 pt, 256 pt @2x = 512 pt).
    public static func pack(id: String, version: Int = 1, coverage: [DocumentIconName] = [.zip], extras: [DocumentIconExtra] = [], tint: UInt8 = 0) -> Pack {
        var entries: [Entry] = [], files: [[String: Any]] = [], icons: [String: [String: String]] = [:], previews: [(name: String, data: Data)] = []
        var extraIcons: [String: [String: String]] = [:]
        let artwork = coverage.map { ($0.rawValue, "Arkiv-\($0.rawValue).iconset/", false) } + extras.map { ($0.rawValue, "extras/Arkiv-\($0.rawValue).iconset/", true) }
        for (index, (name, folder, isExtra)) in artwork.enumerated() {
            var reps: [String: String] = [:]
            var stored: [Int: String] = [:]
            for rep in IconRepresentation.all {
                let tier = rep.points
                // Byte-identical representations share one file, like build.py.
                let key = rep.pixels * 10 + (tier <= 32 ? tier : 0)
                if let path = stored[key] { reps[rep.fileName] = path; continue }
                let path = folder + rep.fileName
                let data = png(width: rep.pixels, height: rep.pixels, rgba: (UInt8(40 + index * 17) &+ tint, UInt8(tier % 251), 90, 255))
                entries.append(Entry(path, data))
                files.append(["path": path, "size": data.count, "sha256": sha256(data), "width": rep.pixels, "height": rep.pixels])
                stored[key] = path
                reps[rep.fileName] = path
                if rep.fileName == "icon_128x128.png" { previews.append((name: "Arkiv-\(name).png", data: data)) }
            }
            if isExtra { extraIcons[name] = reps } else { icons[name] = reps }
        }
        let manifest: [String: Any] = ["schema": 1, "id": id, "version": version, "name": "Fixture \(id)", "icons": icons,
                                       "extras": extraIcons, "files": files, "licence": "Test fixture"]
        var pack = Pack(id: id, version: version, coverage: coverage, extras: extras, entries: [], manifest: manifest, previewFiles: previews)
        pack.entries = [Entry("theme.json", manifestData(manifest))] + entries
        return pack
    }

    public static func manifestData(_ manifest: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    // MARK: Catalogue

    public static let assetBase = "https://github.com/ish4ra/Arkiv/releases/download/"
    public static let catalogURL = URL(string: "https://raw.githubusercontent.com/ish4ra/Arkiv/document-icon-themes/catalog.json")!

    /// Catalogue entry authorising `packData` (a pack's exact bytes, which may be hostile).
    public static func catalogTheme(_ pack: Pack, packData: Data? = nil, tag: String, kind: String = "family",
                                    installedSize: Int? = nil, previewData: Data? = nil) -> [String: Any] {
        let data = packData ?? pack.data
        let preview = previewData ?? zip(pack.previewFiles.map { Entry($0.name, $0.data) })
        return [
            "id": pack.id, "version": pack.version, "name": "Fixture \(pack.id)", "family": "fixture", "familyName": "Fixtures",
            "kind": kind, "summary": "A test theme.", "variantOf": NSNull(), "coverage": pack.coverage.map(\.rawValue), "extras": pack.extras.map(\.rawValue),
            "minimumAppBuild": 0, "licence": "Test fixture", "provenance": ["type": "fixture"],
            "pack": ["url": assetBase + tag + "/\(pack.id)-\(pack.version).arkivtheme", "size": data.count, "sha256": sha256(data),
                     "installedSize": installedSize ?? pack.installedSize, "files": pack.entries.count],
            "preview": ["url": assetBase + tag + "/\(pack.id)-\(pack.version).preview.arkivtheme", "size": preview.count,
                        "sha256": sha256(preview),
                        "files": pack.previewFiles.map { ["name": $0.name, "size": $0.data.count, "sha256": sha256($0.data), "width": 128, "height": 128] }],
        ]
    }

    public static func payload(version: Int, themes: [[String: Any]], schema: Int = 1, defaultTheme: String = "seal-dark") -> Data {
        try! JSONSerialization.data(withJSONObject: ["schema": schema, "catalogVersion": version, "defaultTheme": defaultTheme, "themes": themes],
                                    options: [.sortedKeys])
    }

    public static func envelope(_ payload: Data, key: Curve25519.Signing.PrivateKey) -> Data {
        try! ThemeCatalogSignature.envelope(payload: payload, privateKey: key)
    }

    // MARK: Environment

    public final class Sandbox {
        public let directory: URL
        public let defaults: UserDefaults
        public let suite: String
        public let key = Curve25519.Signing.PrivateKey()
        public let tag = "fixture-" + UUID().uuidString.lowercased()
        public init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("arkiv-theme-tests-" + UUID().uuidString, isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suite = "Arkiv.ThemeTests." + UUID().uuidString
            defaults = UserDefaults(suiteName: suite)!
        }
        deinit {
            defaults.removePersistentDomain(forName: suite)
            ThemeFixtures.removeTree(directory)
        }
        public var store: ThemeStore {
            ThemeStore(root: directory.appendingPathComponent("Themes"), previewRoot: directory.appendingPathComponent("Previews"), defaults: defaults)
        }
        public func environment(keys: [Data]? = nil, catalogURL: URL? = ThemeFixtures.catalogURL, appBuild: Int = 30000) -> ThemeEnvironment {
            ThemeEnvironment(store: store, verifier: ThemeCatalogVerifier(publicKeys: keys ?? [key.publicKey.rawRepresentation], appBuild: appBuild),
                             catalogURL: catalogURL, configuration: { FixtureServer.configuration() })
        }
        public func provider(bundled: @escaping (DocumentIconName) -> URL? = { _ in nil },
                             bundledExtra: @escaping (DocumentIconExtra) -> URL? = { _ in nil }) -> DocumentIconProvider {
            DocumentIconProvider(store: store, bundledIcon: bundled, bundledExtra: bundledExtra)
        }
        public func url(_ name: String) -> URL { URL(string: ThemeFixtures.assetBase + tag + "/" + name)! }
        /// Serves `catalog` and every theme's pack and preview.
        public func serve(catalog payload: Data, packs: [(Pack, Data?)] = []) {
            FixtureServer.set(ThemeFixtures.catalogURL, .init(body: ThemeFixtures.envelope(payload, key: key)))
            for (pack, data) in packs {
                FixtureServer.set(url("\(pack.id)-\(pack.version).arkivtheme"), .init(body: data ?? pack.data))
                FixtureServer.set(url("\(pack.id)-\(pack.version).preview.arkivtheme"), .init(body: ThemeFixtures.zip(pack.previewFiles.map { ThemeFixtures.Entry($0.name, $0.data) })))
            }
        }
    }
}

/// In-process HTTPS stand-in. Each response can be split into chunks with a
/// delay, truncated, padded, or fail with a network error part-way.
public final class FixtureServer: URLProtocol {
    public struct Response {
        public var status: Int = 200
        public var body: Data
        public var chunkSize: Int = 32 << 10
        public var delay: TimeInterval = 0
        public var contentLength: Int?
        public var failAfter: Int?
        public var error: URLError.Code?
        public init(status: Int = 200, body: Data, chunkSize: Int = 32 << 10, delay: TimeInterval = 0,
                    contentLength: Int? = nil, failAfter: Int? = nil, error: URLError.Code? = nil) {
            self.status = status; self.body = body; self.chunkSize = chunkSize; self.delay = delay
            self.contentLength = contentLength; self.failAfter = failAfter; self.error = error
        }
    }
    private static let lock = NSLock()
    private static var routes: [String: Response] = [:]
    private static var log: [String] = []
    private var stopped = false
    private let stateLock = NSLock()

    public static func set(_ url: URL, _ response: Response) { lock.lock(); routes[url.absoluteString] = response; lock.unlock() }
    public static func requests(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return log.filter { $0 == url.absoluteString }.count }
    public static var allRequests: [String] { lock.lock(); defer { lock.unlock() }; return log }
    public static func reset() { lock.lock(); routes = [:]; log = []; lock.unlock() }

    public static func configuration() -> URLSessionConfiguration {
        let configuration = ThemeEnvironment.ephemeralConfiguration()
        configuration.protocolClasses = [FixtureServer.self]
        return configuration
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        Self.lock.lock(); Self.log.append(key); let response = Self.routes[key]; Self.lock.unlock()
        let url = request.url!
        DispatchQueue.global().async { [self] in
            guard let response else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)); return
            }
            if let code = response.error, response.failAfter == nil {
                client?.urlProtocol(self, didFailWithError: URLError(code)); return
            }
            var headers = ["Content-Type": "application/octet-stream"]
            headers["Content-Length"] = String(response.contentLength ?? response.body.count)
            let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            var offset = 0
            while offset < response.body.count {
                if isStopped { return }
                if let failAfter = response.failAfter, offset >= failAfter {
                    client?.urlProtocol(self, didFailWithError: URLError(response.error ?? .networkConnectionLost)); return
                }
                let end = min(offset + response.chunkSize, response.body.count)
                client?.urlProtocol(self, didLoad: response.body.subdata(in: offset..<end))
                offset = end
                if response.delay > 0 { Thread.sleep(forTimeInterval: response.delay) }
            }
            if !isStopped { client?.urlProtocolDidFinishLoading(self) }
        }
    }
    private var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }
    public override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}
