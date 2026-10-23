import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPFolderReplacementTests: XCTestCase {
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
    func testSubtreePackageUnicodeEmptyAndPreservation() throws {
        try fixture { root, archive, snapshot, input in
            let fm = FileManager.default, engine = LibArchiveEngine(), updater = ArchiveZIPUpdater()
            try fm.createDirectory(at: input.appendingPathComponent("new/空 🐈"), withIntermediateDirectories: true)
            try Data("new contents".utf8).write(to: input.appendingPathComponent("match.txt"))
            try Data("added".utf8).write(to: input.appendingPathComponent("new/file"))
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234567890)], ofItemAtPath: input.path)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: input.appendingPathComponent("new/file").path)
            let before = try Data(contentsOf: archive)
            try updater.replaceFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation())
            var fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(Set(fresh.entries.map(\.path)), ["keep.txt","資料.app/","資料.app/match.txt","資料.app/new/","資料.app/new/file","資料.app/new/空 🐈/"])
            let after = try Data(contentsOf: archive)
            // The first unrelated local record is retained byte-for-byte, including its payload.
            let next = try XCTUnwrap(before.range(of: Data([0x50,0x4b,3,4]), in: 4..<before.count)?.lowerBound)
            XCTAssertEqual(before.prefix(next), after.prefix(next))
            let firstChild = try XCTUnwrap(before.range(of: Data([0x50,0x4b,3,4]), in: (next+4)..<before.count)?.lowerBound)
            XCTAssertEqual(before.prefix(firstChild), after.prefix(firstChild), "Preserve the selected directory record and its metadata too")
            XCTAssertEqual(after.suffix(7), Data("comment".utf8))
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation()).state, .ok)
            let out = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/match.txt")), Data("new contents".utf8))
            XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("keep.txt")), Data("unrelated".utf8))
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: out.appendingPathComponent("資料.app/new/空 🐈").path), [])
            XCTAssertEqual((try fm.attributesOfItem(atPath: out.appendingPathComponent("資料.app/new/file").path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
            // Replace a nested folder with empty contents; its archive basename is retained.
            let empty = root.appendingPathComponent("empty")
            try fm.createDirectory(at: empty, withIntermediateDirectories: false)
            try updater.replaceFolder(path: "資料.app/new", with: empty, in: fresh, cancellation: ArchiveCancellation())
            fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(Set(fresh.entries.map(\.path)), ["keep.txt","資料.app/","資料.app/match.txt","資料.app/new/"])
            try updater.replaceFolder(path: "資料.app", with: empty, in: fresh, cancellation: ArchiveCancellation())
            fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(Set(fresh.entries.map(\.path)), ["keep.txt","資料.app/"])
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation()).state, .ok)
        }
    }
    func testInvalidCancellationFailureAndStaleAreAtomic() throws {
        try fixture { root, archive, snapshot, input in
            let updater = ArchiveZIPUpdater(), before = try Data(contentsOf: archive)
            let link = root.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
            for (path, source) in [("keep.txt",input),("missing",input),("資料.app",archive),("資料.app",link)] {
                XCTAssertThrowsError(try updater.replaceFolder(path: path, with: source, in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), before)
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.replaceFolder(path: "資料.app", with: input, in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try FileManager.default.createSymbolicLink(at: input.appendingPathComponent("unsafe"), withDestinationURL: root)
            XCTAssertThrowsError(try updater.replaceFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try FileManager.default.removeItem(at: input.appendingPathComponent("unsafe"))
            XCTAssertThrowsError(try updater.replaceFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("external".utf8).write(to: archive, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: archive), Data("external".utf8))
            XCTAssertThrowsError(try updater.replaceFolder(path: "資料.app", with: input, in: snapshot, cancellation: ArchiveCancellation()))
        }
    }
    func testImplicitFolderEmptyReplacementAndSevenZipRejected() throws {
        try fixture { root, _, _, input in
            let creator = ArchiveCreator(), engine = LibArchiveEngine(), updater = ArchiveZIPUpdater()
            let archive = try creator.create(.init(sources: [root.appendingPathComponent("keep.txt")], destination: root, name: "Implicit"), archiveFolder: "implicit", cancellation: ArchiveCancellation(), progress: { _ in })
            let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(snapshot.entries.count, 1)
            try updater.replaceFolder(path: "implicit", with: input, in: snapshot, cancellation: ArchiveCancellation())
            let fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(fresh.entries.map(\.path), ["implicit/"])
            let out = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("implicit").path), [])
            let seven = try creator.create(.init(sources: [input], destination: root, name: "ReadOnly", format: .sevenZip), cancellation: ArchiveCancellation(), progress: { _ in })
            let before = try Data(contentsOf: seven)
            XCTAssertThrowsError(try updater.replaceFolder(path: "different-name", with: input, in: engine.inspect(seven, cancellation: ArchiveCancellation()), cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: seven), before)
        }
    }

}
