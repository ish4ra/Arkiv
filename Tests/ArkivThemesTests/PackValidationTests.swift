import XCTest
import ArkivCore
import ArkivThemesTestSupport
@testable import ArkivThemes

final class PNGValidationTests: XCTestCase {
    func testStrictPNGRules() throws {
        XCTAssertNoThrow(try ThemePNG.validate(ThemeFixtures.png(width: 32, height: 32), width: 32, height: 32))
        let cases: [(String, Data, Int)] = [
            ("wrong size", ThemeFixtures.png(width: 32, height: 32), 64),
            ("16-bit", ThemeFixtures.png(width: 16, height: 16, bitDepth: 16), 16),
            ("RGB without alpha", ThemeFixtures.png(width: 16, height: 16, colorType: 2), 16),
            ("interlaced", ThemeFixtures.png(width: 16, height: 16, interlace: 1), 16),
            ("text chunk", ThemeFixtures.png(width: 16, height: 16, extraChunks: [("tEXt", Data("Comment\0hi".utf8))]), 16),
            ("animation chunk", ThemeFixtures.png(width: 16, height: 16, extraChunks: [("acTL", Data(count: 8))]), 16),
            ("bad CRC", ThemeFixtures.png(width: 16, height: 16, corruptCRC: true), 16),
            ("data after IEND", ThemeFixtures.png(width: 16, height: 16, trailing: Data("#!/bin/sh\n".utf8)), 16),
            ("damaged image data", ThemeFixtures.png(width: 16, height: 16, idatOverride: Data(repeating: 0xAB, count: 64)), 16),
            ("not a PNG", Data("GIF89a not really".utf8) + Data(count: 64), 16),
            ("truncated", ThemeFixtures.png(width: 16, height: 16).prefix(40), 16),
        ]
        for (name, data, size) in cases {
            XCTAssertThrowsError(try ThemePNG.validate(Data(data), width: size, height: size), name)
        }
    }
}

final class PackValidationTests: XCTestCase {
    var sandbox: ThemeFixtures.Sandbox!
    override func setUp() { sandbox = ThemeFixtures.Sandbox() }
    override func tearDown() { sandbox = nil }

