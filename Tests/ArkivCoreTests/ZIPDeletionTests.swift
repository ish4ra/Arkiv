import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPDeletionTests: XCTestCase {
    private func fixture(_ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("資料 🐘.app")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Contents/empty"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("child".utf8).write(to: folder.appendingPathComponent("Contents/é.txt"))
        let file = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: file)
        let archive = try ArchiveCreator().create(.init(sources: [folder, file], destination: root, name: "Deletion"), cancellation: ArchiveCancellation(), progress: { _ in })
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
        XCTAssertEqual(snapshot.entries.map(\.id), snapshot.entries.indices.map { Int64($0) })
        try body(root, archive, snapshot)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testRecursivePackageParentChildCollapseLastEntryAndAddAgain() throws {
        try fixture { root, archive, snapshot in
            try ArchiveZIPUpdater().delete(paths: ["資料 🐘.app", "資料 🐘.app/Contents/é.txt"], from: snapshot, cancellation: ArchiveCancellation())
            var fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(fresh.entries.map(\.path), ["keep.txt"])
            try ArchiveZIPUpdater().delete(paths: ["keep.txt"], from: fresh, cancellation: ArchiveCancellation())
            fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertTrue(fresh.entries.isEmpty)
            try ArchiveZIPUpdater().add(sources: [root.appendingPathComponent("keep.txt")], to: fresh, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.count, 1)
        }
    }
    func testSelectingAmbiguousFileDoesNotDeleteItsUnselectedDescendant() throws {
        try fixture { _, archive, _ in
            try Data(base64Encoded: "UEsDBBQAAAAAAE8qTF0QNp+MBAAAAAQAAAABAAAAYWZpbGVQSwMEFAAAAAAATypMXSlUsyIFAAAABQAAAAcAAABhL2NoaWxkY2hpbGRQSwECFAMUAAAAAABPKkxdEDafjAQAAAAEAAAAAQAAAAAAAAAAAAAAgAEAAAAAYVBLAQIUAxQAAAAAAE8qTF0pVLMiBQAAAAUAAAAHAAAAAAAAAAAAAACAASMAAABhL2NoaWxkUEsFBgAAAAACAAIAZAAAAE0AAAAAAA==")!.write(to: archive)
            let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertFalse(try XCTUnwrap(snapshot.index.row(at: "a")).isDirectory)
            try ArchiveZIPUpdater().delete(paths: ["a"], from: snapshot, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.map(\.path), ["a/child"])
        }
    }
    func testSnapshotOrdinalAndCountMismatchFailClosed() throws {
        try fixture { _, archive, snapshot in
            let before = try Data(contentsOf: archive)
            let reordered = ArchiveSnapshot(url: archive, entries: snapshot.entries.reversed(), stamp: snapshot.stamp, unlocked: nil)
            XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: ["keep.txt"], from: reordered, cancellation: ArchiveCancellation()))
            let shortened = ArchiveSnapshot(url: archive, entries: Array(snapshot.entries.dropLast()), stamp: snapshot.stamp, unlocked: nil)
            XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: ["資料 🐘.app"], from: shortened, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
        }
    }
    func testMixedSelectionUnicodeFileAndEmptyFolder() throws {
        try fixture { _, archive, snapshot in
            try ArchiveZIPUpdater().delete(paths: ["keep.txt", "資料 🐘.app/Contents/é.txt", "資料 🐘.app/Contents/empty"], from: snapshot, cancellation: ArchiveCancellation())
            let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(fresh.entries.count, 2)
            XCTAssertTrue(fresh.entries.allSatisfy { $0.kind == .directory })
        }
    }
    func testInvalidSelectionCancellationAndStaleSnapshotPreserveOriginal() throws {
        try fixture { _, archive, snapshot in
            let before = try Data(contentsOf: archive)
            for paths: Set<String> in [[], ["missing"]] {
                XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: paths, from: snapshot, cancellation: ArchiveCancellation()))
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: ["資料 🐘.app", "keep.txt"], from: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            let changed = Data("another writer".utf8)
            XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: ["資料 🐘.app"], from: snapshot, cancellation: ArchiveCancellation(), progress: { _ in try? changed.write(to: archive, options: .atomic) }))
            XCTAssertEqual(try Data(contentsOf: archive), changed)
            XCTAssertThrowsError(try ArchiveZIPUpdater().delete(paths: ["keep.txt"], from: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), changed)
        }
    }
}
