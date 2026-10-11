import Foundation
import XCTest
@testable import ArkivCore

final class PackageExtractionTests: XCTestCase {
    /// CI invokes this a second time after creating the exact distributable ZIP.
    func testOfficialPackagedApplicationRoundTrip() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let source = environment["ARKIV_PACKAGE_ZIP"], let destination = environment["ARKIV_PACKAGE_OUTPUT"] else {
            throw XCTSkip("Runs after CI has built and packaged the real app")
        }
        let manager = FileManager.default
        let parent = URL(fileURLWithPath: destination, isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let engine = LibArchiveEngine()
        let snapshot = try engine.inspect(URL(fileURLWithPath: source), cancellation: ArchiveCancellation())
        XCTAssertTrue(snapshot.entries.contains { $0.kind == .symbolicLink })
        let report = try engine.extractReporting(snapshot, ids: nil, into: parent,
            cancellation: ArchiveCancellation(), progress: { _ in })
        XCTAssertEqual(report.warnings, [])
        defer { try? manager.removeItem(at: report.url) }
        let app = report.url.appendingPathComponent("Arkiv.app")
        XCTAssertTrue(manager.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Arkiv").path))
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: app.appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/Current").path), "B")
        // Leave the app for byte/link comparison and codesign/runtime checks in CI.
        try manager.moveItem(at: app, to: parent.appendingPathComponent("Arkiv.app"))
    }
}
