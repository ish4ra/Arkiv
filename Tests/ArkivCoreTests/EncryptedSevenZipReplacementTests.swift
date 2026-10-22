import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class EncryptedSevenZipReplacementTests: XCTestCase {
    private func fixture(password: String? = "secret", headers: Bool = true, _ body: (URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("資料.app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: folder.appendingPathComponent("猫 résumé.txt"))
        try Data("unrelated contents".utf8).write(to: folder.appendingPathComponent("keep.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "Replace", format: .sevenZip, password: password, encryptFilenames: headers), cancellation: ArchiveCancellation(), progress: { _ in })
        try body(root, archive, LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: password))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testSmallerLargerEmptyPreservesNameHeaderPolicyAndOtherFiles() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, initial in
                var snapshot = initial
                let source = root.appendingPathComponent("chosen-name-is-ignored.bin")
                for bytes in [Data([42]), Data(repeating: 77, count: 100_000), Data(), Data("from empty".utf8)] {
                    try bytes.write(to: source)
                    let entries = snapshot.entries.reversed().enumerated().map { ArchiveEntry(id: Int64($0.offset), path: $0.element.path, size: $0.element.size, kind: $0.element.kind) }
                    var reordered = ArchiveSnapshot(url: archive, entries: entries, stamp: snapshot.stamp, unlocked: snapshot.unlocked)
                    reordered.sevenEncryptionPolicy = snapshot.sevenEncryptionPolicy
                    try ArchiveModificationUpdater().replace(path: "資料.app/猫 résumé.txt", with: source, in: reordered, password: "secret", cancellation: ArchiveCancellation())
                    snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
                    XCTAssertEqual(Set(snapshot.entries.map(\.path)), Set(initial.entries.map(\.path)))
                    XCTAssertEqual(snapshot.sevenEncryptionPolicy?.headersEncrypted, headers)
                    XCTAssertEqual(snapshot.sevenEncryptionPolicy?.dataEncrypted, true)
                    XCTAssertEqual(snapshot.sevenEncryptionPolicy?.mixedEncryption, false)
                    XCTAssertEqual(try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation(), password: "secret").state, .ok)
                    let out = try LibArchiveEngine().extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                    XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/猫 résumé.txt")), bytes)
                    XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("資料.app/keep.txt")), Data("unrelated contents".utf8))
                }
            }
        }
    }
    func testPasswordInvalidSelectionAndSourceFailuresAreAtomic() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let original = try Data(contentsOf: archive), updater = ArchiveModificationUpdater()
                let source = root.appendingPathComponent("source")
                try Data("new".utf8).write(to: source)
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected fresh password") }
                }
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, password: "wrong", cancellation: ArchiveCancellation())) {
                    guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected wrong password") }
                }
                let link = root.appendingPathComponent("link")
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
                for (path, input) in [("資料.app", source), ("missing", source), ("資料.app/猫 résumé.txt", root), ("資料.app/猫 résumé.txt", link), ("資料.app/猫 résumé.txt", archive)] {
                    XCTAssertThrowsError(try updater.replace(path: path, with: input, in: snapshot, password: "secret", cancellation: ArchiveCancellation()))
                    XCTAssertEqual(try Data(contentsOf: archive), original)
                }
            }
        }
    }
    func testCancellationChangedSourceAndUnsupportedPolicyNeverCommit() throws {
        for headers in [false, true] {
            try fixture(headers: headers) { root, archive, snapshot in
                let original = try Data(contentsOf: archive), updater = ArchiveModificationUpdater()
                let source = root.appendingPathComponent("source")
                try Data(repeating: 42, count: 200_000).write(to: source)
                var unsupported = snapshot
                unsupported.sevenEncryptionPolicy = SevenZipEncryptionPolicy(dataEncrypted: true, headersEncrypted: headers, mixedEncryption: true, supportedLayout: false, allDataVerified: true)
                XCTAssertFalse(updater.canReplaceEncrypted(unsupported))
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: unsupported, password: "secret", cancellation: ArchiveCancellation()))
                let token = ArchiveCancellation()
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, password: "secret", cancellation: token, progress: { _ in token.cancel() }))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, password: "secret", cancellation: ArchiveCancellation(), progress: { _ in
                    if let handle = try? FileHandle(forWritingTo: source) {
                        try? handle.truncate(atOffset: 0); try? handle.close()
                    }
                }))
                XCTAssertEqual(try Data(contentsOf: archive), original)
                try Data("restored".utf8).write(to: source)
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, password: "secret", cancellation: ArchiveCancellation(), progress: { _ in
                    try? Data("external replacement".utf8).write(to: archive, options: .atomic)
                }))
                XCTAssertEqual(try Data(contentsOf: archive), Data("external replacement".utf8))
                XCTAssertFalse(updater.canReplaceEncrypted(snapshot))
                XCTAssertThrowsError(try updater.replace(path: "資料.app/猫 résumé.txt", with: source, in: snapshot, password: "secret", cancellation: ArchiveCancellation()))
            }
        }
    }
}
