import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class EncryptedSevenZipDeletionTests: XCTestCase {
    private func fixture(headers: Bool, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let keep = root.appendingPathComponent("keep.txt"), remove = root.appendingPathComponent("remove.txt")
        let folder = root.appendingPathComponent("資料.app")
        try Data("retained".utf8).write(to: keep)
        try Data("deleted".utf8).write(to: remove)
        try fm.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
        try Data("child".utf8).write(to: folder.appendingPathComponent("nested/🦋.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [keep, remove, folder], destination: root, name: "Encrypted", format: .sevenZip, password: "secret", encryptFilenames: headers), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret"))
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testSingleMultipleAndPackageDeletionPreservesHeaderPolicy() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let updater = ArchiveModificationUpdater(), engine = LibArchiveEngine()
                XCTAssertTrue(updater.canDeleteEncrypted(snapshot))
                XCTAssertFalse(updater.capability(for: snapshot).isAvailable, "Other encrypted edits remain disabled")
                try updater.delete(paths: ["remove.txt"], from: snapshot, password: "secret", cancellation: ArchiveCancellation())
                var fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertNil(fresh.index.row(at: "remove.txt"))
                try updater.delete(paths: ["資料.app", "資料.app/nested/🦋.txt", "資料.app/nested/empty"], from: fresh, password: "secret", cancellation: ArchiveCancellation())
                fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertEqual(fresh.entries.map(\.path), ["keep.txt"])
                XCTAssertEqual(fresh.sevenEncryptionPolicy?.headersEncrypted, headers)
                XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation(), password: "secret").state, .ok)
                let out = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("keep.txt")), Data("retained".utf8))
            }
        }
    }
    func testMultipleFilesAndOtherEncryptedEditsRemainDisabled() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let updater = ArchiveModificationUpdater(), original = try Data(contentsOf: archive)
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertThrowsError(try updater.replace(path: "keep.txt", with: root.appendingPathComponent("remove.txt"), in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources: [root.appendingPathComponent("keep.txt")], to: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                try updater.delete(paths: ["remove.txt", "資料.app/nested/🦋.txt"], from: snapshot, password: "secret", cancellation: ArchiveCancellation())
                let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertNotNil(fresh.index.row(at: "keep.txt"))
                XCTAssertNotNil(fresh.index.row(at: "資料.app/nested/empty"))
                XCTAssertNil(fresh.index.row(at: "remove.txt"))
                XCTAssertNil(fresh.index.row(at: "資料.app/nested/🦋.txt"))
            }
        }
    }
    func testWrongPasswordCancellationAndStaleSourceAreAtomic() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { _, archive, snapshot in
                let updater = ArchiveModificationUpdater(), original = try Data(contentsOf: archive)
                XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected password request") }
                }
                XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, password: "wrong", cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected wrong password") }
                }
                let token = ArchiveCancellation()
                XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, password: "secret", cancellation: token, progress: { _ in token.cancel() }))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, password: "secret", cancellation: ArchiveCancellation(), progress: { _ in
                    try? Data("changed".utf8).write(to: archive)
                }))
                XCTAssertEqual(try Data(contentsOf: archive), Data("changed".utf8))
                XCTAssertThrowsError(try updater.delete(paths: ["remove.txt"], from: snapshot, password: "secret", cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), Data("changed".utf8))
            }
        }
    }
    func testDeleteAllPreservesHeaderEncryption() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { _, archive, snapshot in
                try ArchiveModificationUpdater().delete(paths: ["keep.txt", "remove.txt", "資料.app"], from: snapshot, password: "secret", cancellation: ArchiveCancellation())
                let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertTrue(fresh.entries.isEmpty)
                XCTAssertEqual(fresh.sevenEncryptionPolicy?.headersEncrypted, headers)
            }
        }
    }
}
