import CryptoKit
import UniformTypeIdentifiers
import XCTest
import ArkivThemesTestSupport
@testable import ArkivThemes

final class CatalogVerificationTests: XCTestCase {
    let key = Curve25519.Signing.PrivateKey()
    var verifier: ThemeCatalogVerifier { ThemeCatalogVerifier(publicKeys: [key.publicKey.rawRepresentation], appBuild: 30000) }

    static let base = ThemeFixtures.pack(id: "folio")
    func theme(_ id: String = "folio", tag: String = "t") -> [String: Any] {
        var pack = Self.base
        pack.id = id
        return ThemeFixtures.catalogTheme(pack, tag: tag)
    }
    func envelope(_ payload: Data, key: Curve25519.Signing.PrivateKey? = nil) -> Data { ThemeFixtures.envelope(payload, key: key ?? self.key) }

    func testValidCatalogueVerifiesAndParses() throws {
        let payload = ThemeFixtures.payload(version: 3, themes: [theme("folio"), theme("strata")])
        let verified = try verifier.verify(envelope(payload), previous: nil)
        XCTAssertEqual(verified.catalog.catalogVersion, 3)
        XCTAssertEqual(verified.catalog.themes.map(\.id), ["folio", "strata"])
        XCTAssertEqual(verified.payload, payload)
        XCTAssertEqual(verified.catalog.themes[0].coverage, ["ZIP"])
    }

