import XCTest
@testable import ArkivCore
import CArkiv

final class FinderActionTests: XCTestCase {
    var root: URL!
    var archive: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        archive = root.appendingPathComponent("Example.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAIBRR12GphA2BQAAAAUAAAAQAAAAZm9sZGVyL2hlbGxvLnR4dGhlbGxvUEsDBBQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAb3RoZXIudHh0b3RoZXJQSwECFAMUAAAAAACAUUddhqYQNgUAAAAFAAAAEAAAAAAAAAAAAAAAgAEAAAAAZm9sZGVyL2hlbGxvLnR4dFBLAQIUAxQAAAAAAIBRR10gNVjZBQAAAAUAAAAJAAAAAAAAAAAAAACAATMAAABvdGhlci50eHRQSwUGAAAAAAIAAgB1AAAAXwAAAAAA")!.write(to: archive)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func extract(_ action: FinderAction, to destination: URL? = nil, token: ArchiveCancellation = ArchiveCancellation()) throws -> URL {
        try FinderExtractor().extract(FinderRequest(action: action, urls: [archive]), destination: destination, cancellation: token, progress: { _ in })
    }
    func testSelectionRejectsMultipleRemoteDirectoriesAndSymlinks() throws {
        XCTAssertThrowsError(try FinderRequest(action: .extractHere, urls: []))
        XCTAssertThrowsError(try FinderRequest(action: .extractHere, urls: [archive, archive]))
        XCTAssertThrowsError(try FinderRequest(action: .open, urls: [URL(string: "https://example.com/a.zip")!]))
        let directory = root.appendingPathComponent("dir.zip")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertThrowsError(try FinderRequest(action: .open, urls: [directory]))
        let link = root.appendingPathComponent("link.zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archive)
        XCTAssertThrowsError(try FinderRequest(action: .open, urls: [link]))
        let text = root.appendingPathComponent("file.txt"); try Data().write(to: text)
        XCTAssertThrowsError(try FinderRequest(action: .open, urls: [text]))
    }
    func testHerePlacesEntriesDirectlyAndPreservesSource() throws {
        let original = try Data(contentsOf: archive)
        XCTAssertEqual(try extract(.extractHere), root)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("folder/hello.txt")), "hello")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("other.txt")), "other")
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["Example.zip", "folder", "other.txt"])
    }
    func testHereConflictLeavesAllExistingItemsUntouchedAndRetainsRecovery() throws {
        let existing = root.appendingPathComponent("other.txt"); try Data("keep".utf8).write(to: existing)
        XCTAssertThrowsError(try extract(.extractHere)) { error in
            guard let failure = error as? FinderExtractionFailure else { return XCTFail("Expected recovery details") }
            XCTAssertEqual(failure.publishedCount, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: failure.recoveryURL.appendingPathComponent("folder/hello.txt").path))
        }
        XCTAssertEqual(try String(contentsOf: existing), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("folder").path))
    }
    func testHereDoesNotMergeExistingFolderOrFollowDanglingLink() throws {
        let existing = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        XCTAssertThrowsError(try extract(.extractHere))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: existing.path).isEmpty)
        try FileManager.default.removeItem(at: existing)
        try FileManager.default.createSymbolicLink(at: existing, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try extract(.extractHere))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("other.txt").path))
    }
    func testFolderNamesAreCollisionSafeAndChooserUsesSelectedParent() throws {
        let first = try extract(.extractFolder), second = try extract(.extractFolder)
        XCTAssertEqual(first.lastPathComponent, "Example")
        XCTAssertEqual(second.lastPathComponent, "Example (2)")
        let destination = root.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertEqual(try extract(.extractTo, to: destination), destination.appendingPathComponent("Example", isDirectory: true))
        XCTAssertThrowsError(try extract(.extractTo))
        XCTAssertThrowsError(try extract(.open))
    }
    func testFolderNameSanitizesUnsafeComponentsAndBoundsUTF8() throws {
        let renamed = root.appendingPathComponent("..Report:2026.zip")
        try FileManager.default.copyItem(at: archive, to: renamed)
        XCTAssertEqual(try FinderRequest(action: .extractFolder, urls: [renamed]).folderName, "Report_2026")
        XCTAssertEqual(try FinderRequest(action: .extractHere, urls: [archive]).parent, root)
        let long = root.appendingPathComponent(String(repeating: "🦊", count: 50) + ".zip")
        try FileManager.default.copyItem(at: archive, to: long)
        XCTAssertLessThanOrEqual(try FinderRequest(action: .extractFolder, urls: [long]).folderName.utf8.count, 180)
    }
    func testCancellationAndCorruptionDoNotPublish() throws {
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try extract(.extractHere, token: token))
        try Data("not an archive".utf8).write(to: archive)
        XCTAssertThrowsError(try extract(.extractHere))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Example.zip"])
    }
    func testAtomicPublisherNeverReplacesFolderOrSymlink() throws {
        let staging = root.appendingPathComponent("staging"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: root.appendingPathComponent("missing"))
        var error = [CChar](repeating: 0, count: 256), published = 0
        let result = arkiv_publish_extracted(root.path, "staging", "target", 0, nil, &published, &error, error.count)
        XCTAssertEqual(result, 3)
        XCTAssertEqual(published, 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.path), root.appendingPathComponent("missing").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
    }
}
