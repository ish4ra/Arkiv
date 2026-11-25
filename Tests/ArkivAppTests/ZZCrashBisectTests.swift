import AppKit
import XCTest
import FinderSync
import ArkivCore
@testable import ArkivApp

/// TEMPORARY diagnostic (removed before review): each test exercises one
/// element of the redesigned window inside an async @MainActor test, to find
/// which leaves the Swift task allocator unbalanced ("freed pointer was not
/// the last allocation" in XCTSwiftErrorObservation). Run one per process.
final class ZZCrashBisectTests: XCTestCase {
    @MainActor private func settle() async throws { try await Task.sleep(nanoseconds: 150_000_000) }
    @MainActor private func plainWindow(_ toolbar: NSToolbar? = nil) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        window.makeKeyAndOrderFront(nil)
        return window
    }
    final class Delegate: NSObject, NSToolbarDelegate {
        let ids: [NSToolbarItem.Identifier]; let make: (NSToolbarItem.Identifier) -> NSToolbarItem?
        init(_ ids: [NSToolbarItem.Identifier], _ make: @escaping (NSToolbarItem.Identifier) -> NSToolbarItem?) { self.ids = ids; self.make = make }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { ids }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { ids }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { make(id) }
    }

    @MainActor func test01Baseline() async throws { _ = NSApplication.shared; try await settle() }

    @MainActor func test02SearchToolbarItem() async throws {
        _ = NSApplication.shared
        let delegate = Delegate([.init("search")]) { id in let item = NSSearchToolbarItem(itemIdentifier: id); item.searchField = NSSearchField(); return item }
        let toolbar = NSToolbar(identifier: "Bisect.Search"); toolbar.delegate = delegate
        let window = plainWindow(toolbar); defer { window.close() }
        try await settle()
    }

    @MainActor func test03MenuToolbarItemAndGroup() async throws {
        _ = NSApplication.shared
        let delegate = Delegate([.init("menu"), .init("group")]) { id in
            if id.rawValue == "menu" { let item = NSMenuToolbarItem(itemIdentifier: id); item.menu = NSMenu(); item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil); return item }
            let group = NSToolbarItemGroup(itemIdentifier: id)
            let a = NSToolbarItem(itemIdentifier: .init("a")); a.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
            group.subitems = [a]; group.isNavigational = true; return group
        }
        let toolbar = NSToolbar(identifier: "Bisect.Menu"); toolbar.delegate = delegate
        let window = plainWindow(toolbar); defer { window.close() }
        try await settle()
    }

    @MainActor func test04ToolbarSwapAndTitlebar() async throws {
        _ = NSApplication.shared
        let delegate = Delegate([]) { _ in nil }
        let first = NSToolbar(identifier: "Bisect.A"), second = NSToolbar(identifier: "Bisect.B")
        first.delegate = delegate; second.delegate = delegate
        let window = plainWindow(first); defer { window.close() }
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        try await settle()
        window.toolbar = second; window.titlebarAppearsTransparent = false; window.titleVisibility = .visible
        window.subtitle = "ZIP · 2 files"; window.titlebarSeparatorStyle = .automatic
        try await settle()
    }

    @MainActor func test05PathControl() async throws {
        _ = NSApplication.shared
        let window = plainWindow(); defer { window.close() }
        let path = NSPathControl(frame: NSRect(x: 0, y: 0, width: 400, height: 22))
        let a = NSPathControlItem(); a.title = "Archive.zip"; a.image = NSWorkspace.shared.icon(for: .archive)
        let b = NSPathControlItem(); b.title = "Folder"
        path.pathItems = [a, b]
        window.contentView?.addSubview(path)
        try await settle()
    }

    @MainActor func test06WelcomeOnly() async throws {
        _ = NSApplication.shared
        let window = plainWindow(); defer { window.close() }
        let welcome = WelcomeView(); welcome.frame = window.contentView!.bounds
        window.contentView?.addSubview(welcome)
        try await settle()
    }

    @MainActor func test07BrowserWindowIdle() async throws {
        _ = NSApplication.shared
        let controller = BrowserWindowController(); defer { controller.close() }
        controller.showWindow(nil)
        try await settle()
    }

    @MainActor func test08BrowserWindowLoaded() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt"); try Data("payload".utf8).write(to: source)
        let archive = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Bisect"), cancellation: ArchiveCancellation(), progress: { _ in })
        let controller = BrowserWindowController(); defer { controller.close() }
        controller.load(archive)
        for _ in 0..<200 where controller.isBusy { try await Task.sleep(nanoseconds: 25_000_000) }
        try await settle()
    }

    @MainActor func test09BrowserWindowNeverShownNoLoad() async throws {
        _ = NSApplication.shared
        let controller = BrowserWindowController(); defer { controller.close() }
        try await settle()
    }

    @MainActor func test10SettingsWindow() async throws {
        _ = NSApplication.shared
        let controller = SettingsWindowController(preferences: .init(defaults: UserDefaults(suiteName: "Bisect.\(UUID())")!),
            recents: RecentArchives(urls: { [] }, note: { _ in }, clear: {}),
            updates: UpdateController(publicKey: { nil }, makeDriver: { fatalError() }), showFinder: {})
        controller.finderEnabled = { false }
        defer { controller.close() }
        controller.present()
        try await settle()
    }

    final class Observer: NSObject { @objc func changed(_ n: Notification) {} }
    @MainActor func test11WorkspaceObserverAndAccessibilityFlags() async throws {
        _ = NSApplication.shared
        let observer = Observer()
        NSWorkspace.shared.notificationCenter.addObserver(observer, selector: #selector(Observer.changed(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        _ = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        _ = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        try await settle()
    }

    @MainActor func test12FinderStatus() async throws {
        _ = NSApplication.shared
        _ = FIFinderSyncController.isExtensionEnabled
        try await settle()
    }
}
