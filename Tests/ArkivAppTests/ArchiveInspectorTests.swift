import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class ArchiveInspectorTests: XCTestCase {
    @MainActor
    func testNativeInspectorCopyablePathAndUnknownRowsOmitted() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip")
        try Data([0x50,0x4b,0x05,0x06]+Array(repeating:UInt8(0),count:18)).write(to:url)
        defer { try? FileManager.default.removeItem(at:url) }
        let metadata = try XCTUnwrap(LibArchiveEngine().inspect(url,cancellation:ArchiveCancellation()).metadata)
        let rows = ArchiveInspector.rows(metadata)
        XCTAssertFalse(rows.contains { ["Solid","Data encrypted","Multipart","Methods","Archive / unpacked"].contains($0.0) })
        XCTAssertTrue(rows.contains { $0.0 == "Files" && $0.1 == "0" })
        let inspector = ArchiveInspector(metadata:metadata)
        defer { inspector.close() }
        func fields(_ view:NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }
        let path = try XCTUnwrap(fields(try XCTUnwrap(inspector.window?.contentView)).first { $0.stringValue == url.path })
        XCTAssertTrue(path.isSelectable); XCTAssertFalse(path.isEditable)
        XCTAssertEqual(inspector.window?.title,"Archive Info")
    }
}
