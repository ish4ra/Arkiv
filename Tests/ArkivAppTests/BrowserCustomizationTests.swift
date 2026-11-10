import AppKit
import XCTest
import ArkivPresentation
@testable import ArkivApp

final class BrowserCustomizationTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor
    func testColumnMenuPersistenceResizingAndAppearance() async throws {
        _ = NSApplication.shared
        let suite = "Arkiv.Column.UI.Tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = BrowserColumnPreferences(defaults: defaults)
        let controller = BrowserWindowController(columnPreferences: preferences)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let table = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTableView }.first)
        let menu = try XCTUnwrap(table.headerView?.menu)
        XCTAssertEqual(menu.items.count, table.tableColumns.count)
        XCTAssertFalse(menu.items[0].isEnabled)
        controller.toggleColumn(menu.items[0])
        XCTAssertFalse(table.tableColumns[0].isHidden)
        menu.performActionForItem(at: 1)
        XCTAssertTrue(table.tableColumns[1].isHidden)
        XCTAssertEqual(menu.items[1].state, .off)
        let size = table.tableColumns[1]
        size.width = 240
        controller.tableViewColumnDidResize(Notification(name: NSTableView.columnDidResizeNotification,
            object: table, userInfo: ["NSTableColumn": size]))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: 640, height: 360))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(size.width, 240)
            XCTAssertFalse(table.tableColumns[0].isHidden)
        }
        let reopened = BrowserWindowController(columnPreferences: BrowserColumnPreferences(defaults: defaults))
        defer { reopened.close() }
        let restored = try XCTUnwrap(descendants(reopened.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertTrue(restored.tableColumns[1].isHidden)
        XCTAssertEqual(restored.tableColumns[1].width, 240)
        let toolbar = try XCTUnwrap(window.toolbar)
        let test = try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: .init("test"), willBeInsertedIntoToolbar: false))
        XCTAssertNotNil(test.toolTip)
        XCTAssertFalse(controller.validateToolbarItem(test))
    }

    @MainActor
    func testCustomizationKeepsSelectionThroughSortAndFilter() async throws {
        _ = NSApplication.shared
        let suite = "Arkiv.Column.Selection.Tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("fixture.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAIBRR12GphA2BQAAAAUAAAAQAAAAZm9sZGVyL2hlbGxvLnR4dGhlbGxvUEsDBBQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAb3RoZXIudHh0b3RoZXJQSwECFAMUAAAAAACAUUddhqYQNgUAAAAFAAAAEAAAAAAAAAAAAAAAgAEAAAAAZm9sZGVyL2hlbGxvLnR4dFBLAQIUAxQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAAAAAAAAAAACAATMAAABvdGhlci50eHRQSwUGAAAAAAIAAgB1AAAAXwAAAAAA")!.write(to: url)
        let controller = BrowserWindowController(columnPreferences: BrowserColumnPreferences(defaults: defaults))
        defer { controller.close() }
        let loaded = expectation(description: "Loaded")
        controller.onAcceptedArchive = { _,_ in loaded.fulfill() }
        controller.load(url)
        await fulfillment(of: [loaded], timeout: 10)
        let views = descendants(controller.window!.contentView!)
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
        table.headerView?.menu?.performActionForItem(at: 1)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        XCTAssertEqual(table.selectedRow, 1)
        let search = try XCTUnwrap(views.compactMap { $0 as? NSSearchField }.first)
        search.stringValue = "folder"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.selectedRow, 1)
        search.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.selectedRow, 1)
        XCTAssertTrue(table.tableColumns[1].isHidden)
    }
}
