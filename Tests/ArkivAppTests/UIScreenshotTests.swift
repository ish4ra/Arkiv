import AppKit
import XCTest
import ArkivCore
import ArkivPresentation
import ArkivThemes
import ArkivThemesTestSupport
@testable import ArkivApp

/// Genuine screenshots of the real windows, drawn by AppKit on a macOS CI
/// runner. Set ARKIV_UI_SCREENSHOTS to an output folder and ARKIV_APP to the
/// built Arkiv.app (its app icon and bundled Seal Dark document icons are
/// used, exactly as the packaged app uses them). Skipped otherwise.
///
/// These are headless CI captures: the window server draws them offscreen,
/// with no desktop wallpaper behind translucent materials.
final class UIScreenshotTests: XCTestCase {
    @MainActor func capture(_ window: NSWindow, _ url: URL) throws {
        window.displayIfNeeded()
        let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
    @MainActor func settle() async throws { try await Task.sleep(nanoseconds: 400_000_000) }

    @MainActor func testCaptureRedesignedWindows() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ARKIV_UI_SCREENSHOTS"],
              let appPath = ProcessInfo.processInfo.environment["ARKIV_APP"] else { throw XCTSkip("Set ARKIV_UI_SCREENSHOTS and ARKIV_APP") }
        let output = URL(fileURLWithPath: outputPath), app = URL(fileURLWithPath: appPath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let resources = app.appendingPathComponent("Contents/Resources")
        let oldIcon = NSApp.applicationIconImage, oldAppearance = NSApp.appearance
        defer { NSApp.applicationIconImage = oldIcon; NSApp.appearance = oldAppearance }
        NSApp.applicationIconImage = try XCTUnwrap(NSImage(contentsOf: resources.appendingPathComponent("Arkiv.icns")))
        let sandbox = ThemeFixtures.Sandbox()
        let icons = DocumentIconProvider(store: sandbox.store,
            bundledIcon: { resources.appendingPathComponent("Arkiv-\($0.rawValue).icns") },
            bundledExtra: { resources.appendingPathComponent("DocumentIconsInApp/Arkiv-\($0.rawValue)", isDirectory: true) })
        let suite = "Arkiv.Screenshots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)

        // Fixtures: an archive to browse and a few recent archives.
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Arkiv Screenshot Fixtures")
        try? FileManager.default.removeItem(at: root)
        let archives = root.appendingPathComponent("Archives", isDirectory: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try RedesignTests.fixtureArchive(in: archives)
        let recents = [archive] + ["raw-backup.7z", "site.tar.xz", "fonts.rar", "exports.tar.gz", "Project Sources.tar"].map { archives.appendingPathComponent($0) }
        for url in recents.dropFirst() { try Data([0]).write(to: url) }

        func shot(_ window: NSWindow, _ name: String) async throws {
            try await settle()
            try capture(window, output.appendingPathComponent(name + ".png"))
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Welcome
        let welcome = BrowserWindowController(documentIcons: icons)
        welcome.preferences = preferences
        welcome.recentArchives = { recents }
        defer { welcome.close() }
        welcome.window?.setContentSize(NSSize(width: 940, height: 600))
        welcome.showWindow(nil)
        try await shot(welcome.window!, "01-welcome-recents-dark")
        let empty = BrowserWindowController(documentIcons: icons)
        empty.preferences = preferences
        defer { empty.close() }
        empty.window?.setContentSize(NSSize(width: 940, height: 600))
        empty.showWindow(nil)
        try await shot(empty.window!, "02-welcome-first-launch-dark")
        empty.window?.setContentSize(NSSize(width: 640, height: 400))
        try await shot(empty.window!, "03-welcome-minimum-size-dark")
        NSApp.appearance = NSAppearance(named: .aqua)
        try await shot(welcome.window!, "04-welcome-recents-light")
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Archive browser
        let browser = BrowserWindowController(documentIcons: icons)
        browser.preferences = preferences
        defer { browser.close() }
        browser.window?.setContentSize(NSSize(width: 1100, height: 640))
        browser.showWindow(nil)
        browser.load(archive)
        for _ in 0..<400 where browser.isBusy || browser.archiveURL == nil { try await Task.sleep(nanoseconds: 25_000_000) }
        let table = try XCTUnwrap(descendants(browser.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        if let row = (0..<table.numberOfRows).first(where: { (table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == "raw-backup.7z" }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        browser.window?.makeFirstResponder(table)
        try await shot(browser.window!, "05-browser-wide-dark")
        browser.window?.setContentSize(NSSize(width: 660, height: 420))
        try await shot(browser.window!, "06-browser-narrow-dark")
        browser.window?.setContentSize(NSSize(width: 1100, height: 640))
        NSApp.appearance = NSAppearance(named: .aqua)
        try await shot(browser.window!, "07-browser-wide-light")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        browser.search.stringValue = "IMG"
        browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: browser.search))
        try await shot(browser.window!, "08-browser-search-dark")
        browser.search.stringValue = ""
        browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: browser.search))
        preferences.density = .comfortable; preferences.alternatingRows = true; preferences.accent = .jade
        try await shot(browser.window!, "09-browser-comfortable-alternating-jade-dark")
        preferences.restoreAppearanceDefaults()
        if let albums = (0..<table.numberOfRows).first(where: { (table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == "Albums" }) {
            browser.activate(row: albums)
        }
        try await shot(browser.window!, "10-browser-folder-path-bar-dark")

        // Archive Info
        let inspector = ArchiveInspector(metadata: try XCTUnwrap(LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).metadata),
                                         iconProvider: { icons.icon(forFileName: archive.lastPathComponent, points: 64) })
        inspector.showWindow(nil)
        try await shot(inspector.window!, "11-archive-info-dark")
        inspector.close()

        // Create Archive
        let create = CreateArchiveSheet(sources: Array(recents.dropFirst().prefix(2)), encrypted: false)
        create.present(parent: nil)
        try await shot(create.window!, "12-create-archive-dark")
        create.close()

        // Settings
        let settings = SettingsWindowController(preferences: preferences, recents: RecentArchives(urls: { recents }, note: { _ in }, clear: {}),
            updates: UpdateController(publicKey: { nil }, makeDriver: { fatalError("Keyless build") }), showFinder: {},
            themeManager: { DocumentIconThemeManager(environment: sandbox.environment(keys: []), provider: icons) })
        settings.finderEnabled = { false }
        settings.currentThemeName = { "Seal Dark (included with Arkiv)" }
        settings.preview.documentIcons = icons
        defer { settings.close() }
        for (pane, name) in [(SettingsWindowController.Pane.general, "13-settings-general"), (.appearance, "14-settings-appearance"),
                             (.updates, "15-settings-updates"), (.documentIcons, "16-settings-document-icons-unconfigured")] {
            settings.present(pane: pane)
            try await shot(settings.window!, name + "-dark")
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        settings.present(pane: .appearance)
        try await shot(settings.window!, "17-settings-appearance-light")
        preferences.accent = .brass; preferences.density = .compact
        try await shot(settings.window!, "18-settings-appearance-brass-compact-light")
        preferences.restoreAppearanceDefaults()

        let files = try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".png") }
        XCTAssertGreaterThanOrEqual(files.count, 18)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
