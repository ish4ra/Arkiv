import AppKit
import XCTest
import ArkivThemesTestSupport
@testable import ArkivCore
@testable import ArkivThemes

/// Names map to artwork exactly as docs/format-icon-coverage.json says, in any
/// letter case, longest suffix first; split 7z volumes follow the engine's rule.
final class DocumentIconArtworkTests: XCTestCase {
    struct Row: Decodable { let name: String; let finderIcon: String?; let inApp: String?; let status: String }
    struct Table: Decodable { let rows: [Row] }

    static func artwork(_ label: String?) -> DocumentIconArtwork? {
        guard let label else { return nil }
        return DocumentIconName(rawValue: label).map(DocumentIconArtwork.icon) ?? DocumentIconExtra(rawValue: label).map(DocumentIconArtwork.extra)
    }

    func testCoverageTableInEveryLetterCase() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: root.appendingPathComponent("docs/format-icon-coverage.json")))
        XCTAssertGreaterThan(table.rows.count, 20)
        for row in table.rows {
            let expected = Self.artwork(row.inApp)
            XCTAssertEqual(row.inApp == nil, expected == nil, "\(row.name): unknown artwork \(row.inApp ?? "")")
            let stem = row.name.split(separator: ".", maxSplits: 1).map(String.init)
            for variant in [row.name, row.name.uppercased(), stem[0].capitalized + "." + stem.dropFirst().joined().capitalized] {
                XCTAssertEqual(DocumentIconArtwork.forFileName(variant), expected, variant)
                // Finder types by the last extension only.
                XCTAssertEqual(DocumentIconName.forFileName(variant)?.rawValue, row.finderIcon, "Finder: \(variant)")
            }
        }
    }

    func testCompoundSuffixesAndVolumes() {
        XCTAssertEqual(DocumentIconArtwork.forFileName("Sparkle-2.10.0.tar.xz"), .extra(.tarXZ))
        XCTAssertEqual(DocumentIconArtwork.forFileName("Sparkle-2.10.0.xz"), .icon(.xz))
        XCTAssertEqual(DocumentIconArtwork.forFileName("Sparkle.TXZ"), .icon(.txz))
        XCTAssertEqual(DocumentIconArtwork.forFileName("backup.TAR.ZST"), .extra(.tarZstd))
        XCTAssertEqual(DocumentIconArtwork.forFileName("backup.tzst"), .extra(.tzst))
        XCTAssertEqual(DocumentIconArtwork.forFileName("backup.tar"), .icon(.tar))
        XCTAssertEqual(DocumentIconArtwork.forFileName("tar.gz"), .icon(.gzip), "A bare suffix is not a compound name")
        XCTAssertEqual(DocumentIconArtwork.forFileName("my.tar.gz.backup"), nil)
        XCTAssertEqual(DocumentIconArtwork.forFileName("x.tar.gz.zip"), .icon(.zip))
        for name in ["a.001", "a.zip.001", "a.rar.001", "a.7z.01a", "a.7z.", "a.7z", "a.z01", "a.r00", "001", "a.7z.001.txt"] {
            XCTAssertNotEqual(DocumentIconArtwork.forFileName(name), .extra(.sevenZipVolume), name)
        }
        for name in ["a.7z.001", "A.7Z.002", "a.b.7z.0128", "set.7z.1"] {
            XCTAssertEqual(DocumentIconArtwork.forFileName(name), .extra(.sevenZipVolume), name)
        }
    }

    func testVolumeRuleIsTheEnginesRule() {
        for name in ["a.7z.001", "A.7Z.002", "a.001", "a.zip.001", "a.7z.01a", "a.7z.", "x.7z.12.7z.003", "a.7z.٣"] {
            XCTAssertEqual(DocumentIconArtwork.isSplitSevenZipVolume(name), SplitSevenZip.matches(URL(fileURLWithPath: "/tmp/" + name)), name)
        }
    }

    // MARK: Provider

    func pixelRed(_ image: NSImage?, file: StaticString = #filePath, line: UInt = #line) -> Int? {
        guard let rep = image?.representations.compactMap({ $0 as? NSBitmapImageRep }).first(where: { $0.pixelsWide == 16 }),
              let data = rep.bitmapData else { XCTFail("no 16 px representation", file: file, line: line); return nil }
        return Int(data[8 * rep.bytesPerRow + 8 * (rep.bitsPerPixel / 8)])
    }

    @MainActor func testInstalledThemeExtrasAndFallbacks() async throws {
        let sandbox = ThemeFixtures.Sandbox()
        FixtureServer.reset()
        // Fixture colours: red = 40 + 17 * index (+1 at x = 8); TXZ is index 0, XZ 1, TAR.XZ 2.
        let full = ThemeFixtures.pack(id: "full", coverage: [.txz, .xz], extras: [.tarXZ])
        let partial = ThemeFixtures.pack(id: "partial", coverage: [.txz])
        let classic = ThemeFixtures.pack(id: "classic-like", coverage: [.zip])
        sandbox.serve(catalog: ThemeFixtures.payload(version: 1, themes: [full, partial, classic].map { ThemeFixtures.catalogTheme($0, tag: sandbox.tag) }),
                      packs: [(full, nil), (partial, nil), (classic, nil)])
        let provider = sandbox.provider()
        let manager = DocumentIconThemeManager(environment: sandbox.environment(), provider: provider)
        manager.activate(refresh: false)
        await manager.refreshCatalogAndWait()
        for id in ["full", "partial", "classic-like"] { await manager.downloadAndWait(id) }

        try manager.apply("full")
        XCTAssertEqual(pixelRed(provider.icon(forFileName: "Sparkle-2.10.0.tar.xz")), 40 + 34 + 1, "Dedicated TAR.XZ artwork")
        XCTAssertEqual(pixelRed(provider.icon(forFileName: "Sparkle-2.10.0.XZ")), 40 + 17 + 1, "Standalone XZ artwork")
        XCTAssertEqual(pixelRed(provider.icon(forFileName: "a.txz")), 41, "TXZ artwork")
        let previews = await manager.previews(for: "full")
        XCTAssertEqual(Set(previews.keys), [.icon(.txz), .icon(.xz), .extra(.tarXZ)])

        try manager.apply("partial")
        XCTAssertEqual(pixelRed(provider.icon(forFileName: "a.tar.xz")), 41, "Without TAR.XZ artwork, the TXZ family icon is used")
        XCTAssertNil(provider.icon(forFileName: "a.tar.gz"), "No TAR.GZ and no TGZ: the system icon is kept")

        try manager.apply("classic-like")
        XCTAssertNil(provider.icon(forFileName: "a.7z.001"))
        XCTAssertNotNil(provider.icon(forFileName: "ARCHIVE.ZIP"))
    }

    func testBundledExtrasUseTheirTiersAndFallBack() throws {
        let sandbox = ThemeFixtures.Sandbox()
        let folder = sandbox.directory.appendingPathComponent("Arkiv-TAR.ZST")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, size) in [("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256)] {
            try ThemeFixtures.png(width: size, height: size).write(to: folder.appendingPathComponent(name))
        }
        let zstd = sandbox.directory.appendingPathComponent("zstd.png")
        try ThemeFixtures.png(width: 64, height: 64).write(to: zstd)
        let provider = sandbox.provider(bundled: { $0 == .zstd ? zstd : nil }, bundledExtra: { $0 == .tarZstd ? folder : nil })
        XCTAssertEqual(provider.icon(forFileName: "x.tar.zst", points: 16)?.representations.map(\.pixelsWide).sorted(), [16, 32])
        XCTAssertEqual(provider.icon(forFileName: "x.tar.zst", points: 64)?.representations.map(\.pixelsWide).sorted(), [128, 256])
        // TZST has no bundled extra here, so its family icon (ZSTD) is used.
        XCTAssertEqual(provider.icon(forFileName: "x.tzst", points: 16)?.representations.first?.pixelsWide, 64)
        // A damaged bundled extra falls back too.
        try Data("broken".utf8).write(to: folder.appendingPathComponent("icon_16x16.png"))
        let fresh = sandbox.provider(bundled: { $0 == .zstd ? zstd : nil }, bundledExtra: { $0 == .tarZstd ? folder : nil })
        XCTAssertEqual(fresh.icon(forFileName: "x.tar.zst", points: 16)?.representations.first?.pixelsWide, 64)
    }
}
