import Foundation
import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ArchiveOpenSessionTests: XCTestCase {
    private let fm = FileManager.default
    private let engine = LibArchiveEngine()
    private func root() throws -> URL {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tests/fixtures/" + name)
    }
    private func snapshot(in root: URL, format: ArchiveFormat = .zip, password: String? = nil) throws -> ArchiveSnapshot {
        let directory = root.appendingPathComponent("入れ物/資料")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0, 1, 2, 255, 128]).write(to: directory.appendingPathComponent("é 🐘.txt"))
        try Data("must not be extracted".utf8).write(to: directory.appendingPathComponent("other.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [root.appendingPathComponent("入れ物")], destination: root,
            name: UUID().uuidString, format: format, password: password, encryptFilenames: password != nil),
            cancellation: ArchiveCancellation(), progress: { _ in })
        return try engine.inspect(archive, cancellation: ArchiveCancellation(), password: password)
    }
    private func files(below root: URL) -> [URL] {
        (fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    private func workspaceRoot(in root: URL) throws -> URL {
        try XCTUnwrap(try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("xyz.isharalakshan.arkiv.open-v1-") })
    }
    func testZIPAndSevenZipOpenOnlyExactNestedUnicodeFileAndRetainCopies() throws {
        for format: ArchiveFormat in [.zip, .sevenZip] {
            let root = try root(), snapshot = try snapshot(in: root, format: format)
            let session = ArchiveOpenSession(temporaryParent: root)
            let token = ArchiveCancellation()
            let first = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: token)
            try session.validateForLaunch(first, cancellation: token)
            XCTAssertEqual(first.url.lastPathComponent, "é 🐘.txt")
            XCTAssertEqual(try Data(contentsOf: first.url), Data([0, 1, 2, 255, 128]))
            let workspace = try workspaceRoot(in: root)
            XCTAssertEqual(files(below: workspace), [first.url])
            let second = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
            XCTAssertNotEqual(first.url, second.url)
            XCTAssertTrue(fm.fileExists(atPath: first.url.path))
            session.discard(second)
            XCTAssertFalse(fm.fileExists(atPath: second.url.path))
            XCTAssertTrue(fm.fileExists(atPath: first.url.path), "Failed launches discard only their own attempt")
            session.close()
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: workspace.path), [])
            XCTAssertThrowsError(try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation()))
        }
    }
    func testTARAndRARUseExistingBackendAndRejectLinksAndDevices() throws {
        let root = try root()
        for name in ["links-and-special.tar", "rar5-stored.rar"] {
            let snapshot = try engine.inspect(fixture(name), cancellation: ArchiveCancellation())
            let session = ArchiveOpenSession(temporaryParent: root)
            defer { session.close() }
            let entry = try XCTUnwrap(snapshot.entries.first { $0.kind == .file })
            let opened = try session.prepare(snapshot, path: entry.path, cancellation: ArchiveCancellation())
            let expected = try engine.extract(snapshot, ids: [entry.id], into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: opened.url), try Data(contentsOf: expected.appendingPathComponent(entry.path)))
            XCTAssertEqual(opened.url.lastPathComponent, URL(fileURLWithPath: entry.path).lastPathComponent)
            for unsafe in snapshot.entries where unsafe.kind != .file {
                XCTAssertNil(ArchiveOpenSession.regularEntry(in: snapshot, path: unsafe.path))
                XCTAssertThrowsError(try session.prepare(snapshot, path: unsafe.path, cancellation: ArchiveCancellation()))
            }
            XCTAssertEqual(files(below: try workspaceRoot(in: root)), [opened.url])
        }
    }
    func testUnlockedSnapshotIsReusedWithoutPasswordOrNewSpool() throws {
        let root = try root()
        var snapshot: ArchiveSnapshot? = try snapshot(in: root, format: .sevenZip, password: "secret")
        let spool = try XCTUnwrap(snapshot?.unlocked?.directory)
        let session = ArchiveOpenSession(temporaryParent: root)
        let file = try session.prepare(snapshot!, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
        XCTAssertTrue(fm.fileExists(atPath: spool.path))
        snapshot = nil
        XCTAssertFalse(fm.fileExists(atPath: spool.path), "Open retains no password or redundant decrypted snapshot")
        XCTAssertEqual(try Data(contentsOf: file.url), Data([0, 1, 2, 255, 128]))
        session.close()
        XCTAssertFalse(fm.fileExists(atPath: file.url.path))
    }
    func testStaleSourceCancellationAndLateCancellationDiscardAttempts() throws {
        let root = try root(), snapshot = try snapshot(in: root)
        let session = ArchiveOpenSession(temporaryParent: root)
        defer { session.close() }
        let before = ArchiveCancellation(); before.cancel()
        XCTAssertThrowsError(try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: before))
        let during = ArchiveCancellation()
        XCTAssertThrowsError(try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: during, progress: { _ in during.cancel() }))
        XCTAssertEqual(files(below: try workspaceRoot(in: root)), [])
        let token = ArchiveCancellation()
        let late = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: token)
        token.cancel()
        XCTAssertThrowsError(try session.validateForLaunch(late, cancellation: token))
        session.discard(late)
        let opened = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
        try Data("changed source".utf8).write(to: snapshot.url)
        XCTAssertThrowsError(try session.validateForLaunch(opened, cancellation: ArchiveCancellation()))
        session.discard(opened)
        XCTAssertThrowsError(try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation()))
        XCTAssertEqual(files(below: try workspaceRoot(in: root)), [])
    }
    func testCloseDuringExtractionCancelsAndCleansAfterWriterStops() throws {
        let root = try root(), snapshot = try snapshot(in: root)
        let session = ArchiveOpenSession(temporaryParent: root)
        let completed = expectation(description: "closed writer exits")
        DispatchQueue.global().async {
            do {
                _ = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation(), progress: { _ in session.close() })
                XCTFail("Closing from progress must cancel preparation")
            } catch { /* Expected cancellation, never launch. */ }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)
        // A second close waits for no work and performs idempotent cleanup.
        session.close()
        let deadline = Date().addingTimeInterval(5)
        while !(try fm.contentsOfDirectory(atPath: workspaceRoot(in: root).path)).isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: workspaceRoot(in: root).path), [])
    }
    func testSweepPreservesLiveSessionsAndUnrelatedDataWithoutFollowingLinks() throws {
        let root = try root(), snapshot = try snapshot(in: root)
        let first = ArchiveOpenSession(temporaryParent: root), second = ArchiveOpenSession(temporaryParent: root)
        defer { first.close(); second.close() }
        let a = try first.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
        let b = try second.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
        let workspace = try workspaceRoot(in: root)
        let stale = workspace.appendingPathComponent("session-" + UUID().uuidString)
        try fm.createDirectory(at: stale, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("precious.txt"))
        try fm.createSymbolicLink(at: stale.appendingPathComponent("link"), withDestinationURL: outside)
        let unrelated = workspace.appendingPathComponent("unrelated")
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let fakeSession = workspace.appendingPathComponent("session-" + UUID().uuidString)
        try fm.createSymbolicLink(at: fakeSession, withDestinationURL: outside)
        ArchiveOpenSession.cleanStaleTemporaryData(in: root)
        XCTAssertFalse(fm.fileExists(atPath: stale.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("precious.txt")), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: a.url), try Data(contentsOf: b.url))
        first.close()
        XCTAssertTrue(fm.fileExists(atPath: b.url.path))
    }
    func testSymlinkParentAndInsecureRootCannotCreateOpenWorkspace() throws {
        let root = try root(), snapshot = try snapshot(in: root)
        let alias = root.appendingPathComponent("alias")
        let target = root.appendingPathComponent("target")
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        try fm.createSymbolicLink(at: alias, withDestinationURL: target)
        let linked = ArchiveOpenSession(temporaryParent: alias)
        XCTAssertThrowsError(try linked.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation()))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: target.path), [])
        let session = ArchiveOpenSession(temporaryParent: root)
        _ = try session.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation())
        session.close()
        let workspace = try workspaceRoot(in: root)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspace.path)
        let insecure = ArchiveOpenSession(temporaryParent: root)
        XCTAssertThrowsError(try insecure.prepare(snapshot, path: "入れ物/資料/é 🐘.txt", cancellation: ArchiveCancellation()))
    }
    func testDeepestAcceptedPathCleansAndDeeperPathIsRejectedBeforeStaging() throws {
        let root = try root()
        let parts = Array(repeating: "d", count: 63)
        let folder = root.appendingPathComponent(parts.joined(separator: "/"))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: folder.appendingPathComponent("file.txt"))
        let archive = try ArchiveCreator().create(.init(sources: [root.appendingPathComponent("d")], destination: root, name: "deep"), cancellation: ArchiveCancellation(), progress: { _ in })
        let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
        let path = parts.joined(separator: "/") + "/file.txt"
        let session = ArchiveOpenSession(temporaryParent: root)
        let file = try session.prepare(snapshot, path: path, cancellation: ArchiveCancellation())
        XCTAssertEqual(try Data(contentsOf: file.url), Data("private".utf8))
        session.discard(file)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: file.url.path.components(separatedBy: "/file-")[0]), [])
        let token = ArchiveCancellation()
        XCTAssertThrowsError(try session.prepare(snapshot, path: path, cancellation: token, progress: { _ in token.cancel() }))
        session.close()
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: workspaceRoot(in: root).path), [])
        let tooDeep = "d/" + path
        let fake = ArchiveSnapshot(url: archive, entries: [ArchiveEntry(id: 0, path: tooDeep, size: 7, kind: .file)], stamp: snapshot.stamp, unlocked: nil)
        XCTAssertNil(ArchiveOpenSession.regularEntry(in: fake, path: tooDeep))
        let rejected = ArchiveOpenSession(temporaryParent: root)
        XCTAssertThrowsError(try rejected.prepare(fake, path: tooDeep, cancellation: ArchiveCancellation()))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: workspaceRoot(in: root).path), [])
    }
    func testNonRegularAmbiguousOrUnsafeEntryCannotBeOpened() throws {
        let root = try root(), original = try snapshot(in: root)
        for entries in [
            [ArchiveEntry(id: 0, path: "same", size: 1, kind: .file), ArchiveEntry(id: 1, path: "same", size: 1, kind: .file)],
            [ArchiveEntry(id: 0, path: "same", size: 1, kind: .file), ArchiveEntry(id: 1, path: "same/child", size: 1, kind: .file)],
            [ArchiveEntry(id: 0, path: "../same", size: 1, kind: .file)],
            [ArchiveEntry(id: 0, path: "/same", size: 1, kind: .file)],
            [ArchiveEntry(id: 0, path: "same", size: 1, kind: .symbolicLink)],
            [ArchiveEntry(id: 0, path: "same", size: 1, kind: .hardLink)],
            [ArchiveEntry(id: 0, path: "same", size: 1, kind: .unsupported)]
        ] {
            let fake = ArchiveSnapshot(url: original.url, entries: entries, stamp: original.stamp, unlocked: nil)
            XCTAssertNil(ArchiveOpenSession.regularEntry(in: fake, path: entries[0].path))
        }
    }
}
