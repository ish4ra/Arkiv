import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp
final class RecentArchivesTests: XCTestCase {
    @MainActor func testFileMenuUsesRecentMenu() {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu; defer { NSApp.mainMenu = previous }
        let recent = RecentArchives(urls:{[]},note:{_ in},clear:{})
        let delegate = AppDelegate(updates:UpdateController(),launchArguments:[],recents:recent)
        delegate.buildMenus()
        let file = NSApp.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu
        XCTAssertTrue(file?.items.first { $0.title == "Open Recent" }?.submenu === recent.menu)
    }
    @MainActor func testAcceptedBoundaryAndFailedOpen() async throws {
        _ = NSApplication.shared
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip")
        try Data([0x50,0x4b,0x05,0x06]+Array(repeating:UInt8(0),count:18)).write(to:archive)
        defer { try? FileManager.default.removeItem(at:archive) }
        let controller = BrowserWindowController(); defer { controller.close() }
        var recorded: [URL] = []
        controller.onAcceptedArchive = { url,nested in if !nested { recorded.append(url) } }
        controller.load(archive)
        XCTAssertNil(controller.recentArchiveURL)
        for _ in 0..<400 where controller.isBusy { try await Task.sleep(nanoseconds:25_000_000) }
        XCTAssertEqual(recorded,[archive])
        XCTAssertEqual(controller.recentArchiveURL,archive)
        let missing = archive.appendingPathExtension("missing")
        controller.load(missing)
        for _ in 0..<400 where controller.isBusy { try await Task.sleep(nanoseconds:25_000_000) }
        XCTAssertEqual(recorded,[archive])
        if let sheet = controller.window?.attachedSheet { controller.window?.endSheet(sheet) }
    }
    @MainActor func testNativeStorageBoundaryRoutingClearAndExclusions() {
        var history: [URL] = []; var opened: URL?
        let recent = RecentArchives(urls:{history},note:{ url in history.removeAll { $0 == url }; history.insert(url,at:0) },clear:{history=[]})
        recent.open = { opened=$0 }
        let normal = URL(fileURLWithPath:"/Users/test/Archive.zip")
        recent.accepted(normal)
        XCTAssertEqual(history,[normal])
        for url in [URL(fileURLWithPath:"/tmp/arkiv-unlocked-secret/contents.tar"),URL(fileURLWithPath:"/tmp/xyz.isharalakshan.arkiv.open-v1-1/session/file.zip")] { recent.accepted(url) }
        recent.accepted(normal,nested:true)
        XCTAssertEqual(history,[normal])
        recent.menuNeedsUpdate(recent.menu)
        XCTAssertEqual(recent.menu.title,"Open Recent")
        XCTAssertEqual(recent.menu.items.last?.title,"Clear Menu")
        recent.openRecent(recent.menu.items[0]); XCTAssertEqual(opened,normal)
        // The missing URL is routed unchanged, never replaced with another file.
        XCTAssertFalse(FileManager.default.fileExists(atPath:normal.path))
        recent.clearMenu(nil); XCTAssertTrue(history.isEmpty)
    }
}
