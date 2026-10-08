import AppKit
import XCTest
@testable import ArkivApp
import ArkivCore

final class FinderServiceTests: XCTestCase {
    func testServiceOpenRoutesFileURLAndRejectsMultiSelection() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.zip")
            try Data().write(to: archive)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            XCTAssertTrue(pasteboard.writeObjects([archive as NSURL]))
            var opened: URL?
            let provider = FinderServiceProvider { opened = $0 }
            XCTAssertTrue(provider.responds(to: NSSelectorFromString("performFinderAction:userData:error:")))
            var error: NSString?
            provider.performFinderAction(pasteboard, userData: "open", error: &error)
            XCTAssertNil(error)
            XCTAssertEqual(opened, archive)
            XCTAssertFalse(provider.isBusy)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([archive as NSURL, archive as NSURL]))
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "not-an-action"))
        }
    }
    func testLegacyFinderPasteboardAndUnsupportedSelections() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.TAR")
            try Data().write(to: archive)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.setPropertyList([archive.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            XCTAssertEqual(try FinderServiceProvider.request(from: pasteboard, userData: "extractFolder").archive, archive)
            pasteboard.clearContents()
            pasteboard.setString("/tmp/not-a-file.zip", forType: .string)
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(string: "https://example.com/a.zip")! as NSURL])
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
        }
    }
}