    func testSignatureFailuresAreRejected() throws {
        let payload = ThemeFixtures.payload(version: 1, themes: [theme()])
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope(payload)) as? [String: Any])
        func reject(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
            let data = try! JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try verifier.verify(data, previous: nil), file: file, line: line) { error in
                XCTAssertTrue(DocumentIconThemeManager.isSecurityRejection(error), "\(error)", file: file, line: line)
            }
        }
        // Tampered payload, same signature.
        var tampered = good
        tampered["payload"] = ThemeFixtures.payload(version: 2, themes: [theme()]).base64EncodedString()
        reject(tampered)
        // Signed by another key that claims the configured key's id.
        var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope(payload, key: Curve25519.Signing.PrivateKey())) as? [String: Any])
        forged["keyID"] = good["keyID"]
        reject(forged)
        // Unknown key id.
        var unknown = good; unknown["keyID"] = "0000000000000000"; reject(unknown)
        // Raw payload signature without the domain-separation context.
        var raw = good; raw["signature"] = try key.signature(for: payload).base64EncodedString(); reject(raw)
        // Malformed envelopes.
        var extra = good; extra["unsigned"] = "x"; reject(extra)
        var schema = good; schema["schema"] = 2; reject(schema)
        var shortSignature = good; shortSignature["signature"] = Data(count: 63).base64EncodedString(); reject(shortSignature)
        XCTAssertThrowsError(try verifier.verify(Data("not json".utf8), previous: nil))
        XCTAssertThrowsError(try verifier.verify(Data(count: ThemeLimits.catalogBytes + 1), previous: nil))
    }

    func testUnconfiguredBuildNeverAcceptsACatalogue() {
        let unconfigured = ThemeCatalogVerifier(publicKeys: [], appBuild: 1)
        XCTAssertFalse(unconfigured.isConfigured)
        XCTAssertThrowsError(try unconfigured.verify(envelope(ThemeFixtures.payload(version: 1, themes: [theme()])), previous: nil)) {
            XCTAssertEqual($0 as? ThemeError, .notConfigured)
        }
        XCTAssertFalse(ThemeCatalogVerifier(publicKeys: [Data(count: 31)], appBuild: 1).isConfigured)
    }

    func testRollbackAndEquivocationAreRejected() throws {
        let v5 = try verifier.verify(envelope(ThemeFixtures.payload(version: 5, themes: [theme()])), previous: nil)
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 4, themes: [theme()])), previous: v5)) {
            XCTAssertEqual($0 as? ThemeError, .rollback(cached: 5, received: 4))
        }
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 5, themes: [theme("other")])), previous: v5))
        XCTAssertNoThrow(try verifier.verify(v5.envelope, previous: v5), "Re-reading the same catalogue is fine")
        XCTAssertEqual(try verifier.verify(envelope(ThemeFixtures.payload(version: 6, themes: [theme()])), previous: v5).catalog.catalogVersion, 6)
    }

    func testInvalidCatalogueContentIsRejected() throws {
        func rejects(_ mutate: (inout [String: Any]) -> Void, version: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
            var t = theme()
            mutate(&t)
            XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: version, themes: [t])), previous: nil), file: file, line: line)
        }
        func pack(_ t: inout [String: Any], _ key: String, _ value: Any) { var p = t["pack"] as! [String: Any]; p[key] = value; t["pack"] = p }
        rejects { $0["id"] = "../folio" }
        rejects { $0["id"] = "Folio" }
        rejects { $0["id"] = "seal-dark" }
        rejects { $0["version"] = 0 }
        rejects { $0["name"] = "" }
        rejects { $0["name"] = "Bad\u{0007}name" }
        rejects { $0["coverage"] = ["ZIP", "EXE"] }
        rejects { $0["coverage"] = [String]() }
        rejects { $0["coverage"] = ["ZIP", "ZIP"] }
        rejects { $0["extras"] = ["../x"] }
        rejects { $0["variantOf"] = "missing-parent" }
        rejects { pack(&$0, "url", "http://github.com/ish4ra/Arkiv/releases/download/t/x.arkivtheme") }
        rejects { pack(&$0, "url", "https://example.com/ish4ra/Arkiv/releases/download/t/x.arkivtheme") }
        rejects { pack(&$0, "url", "https://github.com/ish4ra/Arkiv/releases/download/t/x.arkivtheme?x=1") }
        rejects { pack(&$0, "size", ThemeLimits.packBytes + 1) }
        rejects { pack(&$0, "size", 0) }
        rejects { pack(&$0, "sha256", "ABC") }
        rejects { pack(&$0, "installedSize", ThemeLimits.installedBytes + 1) }
        rejects { pack(&$0, "files", ThemeLimits.files + 1) }
        rejects { var p = $0["preview"] as! [String: Any]; p["files"] = [[String: Any]](); $0["preview"] = p }
        // Schema from the future, the wrong default, duplicates and too many themes.
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 1, themes: [theme()], schema: 2)), previous: nil)) {
            XCTAssertEqual($0 as? ThemeError, .requiresNewerArkiv)
        }
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 1, themes: [theme()], defaultTheme: "folio")), previous: nil))
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 1, themes: [theme("a", tag: "1"), theme("a", tag: "2")])), previous: nil))
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 0, themes: [theme()])), previous: nil))
        let many = (0...ThemeLimits.themes).map { theme("t\($0)", tag: "\($0)") }
        XCTAssertThrowsError(try verifier.verify(envelope(ThemeFixtures.payload(version: 1, themes: many)), previous: nil))
    }

    func testKeyRotationAcceptsAnyConfiguredKey() throws {
        let next = Curve25519.Signing.PrivateKey()
        let rotating = ThemeCatalogVerifier(publicKeys: [key.publicKey.rawRepresentation, next.publicKey.rawRepresentation], appBuild: 1)
        XCTAssertNoThrow(try rotating.verify(envelope(ThemeFixtures.payload(version: 1, themes: [theme()]), key: next), previous: nil))
        XCTAssertEqual(ThemeCatalogSignature.keyID(key.publicKey.rawRepresentation).count, 16)
    }

    func testHostPolicy() {
        let policy = ThemeHostPolicy.github
        XCTAssertTrue(policy.allowsAsset(URL(string: "https://github.com/ish4ra/Arkiv/releases/download/document-icon-themes-v1/folio-1.arkivtheme")!))
        XCTAssertFalse(policy.allowsAsset(URL(string: "https://github.com/someone/Arkiv/releases/download/x/folio.arkivtheme")!))
        XCTAssertFalse(policy.allowsAsset(URL(string: "https://github.com/ish4ra/Arkiv/releases/download/../../x")!))
        XCTAssertTrue(policy.allowsRedirect(URL(string: "https://objects.githubusercontent.com/github-production-release-asset/1")!))
        XCTAssertTrue(policy.allowsRedirect(URL(string: "https://release-assets.githubusercontent.com/x")!))
        XCTAssertFalse(policy.allowsRedirect(URL(string: "http://objects.githubusercontent.com/x")!))
        XCTAssertFalse(policy.allowsRedirect(URL(string: "https://evil.example/x")!))
        XCTAssertFalse(policy.allowsRedirect(nil))
    }

    func testFileNameMappingMatchesInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let declarations = ((plist["UTImportedTypeDeclarations"] as? [[String: Any]]) ?? [])
        var checked = 0
        for type in types {
            guard let icon = type["CFBundleTypeIconFile"] as? String else { continue }
            let name = String(icon.dropFirst("Arkiv-".count)).replacingOccurrences(of: ".icns", with: "")
            let utis = type["LSItemContentTypes"] as? [String] ?? []
            var extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
            for declaration in declarations where utis.contains(declaration["UTTypeIdentifier"] as? String ?? "") {
                extensions += ((declaration["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String]) ?? []
            }
            for ext in extensions {
                XCTAssertEqual(DocumentIconName.forFileName("archive." + ext)?.rawValue, name, ext)
                checked += 1
            }
        }
        // Types macOS itself declares (confirmed on the CI runners; see docs/document-icons.md).
        for ext in ["zip", "tar", "tgz", "tbz2", "tbz", "txz"] {
            guard let uti = UTType(filenameExtension: ext)?.identifier,
                  let type = types.first(where: { ($0["LSItemContentTypes"] as? [String] ?? []).contains(uti) }),
                  let icon = type["CFBundleTypeIconFile"] as? String else { XCTFail("No document type for .\(ext)"); continue }
            XCTAssertEqual(DocumentIconName.forFileName("archive." + ext).map { "Arkiv-\($0.rawValue).icns" }, icon, ext)
            checked += 1
        }
        XCTAssertEqual(checked, 13)
        XCTAssertEqual(DocumentIconName.forFileName("a.tar.gz"), .gzip, "Finder types by the last extension")
        XCTAssertEqual(DocumentIconName.forFileName("a.tar.zst"), .zstd)
        XCTAssertNil(DocumentIconName.forFileName("a.7z.001"), "No generic numeric extensions")
        XCTAssertNil(DocumentIconName.forFileName("notes.txt"))
    }
}