    /// Runs the validator on `data` as if the signed catalogue authorised it.
    func validate(_ data: Data, pack: ThemeFixtures.Pack, installedSize: Int? = nil) throws -> URL {
        let entry = ThemeFixtures.catalogTheme(pack, packData: data, tag: sandbox.tag, installedSize: installedSize)
        let catalog = try ThemeCatalogVerifier(publicKeys: [sandbox.key.publicKey.rawRepresentation], appBuild: 1)
            .verify(ThemeFixtures.envelope(ThemeFixtures.payload(version: 1, themes: [entry]), key: sandbox.key), previous: nil)
        let staging = sandbox.directory.appendingPathComponent("staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let file = staging.appendingPathComponent("pack.zip")
        try data.write(to: file)
        return try ThemePackValidator().validate(pack: file, mode: .theme(catalog.catalog.themes[0]), staging: staging, cancellation: ArchiveCancellation())
    }

    func testValidPackIsAcceptedAndSealedReadOnly() throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: DocumentIconName.allCases)
        let directory = try validate(pack.data, pack: pack)
        let files = try ThemePackValidator.regularFiles(in: directory)
        XCTAssertEqual(files.count, pack.entries.count)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("Arkiv-ZIP.iconset/icon_16x16.png").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o444)
    }

    func testHostilePacksAreRejected() throws {
        let base = ThemeFixtures.pack(id: "folio")
        let png = ThemeFixtures.png(width: 16, height: 16)
        var cases: [(String, [ThemeFixtures.Entry])] = [
            ("parent traversal", base.entries + [ThemeFixtures.Entry("../escape.png", png)]),
            ("absolute path", base.entries + [ThemeFixtures.Entry("/tmp/arkiv-escape.png", png)]),
            ("nested traversal", base.entries + [ThemeFixtures.Entry("Arkiv-ZIP.iconset/../../escape.png", png)]),
            ("symbolic link", base.entries + [ThemeFixtures.Entry("Arkiv-ZIP.iconset/link.png", Data("/etc/passwd".utf8), mode: 0o120777)]),
            ("link replacing an icon", [base.entries[0]] + base.entries.dropFirst().map { $0.name.hasSuffix("icon_16x16.png") ? ThemeFixtures.Entry($0.name, Data("/etc".utf8), mode: 0o120777) : $0 }),
            ("directory entry", base.entries + [ThemeFixtures.Entry("Arkiv-ZIP.iconset/", Data(), mode: 0o040755)]),
            ("duplicate path", base.entries + [base.entries[1]]),
            ("case conflict", base.entries + [ThemeFixtures.Entry(base.entries[1].name.uppercased(), base.entries[1].data)]),
            ("executable", [base.entries[0]] + base.entries.dropFirst().map { ThemeFixtures.Entry($0.name, $0.data, mode: 0o100755) }),
            ("script", base.entries + [ThemeFixtures.Entry("Arkiv-ZIP.iconset/install.sh", Data("#!/bin/sh\nrm -rf ~\n".utf8))]),
            ("unexpected folder", base.entries + [ThemeFixtures.Entry("Contents/MacOS/Arkiv", png)]),
            ("unknown icon", base.entries + [ThemeFixtures.Entry("Arkiv-EXE.iconset/icon_16x16.png", png)]),
            ("icon outside coverage", base.entries + [ThemeFixtures.Entry("Arkiv-RAR.iconset/icon_16x16.png", png)]),
            ("missing manifest", Array(base.entries.dropFirst())),
            ("encrypted entry flag", [base.entries[0]] + base.entries.dropFirst().map { ThemeFixtures.Entry($0.name, $0.data, flags: 1) }),
        ]
        // Manifest problems.
        func manifest(_ change: (inout [String: Any]) -> Void) -> [ThemeFixtures.Entry] {
            var m = base.manifest; change(&m)
            return [ThemeFixtures.Entry("theme.json", ThemeFixtures.manifestData(m))] + base.entries.dropFirst()
        }
        cases.append(("manifest names another theme", manifest { $0["id"] = "strata" }))
        cases.append(("manifest misses a representation", manifest {
            var icons = $0["icons"] as! [String: [String: String]]; icons["ZIP"]?["icon_512x512@2x.png"] = nil; $0["icons"] = icons }))
        cases.append(("manifest with wrong checksum", manifest {
            var files = $0["files"] as! [[String: Any]]; files[0]["sha256"] = String(repeating: "0", count: 64); $0["files"] = files }))
        cases.append(("manifest with wrong dimensions", manifest {
            var files = $0["files"] as! [[String: Any]]; files[0]["width"] = 17; $0["files"] = files }))
        cases.append(("manifest maps to an unlisted file", manifest {
            var icons = $0["icons"] as! [String: [String: String]]; icons["ZIP"]?["icon_16x16.png"] = "Arkiv-ZIP.iconset/missing.png"; $0["icons"] = icons }))
        cases.append(("malformed manifest", [ThemeFixtures.Entry("theme.json", Data("{".utf8))] + base.entries.dropFirst()))
        // Malformed or mis-sized images behind a correct manifest checksum.
        func replacing(_ data: Data) -> [ThemeFixtures.Entry] {
            var m = base.manifest
            var files = m["files"] as! [[String: Any]]
            let index = files.firstIndex { ($0["path"] as! String).hasSuffix("icon_16x16.png") }!
            files[index]["sha256"] = ThemeFixtures.sha256(data); files[index]["size"] = data.count; m["files"] = files
            return [ThemeFixtures.Entry("theme.json", ThemeFixtures.manifestData(m))] + base.entries.dropFirst().map {
                $0.name.hasSuffix("icon_16x16.png") ? ThemeFixtures.Entry($0.name, data) : $0 }
        }
        cases.append(("corrupted PNG", replacing(ThemeFixtures.png(width: 16, height: 16, corruptCRC: true))))
        cases.append(("unexpected dimensions", replacing(ThemeFixtures.png(width: 24, height: 24))))
        cases.append(("not an image", replacing(Data("#!/bin/sh\necho hi\n".utf8))))

        for (name, entries) in cases {
            let data = ThemeFixtures.zip(entries)
            XCTAssertThrowsError(try validate(data, pack: base, installedSize: entries.reduce(0) { $0 + $1.data.count }), name)
        }
    }

    func testSizeLimitsAreEnforced() throws {
        let base = ThemeFixtures.pack(id: "folio")
        // A single file above the per-file limit.
        let huge = Data(count: ThemeLimits.fileBytes + 1)
        XCTAssertThrowsError(try validate(ThemeFixtures.zip(base.entries + [ThemeFixtures.Entry("Arkiv-ZIP.iconset/icon_128x128@2x.png", huge)]), pack: base))
        // Too many files.
        let many = (0..<(ThemeLimits.files + 1)).map { ThemeFixtures.Entry("Arkiv-ZIP.iconset/icon_16x16-\($0).png", Data([1])) }
        XCTAssertThrowsError(try validate(ThemeFixtures.zip(base.entries + many), pack: base))
        // Installed size different from the signed catalogue.
        XCTAssertThrowsError(try validate(base.data, pack: base, installedSize: base.installedSize + 1))
        // Not a ZIP at all.
        XCTAssertThrowsError(try validate(Data("7z\u{BC}\u{AF}'\u{1C}".utf8) + Data(count: 100), pack: base))
    }

    func testCancellationStopsValidation() throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: [.zip, .rar])
        let entry = ThemeFixtures.catalogTheme(pack, tag: sandbox.tag)
        let catalog = try ThemeCatalogVerifier(publicKeys: [sandbox.key.publicKey.rawRepresentation], appBuild: 1)
            .verify(ThemeFixtures.envelope(ThemeFixtures.payload(version: 1, themes: [entry]), key: sandbox.key), previous: nil)
        let staging = sandbox.directory.appendingPathComponent("cancelled")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try pack.data.write(to: staging.appendingPathComponent("pack.zip"))
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try ThemePackValidator().validate(pack: staging.appendingPathComponent("pack.zip"), mode: .theme(catalog.catalog.themes[0]),
                                                                staging: staging, cancellation: token)) {
            XCTAssertEqual($0 as? ThemeError, .cancelled)
        }
    }
}
