import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class BrowserWindowTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    func testEmptyWindowHasOriginalIdentityAndNoVisibleTable() async {
        await MainActor.run {
            _ = NSApplication.shared
            let controller = BrowserWindowController()
            defer { controller.close() }
            let window = controller.window!
            let views = descendants(window.contentView!)
            XCTAssertEqual(window.tabbingMode, .disallowed)
            XCTAssertNil(controller.archiveURL)
            XCTAssertTrue(controller.routingState.isAvailable)
            let table = views.compactMap { $0 as? NSTableView }.first!
            XCTAssertTrue(table.isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(table.usesAlternatingRowBackgroundColors)
            XCTAssertTrue(table.allowsMultipleSelection)
            XCTAssertEqual(table.tableColumns.map(\.title), ["Name", "Size", "Kind"])
            XCTAssertTrue(views.contains { ($0 as? NSImageView)?.image === NSApp.applicationIconImage })
            let button = views.compactMap { $0 as? NSButton }.first { $0.title == "Open Archive…" }!
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
            var requestedOpen = false
            controller.onOpen = { requestedOpen = true }
            button.performClick(nil)
            XCTAssertTrue(requestedOpen)
            let toolbar = window.toolbar!
            XCTAssertEqual(controller.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue),
                ["open", NSToolbarItem.Identifier.flexibleSpace.rawValue, "extract", "all", "test", "info"])
            XCTAssertFalse(controller.validateMenuItem(NSMenuItem(title: "", action: #selector(BrowserWindowController.extractAll(_:)), keyEquivalent: "")))
            XCTAssertFalse(controller.validateMenuItem(NSMenuItem(title: "", action: #selector(BrowserWindowController.testArchive(_:)), keyEquivalent: "")))
        }
    }
    func testExplicitNewWindowRetainsIndependentWindows() async {
        await MainActor.run {
            _ = NSApplication.shared
            let delegate = AppDelegate()
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            delegate.newWindow(nil)
            delegate.newWindow(nil)
            let created = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.windowController is BrowserWindowController }
            defer { created.forEach { $0.close() } }
            XCTAssertEqual(created.count, 2)
            XCTAssertTrue(created.allSatisfy { $0.tabbingMode == .disallowed })
        }
    }
    @MainActor
    func testOpeningArchiveReusesWindowAndSortingKeepsSelectedFolder() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("fixture.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAIBRR12GphA2BQAAAAUAAAAQAAAAZm9sZGVyL2hlbGxvLnR4dGhlbGxvUEsDBBQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAb3RoZXIudHh0b3RoZXJQSwECFAMUAAAAAACAUUddhqYQNgUAAAAFAAAAEAAAAAAAAAAAAAAAgAEAAAAAZm9sZGVyL2hlbGxvLnR4dFBLAQIUAxQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAAAAAAAAAAACAATMAAABvdGhlci50eHRQSwUGAAAAAAIAAgB1AAAAXwAAAAAA")!.write(to: archive)
        let delegate = AppDelegate()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        delegate.newWindow(nil)
        let window = try XCTUnwrap(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.windowController is BrowserWindowController })
        let controller = try XCTUnwrap(window.windowController as? BrowserWindowController)
        defer { controller.cancel(nil); controller.close() }
        delegate.application(NSApp, open: [archive, archive])
        XCTAssertEqual(controller.archiveURL, archive)
        XCTAssertTrue(controller.isBusy)
        for _ in 0..<200 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy, "Archive loading should finish within five seconds")
        XCTAssertEqual(window.representedURL, archive)
        delegate.application(NSApp, open: [archive])
        XCTAssertEqual(NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.windowController is BrowserWindowController }.count, 1)
        let table = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertFalse(table.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(table.numberOfRows, 2)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        XCTAssertEqual(table.selectedRow, 1, "Selection must stay on the folder after its row moves")
        let search = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSSearchField }.first)
        search.stringValue = "folder"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRow, 1)
    }
    @MainActor
    func testZIPAdditionRefreshesBrowserAndSoundsOnce() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.txt")
        let added = root.appendingPathComponent("追加 🐘.txt")
        try Data("original".utf8).write(to: original)
        try Data("added".utf8).write(to: added)
        let archive = try ArchiveCreator().create(ArchiveCreationRequest(sources: [original], destination: root, name: "Example"),
            cancellation: ArchiveCancellation(), progress: { _ in })
        var sounds = 0
        let controller = BrowserWindowController(modificationFeedback: { result in
            ExtractionFeedback.completed(result, play: { sounds += 1 })
        })
        defer { controller.close() }
        let addFiles = NSMenuItem(title: "", action: #selector(BrowserWindowController.addFiles(_:)), keyEquivalent: "")
        let addFolder = NSMenuItem(title: "", action: #selector(BrowserWindowController.addFolder(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(addFiles))
        controller.load(archive)
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.validateMenuItem(addFiles))
        XCTAssertTrue(controller.validateMenuItem(addFolder))
        controller.addItems([added])
        XCTAssertTrue(controller.isBusy)
        XCTAssertFalse(controller.validateMenuItem(addFiles))
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(sounds, 1)
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(controller.archiveURL?.standardizedFileURL, archive.standardizedFileURL)
        let bytes = try Data(contentsOf: archive)
        let another = root.appendingPathComponent("cancelled.txt")
        try Data(repeating: 65, count: 1_000_000).write(to: another)
        controller.addItems([another]); controller.cancel(nil)
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
        XCTAssertEqual(sounds, 1)
        let seven = try ArchiveCreator().create(ArchiveCreationRequest(sources: [original], destination: root, name: "ReadOnly", format: .sevenZip),
            cancellation: ArchiveCancellation(), progress: { _ in })
        let disguised = root.appendingPathComponent("NotActuallyZIP.zip")
        try FileManager.default.moveItem(at: seven, to: disguised)
        controller.load(disguised)
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.validateMenuItem(addFiles), "Plain 7z Add is detected by content, regardless of extension")
        XCTAssertTrue(controller.validateMenuItem(addFolder))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(controller.validateMenuItem(NSMenuItem(title: "Rename…", action: #selector(BrowserWindowController.renameSelected(_:)), keyEquivalent: "")))
        XCTAssertTrue(controller.validateMenuItem(NSMenuItem(title: "Delete…", action: #selector(BrowserWindowController.deleteSelected(_:)), keyEquivalent: "")))
        XCTAssertFalse(controller.validateMenuItem(NSMenuItem(title: "Replace…", action: #selector(BrowserWindowController.replaceSelected(_:)), keyEquivalent: "")))
        let folder = root.appendingPathComponent("資料")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("new.txt"))
        controller.addItems([added, folder])
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(sounds, 2)
        XCTAssertEqual(table.numberOfRows, 3)
        let fresh = try LibArchiveEngine().inspect(disguised, cancellation: ArchiveCancellation())
        XCTAssertNotNil(fresh.index.row(at: "資料/empty"))
        XCTAssertNotNil(fresh.index.row(at: "追加 🐘.txt"))
        XCTAssertEqual(try LibArchiveEngine().test(disguised, cancellation: ArchiveCancellation()).state, .ok)
    }

    @MainActor
    func testDeleteConfirmationCancellationRefreshAndSound() async throws {
        try await verifyDeleteConfirmation(format: .zip)
    }
    @MainActor
    func testSevenZipDeleteConfirmationCancellationRefreshAndSound() async throws {
        try await verifyDeleteConfirmation(format: .sevenZip)
    }
    @MainActor
    private func verifyDeleteConfirmation(format: ArchiveFormat) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("payload".utf8).write(to: source)
        let archive = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Delete", format: format), cancellation: ArchiveCancellation(), progress: { _ in })
        var sounds = 0
        let controller = BrowserWindowController(modificationFeedback: { result in
            ExtractionFeedback.completed(result, play: { sounds += 1 })
        })
        defer { controller.close() }
        let item = NSMenuItem(title: "Delete…", action: #selector(BrowserWindowController.deleteSelected(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        controller.load(archive)
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertNotNil(table.menu?.items.first { $0.action == item.action })
        XCTAssertFalse(controller.validateMenuItem(item))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(controller.validateMenuItem(item))
        let before = try Data(contentsOf: archive)
        controller.deleteSelected(nil)
        func sheetButton(_ sheet: NSWindow, _ title: String) throws -> NSButton {
            try XCTUnwrap(descendants(sheet.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title })
        }
        func dismissed() async throws {
            for _ in 0..<200 {
                if controller.window?.attachedSheet == nil { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Confirmation sheet should dismiss")
        }
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let delete = try sheetButton(sheet, "Delete")
        XCTAssertTrue(delete.hasDestructiveAction)
        XCTAssertFalse(sheet.defaultButtonCell === delete.cell, "Delete must never be the default action")
        XCTAssertNotEqual(delete.keyEquivalent, "\r")
        // Return activates the native default button. It may be absent for a
        // destructive alert, but it must never refer to Delete.
        if let defaultCell = sheet.defaultButtonCell {
            try XCTUnwrap(defaultCell.controlView as? NSButton).performClick(nil)
        }
        XCTAssertFalse(controller.isBusy, "The default action must not start destructive work")
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(sounds, 0)
        // Test explicit Cancel independently of AppKit's default-button representation.
        if controller.window?.attachedSheet != nil {
            try sheetButton(sheet, "Cancel").performClick(nil)
        }
        try await dismissed()
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(sounds, 0)
        controller.deleteSelected(nil)
        let escapeSheet = try XCTUnwrap(controller.window?.attachedSheet)
        // Escape's standard responder action, without manufacturing a hardware event.
        escapeSheet.cancelOperation(nil)
        try await dismissed()
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(sounds, 0)
        controller.deleteSelected(nil)
        let confirmedSheet = try XCTUnwrap(controller.window?.attachedSheet)
        try sheetButton(confirmedSheet, "Delete").performClick(nil)
        try await dismissed()
        for _ in 0..<400 {
            if !controller.isBusy && sounds == 1 && table.numberOfRows == 0 { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertEqual(sounds, 1)
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertTrue(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.isEmpty)
    }

    @MainActor
    func testPackageContextNavigationAndDragHierarchy() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example.app")
        try fm.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: bundle.appendingPathComponent("Contents/data"))
        let archive = try ArchiveCreator().create(ArchiveCreationRequest(sources: [bundle], destination: root, name: "Fixture"),
            cancellation: ArchiveCancellation(), progress: { _ in })
        let controller = BrowserWindowController()
        defer { controller.close() }
        controller.load(archive)
        for _ in 0..<400 {
            if !controller.isBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(controller.isBusy)
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        let menu = try XCTUnwrap(table.menu?.items.first { $0.title == "Show Package Contents" })
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(controller.validateMenuItem(menu))
        let cell = try XCTUnwrap(controller.tableView(table, viewFor: table.tableColumns[2], row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "Application")
        controller.activate(row: 0)
        XCTAssertTrue(controller.validateMenuItem(menu), "Double-click must leave the package selected at its parent")
        let promise = try XCTUnwrap(controller.tableView(table, pasteboardWriterForRow: 0) as? NSFilePromiseProvider)
        XCTAssertEqual(promise.delegate?.filePromiseProvider(promise, fileNameForType: promise.fileType), "Example.app")
        controller.showPackageContents(nil)
        XCTAssertFalse(controller.validateMenuItem(menu))
        let contents = try XCTUnwrap(controller.tableView(table, viewFor: table.tableColumns[0], row: 0) as? NSTableCellView)
        XCTAssertEqual(contents.textField?.stringValue, "Contents")
        controller.activate(row: 0)
        let data = try XCTUnwrap(controller.tableView(table, viewFor: table.tableColumns[0], row: 0) as? NSTableCellView)
        XCTAssertEqual(data.textField?.stringValue, "data", "Ordinary folders still descend")
        controller.goBack(nil); controller.goBack(nil)
        XCTAssertEqual(table.numberOfRows, 1)
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["Example.app"])
        let destination = root.appendingPathComponent("Delivered.app")
        _ = try session.write(item: session.items[0], to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Contents/data")), Data("payload".utf8))
    }

    @MainActor
    func testFinderDropTargetsAndReadOnlyRejection() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Dropped 🐘.txt")
        try Data("payload".utf8).write(to: file)
        let archive = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "Writable"), cancellation: ArchiveCancellation(), progress: { _ in })
        var sounds = 0
        let controller = BrowserWindowController(modificationFeedback: { result in
            ExtractionFeedback.completed(result, play: { sounds += 1 })
        })
        defer { controller.close() }
        func idle() async throws {
            for _ in 0..<400 {
                if !controller.isBusy { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTFail("Operation did not finish")
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([file as NSURL])
        XCTAssertFalse(controller.acceptFiles(pasteboard, row: -1, operation: .on))
        controller.load(archive); try await idle()
        XCTAssertEqual(controller.dropFolder(proposedRow: -1, operation: .on), "")
        XCTAssertEqual(controller.dropFolder(proposedRow: 0, operation: .on), "Folder")
        controller.activate(row: 0)
        XCTAssertEqual(controller.dropFolder(proposedRow: -1, operation: .on), "Folder")
        XCTAssertTrue(controller.acceptFiles(pasteboard, row: -1, operation: .on))
        XCTAssertNil(controller.dropFolder(proposedRow: -1, operation: .on), "Busy archives must reject drops")
        try await idle()
        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(controller.dropFolder(proposedRow: -1, operation: .on), "Folder")
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertNotNil(snapshot.index.row(at: "Folder/Dropped 🐘.txt"))
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertNotNil(controller.tableView(table, pasteboardWriterForRow: 0), "Drag-out must remain available")
        let second = root.appendingPathComponent("Second.txt")
        try Data("second".utf8).write(to: second)
        pasteboard.clearContents(); pasteboard.writeObjects([second as NSURL])
        controller.goUp(nil)
        XCTAssertTrue(controller.acceptFiles(pasteboard, row: 0, operation: .on))
        try await idle()
        XCTAssertEqual(sounds, 2)
        XCTAssertNotNil(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).index.row(at: "Folder/Second.txt"))
        let seven = try ArchiveCreator().create(.init(sources: [file], destination: root, name: "ReadOnly", format: .sevenZip), cancellation: ArchiveCancellation(), progress: { _ in })
        controller.load(seven); try await idle()
        XCTAssertNil(controller.dropFolder(proposedRow: -1, operation: .on))
        XCTAssertFalse(controller.acceptFiles(pasteboard, row: -1, operation: .on))
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures")
        for name in ["links-and-special.tar", "rar5-stored.rar"] {
            controller.load(fixtures.appendingPathComponent(name)); try await idle()
            XCTAssertNil(controller.dropFolder(proposedRow: -1, operation: .on))
            XCTAssertFalse(controller.acceptFiles(pasteboard, row: -1, operation: .on))
        }
    }

    @MainActor
    func testRenameSheetCancellationSelectionRefreshAndAvailability() async throws {
        try await verifyRenameSheet(format: .zip)
    }
    @MainActor
    func testSevenZipRenameSheetCancellationSelectionRefreshAndAvailability() async throws {
        try await verifyRenameSheet(format: .sevenZip)
    }
    @MainActor
    private func verifyRenameSheet(format: ArchiveFormat) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = ["file.txt", "other.txt"].map { root.appendingPathComponent($0) }
        for source in sources { try Data("payload".utf8).write(to: source) }
        let archive = try ArchiveCreator().create(.init(sources: sources, destination: root, name: "Rename", format: format), cancellation: ArchiveCancellation(), progress: { _ in })
        var sounds = 0
        let controller = BrowserWindowController(modificationFeedback: { result in
            ExtractionFeedback.completed(result, play: { sounds += 1 })
        })
        defer { controller.close() }
        let item = NSMenuItem(title: "Rename…", action: #selector(BrowserWindowController.renameSelected(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        controller.load(archive)
        func idle() async throws {
            for _ in 0..<400 {
                if !controller.isBusy && controller.window?.attachedSheet == nil { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTFail("Rename should finish and dismiss its sheet")
        }
        try await idle()
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertNotNil(table.menu?.items.first { $0.action == item.action })
        XCTAssertFalse(controller.validateMenuItem(item))
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        XCTAssertFalse(controller.validateMenuItem(item))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(controller.validateMenuItem(item))
        let before = try Data(contentsOf: archive)
        controller.renameSelected(nil)
        let cancelledSheet = try XCTUnwrap(controller.window?.attachedSheet)
        let field = try XCTUnwrap(descendants(cancelledSheet.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertEqual(field.stringValue, "file.txt")
        XCTAssertFalse(controller.validateMenuItem(item))
        cancelledSheet.cancelOperation(nil)
        try await idle()
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(sounds, 0)
        controller.renameSelected(nil)
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let name = try XCTUnwrap(descendants(sheet.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        name.stringValue = "資料 🐘.txt"
        try XCTUnwrap(descendants(sheet.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Rename" }).performClick(nil)
        try await idle()
        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRowIndexes.count, 1)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(Set(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.map(\.path)), ["資料 🐘.txt", "other.txt"])
    }

    @MainActor
    func testReplacementAvailabilitySameParentReselectionAndOneSound() async throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Folder")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data("old".utf8).write(to: folder.appendingPathComponent(name)) }
        let source = root.appendingPathComponent("different.txt")
        try Data("chosen replacement".utf8).write(to: source)
        let archive = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "Replace"), cancellation: ArchiveCancellation(), progress: { _ in })
        var sounds = 0
        let controller = BrowserWindowController(modificationFeedback: { result in
            ExtractionFeedback.completed(result, play: { sounds += 1 })
        })
        defer { controller.close() }
        let item = NSMenuItem(title: "Replace File…", action: #selector(BrowserWindowController.replaceSelected(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        func idle() async throws {
            for _ in 0..<400 {
                if !controller.isBusy { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTFail("Replacement did not finish")
        }
        controller.load(archive); try await idle()
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertNotNil(table.menu?.items.first { $0.action == item.action })
        XCTAssertFalse(controller.validateMenuItem(item))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertFalse(controller.validateMenuItem(item), "Folders cannot be replaced")
        controller.activate(row: 0)
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        XCTAssertFalse(controller.validateMenuItem(item))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.replaceItem("Folder/a.txt", with: source)
        XCTAssertFalse(controller.validateMenuItem(item), "Busy archives cannot be edited")
        try await idle()
        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))
        XCTAssertEqual(controller.dropFolder(proposedRow: -1, operation: .on), "Folder")
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertNotNil(controller.tableView(table, pasteboardWriterForRow: 0))
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertEqual(Set(snapshot.entries.map(\.path)), ["Folder/", "Folder/a.txt", "Folder/b.txt"])
        let output = try LibArchiveEngine().extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Folder/a.txt")), Data("chosen replacement".utf8))
        let seven = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "ReadOnly", format: .sevenZip), cancellation: ArchiveCancellation(), progress: { _ in })
        controller.load(seven); try await idle()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertEqual(sounds, 1)
    }

}
