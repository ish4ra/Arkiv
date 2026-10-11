import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class ArchiveDragPromiseTests: XCTestCase {
    @MainActor
    func testPromiseMetadataIsLazyAndCallbackUsesExactRenamedDestination() async throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tests/fixtures/links-and-special.tar")
        let snapshot = try LibArchiveEngine().inspect(fixture, cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt"])
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let feedback = expectation(description: "asynchronous feedback")
        feedback.assertForOverFulfill = true
        let provider = ArchiveDragPromiseProvider(session: session, item: session.items[0], queue: queue) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            feedback.fulfill()
        }
        let delegate = try XCTUnwrap(provider.delegate)
        XCTAssertEqual(delegate.filePromiseProvider(provider, fileNameForType: provider.fileType), "ordinary.txt")
        XCTAssertTrue(delegate.operationQueue?(for: provider) === queue)
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), [])
        let destination = root.appendingPathComponent("Finder Renamed.txt")
        let completion = expectation(description: "exactly one completion")
        completion.assertForOverFulfill = true
        queue.addOperation {
            delegate.filePromiseProvider(provider, writePromiseTo: destination) { error in
                XCTAssertNil(error); completion.fulfill()
            }
        }
        await fulfillment(of: [completion, feedback], timeout: 10)
        XCTAssertEqual(try Data(contentsOf: destination), Data("preserved".utf8))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), ["Finder Renamed.txt"])
    }
    @MainActor
    func testEmptyBrowserDoesNotOfferPromiseAndSelectionStaysNative() {
        _ = NSApplication.shared
        let controller = BrowserWindowController()
        defer { controller.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let table = descendants(controller.window!.contentView!).compactMap { $0 as? NSTableView }.first!
        XCTAssertNil(controller.tableView(table, pasteboardWriterForRow: 0))
        XCTAssertTrue(table.allowsMultipleSelection)
        XCTAssertTrue(table.selectedRowIndexes.isEmpty)
    }
}
