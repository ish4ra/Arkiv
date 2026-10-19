import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipRenameTests: XCTestCase {
    private func fixture(password: String? = nil, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder.app")
        let sibling = root.appendingPathComponent("sibling.txt")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
        try Data("original bytes".utf8).write(to: folder.appendingPathComponent("nested/file.txt"))
        try Data().write(to: folder.appendingPathComponent("zero"))
        try Data("sibling bytes".utf8).write(to: sibling)
        let archive = try ArchiveCreator().create(.init(sources: [folder, sibling], destination: root, name: "Rename", format: .sevenZip, password: password), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: password))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testRenameFileAndFolderPreservesHierarchyAndBytes() throws {
        try fixture { root, archive, snapshot in
            let updater = ArchiveModificationUpdater()
            try updater.rename(path: "Folder.app/nested/file.txt", to: "資料 🐈.txt", in: snapshot, cancellation: ArchiveCancellation())
            var fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertNil(fresh.index.row(at: "Folder.app/nested/file.txt"))
            XCTAssertNotNil(fresh.index.row(at: "Folder.app/nested/資料 🐈.txt"))
            try updater.rename(path: "Folder.app", to: "Renamed.app", in: fresh, cancellation: ArchiveCancellation())
            fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertNil(fresh.index.row(at: "Folder.app"))
            XCTAssertNotNil(fresh.index.row(at: "Renamed.app/nested/empty"))
            let output = try LibArchiveEngine().extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Renamed.app/nested/資料 🐈.txt")), Data("original bytes".utf8))
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Renamed.app/zero")), Data())
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("sibling.txt")), Data("sibling bytes".utf8))
            XCTAssertEqual(try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation()).state, .ok)
        }
    }
    func testCaseOnlyRenameAndReorderedSnapshot() throws {
        try fixture { _, archive, snapshot in
            let entries = snapshot.entries.reversed().enumerated().map {
                ArchiveEntry(id: Int64($0.offset), path: $0.element.path, size: $0.element.size, kind: $0.element.kind)
            }
            let reordered = ArchiveSnapshot(url: snapshot.url, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
            try ArchiveModificationUpdater().rename(path: "Folder.app", to: "folder.app", in: reordered, cancellation: ArchiveCancellation())
            let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertNotNil(fresh.index.row(at: "folder.app/nested/file.txt"))
            XCTAssertNil(fresh.index.row(at: "Folder.app"))
            XCTAssertNotNil(fresh.index.row(at: "sibling.txt"))
        }
    }
    func testConflictsAndInvalidBasenamesLeaveOriginalUnchanged() throws {
        try fixture { _, archive, snapshot in
            let original = try Data(contentsOf: archive)
            for name in ["", ".", "..", "a/b", "a\\b", "bad:name", "bad\nname", "bad\0name", "SIBLING.TXT", String(repeating: "x", count: 4097)] {
                XCTAssertThrowsError(try ArchiveModificationUpdater().rename(path: "Folder.app", to: name, in: snapshot, cancellation: ArchiveCancellation()), name)
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
            XCTAssertThrowsError(try ArchiveModificationUpdater().rename(path: "missing", to: "new", in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }
    func testCancellationAndChangedSourceLeaveOriginalUntouched() throws {
        try fixture { _, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveModificationUpdater().rename(path: "Folder.app", to: "Renamed", in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            try Data("external update".utf8).write(to: archive)
            XCTAssertThrowsError(try ArchiveModificationUpdater().rename(path: "Folder.app", to: "Renamed", in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external update".utf8))
        }
    }
    func testEncryptedDeleteAndRenameRemainReadOnlyAfterUnlock() throws {
        try fixture(password: "fixture password") { _, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let updater = ArchiveModificationUpdater()
            XCTAssertFalse(updater.capability(for: snapshot).isAvailable)
            XCTAssertThrowsError(try updater.rename(path: "Folder.app", to: "Renamed", in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertThrowsError(try updater.delete(paths: ["Folder.app"], from: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }
}
