import AppKit
import XCTest
import ArkivPresentation
import ArkivThemes
import ArkivThemesTestSupport
@testable import ArkivApp

/// Runs in the "Document icon themes" CI workflow against the real packs built
/// from the preserved archives (ARKIV_THEME_PACKS) and a catalogue signed by
/// scripts/document-icon-theme-catalog.swift with an isolated test key.
/// Network access is served from those local files; nothing is published.
final class DocumentIconThemeEndToEndTests: XCTestCase {
    struct Inputs {
        let packs: URL, envelope: Data, key: Data, screenshots: URL?, bundledIcons: URL?
    }
    @MainActor func inputs() throws -> Inputs {
        let env = ProcessInfo.processInfo.environment
        guard let packs = env["ARKIV_THEME_PACKS"], let catalog = env["ARKIV_THEME_CATALOG"],
              let key = env["ARKIV_THEME_PUBLIC_ED_KEY"].flatMap({ Data(base64Encoded: $0) }) else {
            throw XCTSkip("Set ARKIV_THEME_PACKS, ARKIV_THEME_CATALOG and ARKIV_THEME_PUBLIC_ED_KEY (CI theme workflow)")
        }
        return Inputs(packs: URL(fileURLWithPath: packs), envelope: try Data(contentsOf: URL(fileURLWithPath: catalog)), key: key,
                      screenshots: env["ARKIV_THEME_SCREENSHOTS"].map { URL(fileURLWithPath: $0) },
                      bundledIcons: env["ARKIV_BUNDLED_ICONS"].map { URL(fileURLWithPath: $0) })
    }

