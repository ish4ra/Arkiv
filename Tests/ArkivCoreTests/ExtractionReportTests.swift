import Foundation
import XCTest
@testable import ArkivCore

final class ExtractionReportTests: XCTestCase {
    func testLinksAndSpecialWarningsReachBrowserAndFinderReports() throws {
        let manager = FileManager.default
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tests/fixtures/links-and-special.tar")
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let archive = root.appendingPathComponent("fixture.tar")
        try manager.copyItem(at: fixture, to: archive)
        let engine = LibArchiveEngine()
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertEqual(snapshot.entries.map(\.kind), [.file, .symbolicLink, .hardLink, .unsupported])
        let report = try engine.extractReporting(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
        XCTAssertEqual(report.warnings.map(\.path), ["unsupported-pipe"])
        XCTAssertFalse(report.warnings[0].reason.isEmpty)
        XCTAssertEqual(try Data(contentsOf: report.url.appendingPathComponent("ordinary.txt")), Data("preserved".utf8))
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: report.url.appendingPathComponent("relative").path), "ordinary.txt")
        let original = try manager.attributesOfItem(atPath: report.url.appendingPathComponent("ordinary.txt").path)
        let alias = try manager.attributesOfItem(atPath: report.url.appendingPathComponent("alias").path)
        XCTAssertEqual(original[.systemFileNumber] as? NSNumber, alias[.systemFileNumber] as? NSNumber)
        let finder = try FinderExtractor().extractReporting(FinderRequest(action: .extractFolder, urls: [archive]),
            cancellation: ArchiveCancellation(), progress: { _ in })
        XCTAssertEqual(finder.warnings, report.warnings)
        XCTAssertTrue(manager.isExecutableFile(atPath: finder.url.appendingPathComponent("ordinary.txt").path))
        XCTAssertFalse(manager.fileExists(atPath: finder.url.appendingPathComponent("unsupported-pipe").path))
    }
}
