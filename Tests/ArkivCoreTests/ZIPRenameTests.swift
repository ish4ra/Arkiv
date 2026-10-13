import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPRenameTests: XCTestCase {
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
    func testFileCaseUnicodePackageNestedEmptyAndAddDelete() throws {
        try fixture { root, archive, initial in
            var snapshot = initial
            for (path, name) in [("keep.txt", "KEEP.txt"), ("KEEP.txt", "é 🐘.txt"), ("資料 🐘.app/Contents/empty", "空"), ("資料 🐘.app/Contents", "Nested"), ("資料 🐘.app", "Renamed.app")] {
                try ArchiveZIPUpdater().rename(path: path, to: name, in: snapshot, cancellation: ArchiveCancellation())
                snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            }
            XCTAssertTrue(snapshot.entries.contains { $0.path == "Renamed.app/Nested/é.txt" })
            XCTAssertTrue(snapshot.index.row(at: "Renamed.app/Nested/空")?.isDirectory == true)
            _ = try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation())
            let extracted = try LibArchiveEngine().extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Renamed.app/Nested/é.txt")), Data("child".utf8))
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("é 🐘.txt")), Data("keep".utf8))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: extracted.appendingPathComponent("Renamed.app/Nested/空").path), [])
            try ArchiveZIPUpdater().add(sources: [root.appendingPathComponent("keep.txt")], to: snapshot, cancellation: ArchiveCancellation())
            snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            try ArchiveZIPUpdater().delete(paths: ["Renamed.app"], from: snapshot, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.count, 2)
        }
    }
    func testInvalidNamesCollisionCancellationAndStalePreserveOriginal() throws {
        try fixture { _, archive, snapshot in
            let before = try Data(contentsOf: archive)
            for name in ["", ".", "..", "a/b", "a\\b", "a:b", "a\u{7f}", "a\n", "資料 🐘.app"] {
                XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "keep.txt", to: name, in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), before)
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "keep.txt", to: "renamed", in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            let changed = Data("another writer".utf8)
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "keep.txt", to: "renamed", in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in try? changed.write(to: archive, options: .atomic) }))
            XCTAssertEqual(try Data(contentsOf: archive), changed)
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "keep.txt", to: "renamed", in: snapshot, cancellation: ArchiveCancellation()))
        }
    }
    func testAmbiguousPathsOrdinalCountAndReadOnlyFailClosed() throws {
        try fixture { _, archive, snapshot in
            let before = try Data(contentsOf: archive)
            let reordered = ArchiveSnapshot(url: archive, entries: snapshot.entries.reversed(), stamp: snapshot.stamp, unlocked: nil)
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "keep.txt", to: "renamed", in: reordered, cancellation: ArchiveCancellation()))
            let shortened = ArchiveSnapshot(url: archive, entries: Array(snapshot.entries.dropLast()), stamp: snapshot.stamp, unlocked: nil)
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "資料 🐘.app", to: "renamed", in: shortened, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try Data(base64Encoded: "UEsDBBQAAAAAAE8qTF0QNp+MBAAAAAQAAAABAAAAYWZpbGVQSwMEFAAAAAAATypMXSlUsyIFAAAABQAAAAcAAABhL2NoaWxkY2hpbGRQSwECFAMUAAAAAABPKkxdEDafjAQAAAAEAAAAAQAAAAAAAAAAAAAAgAEAAAAAYVBLAQIUAxQAAAAAAE8qTF0pVLMiBQAAAAUAAAAHAAAAAAAAAAAAAACAASMAAABhL2NoaWxkUEsFBgAAAAACAAIAZAAAAE0AAAAAAA==")!.write(to: archive)
            let ambiguous = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "a", to: "renamed", in: ambiguous, cancellation: ArchiveCancellation()))
            try Data("not a ZIP".utf8).write(to: archive)
            XCTAssertFalse(ArchiveZIPUpdater().canAdd(to: ambiguous))
            XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "a", to: "renamed", in: ambiguous, cancellation: ArchiveCancellation()))
        }
    }
    func testUnicodeNormalizedAndCaseFoldedSiblingCollision() throws {
        try fixture { _, archive, snapshot in
            try ArchiveZIPUpdater().rename(path: "keep.txt", to: "É.APP", in: snapshot, cancellation: ArchiveCancellation())
            let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            for name in ["é.app", "e\u{301}.app"] {
                XCTAssertThrowsError(try ArchiveZIPUpdater().rename(path: "資料 🐘.app", to: name, in: fresh, cancellation: ArchiveCancellation()))
            }
        }
    }
}