    /// Routes the catalogue and every pack and preview URL to the local build output.
    @MainActor func route(_ inputs: Inputs, slow: String? = nil) throws -> ThemeCatalog {
        FixtureServer.reset()
        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: inputs.envelope))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: inputs.envelope) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: object["payload"] as? String ?? ""))
        let catalog = try JSONDecoder().decode(ThemeCatalog.self, from: payload)
        for theme in catalog.themes {
            for url in [theme.pack.url, theme.preview.url] {
                let body = try Data(contentsOf: inputs.packs.appendingPathComponent(url.lastPathComponent))
                FixtureServer.set(url, theme.id == slow && url == theme.pack.url ? .init(body: body, chunkSize: 16 << 10, delay: 0.05) : .init(body: body))
            }
        }
        return catalog
    }

    @MainActor func environment(_ sandbox: ThemeFixtures.Sandbox, _ inputs: Inputs) -> ThemeEnvironment {
        sandbox.environment(keys: [inputs.key])
    }

    @MainActor func bundledIcon(_ inputs: Inputs) -> (DocumentIconName) -> URL? {
        { name in inputs.bundledIcons?.appendingPathComponent("Arkiv-\(name.rawValue).iconset/icon_128x128@2x.png") }
    }

    @MainActor func testEveryArchivedThemeInstallsAppliesAndRemoves() async throws {
        let inputs = try inputs()
        let catalog = try route(inputs)
        XCTAssertEqual(catalog.themes.count, 20)
        let sandbox = ThemeFixtures.Sandbox()
        let provider = sandbox.provider()
        let manager = DocumentIconThemeManager(environment: environment(sandbox, inputs), provider: provider)
        manager.activate(refresh: false)
        await manager.refreshCatalogAndWait()
        XCTAssertEqual(manager.catalogStatus, .current, "The CLI-signed catalogue verifies with the app's verifier")

        for theme in catalog.themes {
            await manager.downloadAndWait(theme.id)
            XCTAssertNil(manager.lastError[theme.id], theme.id)
            let installed = try XCTUnwrap(sandbox.store.loadInstalled(id: theme.id, version: theme.version), theme.id)
            XCTAssertEqual(installed.manifest.files.count + 1, theme.pack.files, theme.id)
            XCTAssertEqual(Set(installed.manifest.icons.keys), Set(theme.coverage), theme.id)
            XCTAssertEqual(Set(installed.manifest.extras.keys), Set(theme.extras), theme.id)
            try manager.apply(theme.id)
            XCTAssertEqual(provider.effectiveSelection, .installed(id: theme.id, version: theme.version))
            for name in DocumentIconName.allCases {
                for (points, pixels) in [(CGFloat(16), [16, 32]), (32, [32, 64]), (128, [128, 256]), (512, [512, 1024])] {
                    let image = provider.icon(name, points: points)
                    if theme.coverage.contains(name.rawValue) {
                        XCTAssertEqual(image?.representations.map(\.pixelsWide).sorted(), pixels, "\(theme.id) \(name.rawValue) \(points)")
                    } else {
                        XCTAssertNil(image, "\(theme.id) has no \(name.rawValue) artwork; the system icon is kept")
                    }
                }
            }
            XCTAssertNil(provider.damagedTheme)
            let previews = await manager.previews(for: theme.id)
            XCTAssertEqual(previews.count, theme.coverage.count, theme.id)
        }
        XCTAssertEqual(sandbox.store.installedThemes().count, catalog.themes.count)
        // Offline: no network at all, every installed theme still applies.
        FixtureServer.reset()
        let offline = DocumentIconThemeManager(environment: environment(sandbox, inputs), provider: provider)
        offline.activate(refresh: false)
        for theme in catalog.themes { XCTAssertNoThrow(try offline.apply(theme.id)) }
        offline.restoreDefault()
        for theme in catalog.themes { try offline.remove(theme.id) }
        XCTAssertTrue(sandbox.store.installedThemes().isEmpty)
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        XCTAssertEqual(FixtureServer.allRequests, [])
    }

    @MainActor func testEveryPreviewPackVerifies() async throws {
        let inputs = try inputs()
        let catalog = try route(inputs)
        let sandbox = ThemeFixtures.Sandbox()
        let manager = DocumentIconThemeManager(environment: environment(sandbox, inputs), provider: sandbox.provider())
        manager.activate(refresh: false)
        await manager.refreshCatalogAndWait()
        for theme in catalog.themes {
            let previews = await manager.previews(for: theme.id)
            XCTAssertEqual(Set(previews.keys.map(\.rawValue)), Set(theme.coverage), theme.id)
            XCTAssertTrue(previews.values.allSatisfy { $0.representations.first?.pixelsWide == 128 })
        }
        XCTAssertTrue(sandbox.store.installedThemes().isEmpty, "Previews never install a theme")
    }

    // MARK: Screenshots of the real Settings pane with real artwork

    @MainActor func testSettingsScreenshots() async throws {
        let inputs = try inputs()
        guard let output = inputs.screenshots else { throw XCTSkip("Set ARKIV_THEME_SCREENSHOTS") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let oldAppearance = NSApp.appearance
        defer { NSApp.appearance = oldAppearance }
        _ = try route(inputs, slow: "strata")
        let sandbox = ThemeFixtures.Sandbox()
        let provider = sandbox.provider(bundled: { name in inputs.bundledIcons?.appendingPathComponent("Arkiv-\(name.rawValue).iconset/icon_16x16.png") })
        let manager = DocumentIconThemeManager(environment: environment(sandbox, inputs), provider: provider)
        manager.providerBundledIcon = bundledIcon(inputs)
        let controller = SettingsWindowController(preferences: AppPreferences(defaults: sandbox.defaults),
            recents: RecentArchives(urls: { [] }, note: { _ in }, clear: {}),
            updates: UpdateController(publicKey: { nil }, makeDriver: { fatalError("Keyless build") }),
            showFinder: {}, themeManager: { manager })
        defer { controller.close() }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        controller.present()
        controller.showAppearance()
        let pane = controller.themePane
        try await waitUntil(60) { manager.catalogStatus == .current }

        func shot(_ name: String, _ id: String) async throws {
            pane.show(id)
            await pane.waitForPreviews()
            try await Task.sleep(nanoseconds: 300_000_000)
            try capture(controller.window!, output.appendingPathComponent(name + ".png"))
        }
        try await shot("01-bundled-default-dark", "seal-dark")
        try await shot("02-available-seal-wine-dark", "seal-wine")
        await manager.downloadAndWait("seal-wine")
        try manager.apply("seal-wine")
        try await shot("03-installed-in-use-seal-wine-dark", "seal-wine")
        await manager.downloadAndWait("classic")
        try await shot("04-classic-partial-coverage-dark", "classic")
        try await shot("05-variation-seal-rar-ring-dark", "seal-rar-ring")
        pane.show("strata")
        manager.download("strata")
        try await waitUntil(60) { if case .downloading(let p)? = manager.entry("strata")?.status { return p > 0.2 }; return false }
        await pane.waitForPreviews()
        try capture(controller.window!, output.appendingPathComponent("06-download-progress-strata-dark.png"))
        manager.cancel("strata")
        try await waitUntil { !manager.isBusy("strata") }
        NSApp.appearance = NSAppearance(named: .aqua)
        try await shot("07-available-folio-light", "folio")
        await manager.downloadAndWait("folio")
        try manager.apply("folio")
        try await shot("08-installed-in-use-folio-light", "folio")
        manager.restoreDefault()
        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: Data(), error: .notConnectedToInternet))
        await manager.refreshCatalogAndWait()
        try await shot("09-offline-restored-default-light", "seal-dark")
        let files = try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".png") }
        XCTAssertGreaterThanOrEqual(files.count, 9)
    }

    /// The window as AppKit draws it, including the title bar (the frame view).
    @MainActor func capture(_ window: NSWindow, _ url: URL) throws {
        let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
