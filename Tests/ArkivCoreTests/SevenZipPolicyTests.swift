#if os(Linux)
import Glibc
#endif
import XCTest
@testable import ArkivCore

final class SevenZipPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
    }
    func testOriginalPolicyAndOperationLocalPassword() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("資料 🐈.txt")
        try Data("secret payload".utf8).write(to: source)
        let inspector = SevenZipPolicyInspector()
        for headers in [false, true] {
            let archive = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Protected", format: .sevenZip, password: "secret", encryptFilenames: headers), cancellation: ArchiveCancellation(), progress: { _ in })
            let original = try Data(contentsOf: archive)
            let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation(), password: "secret")
            // Already unlocked does not make the password available to editing.
            XCTAssertThrowsError(try inspector.inspect(snapshot, password: nil, cancellation: ArchiveCancellation())) {
                guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected password request") }
            }
            var requests = 0
            let policy = try inspector.prepareEncryptedEdit(in: snapshot, cancellation: ArchiveCancellation()) { requests += 1; return "secret" }
            XCTAssertEqual(requests, 1)
            XCTAssertTrue(policy.dataEncrypted)
            XCTAssertEqual(policy.headersEncrypted, headers)
            XCTAssertFalse(policy.mixedEncryption)
            XCTAssertTrue(policy.eligibleForFutureEncryptedModification)
            XCTAssertFalse(policy.modificationEnabled)
            XCTAssertFalse(ArchiveAdditionUpdater().capability(for: snapshot).isAvailable)
            XCTAssertThrowsError(try inspector.prepareEncryptedEdit(in: snapshot, cancellation: ArchiveCancellation()) { "wrong" }) {
                guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected password error") }
            }
            XCTAssertThrowsError(try inspector.prepareEncryptedEdit(in: snapshot, cancellation: ArchiveCancellation()) { nil }) {
                guard case ArchiveFailure.cancelled = $0 else { return XCTFail("Expected cancellation") }
            }
            let cancelled = ArchiveCancellation(); cancelled.cancel()
            XCTAssertThrowsError(try inspector.prepareEncryptedEdit(in: snapshot, cancellation: cancelled) { XCTFail("Must not request after cancel"); return "secret" })
            XCTAssertEqual(try Data(contentsOf: archive), original)
            XCTAssertThrowsError(try inspector.prepareEncryptedEdit(in: snapshot, cancellation: ArchiveCancellation()) {
                try Data("changed".utf8).write(to: archive)
                return "secret"
            })
            XCTAssertThrowsError(try inspector.prepareEncryptedEdit(in: snapshot, cancellation: ArchiveCancellation()) { XCTFail("Stale snapshot"); return "secret" })
        }
    }
}
