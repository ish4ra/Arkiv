import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipDeletionTests: XCTestCase {
    private func fixture(_ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = root.appendingPathComponent("keep.txt")
        let remove = root.appendingPathComponent("remove.txt")
        let folder = root.appendingPathComponent("資料.app")
        try Data("kept payload".utf8).write(to: kept)
        try Data("removed payload".utf8).write(to: remove)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
        try Data("child".utf8).write(to: folder.appendingPathComponent("nested/é.txt"))
        try Data().write(to: folder.appendingPathComponent("zero"))
        let archive = try ArchiveCreator().create(.init(sources: [kept, remove, folder], destination: root, name: "Delete", format: .sevenZip), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testDeleteSingleThenOverlappingFolderAndMultipleSelections() throws {
        try fixture { root, archive, snapshot in
            let updater = ArchiveModificationUpdater()
            XCTAssertEqual(updater.capability(for: snapshot), .sevenZip)
            try updater.delete(paths: ["remove.txt"], from: snapshot, cancellation: ArchiveCancellation())
            var fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertNil(fresh.index.row(at: "remove.txt"))
            XCTAssertNotNil(fresh.index.row(at: "資料.app/nested/é.txt"))
            try updater.delete(paths: ["資料.app", "資料.app/nested/é.txt", "資料.app/nested/empty"], from: fresh, cancellation: ArchiveCancellation())
            fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(fresh.entries.map(\.path), ["keep.txt"])
            let output = try LibArchiveEngine().extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("keep.txt")), Data("kept payload".utf8))
            XCTAssertEqual(try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation()).state, .ok)
        }
    }
    func testDeleteLastItemProducesValidEmptyArchiveThatCanBeAddedTo() throws {
        try fixture { root, archive, snapshot in
            try ArchiveModificationUpdater().delete(paths: ["keep.txt", "remove.txt", "資料.app"], from: snapshot, cancellation: ArchiveCancellation())
            let empty = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertTrue(empty.entries.isEmpty)
            XCTAssertEqual(try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation()).state, .ok)
            XCTAssertEqual(ArchiveAdditionUpdater().capability(for: empty), .sevenZip)
            try ArchiveAdditionUpdater().add(sources: [root.appendingPathComponent("keep.txt")], to: empty, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.map(\.path), ["keep.txt"])
        }
    }
    func testDeleteUsesRawPathsRatherThanSnapshotOrder() throws {
        try fixture { _, archive, snapshot in
            let entries = snapshot.entries.reversed().enumerated().map {
                ArchiveEntry(id: Int64($0.offset), path: $0.element.path, size: $0.element.size, kind: $0.element.kind)
            }
            let reordered = ArchiveSnapshot(url: snapshot.url, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
            try ArchiveModificationUpdater().delete(paths: ["remove.txt", "資料.app/nested/empty"], from: reordered, cancellation: ArchiveCancellation())
            let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertNil(fresh.index.row(at: "remove.txt"))
            XCTAssertNil(fresh.index.row(at: "資料.app/nested/empty"))
            XCTAssertNotNil(fresh.index.row(at: "keep.txt"))
            XCTAssertNotNil(fresh.index.row(at: "資料.app/zero"))
        }
    }
    func testCancelledInvalidAndStaleDeletionLeaveOriginalUntouched() throws {
        try fixture { _, archive, snapshot in
            let bytes = try Data(contentsOf: archive)
            let updater = ArchiveModificationUpdater()
            for paths: Set<String> in [[], ["missing"], ["keep.txt", "missing"]] {
                XCTAssertThrowsError(try updater.delete(paths: paths, from: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), bytes)
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), bytes)
            try Data("changed externally".utf8).write(to: archive)
            XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), Data("changed externally".utf8))
        }
    }
}
