import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPFolderUpdateTests: XCTestCase {
    private func fixture(_ body: (URL, URL, ArchiveSnapshot, URL) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("資料.app")
        try fm.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("old".utf8).write(to: folder.appendingPathComponent("match.txt"))
        try Data("remove".utf8).write(to: folder.appendingPathComponent("nested/old"))
        let keep = root.appendingPathComponent("keep.txt")
        try Data("unrelated".utf8).write(to: keep)
        let archive = try ArchiveCreator().create(.init(sources: [keep, folder], destination: root, name: "ReplaceFolder"), cancellation: ArchiveCancellation(), progress: { _ in })
        var bytes = try Data(contentsOf: archive)
        bytes.replaceSubrange((bytes.count-2)..<bytes.count, with: [7,0]); bytes.append(Data("comment".utf8))
        try bytes.write(to: archive)
        let input = root.appendingPathComponent("different-name")
        try fm.createDirectory(at: input, withIntermediateDirectories: false)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234567890)], ofItemAtPath: input.path)
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()), input)
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }

    func testMergeKeepsArchiveOnlyAddsReplacesAndEmptySource() throws {
        try fixture { root, archive, snapshot, input in
            let fm = FileManager.default, engine = LibArchiveEngine(), updater = ArchiveZIPUpdater()
            try fm.createDirectory(at: input.appendingPathComponent("new/空 🐈"), withIntermediateDirectories: true)
            try Data("updated".utf8).write(to: input.appendingPathComponent("match.txt"))
            try Data("added".utf8).write(to: input.appendingPathComponent("new/file"))
            try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation())
            let fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(Set(fresh.entries.map(\.path)), ["keep.txt","資料.app/","資料.app/match.txt","資料.app/nested/","資料.app/nested/old","資料.app/new/","資料.app/new/file","資料.app/new/空 🐈/"])
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation()).state, .ok)
            let out = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/match.txt")), Data("updated".utf8))
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/nested/old")), Data("remove".utf8))
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/new/file")), Data("added".utf8))
            let empty = root.appendingPathComponent("empty")
            try fm.createDirectory(at: empty, withIntermediateDirectories: false)
            let before = try Data(contentsOf: archive)
            try updater.updateFolder(path: "資料.app", with: empty, in: fresh, cancellation: ArchiveCancellation())
            XCTAssertEqual(try Data(contentsOf: archive), before, "Empty source preserves every raw record and metadata")
        }
    }
    func testConflictsCancellationStaleAndFailureAreAtomic() throws {
        try fixture { root, archive, snapshot, input in
            let fm = FileManager.default, updater = ArchiveZIPUpdater(), before = try Data(contentsOf: archive)
            let match = input.appendingPathComponent("match.txt")
            try fm.createDirectory(at: match, withIntermediateDirectories: false)
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try fm.removeItem(at: match)
            try Data("alias".utf8).write(to: input.appendingPathComponent("MATCH.TXT"))
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try fm.removeItem(at: input.appendingPathComponent("MATCH.TXT"))
            try Data("updated".utf8).write(to: match)
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            XCTAssertThrowsError(try updater.updateFolder(path: "keep.txt", with: input, in: snapshot, cancellation: ArchiveCancellation()))
            let link = root.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: input)
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: link, in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("external".utf8).write(to: archive, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external".utf8))
            XCTAssertThrowsError(try updater.updateFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation()))
        }
    }
}
