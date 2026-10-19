import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipAdditionTests: XCTestCase {
    private func fixture(password: String? = nil, headers: Bool = false, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing.txt")
        try Data("original payload".utf8).write(to: existing)
        let archive = try ArchiveCreator().create(.init(sources: [existing], destination: root, name: "Original", format: .sevenZip, password: password, encryptFilenames: headers), cancellation: ArchiveCancellation(), progress: { _ in })
        let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: password)
        try body(root, archive, snapshot)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testRootFilesUnicodeFoldersAndEmptyItemsRoundTrip() throws {
        try fixture { root, archive, snapshot in
            let updater = ArchiveAdditionUpdater()
            XCTAssertEqual(updater.capability(for: snapshot), .sevenZip)
            XCTAssertNotNil(snapshot.unlocked)
            XCTAssertFalse(ArchiveZIPUpdater().canAdd(to: snapshot))
            let folder = root.appendingPathComponent("資料 🐈")
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
            try Data("Unicode bytes".utf8).write(to: folder.appendingPathComponent("nested/é.txt"))
            try Data().write(to: folder.appendingPathComponent("zero"))
            let file = root.appendingPathComponent("new.txt")
            try Data("new payload".utf8).write(to: file)
            try updater.add(sources: [folder, file], to: snapshot, cancellation: ArchiveCancellation())
            let engine = LibArchiveEngine()
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation()).state, .ok)
            let fresh = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(updater.capability(for: fresh), .sevenZip)
            let output = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("existing.txt")), Data("original payload".utf8))
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("new.txt")), Data("new payload".utf8))
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("資料 🐈/nested/é.txt")), Data("Unicode bytes".utf8))
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("資料 🐈/zero")), Data())
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("資料 🐈/nested/empty").path))
        }
    }
    func testConflictsAndNonRootRequestsLeaveOriginalIntact() throws {
        try fixture { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let conflict = root.appendingPathComponent("EXISTING.TXT")
            try Data("conflict".utf8).write(to: conflict)
            let new = root.appendingPathComponent("new.txt")
            try Data("new".utf8).write(to: new)
            for sources in [[conflict], [new, conflict], [new, new], [archive]] {
                XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: sources, to: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
            XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [new], to: snapshot, folder: "nested", cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }
    func testCancellationMissingSourcesAndStaleSnapshotLeaveOriginalIntact() throws {
        try fixture { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let source = root.appendingPathComponent("large")
            try Data(repeating: 8, count: 1_000_000).write(to: source)
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [source], to: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [root.appendingPathComponent("missing")], to: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            let changed = Data("changed source".utf8)
            try changed.write(to: archive)
            XCTAssertFalse(ArchiveAdditionUpdater().capability(for: snapshot).isAvailable)
            XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [source], to: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), changed)
        }
    }
    func testEncryptedArchivesRemainReadOnlyAfterUnlocking() throws {
        for headers in [false, true] {
            try fixture(password: "fixture password", headers: headers) { root, archive, snapshot in
                let original = try Data(contentsOf: archive)
                let updater = ArchiveAdditionUpdater()
                XCTAssertFalse(updater.capability(for: snapshot).isAvailable)
                XCTAssertThrowsError(try updater.add(sources: [root.appendingPathComponent("existing.txt")], to: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
        }
    }
    func testZIPOnlyEditsStayDisabledForSevenZip() throws {
        try fixture { root, archive, snapshot in
            let original = try Data(contentsOf: archive)
            let zip = ArchiveZIPUpdater()
            XCTAssertThrowsError(try zip.add(sources: [root.appendingPathComponent("existing.txt")], to: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertThrowsError(try zip.delete(paths: ["existing.txt"], from: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertThrowsError(try zip.rename(path: "existing.txt", to: "renamed.txt", in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertThrowsError(try zip.replace(path: "existing.txt", with: root.appendingPathComponent("existing.txt"), in: snapshot, cancellation: ArchiveCancellation()))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }
    func testMagicDetectionAndZIPDispatch() throws {
        try fixture { root, archive, _ in
            let renamed = root.appendingPathComponent("renamed.bin")
            try FileManager.default.moveItem(at: archive, to: renamed)
            let snapshot = try LibArchiveEngine().inspect(renamed, cancellation: ArchiveCancellation())
            XCTAssertEqual(ArchiveAdditionUpdater().capability(for: snapshot), .sevenZip)
            let new = root.appendingPathComponent("new")
            try Data().write(to: new)
            try ArchiveAdditionUpdater().add(sources: [new], to: snapshot, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().test(renamed, cancellation: ArchiveCancellation()).state, .ok)
            let zip = try ArchiveCreator().create(.init(sources: [new], destination: root, name: "ZIP"), cancellation: ArchiveCancellation(), progress: { _ in })
            let zipSnapshot = try LibArchiveEngine().inspect(zip, cancellation: ArchiveCancellation())
            XCTAssertEqual(ArchiveAdditionUpdater().capability(for: zipSnapshot), .zip)
            try ArchiveAdditionUpdater().add(sources: [root.appendingPathComponent("existing.txt")], to: zipSnapshot, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(zip, cancellation: ArchiveCancellation()).entries.count, 2)
        }
    }
    func testAmbiguousExistingAndIncomingNamespacesAreRejected() throws {
        try fixture { root, archive, snapshot in
            for paths in [["A/one", "a/two"], ["é/one", "e\u{301}/two"], ["file", "file/child"], ["same", "same"]] {
                let entries = paths.enumerated().map { ArchiveEntry(id: Int64($0.offset), path: $0.element, size: 0, kind: .file) }
                let ambiguous = ArchiveSnapshot(url: snapshot.url, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
                XCTAssertFalse(ArchiveAdditionUpdater().capability(for: ambiguous).isAvailable)
            }
            let folder = root.appendingPathComponent("incoming")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("first".utf8).write(to: folder.appendingPathComponent("A"))
            try Data("second".utf8).write(to: folder.appendingPathComponent("a"))
            // A case-insensitive filesystem cannot construct this hostile input.
            if try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2 {
                let original = try Data(contentsOf: archive)
                XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [folder], to: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
        }
    }
    #if os(macOS)
    func testAddThroughTrustedSystemAliases() throws {
        for alias in ["/var/tmp", "/tmp"] {
            let root = URL(fileURLWithPath: alias).appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let old = root.appendingPathComponent("old")
            let new = root.appendingPathComponent("new")
            try Data("old".utf8).write(to: old); try Data("new".utf8).write(to: new)
            let archive = try ArchiveCreator().create(.init(sources: [old], destination: root, name: "Archive", format: .sevenZip), cancellation: ArchiveCancellation(), progress: { _ in })
            let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(ArchiveAdditionUpdater().capability(for: snapshot), .sevenZip)
            try ArchiveAdditionUpdater().add(sources: [new], to: snapshot, cancellation: ArchiveCancellation())
            XCTAssertEqual(try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation()).entries.count, 2)
        }
    }
    #endif

}
