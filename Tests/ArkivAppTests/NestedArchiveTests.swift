import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class NestedArchiveTests: XCTestCase {
    private let fm = FileManager.default
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func nested(password: String? = nil) throws -> (URL, URL) {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let text = root.appendingPathComponent("資料.txt")
        try Data("inside".utf8).write(to: text)
        let inner = try ArchiveCreator().create(.init(sources: [text], destination: root, name: "inner",
            format: password == nil ? .zip : .sevenZip, password: password, encryptFilenames: password != nil),
            cancellation: ArchiveCancellation(), progress: { _ in })
        let renamed = root.appendingPathComponent("入れ物.bin")
        try fm.moveItem(at: inner, to: renamed)
        let outer = try ArchiveCreator().create(.init(sources: [renamed, text], destination: root, name: "outer"),
            cancellation: ArchiveCancellation(), progress: { _ in })
        return (root, outer)
    }
    @MainActor private func idle(_ controller: BrowserWindowController) async throws {
        for _ in 0..<400 {
            if !controller.isBusy { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Nested opening did not finish")
    }
    @MainActor private func select(_ name: String, in controller: BrowserWindowController) throws -> (NSTableView, Int) {
        let table = try XCTUnwrap(descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first)
        let row = try XCTUnwrap((0..<table.numberOfRows).first {
            guard let cell = table.view(atColumn: 0, row: $0, makeIfNecessary: true) else { return false }
            return descendants(cell).compactMap { $0 as? NSTextField }.contains { $0.stringValue == name }
        })
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return (table, row)
    }
    @MainActor func testAutomaticNewWindowAdoptsValidatedSnapshotAndOwnsTemporarySource() async throws {
        _ = NSApplication.shared
        let (root, outer) = try nested()
        defer { try? fm.removeItem(at: root) }
        let parent = BrowserWindowController(openFileLauncher: { _ in XCTFail("Archive launched externally"); return false })
        var child: BrowserWindowController?
        parent.onOpenNestedArchive = { snapshot, source in
            XCTAssertTrue(Thread.isMainThread)
            let window = BrowserWindowController()
            window.adoptNestedArchive(snapshot, source: source)
            child = window
        }
        parent.load(outer); try await idle(parent)
        let (table, row) = try select("入れ物.bin", in: parent)
        let menu = NSMenuItem(title: "Open as Archive", action: #selector(BrowserWindowController.openSelectedArchive(_:)), keyEquivalent: "")
        XCTAssertTrue(parent.validateMenuItem(menu))
        XCTAssertNotNil(table.menu?.items.first { $0.action == menu.action })
        table.selectAll(nil)
        XCTAssertFalse(parent.validateMenuItem(menu))
        parent.activate(row: row)
        XCTAssertFalse(parent.isBusy)
        _ = try select("入れ物.bin", in: parent)
        parent.activate(row: row); try await idle(parent)
        let opened = try XCTUnwrap(child)
        XCTAssertNotEqual(parent.windowID, opened.windowID)
        XCTAssertEqual(parent.archiveURL, outer)
        let source = try XCTUnwrap(opened.archiveURL)
        XCTAssertNoThrow(try select("資料.txt", in: opened))
        parent.endArchiveSession()
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        opened.load(source); try await idle(opened)
        XCTAssertNoThrow(try select("資料.txt", in: opened))
        opened.endArchiveSession()
        for _ in 0..<100 where fm.fileExists(atPath: source.path) { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        parent.close(); opened.close(); child = nil
    }
    @MainActor func testPasswordCancellationCreatesNoWindowAndReleasesCopy() async throws {
        _ = NSApplication.shared
        let (root, outer) = try nested(password: "secret")
        defer { try? fm.removeItem(at: root) }
        var temporary: URL?, prompts = 0
        let parent = BrowserWindowController(openFileLauncher: { _ in XCTFail("Cancelled archive launched externally"); return false },
            prepareOpenFile: { session, snapshot, path, token, progress in
                let file = try session.prepare(snapshot, path: path, cancellation: token, progress: progress)
                temporary = file.url
                return file
            }, requestArchivePassword: { _, _, _, completion in prompts += 1; completion(nil) })
        defer { parent.endArchiveSession(); parent.close() }
        parent.onOpenNestedArchive = { _, _ in XCTFail("Password cancellation created a window") }
        parent.load(outer); try await idle(parent)
        _ = try select("入れ物.bin", in: parent)
        parent.openSelectedArchive(nil); try await idle(parent)
        XCTAssertEqual(prompts, 1)
        let copy = try XCTUnwrap(temporary)
        for _ in 0..<100 where fm.fileExists(atPath: copy.path) { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(fm.fileExists(atPath: copy.path))
    }
    @MainActor func testExplicitNonArchiveFailurePreservesDefaultOpenFallback() async throws {
        _ = NSApplication.shared
        let (root, outer) = try nested()
        defer { try? fm.removeItem(at: root) }
        var launches = 0
        let parent = BrowserWindowController(openFileLauncher: { _ in launches += 1; return true })
        defer { parent.endArchiveSession(); parent.close() }
        parent.onOpenNestedArchive = { _, _ in XCTFail("Plain file created a window") }
        parent.load(outer); try await idle(parent)
        _ = try select("資料.txt", in: parent)
        parent.openSelectedArchive(nil); try await idle(parent)
        XCTAssertEqual(launches, 0)
        let sheet = try XCTUnwrap(parent.window?.attachedSheet)
        parent.window?.endSheet(sheet)
        parent.openSelectedFile(nil); try await idle(parent)
        XCTAssertEqual(launches, 1)
    }
    @MainActor func testExplicitOpenStillUsesDefaultApplicationForAnArchive() async throws {
        _ = NSApplication.shared
        let (root, outer) = try nested()
        defer { try? fm.removeItem(at: root) }
        var launches = 0
        let parent = BrowserWindowController(openFileLauncher: { _ in launches += 1; return true })
        defer { parent.endArchiveSession(); parent.close() }
        parent.onOpenNestedArchive = { _, _ in XCTFail("Explicit Open created a nested window") }
        parent.load(outer); try await idle(parent)
        _ = try select("入れ物.bin", in: parent)
        parent.openSelectedFile(nil); try await idle(parent)
        XCTAssertEqual(launches, 1)
    }
    @MainActor func testEncryptedNestedPreflightRetriesBeforeCreatingChild() async throws {
        _ = NSApplication.shared
        let (root, outer) = try nested(password: "secret")
        defer { try? fm.removeItem(at: root) }
        var retries: [Bool] = [], opened = 0
        let parent = BrowserWindowController(openFileLauncher: { _ in XCTFail("Encrypted archive launched externally"); return false },
            requestArchivePassword: { _, retry, _, completion in
                retries.append(retry)
                completion(retry ? "secret" : "wrong")
            })
        defer { parent.endArchiveSession(); parent.close() }
        parent.onOpenNestedArchive = { snapshot, _ in
            XCTAssertEqual(snapshot.entries.map(\.path), ["資料.txt"])
            opened += 1
        }
        parent.load(outer); try await idle(parent)
        _ = try select("入れ物.bin", in: parent)
        parent.openSelectedArchive(nil); try await idle(parent)
        XCTAssertEqual(retries, [false, true])
        XCTAssertEqual(opened, 1)
    }
    @MainActor func testMalformedCandidateReportsFailureAndExplicitOpenRemainsFallback() async throws {
        _ = NSApplication.shared
        let (root, _) = try nested()
        defer { try? fm.removeItem(at: root) }
        let malformed = root.appendingPathComponent("broken.bin")
        try Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]).write(to: malformed)
        let outer = try ArchiveCreator().create(.init(sources: [malformed], destination: root, name: "broken"),
            cancellation: ArchiveCancellation(), progress: { _ in })
        var launches = 0
        let parent = BrowserWindowController(openFileLauncher: { _ in launches += 1; return true })
        defer { parent.endArchiveSession(); parent.close() }
        parent.onOpenNestedArchive = { _, _ in XCTFail("Failed inspection created a window") }
        parent.load(outer); try await idle(parent)
        let (_, row) = try select("broken.bin", in: parent)
        parent.activate(row: row); try await idle(parent)
        XCTAssertEqual(launches, 0)
        let sheet = try XCTUnwrap(parent.window?.attachedSheet)
        parent.window?.endSheet(sheet)
        parent.openSelectedFile(nil); try await idle(parent)
        XCTAssertEqual(launches, 1)
    }
}
