import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class EncryptedSevenZipAdditionTests: XCTestCase {
    private func fixture(password: String? = "secret", headers: Bool = false, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
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
    func testFilesFoldersUnicodeAndEmptyItemsPreservePolicy() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let updater = ArchiveAdditionUpdater(), engine = LibArchiveEngine()
                XCTAssertTrue(updater.canAddEncrypted(snapshot))
                let folder = root.appendingPathComponent("資料 🐈.app")
                try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
                try Data("Unicode bytes".utf8).write(to: folder.appendingPathComponent("nested/résumé.txt"))
                try Data().write(to: folder.appendingPathComponent("zero"))
                let file = root.appendingPathComponent("new.txt")
                try Data("new bytes".utf8).write(to: file)
                try updater.add(sources: [file], to: snapshot, password: "secret", cancellation: ArchiveCancellation())
                var fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                try updater.add(sources: [folder], to: fresh, password: "secret", cancellation: ArchiveCancellation())
                fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertEqual(fresh.sevenEncryptionPolicy?.headersEncrypted, headers)
                XCTAssertEqual(fresh.sevenEncryptionPolicy?.dataEncrypted, true)
                XCTAssertEqual(fresh.sevenEncryptionPolicy?.mixedEncryption, false)
                XCTAssertTrue(updater.canAddEncrypted(fresh))
                XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation(), password: "secret").state, .ok)
                let output = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                for (path, bytes) in [("existing.txt", "original payload"), ("new.txt", "new bytes"), ("資料 🐈.app/nested/résumé.txt", "Unicode bytes"), ("資料 🐈.app/zero", "")] {
                    XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent(path)), Data(bytes.utf8))
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("資料 🐈.app/nested/empty").path))
                try ArchiveModificationUpdater().rename(path: "資料 🐈.app", to: "Renamed.app", in: fresh, password: "secret", cancellation: ArchiveCancellation())
                fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                try ArchiveModificationUpdater().delete(paths: ["Renamed.app"], from: fresh, password: "secret", cancellation: ArchiveCancellation())
                fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertEqual(Set(fresh.entries.map(\.path)), ["existing.txt", "new.txt"])
                XCTAssertThrowsError(try ArchiveModificationUpdater().replace(path: "existing.txt", with: file, in: fresh, cancellation: ArchiveCancellation()))
            }
        }
    }
    func testPasswordConflictsAndNonRootRequestsFailAtomically() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let original = try Data(contentsOf: archive), updater = ArchiveAdditionUpdater()
                let file = root.appendingPathComponent("new.txt"), conflict = root.appendingPathComponent("EXISTING.TXT")
                try Data("new".utf8).write(to: file)
                try Data("conflict".utf8).write(to: conflict)
                XCTAssertThrowsError(try updater.add(sources: [file], to: snapshot, cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected fresh password") }
                }
                XCTAssertThrowsError(try updater.add(sources: [file], to: snapshot, password: "wrong", cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected wrong password") }
                }
                for sources in [[file, conflict], [file, file], [archive], [], [root.appendingPathComponent("missing")]] {
                    XCTAssertThrowsError(try updater.add(sources: sources, to: snapshot, password: "secret", cancellation: ArchiveCancellation()))
                    XCTAssertEqual(try Data(contentsOf: archive), original)
                }
                XCTAssertThrowsError(try updater.add(sources: [file], to: snapshot, folder: "subfolder", password: "secret", cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
        }
    }
    func testCancellationAndChangedSourceNeverCommit() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let source = root.appendingPathComponent("new.txt"), original = try Data(contentsOf: archive)
                try Data(repeating: 65, count: 100000).write(to: source)
                let updater = ArchiveAdditionUpdater(), token = ArchiveCancellation()
                XCTAssertThrowsError(try updater.add(sources: [source], to: snapshot, password: "secret", cancellation: token, progress: { _ in token.cancel() }))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                XCTAssertThrowsError(try updater.add(sources: [source], to: snapshot, password: "secret", cancellation: ArchiveCancellation(), progress: { _ in
                    try? Data("external change".utf8).write(to: archive)
                }))
                XCTAssertEqual(try Data(contentsOf: archive), Data("external change".utf8))
                XCTAssertFalse(updater.canAddEncrypted(snapshot))
                XCTAssertThrowsError(try updater.add(sources: [source], to: snapshot, password: "secret", cancellation: ArchiveCancellation()))
            }
        }
    }
}
