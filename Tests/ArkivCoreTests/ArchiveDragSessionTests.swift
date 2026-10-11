import Foundation
import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ArchiveDragSessionTests: XCTestCase {
    private let manager = FileManager.default
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tests/fixtures/" + name)
    }
    private func root() throws -> URL {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let url = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testLazyCancellationAndFailureCleanPrivateStaging() throws {
        let parent = try root()
        let snapshot = try LibArchiveEngine().inspect(fixture("links-and-special.tar"), cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt"])
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), [])
        session.cancel()
        XCTAssertThrowsError(try session.write(item: session.items[0], to: parent.appendingPathComponent("renamed")))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), [])
        let conflict = parent.appendingPathComponent("existing")
        try Data("keep".utf8).write(to: conflict)
        let failing = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt"])
        XCTAssertThrowsError(try failing.write(item: failing.items[0], to: conflict))
        XCTAssertEqual(try Data(contentsOf: conflict), Data("keep".utf8))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), ["existing"])
    }
    func testMultiplePromisesPreserveHardlinksAndExecutableMode() throws {
        let parent = try root()
        let snapshot = try LibArchiveEngine().inspect(fixture("links-and-special.tar"), cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt", "alias", "relative"])
        for item in session.items { _ = try session.write(item: item, to: parent.appendingPathComponent(item.name)) }
        let ordinary = parent.appendingPathComponent("ordinary.txt")
        XCTAssertTrue(manager.isExecutableFile(atPath: ordinary.path))
        XCTAssertEqual(try manager.attributesOfItem(atPath: ordinary.path)[.systemFileNumber] as? NSNumber,
                       try manager.attributesOfItem(atPath: parent.appendingPathComponent("alias").path)[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: parent.appendingPathComponent("relative").path), "ordinary.txt")
        XCTAssertEqual(Set(try manager.contentsOfDirectory(atPath: parent.path)), ["ordinary.txt", "alias", "relative"])
    }
    func testHardlinkAlonePublishesOnlyRequestedRenamedFile() throws {
        let parent = try root()
        let snapshot = try LibArchiveEngine().inspect(fixture("links-and-special.tar"), cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["alias"])
        let destination = parent.appendingPathComponent("別名.txt")
        _ = try session.write(item: session.items[0], to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("preserved".utf8))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), ["別名.txt"])
        XCTAssertThrowsError(try session.write(item: session.items[0], to: destination))
    }
    func testFolderSuppressesChildAndPreservesNestedUnicode() throws {
        let parent = try root()
        let source = parent.appendingPathComponent("入れ物.app")
        let nested = source.appendingPathComponent("Contents/資料")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("é.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [source], destination: parent, name: "fixture"),
            cancellation: ArchiveCancellation(), progress: { _ in })
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["入れ物.app", "入れ物.app/Contents/資料/é.txt"])
        XCTAssertEqual(session.items.count, 1)
        let output = parent.appendingPathComponent("renamed.app")
        _ = try session.write(item: session.items[0], to: output)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Contents/資料/é.txt")), Data("nested".utf8))
        XCTAssertFalse(try manager.contentsOfDirectory(atPath: parent.path).contains { $0.hasPrefix(".arkiv") })
    }
    func testUnlockedSnapshotLivesUntilSessionRelease() throws {
        let parent = try root()
        let source = parent.appendingPathComponent("secret.txt")
        try Data("secret contents".utf8).write(to: source)
        let archive = try ArchiveCreator().create(.init(sources: [source], destination: parent, name: "Protected",
            format: .sevenZip, password: "secret", encryptFilenames: true), cancellation: ArchiveCancellation(), progress: { _ in })
        var snapshot: ArchiveSnapshot? = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
        let spool = snapshot!.unlocked!.directory
        var session: ArchiveDragSession? = try ArchiveDragSession(snapshot: snapshot!, paths: ["secret.txt"])
        snapshot = nil
        XCTAssertTrue(manager.fileExists(atPath: spool.path))
        let output = parent.appendingPathComponent("renamed.txt")
        _ = try session!.write(item: session!.items[0], to: output)
        XCTAssertEqual(try Data(contentsOf: output), Data("secret contents".utf8))
        session = nil
        XCTAssertFalse(manager.fileExists(atPath: spool.path))
    }
    func testPartiallyRequestedSessionCleansOnCancelAndRelease() throws {
        let parent = try root()
        let snapshot = try LibArchiveEngine().inspect(fixture("links-and-special.tar"), cancellation: ArchiveCancellation())
        var session: ArchiveDragSession? = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt", "alias"])
        _ = try session!.write(item: session!.items.first { $0.path == "ordinary.txt" }!, to: parent.appendingPathComponent("file"))
        XCTAssertTrue(try manager.contentsOfDirectory(atPath: parent.path).contains { $0.hasPrefix(".arkiv-drag") })
        session!.cancel()
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), ["file"])
        session = nil
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), ["file"])
    }

    func testPartialIdleExpiryDiscardsOutputAndRejectsLatePromise() throws {
        let parent = try root()
        let snapshot = try LibArchiveEngine().inspect(fixture("links-and-special.tar"), cancellation: ArchiveCancellation())
        let session = try ArchiveDragSession(snapshot: snapshot, paths: ["ordinary.txt", "alias"])
        session.idleTimeout = 0.02
        _ = try session.write(item: session.items.first { $0.path == "ordinary.txt" }!, to: parent.appendingPathComponent("first"))
        let expired = expectation(description: "idle staging expires")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { expired.fulfill() }
        wait(for: [expired], timeout: 2)
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: parent.path), ["first"])
        XCTAssertThrowsError(try session.write(item: session.items.first { $0.path == "alias" }!, to: parent.appendingPathComponent("late")))
    }

}
