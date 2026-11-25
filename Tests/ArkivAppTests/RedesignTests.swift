import AppKit
import XCTest
import ArkivCore
import ArkivPresentation
import ArkivThemes
import ArkivThemesTestSupport
@testable import ArkivApp

/// Regression tests for the redesigned windows: geometry at narrow and wide
/// sizes, both appearances, live presentation preferences, immediate document
/// icon theme switching, drop-to-open and accessibility labels.
final class RedesignTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func frame(_ view: NSView, in window: NSWindow) -> NSRect {
        view.convert(view.bounds, to: window.contentView!)
    }
    private func isolatedDefaults() throws -> (UserDefaults, () -> Void) {
        let name = "Arkiv.Redesign.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }
    /// A ZIP with a folder, nested archives and ordinary files.
    static func fixtureArchive(in root: URL, name: String = "Photos 2024") throws -> URL {
        let source = root.appendingPathComponent("source-\(UUID().uuidString)")
        let albums = source.appendingPathComponent("Albums/2024", isDirectory: true)
        try FileManager.default.createDirectory(at: albums, withIntermediateDirectories: true)
        for (path, bytes) in [("Albums/2024/IMG_0001.HEIC", 120_000), ("Albums/2024/IMG_0002.HEIC", 98_000), ("raw-backup.7z", 64_000),
                              ("exports.tar.gz", 48_000), ("fonts.zip", 12_000), ("site.tar.xz", 9_000), ("notes.txt", 2_000), ("Report.pdf", 30_000)] {
            try Data(repeating: UInt8(path.count % 251), count: bytes).write(to: source.appendingPathComponent(path))
        }
        let items = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        return try ArchiveCreator().create(ArchiveCreationRequest(sources: items, destination: root, name: name),
                                           cancellation: ArchiveCancellation(), progress: { _ in })
    }
    @MainActor private func waitForLoad(_ controller: BrowserWindowController) async throws {
        for _ in 0..<400 {
            if !controller.isBusy && controller.archiveURL != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
    }
    private func archiveTable(_ controller: BrowserWindowController) throws -> NSTableView {
        try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
    }
    private func row(named name: String, in table: NSTableView) -> Int? {
        (0..<table.numberOfRows).first { row in
            (table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == name
        }
    }

    // MARK: Welcome

    @MainActor func testWelcomeShowsIdentityActionsRecentsAndAcceptsDrops() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recent = root.appendingPathComponent("backup.7z"), missing = root.appendingPathComponent("gone.zip")
        try Data([1, 2, 3]).write(to: recent)
        let controller = BrowserWindowController(recentArchives: { [recent, missing, recent] })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let welcome = controller.welcome
        XCTAssertFalse(welcome.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(welcome.recentButtons.compactMap(\.toolTip), [recent.path], "Missing and duplicate recents are left out")
        XCTAssertTrue(welcome.dropZone.isHidden, "The drop zone stands in only when there is no history")
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)

        var opened: [URL] = []
        controller.onOpenURLs = { opened += $0 }
        welcome.recentButtons.first?.performClick(nil)
        XCTAssertEqual(opened, [recent])
        var created = 0, appearance: [SettingsWindowController.Pane?] = []
        controller.onCreate = { created += 1 }
        controller.onShowSettings = { appearance.append($0) }
        welcome.createButton.performClick(nil)
        welcome.appearanceButton.performClick(nil)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(appearance, [.appearance])

        // Drop to open: regular files only.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Arkiv.Redesign.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([recent as NSURL, root as NSURL])
        XCTAssertEqual(WelcomeView.droppedArchives(pasteboard), [recent], "Folders are not opened as archives")

        // Geometry at the minimum size and a wide size, in both appearances.
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 640, height: 400), NSSize(width: 1200, height: 760)] {
                window.setContentSize(size)
                window.contentView?.layoutSubtreeIfNeeded()
                let open = frame(welcome.openButton, in: window), create = frame(welcome.createButton, in: window)
                let list = frame(welcome.recentButtons[0], in: window)
                let bounds = window.contentView!.bounds
                for rect in [open, create, list] { XCTAssertTrue(bounds.contains(rect), "\(rect) outside \(bounds) at \(size)") }
                XCTAssertFalse(open.intersects(list), "Actions and recents never overlap at \(size)")
                XCTAssertEqual(open.width, create.width, accuracy: 0.5, "Primary actions share one width")
                XCTAssertGreaterThanOrEqual(open.width, welcome.openButton.intrinsicContentSize.width - 0.5, "Open is not clipped")
            }
        }

        let empty = BrowserWindowController(recentArchives: { [] })
        defer { empty.close() }
        XCTAssertFalse(empty.welcome.dropZone.isHidden)
        XCTAssertTrue(empty.welcome.recentButtons.isEmpty)
    }

    // MARK: Archive browser

    @MainActor func testBrowserToolbarPathBarAndFooterAtNarrowAndWideSizes() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try Self.fixtureArchive(in: root)
        let (defaults, cleanup) = try isolatedDefaults(); defer { cleanup() }
        let controller = BrowserWindowController(columnPreferences: BrowserColumnPreferences(defaults: defaults), preferences: AppPreferences(defaults: defaults))
        defer { controller.close() }
        controller.showWindow(nil)
        controller.load(archive)
        try await waitForLoad(controller)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.toolbar === controller.browserToolbar)
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.title, archive.lastPathComponent)
        XCTAssertTrue(window.subtitle.contains("files"), window.subtitle)
        XCTAssertTrue(controller.welcome.isHiddenOrHasHiddenAncestor)
        let items = controller.browserToolbar.items.map(\.itemIdentifier.rawValue)
        for id in ["navigation", "open", "extract", "all", "add", "test", "info", "search"] { XCTAssertTrue(items.contains(id), "\(id) in \(items)") }
        XCTAssertEqual(controller.browserToolbar.displayMode, .iconOnly)
        XCTAssertTrue(controller.browserToolbar.allowsUserCustomization)
        XCTAssertTrue(controller.browserToolbar.items.allSatisfy { !$0.label.isEmpty || $0.itemIdentifier == .flexibleSpace || $0.itemIdentifier == .space },
                      "Every item has a label for the palette, VoiceOver and Icon and Text mode")

        // Path bar: archive, then folders; clicking navigates.
        let table = try archiveTable(controller)
        let albums = try XCTUnwrap(row(named: "Albums", in: table))
        controller.activate(row: albums)
        XCTAssertEqual(controller.pathControl.pathItems.map(\.title), [archive.lastPathComponent, "Albums"])
        XCTAssertTrue(controller.validateMenuItem(NSMenuItem(title: "", action: #selector(BrowserWindowController.goBack(_:)), keyEquivalent: "")))

        let status = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.stringValue.contains("in archive") })
        for size in [NSSize(width: 640, height: 400), NSSize(width: 1280, height: 800)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            let path = frame(controller.pathControl, in: window), text = frame(status, in: window)
            XCTAssertFalse(path.intersects(text), "Path bar and status overlap at \(size)")
            XCTAssertLessThanOrEqual(text.maxX, size.width + 0.5)
            XCTAssertGreaterThanOrEqual(path.minX, 0)
            let scroll = try XCTUnwrap(table.enclosingScrollView)
            let header = frame(try XCTUnwrap(table.headerView), in: window)
            XCTAssertLessThanOrEqual(header.maxY, window.contentLayoutRect.maxY + 0.5, "The column header starts below the toolbar; rows scroll under it")
            XCTAssertLessThanOrEqual(frame(scroll, in: window).maxY, size.height + 0.5)
            XCTAssertGreaterThanOrEqual(frame(scroll, in: window).minY, frame(status, in: window).maxY - 1, "The table never runs under the footer")
        }
    }

    @MainActor func testPresentationPreferencesReachEveryOpenWindowAndPersist() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try Self.fixtureArchive(in: root)
        let (defaults, cleanup) = try isolatedDefaults(); defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        let windows = [BrowserWindowController(preferences: preferences), BrowserWindowController(preferences: preferences)]
        defer { windows.forEach { $0.close() } }
        for window in windows { window.load(archive); try await waitForLoad(window) }
        let tables = try windows.map(archiveTable)
        XCTAssertEqual(tables.map(\.rowHeight), [26, 26], "Standard density keeps the existing 26 pt rows")
        tables[0].selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        preferences.density = .comfortable
        preferences.alternatingRows = true
        preferences.accent = .jade
        for (controller, table) in zip(windows, tables) {
            XCTAssertEqual(table.rowHeight, 34)
            XCTAssertTrue(table.usesAlternatingRowBackgroundColors)
            XCTAssertEqual(controller.density, .comfortable)
            let rowView = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: true) as? ArchiveRowView)
            XCTAssertEqual(rowView.accent, ArkivStyle.color(for: .jade))
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? ArchiveCellView)
            XCTAssertEqual(cell.iconSize, 24, "Comfortable rows use larger icons")
        }
        XCTAssertEqual(tables[0].selectedRow, 1, "Changing presentation keeps the selection")
        preferences.accent = .system
        XCTAssertNil((tables[0].rowView(atRow: 0, makeIfNecessary: true) as? ArchiveRowView)?.accent, "System accent draws what macOS draws")

        // A new window (or a relaunch) reads the stored choices.
        let reopened = BrowserWindowController(preferences: AppPreferences(defaults: defaults))
        defer { reopened.close() }
        XCTAssertEqual(try archiveTable(reopened).rowHeight, 34)
        XCTAssertTrue(try archiveTable(reopened).usesAlternatingRowBackgroundColors)
        preferences.restoreAppearanceDefaults()
        XCTAssertEqual(tables[0].rowHeight, 26)
        XCTAssertFalse(tables[0].usesAlternatingRowBackgroundColors)
    }

    // MARK: Immediate theme switching

    @MainActor func testThemeSwitchUpdatesEveryIconConsumerInPlace() async throws {
        _ = NSApplication.shared
        FixtureServer.reset()
        let sandbox = ThemeFixtures.Sandbox()
        let pack = ThemeFixtures.pack(id: "folio", coverage: [.zip])
        sandbox.serve(catalog: ThemeFixtures.payload(version: 1, themes: [ThemeFixtures.catalogTheme(pack, tag: sandbox.tag)]), packs: [(pack, nil)])
        let provider = sandbox.provider()
        let manager = DocumentIconThemeManager(environment: sandbox.environment(), provider: provider)
        manager.activate(refresh: false)
        await manager.refreshCatalogAndWait()
        await manager.downloadAndWait("folio")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try Self.fixtureArchive(in: root, name: "Outer")
        let windows = [BrowserWindowController(documentIcons: provider), BrowserWindowController(documentIcons: provider)]
        defer { windows.forEach { $0.close() } }
        for window in windows { window.showWindow(nil); window.load(archive); try await waitForLoad(window) }
        let tables = try windows.map(archiveTable)
        let rows = try tables.map { try XCTUnwrap(row(named: "fonts.zip", in: $0)) }
        tables[0].selectRowIndexes(IndexSet(integer: rows[0]), byExtendingSelection: false)
        func pixelWidths(_ index: Int) -> Set<Int> {
            Set(((tables[index].view(atColumn: 0, row: rows[index], makeIfNecessary: false) as? ArchiveCellView)?.imageView?.image?.representations ?? []).map(\.pixelsWide))
        }
        XCTAssertNotEqual(pixelWidths(0), [16, 32], "Seal Dark resources are absent in tests, so the system icon is drawn")
        windows[0].showInfo(nil)
        let snapshotsBefore = windows.map(\.archiveURL)

        try manager.apply("folio")
        for index in windows.indices {
            XCTAssertEqual(pixelWidths(index), [16, 32], "Window \(index) redrew the nested archive with the theme")
        }
        XCTAssertEqual(windows.map(\.archiveURL), snapshotsBefore, "The archive was not reopened")
        XCTAssertFalse(windows.contains(where: \.isBusy), "Nothing was reread")
        XCTAssertEqual(tables[0].selectedRow, rows[0], "Selection is untouched")
        XCTAssertEqual(windows[0].pathControl.pathItems.first?.image?.representations.map(\.pixelsWide).sorted(), [16, 32], "Path bar archive icon follows the theme")
        if let sheet = windows[0].window?.attachedSheet, let inspector = sheet.windowController as? ArchiveInspector {
            XCTAssertTrue(inspector.iconView.image?.representations.contains { $0.pixelsWide == 128 } == true, "Archive Info follows the theme while open")
            windows[0].window?.endSheet(sheet)
        }

        // Relaunch: a fresh provider reads the stored selection; no network is needed.
        FixtureServer.set(ThemeFixtures.catalogURL, .init(body: Data(), error: .notConnectedToInternet))
        let relaunched = sandbox.provider()
        XCTAssertEqual(relaunched.effectiveSelection, .installed(id: "folio", version: 1))
        XCTAssertNotNil(relaunched.icon(forFileName: "a.zip", points: 16), "Installed themes work offline")

        // A damaged installed theme falls back to Seal Dark and tells every consumer.
        let damaged = expectation(forNotification: .arkivDocumentIconThemeDidChange, object: relaunched)
        let files = try FileManager.default.subpathsOfDirectory(atPath: sandbox.store.directory(id: "folio", version: 1).path).filter { $0.hasSuffix(".png") }
        for file in files { try Data("damaged".utf8).write(to: sandbox.store.directory(id: "folio", version: 1).appendingPathComponent(file)) }
        let reread = sandbox.provider()
        XCTAssertNil(reread.icon(forFileName: "b.zip", points: 32), "Damaged artwork is never drawn")
        XCTAssertEqual(reread.damagedTheme, "folio")
        XCTAssertEqual(reread.effectiveSelection, .bundled)
        await fulfillment(of: [damaged], timeout: 5)
        _ = relaunched

        // Removing the active theme switches back before deleting files.
        try manager.remove("folio")
        XCTAssertEqual(provider.effectiveSelection, .bundled)
        for index in windows.indices { XCTAssertNotEqual(pixelWidths(index), [16, 32]) }
    }

    // MARK: Settings

    @MainActor func testSettingsSidebarPanesFitAndDriveLivePreview() throws {
        _ = NSApplication.shared
        let (defaults, cleanup) = try isolatedDefaults(); defer { cleanup() }
        let sandbox = ThemeFixtures.Sandbox()
        let preferences = AppPreferences(defaults: defaults)
        var made = 0
        let controller = SettingsWindowController(preferences: preferences, recents: RecentArchives(urls: { [] }, note: { _ in }, clear: {}),
            updates: UpdateController(publicKey: { nil }, makeDriver: { fatalError("Keyless build") }), showFinder: {},
            themeManager: { made += 1; return DocumentIconThemeManager(environment: sandbox.environment(keys: []), provider: sandbox.provider()) },
            finderEnabled: { false }, currentThemeName: { "Seal Dark (included with Arkiv)" }, documentIcons: sandbox.provider())
        defer { controller.close() }
        controller.present()
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.contentView?.bounds.size, SettingsWindowController.contentSize)
        XCTAssertEqual(controller.sidebar.numberOfRows, 4)
        XCTAssertEqual(made, 0, "The theme manager is created only for the Document Icons pane")
        let oldAppearance = NSApp.appearance
        defer { NSApp.appearance = oldAppearance }
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            for pane in SettingsWindowController.Pane.allCases {
                controller.select(pane)
                window.contentView?.layoutSubtreeIfNeeded()
                XCTAssertEqual(window.frame.size, window.frameRect(forContentRect: NSRect(origin: .zero, size: SettingsWindowController.contentSize)).size,
                               "Switching to \(pane) never resizes the window")
                let bounds = window.contentView!.bounds
                for field in descendants(window.contentView!).compactMap({ $0 as? NSControl }) where !field.isHiddenOrHasHiddenAncestor && field.window != nil {
                    guard field.enclosingScrollView == nil || field.enclosingScrollView?.documentView is FlippedView else { continue }
                    let rect = frame(field, in: window)
                    XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + 0.5, "\(type(of: field)) ‘\((field as? NSTextField)?.stringValue ?? (field as? NSButton)?.title ?? "")’ clipped on the right in \(pane)")
                    if let label = field as? NSTextField, !label.isEditable, label.maximumNumberOfLines == 1, label.lineBreakMode != .byTruncatingTail, label.lineBreakMode != .byTruncatingMiddle {
                        XCTAssertGreaterThanOrEqual(rect.width + 0.5, label.intrinsicContentSize.width, "‘\(label.stringValue)’ clipped in \(pane)")
                    }
                }
            }
        }
        XCTAssertEqual(made, 1)

        controller.select(.appearance)
        XCTAssertEqual(controller.appearancePicker.segmentCount, 3)
        XCTAssertEqual(controller.accentPicker.swatches.map(\.accent), AppAccent.allCases)
        XCTAssertEqual(controller.accentPicker.selection, .arkiv, "Arkiv's accent is the default")
        XCTAssertFalse(controller.restoreDefaultsButton.isEnabled, "Nothing to restore on a new install")
        controller.accentPicker.swatches.first { $0.accent == .brass }?.performClick(nil)
        XCTAssertEqual(preferences.accent, .brass)
        controller.densityPicker.selectedSegment = 0
        controller.changeDensity(nil)
        XCTAssertEqual(preferences.density, .compact)
        controller.alternatingRows.state = .on
        controller.changeAlternatingRows(nil)
        XCTAssertTrue(preferences.alternatingRows)
        XCTAssertTrue(controller.restoreDefaultsButton.isEnabled)
        controller.restoreDefaults(nil)
        XCTAssertTrue(preferences.isDefault)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua, "Restore Defaults returns to Dark")
        for swatch in controller.accentPicker.swatches {
            XCTAssertEqual(swatch.accessibilityLabel(), swatch.accent.title)
            XCTAssertEqual(swatch.accessibilityRole(), .radioButton)
        }
        XCTAssertEqual(controller.themeName.stringValue, "Seal Dark (included with Arkiv)")
    }
}
