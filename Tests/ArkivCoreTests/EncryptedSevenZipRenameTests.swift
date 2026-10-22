import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class EncryptedSevenZipRenameTests: XCTestCase {
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
    func testFilePackageUnicodeAndCaseOnlyRenamePreservesPolicyAndData() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let updater = ArchiveModificationUpdater(), engine = LibArchiveEngine()
                XCTAssertTrue(updater.canRenameEncrypted(snapshot))
                var fresh = snapshot
                for (path, name) in [("keep.txt", "KEEP.txt"), ("資料.app", "新しい 🦋.app"), ("新しい 🦋.app/nested/🦋.txt", "résumé 🐈.txt"), ("新しい 🦋.app/nested/empty", "EMPTY")] {
                    do { try updater.rename(path: path, to: name, in: fresh, password: "secret", cancellation: ArchiveCancellation()) }
                    catch { XCTFail("Rename transaction failed for \(path): \(error)"); return }
                    do { fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret") }
                    catch { XCTFail("Reopen after rename failed: \(error)"); return }
                    XCTAssertEqual(fresh.sevenEncryptionPolicy?.headersEncrypted, headers)
                    XCTAssertEqual(fresh.sevenEncryptionPolicy?.dataEncrypted, true)
                    XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation(), password: "secret").state, .ok)
                }
                let out: URL
                do { out = try engine.extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in }) }
                catch { XCTFail("Extraction after rename failed: \(error)"); return }
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("KEEP.txt")), Data("retained".utf8))
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("remove.txt")), Data("deleted".utf8))
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("新しい 🦋.app/nested/résumé 🐈.txt")), Data("child".utf8))
                XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("新しい 🦋.app/nested/EMPTY").path))
                do { try updater.delete(paths: ["新しい 🦋.app"], from: fresh, password: "secret", cancellation: ArchiveCancellation()) }
                catch { XCTFail("Encrypted Delete after rename failed: \(error)"); return }
                fresh = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                XCTAssertEqual(Set(fresh.entries.map(\.path)), ["KEEP.txt", "remove.txt"])
            }
        }
    }
    func testInvalidConflictingNamesAndWrongPasswordLeaveOriginalUnchanged() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { _, archive, snapshot in
                let updater = ArchiveModificationUpdater(), original = try Data(contentsOf: archive)
                for name in ["", ".", "..", "a/b", "a\\b", "a:b", "a\n", "REMOVE.TXT", "資料.app"] {
                    XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: name, in: snapshot, password: "secret", cancellation: ArchiveCancellation()), name)
                    XCTAssertEqual(try Data(contentsOf: archive), original)
                }
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected operation-local password request") }
                }
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, password: "wrong", cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected wrong password") }
                }
                XCTAssertEqual(try Data(contentsOf: archive), original)
            }
        }
    }
    func testCancellationAndSourceChangeAreAtomic() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { _, archive, snapshot in
                let updater = ArchiveModificationUpdater(), original = try Data(contentsOf: archive)
                let token = ArchiveCancellation()
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, password: "secret", cancellation: token, progress: { _ in token.cancel() }))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, password: "secret", cancellation: ArchiveCancellation(), progress: { _ in
                    try? Data("external change".utf8).write(to: archive)
                }))
                XCTAssertEqual(try Data(contentsOf: archive), Data("external change".utf8))
                XCTAssertFalse(updater.canRenameEncrypted(snapshot))
                XCTAssertThrowsError(try updater.rename(path: "keep.txt", to: "new.txt", in: snapshot, password: "secret", cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), Data("external change".utf8))
            }
        }
    }
}
