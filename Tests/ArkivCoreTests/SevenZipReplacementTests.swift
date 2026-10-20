import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipReplacementTests: XCTestCase {
    private func fixture(password: String? = nil, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("資料.app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: folder.appendingPathComponent("猫.txt"))
        try Data("unrelated contents".utf8).write(to: folder.appendingPathComponent("keep.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "Replace", format: .sevenZip, password: password), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: password))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testSmallerLargerEmptyPreservesUnicodePathAndUnrelatedContents() throws {
        try fixture { root, archive, initial in
            var snapshot = initial
            let source = root.appendingPathComponent("chosen-name-is-ignored.bin")
            for bytes in [Data([42]), Data(repeating: 77, count: 100_000), Data()] {
                try bytes.write(to: source)
                // The decoded snapshot's order need not match the original handler.
                let entries = snapshot.entries.reversed().enumerated().map { ArchiveEntry(id: Int64($0.offset), path: $0.element.path, size: $0.element.size, kind: $0.element.kind) }
                let reordered = ArchiveSnapshot(url: archive, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
                try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: source, in: reordered, cancellation: ArchiveCancellation())
                snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
                XCTAssertEqual(Set(snapshot.entries.map(\.path)), Set(initial.entries.map(\.path)))
                let out = try LibArchiveEngine().extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/猫.txt")), bytes)
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/keep.txt")), Data("unrelated contents".utf8))
            }
        }
    }
    func testInvalidSourcesCancellationAndStaleArchiveLeaveOriginalUntouched() throws {
        try fixture { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let source = root.appendingPathComponent("source")
            try Data(repeating: 7, count: 100_000).write(to: source)
            let link = root.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            for (path, input) in [("資料.app", source), ("missing", source), ("資料.app/猫.txt", root), ("資料.app/猫.txt", link), ("資料.app/猫.txt", archive)] {
                XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: path, with: input, in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: source, in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            try Data("external change".utf8).write(to: archive)
            XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: source, in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external change".utf8))
        }
    }
    func testSourceChangesDuringStagingAndArchiveSwapBeforeCommit() throws {
        try fixture { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let source = root.appendingPathComponent("changing-source")
            try Data(repeating: 42, count: 200_000).write(to: source)
            XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: source, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                if let handle = try? FileHandle(forWritingTo: source) {
                    try? handle.truncate(atOffset: 0)
                    try? handle.close()
                }
            }))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            try Data("restored".utf8).write(to: source)
            XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: source, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("external replacement".utf8).write(to: archive, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external replacement".utf8))
        }
    }
    func testEncryptedRemainsReadOnlyAfterUnlock() throws {
        try fixture(password: "fixture password") { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "資料.app/猫.txt", with: root.appendingPathComponent("資料.app/猫.txt"), in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }
}
