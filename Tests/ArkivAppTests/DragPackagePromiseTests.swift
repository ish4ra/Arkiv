import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class DragPackagePromiseTests: XCTestCase {
    @MainActor
    func testActualPackagedAppThroughFilePromiseDelegate() async throws {
        _ = NSApplication.shared
        let environment = ProcessInfo.processInfo.environment
        guard let source = environment["ARKIV_PROMISE_ZIP"], let output = environment["ARKIV_PROMISE_OUTPUT"] else {
            throw XCTSkip("Runs after packaging the real app ZIP")
        }
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: output, isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let snapshot = try LibArchiveEngine().inspect(URL(fileURLWithPath: source), cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["Arkiv.app"])
        let item = try XCTUnwrap(session.items.first)
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let feedback = expectation(description: "Promise feedback")
        let provider = ArchiveDragPromiseProvider(session: session, item: item, queue: queue) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            feedback.fulfill()
        }
        let delegate = try XCTUnwrap(provider.delegate)
        XCTAssertEqual(delegate.filePromiseProvider(provider, fileNameForType: provider.fileType), "Arkiv.app")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: parent.path), [], "Advertising a promise must not extract")
        let destination = parent.appendingPathComponent("Arkiv.app")
        let error: Error? = await withCheckedContinuation { continuation in
            queue.addOperation {
                delegate.filePromiseProvider(provider, writePromiseTo: destination) { error in
                    continuation.resume(returning: error)
                }
            }
        }
        XCTAssertNil(error)
        await fulfillment(of: [feedback], timeout: 10)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: parent.path), ["Arkiv.app"])
        XCTAssertTrue(fm.isExecutableFile(atPath: destination.appendingPathComponent("Contents/MacOS/Arkiv").path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/Current").path), "B")
    }
}
