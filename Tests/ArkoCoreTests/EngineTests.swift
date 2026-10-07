import XCTest
@testable import ArkoCore

final class EngineTests: XCTestCase {
    var root: URL!
    var archive: URL!
    let engine = LibArchiveEngine()
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        archive = root.appendingPathComponent("fixture.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAIBRR12GphA2BQAAAAUAAAAQAAAAZm9sZGVyL2hlbGxvLnR4dGhlbGxvUEsDBBQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAb3RoZXIudHh0b3RoZXJQSwECFAMUAAAAAACAUUddhqYQNgUAAAAFAAAAEAAAAAAAAAAAAAAAgAEAAAAAZm9sZGVyL2hlbGxvLnR4dFBLAQIUAxQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAAAAAAAAAAACAATMAAABvdGhlci50eHRQSwUGAAAAAAIAAgB1AAAAXwAAAAAA")!.write(to: archive)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testInspectAndSelectiveExtraction() throws {
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertEqual(snapshot.entries.map(\.path), ["folder/hello.txt", "other.txt"])
        let output = try engine.extract(snapshot, ids: [0], into: root, cancellation: ArchiveCancellation(), progress: { _ in })
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("folder/hello.txt")), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("other.txt").path))
    }
    func testChangedSourceIsRejected() throws {
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        try Data("changed".utf8).write(to: archive)
        XCTAssertThrowsError(try engine.extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["fixture.zip"])
    }
    func testCancelledExtractionRemovesStaging() throws {
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try engine.extract(snapshot, ids: nil, into: root, cancellation: token, progress: { _ in }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["fixture.zip"])
    }
    func testCancelDuringExtractionRemovesStaging() throws {
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        let token = ArchiveCancellation()
        XCTAssertThrowsError(try engine.extract(snapshot, ids: nil, into: root, cancellation: token, progress: { _ in token.cancel() })) { error in
            guard case ArchiveFailure.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["fixture.zip"])
    }
    func testEmptySelectionDoesNotExtractEverything() throws {
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertThrowsError(try engine.extract(snapshot, ids: [], into: root, cancellation: ArchiveCancellation(), progress: { _ in }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["fixture.zip"])
    }
}
