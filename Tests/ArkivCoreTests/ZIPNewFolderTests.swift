import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPNewFolderTests: XCTestCase {
    private func fixture(_ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep.txt")
        try Data("retained".utf8).write(to: file)
        let archive = try ArchiveCreator().create(.init(sources: [file], destination: root, name: "Folders"), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testRootNestedUnicodeReopenExtractAndRetainedRecords() throws {
        try fixture { root, archive, snapshot in
            let before = try Data(contentsOf: archive)
            let updater = ArchiveZIPUpdater(), engine = LibArchiveEngine()
            try updater.createFolder(named: "Café 🐈", in: snapshot, cancellation: ArchiveCancellation())
            let fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            try updater.createFolder(named: "empty", in: fresh, folder: "Café 🐈", cancellation: ArchiveCancellation())
            let final = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(Set(final.entries.map(\.path)), ["keep.txt", "Café 🐈/", "Café 🐈/empty/"])
            XCTAssertTrue(final.entries.filter { $0.kind == .directory }.allSatisfy { $0.size == 0 })
            let offset = try XCTUnwrap(before.range(of: Data([0x50,0x4b,1,2]))?.lowerBound)
            XCTAssertEqual(before.prefix(offset), try Data(contentsOf: archive).prefix(offset))
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation()).state, .ok)
            let out = try engine.extract(final, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("Café 🐈/empty").path), [])
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("keep.txt")), Data("retained".utf8))
        }
    }
    func testInvalidConflictCancellationAndStaleAreAtomic() throws {
        try fixture { _, archive, snapshot in
            let updater = ArchiveZIPUpdater(), before = try Data(contentsOf: archive)
            for name in ["", ".", "..", "a/b", "a\\b", "a:b", "a\n", "\u{7f}", "KEEP.TXT"] {
                XCTAssertThrowsError(try updater.createFolder(named: name, in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), before)
            }
            for parent in ["missing", "../", "keep.txt"] {
                XCTAssertThrowsError(try updater.createFolder(named: "child", in: snapshot, folder: parent, cancellation: ArchiveCancellation()))
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.createFolder(named: "cancel", in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try updater.createFolder(named: "Café", in: snapshot, cancellation: ArchiveCancellation())
            let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            let changed = try Data(contentsOf: archive)
            XCTAssertThrowsError(try updater.createFolder(named: "CAFE\u{301}", in: fresh, cancellation: ArchiveCancellation()))
            XCTAssertThrowsError(try updater.createFolder(named: "stale", in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), changed)
            XCTAssertThrowsError(try updater.createFolder(named: "race", in: fresh, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("external writer".utf8).write(to: archive, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external writer".utf8))
        }
    }
}
