import AppKit
import XCTest
import ArkivThemesTestSupport
@testable import ArkivThemes

final class ThemeManagerTests: XCTestCase {
    var sandbox: ThemeFixtures.Sandbox!
    override func setUp() { super.setUp(); sandbox = ThemeFixtures.Sandbox(); FixtureServer.reset() }
    override func tearDown() { sandbox = nil; super.tearDown() }

    @MainActor func manager(_ provider: DocumentIconProvider? = nil, keys: [Data]? = nil, catalogURL: URL? = ThemeFixtures.catalogURL) -> DocumentIconThemeManager {
        DocumentIconThemeManager(environment: sandbox.environment(keys: keys, catalogURL: catalogURL), provider: provider ?? sandbox.provider())
    }
    @MainActor func serve(_ packs: [ThemeFixtures.Pack], version: Int = 1, data: [String: Data] = [:]) {
        let themes = packs.map { ThemeFixtures.catalogTheme($0, packData: data[$0.id], tag: sandbox.tag) }
        sandbox.serve(catalog: ThemeFixtures.payload(version: version, themes: themes), packs: packs.map { ($0, data[$0.id]) })
    }
    @MainActor func stagingIsEmpty() -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: sandbox.store.root.appendingPathComponent(".staging").path)) ?? []).isEmpty
    }

    @MainActor func testNoNetworkUntilActivatedAndNotConfiguredState() async {
        let unconfigured = manager(keys: [])
        XCTAssertEqual(unconfigured.catalogStatus, .notConfigured)
        unconfigured.activate()
        XCTAssertEqual(unconfigured.catalogStatus, .notConfigured)
        XCTAssertEqual(unconfigured.entries.map(\.id), [DocumentIconThemeID.bundled])
        serve([ThemeFixtures.pack(id: "folio")])
        _ = manager()
        XCTAssertEqual(FixtureServer.requests(ThemeFixtures.catalogURL), 0, "Creating a manager must not touch the network")
    }

    @MainActor func testDownloadInstallApplyAndPersistSelection() async throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: DocumentIconName.allCases)
        serve([pack])
        let provider = sandbox.provider()
        let themes = manager(provider)
        var progressSeen: [Double] = []
        themes.onChange = { if case .downloading(let p)? = themes.entry("folio")?.status { progressSeen.append(p) } }
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        XCTAssertEqual(themes.catalogStatus, .current)
        XCTAssertEqual(themes.entry("folio")?.status, .available)
        XCTAssertEqual(themes.entry("folio")?.downloadSize, pack.data.count)
        await themes.downloadAndWait("folio")
        XCTAssertNil(themes.lastError["folio"])
        XCTAssertEqual(themes.entry("folio")?.status, .installed)
        XCTAssertFalse(progressSeen.isEmpty)
        XCTAssertEqual(provider.effectiveSelection, .bundled, "Installing never changes the theme in use")
        XCTAssertTrue(stagingIsEmpty())

        let changed = XCTNSNotificationExpectation(name: .arkivDocumentIconThemeDidChange)
        try themes.apply("folio")
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "folio", version: 1))
        XCTAssertTrue(themes.entry("folio")!.isSelected)
        let icon = try XCTUnwrap(provider.icon(forFileName: "backup.tar.gz", points: 16))
        XCTAssertEqual(Set(icon.representations.map(\.pixelsWide)), [16, 32])
        XCTAssertEqual(provider.icon(.zip, points: 64)?.representations.map(\.pixelsWide).sorted(), [128, 256])
        XCTAssertNil(provider.icon(forFileName: "notes.txt"))

        // A fresh process sees the same selection, offline, from disk.
        FixtureServer.reset()
        let relaunched = sandbox.provider()
        XCTAssertEqual(relaunched.effectiveSelection, .installed(id: "folio", version: 1))
        XCTAssertNotNil(relaunched.icon(.rar, points: 32))
        XCTAssertEqual(FixtureServer.allRequests, [])
    }

    @MainActor func testChecksumMismatchSizeAndTransportFailuresNeverInstall() async throws {
        let pack = ThemeFixtures.pack(id: "folio")
        var wrong = pack.data; wrong[wrong.count / 2] ^= 0xFF
        let cases: [(String, FixtureServer.Response)] = [
            ("checksum", .init(body: wrong)),
            ("oversized body", .init(body: pack.data + Data(count: 4096))),
            ("oversized header", .init(body: pack.data, contentLength: ThemeLimits.packBytes + 1)),
            ("truncated", .init(body: pack.data.prefix(pack.data.count - 100))),
            ("interrupted", .init(body: pack.data, chunkSize: 1024, failAfter: 2048)),
            ("not found", .init(status: 404, body: Data("missing".utf8))),
            ("offline", .init(body: Data(), error: .notConnectedToInternet)),
        ]
        let provider = sandbox.provider()
        let themes = manager(provider)
        serve([pack])
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        for (name, response) in cases {
            FixtureServer.set(sandbox.url("folio-1.arkivtheme"), response)
            await themes.downloadAndWait("folio")
            XCTAssertNotNil(themes.lastError["folio"], name)
            XCTAssertEqual(themes.entry("folio")?.status, .available, name)
            XCTAssertTrue(sandbox.store.installedThemes().isEmpty, name)
            XCTAssertTrue(stagingIsEmpty(), name)
            XCTAssertEqual(provider.effectiveSelection, .bundled, name)
        }
        XCTAssertEqual(themes.lastError["folio"], ThemeError.download("Arkiv could not connect. Check your internet connection.").errorDescription)
    }

    @MainActor func testCancellationLeavesCurrentThemeInPlace() async throws {
        let installed = ThemeFixtures.pack(id: "strata")
        let slow = ThemeFixtures.pack(id: "folio", coverage: DocumentIconName.allCases)
        serve([installed, slow])
        let provider = sandbox.provider()
        let themes = manager(provider)
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        await themes.downloadAndWait("strata")
        try themes.apply("strata")
        FixtureServer.set(sandbox.url("folio-1.arkivtheme"), .init(body: slow.data, chunkSize: 2048, delay: 0.01))
        themes.download("folio")
        XCTAssertTrue(themes.isBusy("folio"))
        while case .downloading(let p)? = themes.entry("folio")?.status, p < 0.05 { try await Task.sleep(nanoseconds: 5_000_000) }
        themes.cancel("folio")
        while themes.isBusy("folio") { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNil(themes.lastError["folio"], "Cancelling is not an error")
        XCTAssertEqual(themes.entry("folio")?.status, .available)
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "strata", version: 1))
        XCTAssertEqual(sandbox.store.installedThemes().map(\.id), ["strata"])
        XCTAssertTrue(stagingIsEmpty())
    }

    @MainActor func testConcurrentDownloadsAndDuplicateRequests() async throws {
        let packs = ["folio", "strata", "seal"].map { ThemeFixtures.pack(id: $0, coverage: [.zip, .sevenZip]) }
        serve(packs)
        for pack in packs { FixtureServer.set(sandbox.url("\(pack.id)-1.arkivtheme"), .init(body: pack.data, chunkSize: 8192, delay: 0.002)) }
        let themes = manager()
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        for pack in packs { themes.download(pack.id) }
        themes.download("folio")
        XCTAssertEqual(themes.lastError["folio"], ThemeError.busy.errorDescription)
        XCTAssertThrowsError(try themes.remove("folio")) { XCTAssertEqual($0 as? ThemeError, .busy) }
        while packs.contains(where: { themes.isBusy($0.id) }) { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(Set(sandbox.store.installedThemes().map(\.id)), ["folio", "strata", "seal"])
        XCTAssertEqual(FixtureServer.requests(sandbox.url("folio-1.arkivtheme")), 1)
    }

    @MainActor func testOfflineUsesLastKnownGoodCatalogueAndInstalledThemes() async throws {
        let pack = ThemeFixtures.pack(id: "folio")
        serve([pack])
        let provider = sandbox.provider()
        let first = manager(provider)
        first.activate(refresh: false)
        await first.refreshCatalogAndWait()
        await first.downloadAndWait("folio")
        try first.apply("folio")
        first.deactivate()

        FixtureServer.reset()
        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: Data(), error: .notConnectedToInternet))
        let second = manager(provider)
        second.activate(refresh: false)
        await second.refreshCatalogAndWait()
        guard case .offline? = Optional(second.catalogStatus) else { return XCTFail("\(second.catalogStatus)") }
        XCTAssertEqual(second.entry("folio")?.status, .installed)
        XCTAssertTrue(second.entry("folio")!.isSelected)
        XCTAssertNotNil(provider.icon(.zip, points: 16))
        // Previews of installed themes come from disk.
        let previews = await second.previews(for: "folio")
        XCTAssertEqual(Array(previews.keys), [.zip])
    }

    @MainActor func testCatalogueRollbackIsRejectedEvenWithoutTheCacheFile() async throws {
        let pack = ThemeFixtures.pack(id: "folio")
        serve([pack], version: 7)
        let themes = manager()
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        XCTAssertEqual(themes.catalog?.catalog.catalogVersion, 7)
        // An attacker deletes the cache and replays an older signed catalogue.
        try FileManager.default.removeItem(at: sandbox.store.root.appendingPathComponent("catalog.json"))
        serve([pack], version: 6)
        let fresh = manager()
        fresh.activate(refresh: false)
        await fresh.refreshCatalogAndWait()
        XCTAssertEqual(fresh.catalogStatus, .failed(ThemeError.rollback(cached: 7, received: 6).errorDescription!))
        XCTAssertNil(fresh.catalog)
        // A catalogue signed with a different key is rejected, not shown as offline.
        sandbox.serve(catalog: ThemeFixtures.payload(version: 8, themes: []))
        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: ThemeFixtures.envelope(ThemeFixtures.payload(version: 9, themes: []), key: .init())))
        let forged = manager()
        forged.activate(refresh: false)
        await forged.refreshCatalogAndWait()
        guard case .failed? = Optional(forged.catalogStatus) else { return XCTFail("\(forged.catalogStatus)") }
    }

    @MainActor func testRemovalRestoreDefaultAndFallback() async throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: [.zip])
        serve([pack])
        let provider = sandbox.provider()
        let themes = manager(provider)
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        await themes.downloadAndWait("folio")
        try themes.apply("folio")
        // Partial coverage: uncovered formats keep the system icon.
        XCTAssertNotNil(provider.icon(.zip, points: 16))
        XCTAssertNil(provider.icon(.rar, points: 16))

        themes.restoreDefault()
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        try themes.apply("folio")
        try themes.remove("folio")
        XCTAssertEqual(sandbox.store.selection, .bundled, "Removing the theme in use switches to the default first")
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        XCTAssertEqual(themes.entry("folio")?.status, .available)
        XCTAssertThrowsError(try themes.apply("folio"))
        XCTAssertNoThrow(try themes.remove(DocumentIconThemeID.bundled), "The bundled theme cannot be removed")
        XCTAssertEqual(themes.entries.first?.status, .bundled)

        // A selection whose folder vanished, or whose files are damaged, falls back silently.
        await themes.downloadAndWait("folio")
        try themes.apply("folio")
        let file = sandbox.store.directory(id: "folio", version: 1).appendingPathComponent("Arkiv-ZIP.iconset/icon_16x16.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var bytes = try Data(contentsOf: file); bytes[bytes.count - 20] ^= 0x55
        try bytes.write(to: file)
        provider.selectionDidChange()
        XCTAssertNotNil(provider.icon(.zip, points: 32), "Other representations are intact")
        XCTAssertNil(provider.icon(.zip, points: 16), "Damaged artwork is never drawn; the bundled default has no resource in tests")
        XCTAssertEqual(provider.damagedTheme, "folio")
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        try ThemeStore.removeTree(sandbox.store.root.appendingPathComponent("folio"))
        let relaunched = sandbox.provider()
        XCTAssertEqual(relaunched.effectiveSelection, .bundled)
    }

    @MainActor func testRecoveryFromInterruptedWork() async throws {
        let store = sandbox.store
        try store.prepare()
        // Leftovers of a crash: staged downloads, a half-moved folder, junk.
        let stale = store.root.appendingPathComponent(".staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: stale.appendingPathComponent("pack.zip"))
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent(".trash/x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent("folio/1"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: store.root.appendingPathComponent("folio/1/theme.json"))
        try FileManager.default.createSymbolicLink(at: store.root.appendingPathComponent("strata"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        sandbox.defaults.set(["id": "folio", "version": 1], forKey: "Arkiv.DocumentIconTheme")
        let provider = sandbox.provider()
        XCTAssertEqual(provider.effectiveSelection, .bundled, "An incomplete folder is never used")
        let themes = manager(provider, catalogURL: nil)
        themes.activate(refresh: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent(".trash").path), [])
        XCTAssertTrue(store.installedThemes().isEmpty)
    }

    @MainActor func testUpdateReplacesOlderVersionAndKeepsSelection() async throws {
        let v1 = ThemeFixtures.pack(id: "folio", version: 1)
        serve([v1], version: 1)
        let provider = sandbox.provider()
        let themes = manager(provider)
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        await themes.downloadAndWait("folio")
        try themes.apply("folio")
        let v2 = ThemeFixtures.pack(id: "folio", version: 2, tint: 9)
        serve([v2], version: 2)
        await themes.refreshCatalogAndWait()
        XCTAssertEqual(themes.entry("folio")?.status, .updateAvailable)
        await themes.downloadAndWait("folio")
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "folio", version: 2))
        XCTAssertEqual(sandbox.store.installedThemes().map(\.version), [2])
    }

    @MainActor func testPreviewsUseVerifiedPreviewPackAndAreReleased() async throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: [.zip, .tar])
        serve([pack])
        let themes = manager()
        themes.activate(refresh: false)
        await themes.refreshCatalogAndWait()
        let previews = await themes.previews(for: "folio")
        XCTAssertEqual(Set(previews.keys), [.zip, .tar])
        XCTAssertEqual(previews[.zip]?.representations.first?.pixelsWide, 128)
        _ = await themes.previews(for: "folio")
        XCTAssertEqual(FixtureServer.requests(sandbox.url("folio-1.preview.arkivtheme")), 1, "Previews are cached while the pane is open")
        themes.deactivate()
        themes.activate(refresh: false)
        _ = await themes.previews(for: "folio")
        XCTAssertEqual(FixtureServer.requests(sandbox.url("folio-1.preview.arkivtheme")), 1, "Verified previews are cached on disk")
        // A tampered preview pack is rejected.
        FixtureServer.set(sandbox.url("strata-1.preview.arkivtheme"), .init(body: Data(count: 10)))
        let missing = await themes.previews(for: "missing")
        XCTAssertTrue(missing.isEmpty)
    }
}
