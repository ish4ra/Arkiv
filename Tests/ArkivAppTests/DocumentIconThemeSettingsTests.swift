import AppKit
import XCTest
import ArkivPresentation
@testable import ArkivCore
import ArkivThemes
import ArkivThemesTestSupport
@testable import ArkivApp

@MainActor
func waitUntil(_ timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("Timed out", file: file, line: line); return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

final class DocumentIconThemeSettingsTests: XCTestCase {
    var sandbox: ThemeFixtures.Sandbox!
    override func setUp() { super.setUp(); FixtureServer.reset(); sandbox = ThemeFixtures.Sandbox() }
    override func tearDown() { sandbox = nil; super.tearDown() }

    @MainActor func settings(_ manager: @escaping @MainActor () -> DocumentIconThemeManager) -> SettingsWindowController {
        _ = NSApplication.shared
        return SettingsWindowController(preferences: AppPreferences(defaults: sandbox.defaults),
            recents: RecentArchives(urls: { [] }, note: { _ in }, clear: {}),
            updates: UpdateController(publicKey: { nil }, makeDriver: { fatalError("Keyless build") }),
            showFinder: {}, themeManager: manager)
    }

    @MainActor func testAppearancePaneIsLazyAndDrivesTheFullThemeLifecycle() async throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: DocumentIconName.allCases)
        let variation = ThemeFixtures.pack(id: "folio-variant", coverage: [.zip])
        var entry = ThemeFixtures.catalogTheme(variation, tag: sandbox.tag, kind: "variation")
        entry["variantOf"] = "folio"
        sandbox.serve(catalog: ThemeFixtures.payload(version: 1, themes: [ThemeFixtures.catalogTheme(pack, tag: sandbox.tag), entry]),
                      packs: [(pack, nil), (variation, nil)])
        let provider = sandbox.provider()
        var made = 0
        let controller = settings { made += 1; return DocumentIconThemeManager(environment: self.sandbox.environment(), provider: provider) }
        defer { controller.close() }
        controller.present()
        XCTAssertEqual(made, 0, "Opening Settings creates no theme manager")
        XCTAssertFalse(controller.isThemePaneLoaded)
        XCTAssertEqual(FixtureServer.requests(ThemeFixtures.catalogURL), 0, "No catalogue request until the pane is shown")

        controller.showAppearance()
        XCTAssertEqual(made, 1)
        let pane = controller.themePane
        try await waitUntil { pane.manager.catalogStatus == .current }
        XCTAssertEqual(FixtureServer.requests(ThemeFixtures.catalogURL), 1)
        XCTAssertGreaterThanOrEqual(controller.window!.frame.width, 820)

        // Bundled default first, then the family; the variation follows its parent.
        XCTAssertEqual(pane.rows.map { row -> String in
            switch row { case .group(let title): return "# " + title; case .theme(let e): return e.id }
        }, ["# Included with Arkiv", "seal-dark", "# Fixtures", "folio", "folio-variant"])
        XCTAssertEqual(pane.shownID, "seal-dark")
        XCTAssertTrue(pane.removeButton.isHidden, "The bundled theme cannot be removed")
        XCTAssertTrue(pane.downloadButton.isHidden)
        XCTAssertEqual(pane.applyButton.title, "In Use")
        XCTAssertFalse(pane.restoreButton.isEnabled)
        XCTAssertTrue(pane.catalogLabel.stringValue.contains("Catalogue verified"))

        pane.show("folio")
        XCTAssertEqual(pane.nameLabel.stringValue, "Fixture folio")
        XCTAssertFalse(pane.downloadButton.isHidden)
        XCTAssertTrue(pane.applyButton.isHidden)
        XCTAssertTrue(pane.sizeLabel.stringValue.contains("Download"))
        await pane.waitForPreviews()
        XCTAssertEqual(pane.previewViews.values.filter { $0.image != nil }.count, 11, "Previews are the theme's own artwork from its signed preview pack")

        FixtureServer.set(sandbox.url("folio-1.arkivtheme"), .init(body: pack.data, chunkSize: 2048, delay: 0.005))
        pane.downloadButton.performClick(nil)
        try await waitUntil { !pane.progress.isHidden }
        XCTAssertFalse(pane.cancelButton.isHidden)
        XCTAssertTrue(pane.downloadButton.isHidden)
        try await waitUntil { pane.manager.entry("folio")?.status == .installed }
        XCTAssertEqual(provider.effectiveSelection, .bundled, "Download alone never changes the theme in use")
        XCTAssertFalse(pane.applyButton.isHidden)
        XCTAssertFalse(pane.removeButton.isHidden)

        pane.applyButton.performClick(nil)
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "folio", version: 1))
        XCTAssertEqual(pane.applyButton.title, "In Use")
        XCTAssertTrue(pane.detailLabel.stringValue.contains("In use"))
        XCTAssertTrue(pane.restoreButton.isEnabled)

        // Removing the theme in use asks first and switches to Seal Dark.
        var asked = 0
        pane.confirmRemoval = { _, _, answer in asked += 1; answer(false) }
        pane.removeButton.performClick(nil)
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "folio", version: 1), "Declining keeps everything")
        pane.confirmRemoval = { _, _, answer in asked += 1; answer(true) }
        pane.removeButton.performClick(nil)
        XCTAssertEqual(asked, 2)
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        XCTAssertEqual(pane.manager.entry("folio")?.status, .available)

        // Restore Default from another installed theme.
        pane.show("folio-variant")
        XCTAssertTrue(pane.detailLabel.stringValue.contains("Variation of Fixture folio"))
        await pane.manager.downloadAndWait("folio-variant")
        pane.applyButton.performClick(nil)
        XCTAssertEqual(provider.effectiveSelection, .installed(id: "folio-variant", version: 1))
        pane.restoreButton.performClick(nil)
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        XCTAssertEqual(sandbox.store.selection, .bundled)

        // Leaving the tab releases previews; returning reuses the verified catalogue.
        controller.window?.close()
        XCTAssertNil(pane.previewsShownFor)
        XCTAssertTrue(pane.previewViews.values.allSatisfy { $0.image == nil })
    }

    @MainActor func testOfflineAndUnconfiguredStates() async throws {
        let pack = ThemeFixtures.pack(id: "folio")
        sandbox.serve(catalog: ThemeFixtures.payload(version: 1, themes: [ThemeFixtures.catalogTheme(pack, tag: sandbox.tag)]), packs: [(pack, nil)])
        let provider = sandbox.provider()
        let online = DocumentIconThemeManager(environment: sandbox.environment(), provider: provider)
        online.activate(refresh: false)
        await online.refreshCatalogAndWait()
        online.deactivate()

        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: Data(), error: .notConnectedToInternet))
        let controller = settings { DocumentIconThemeManager(environment: self.sandbox.environment(), provider: provider) }
        defer { controller.close() }
        controller.present(); controller.showAppearance()
        let pane = controller.themePane
        try await waitUntil { if case .offline = pane.manager.catalogStatus { return true }; return false }
        XCTAssertTrue(pane.catalogLabel.stringValue.hasPrefix("Offline"))
        XCTAssertEqual(pane.rows.count, 4, "The last verified catalogue is still listed")
        XCTAssertTrue(pane.refreshButton.isEnabled)

        let unconfigured = settings { DocumentIconThemeManager(environment: self.sandbox.environment(keys: []), provider: provider) }
        defer { unconfigured.close() }
        unconfigured.present(); unconfigured.showAppearance()
        XCTAssertTrue(unconfigured.themePane.catalogLabel.stringValue.contains("not configured"))
        XCTAssertFalse(unconfigured.themePane.refreshButton.isEnabled)
        XCTAssertEqual(unconfigured.themePane.rows.count, 2)
    }

    @MainActor func testFinderBoundaryIsExplained() {
        let pane = DocumentIconThemePane(manager: DocumentIconThemeManager(environment: sandbox.environment(keys: []), provider: sandbox.provider()))
        func texts(_ view: NSView) -> [String] { ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(texts) }
        let all = texts(pane).joined(separator: " ")
        XCTAssertTrue(all.contains("Downloaded themes apply inside Arkiv"))
        XCTAssertTrue(all.contains("Finder keeps Arkiv’s bundled Seal Dark document icons, and only when Arkiv is the default app"))
        XCTAssertTrue(all.contains("optional Quick Look thumbnail setting is planned"))
        XCTAssertTrue(all.contains("Inside Arkiv only: .tar.gz"))
    }

    @MainActor func testArchiveRowsAndInspectorUseTheSelectedTheme() async throws {
        let pack = ThemeFixtures.pack(id: "folio", coverage: [.zip])
        sandbox.serve(catalog: ThemeFixtures.payload(version: 1, themes: [ThemeFixtures.catalogTheme(pack, tag: sandbox.tag)]), packs: [(pack, nil)])
        let provider = sandbox.provider()
        let manager = DocumentIconThemeManager(environment: sandbox.environment(), provider: provider)
        manager.activate(refresh: false)
        await manager.refreshCatalogAndWait()
        await manager.downloadAndWait("folio")
        try manager.apply("folio")
        let cell = ArchiveCellView(column: "name")
        cell.configure(BrowserRow(path: "inner.zip", name: "inner.zip", size: 10, isDirectory: false), column: "name", searching: false, documentIcons: provider)
        let image = try XCTUnwrap(cell.imageView?.image)
        XCTAssertEqual(Set(image.representations.map(\.pixelsWide)), [16, 32], "Themed 16 pt artwork")
        cell.configure(BrowserRow(path: "notes.txt", name: "notes.txt", size: 10, isDirectory: false), column: "name", searching: false, documentIcons: provider)
        XCTAssertNotEqual(Set(cell.imageView?.image?.representations.map(\.pixelsWide) ?? []), [16, 32], "Other files keep their system icon")
        cell.configure(BrowserRow(path: "inner.rar", name: "inner.rar", size: 10, isDirectory: false), column: "name", searching: false, documentIcons: provider)
        XCTAssertNotNil(cell.imageView?.image, "Formats the theme does not cover keep the system icon")
    }
}
