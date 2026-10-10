import XCTest
@testable import ArkivCore

final class SevenZipTests: XCTestCase {
    #if os(macOS)
    func testAESPasswordRetryThroughTrustedSystemAliases() throws {
        let fm = FileManager.default
        let engine = LibArchiveEngine()
        for alias in ["/var/tmp", "/tmp"] {
            let root = URL(fileURLWithPath: alias).appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: root) }
            let source = root.appendingPathComponent("hello.txt")
            let bytes = Data("trusted alias".utf8)
            try bytes.write(to: source)
            let archive = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Protected", format: .sevenZip, password: "secret", encryptFilenames: true), cancellation: ArchiveCancellation(), progress: { _ in })
            let renamed = root.appendingPathComponent("renamed.bin")
            try fm.moveItem(at: archive, to: renamed)
            XCTAssertTrue(renamed.path.hasPrefix(alias + "/"))
            XCTAssertThrowsError(try engine.inspect(renamed, cancellation: ArchiveCancellation())) { error in
                guard case ArchiveFailure.passwordRequired = error else { return XCTFail("Unexpected \(error)") }
            }
            XCTAssertThrowsError(try engine.inspect(renamed, cancellation: ArchiveCancellation(), password: "incorrect")) { error in
                guard case ArchiveFailure.wrongPassword = error else { return XCTFail("Unexpected \(error)") }
            }
            let snapshot = try engine.inspect(renamed, cancellation: ArchiveCancellation(), password: "secret")
            XCTAssertEqual(snapshot.url, renamed)
            XCTAssertEqual(snapshot.stamp, try SourceStamp(renamed))
            XCTAssertNotNil(snapshot.unlocked)
            let result = try engine.extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("hello.txt")), bytes)
        }
    }
    #endif

    func testPlainAndAESRoundTripsWithPrivateLifetimeAndCollision() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("資料 🐈")
        try fm.createDirectory(at: folder.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let bytes = Data((0..<120_000).map { UInt8($0 % 251) })
        try bytes.write(to: folder.appendingPathComponent("hello.txt"))
        try Data().write(to: folder.appendingPathComponent("zero"))
        let engine = LibArchiveEngine()
        for (index, options) in [(nil as String?, false), ("päss 🔒 ", false), ("päss 🔒 ", true)].enumerated() {
            let archive = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "Result", format: .sevenZip, password: options.0, encryptFilenames: options.1), cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(archive.lastPathComponent, index == 0 ? "Result.7z" : "Result (\(index + 1)).7z")
            XCTAssertEqual(try Data(contentsOf: archive).prefix(6), Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]))
            if options.0 != nil {
                XCTAssertThrowsError(try engine.inspect(archive, cancellation: ArchiveCancellation())) { error in
                    guard case ArchiveFailure.passwordRequired = error else { return XCTFail("Unexpected \(error)") }
                }
                XCTAssertThrowsError(try engine.inspect(archive, cancellation: ArchiveCancellation(), password: "incorrect")) { error in
                    guard case ArchiveFailure.wrongPassword = error else { return XCTFail("Unexpected \(error)") }
                }
            }
            XCTAssertEqual(try engine.test(archive, cancellation: ArchiveCancellation(), password: options.0).state, .ok)
            if options.0 != nil {
                XCTAssertThrowsError(try engine.test(archive, cancellation: ArchiveCancellation())) { error in
                    guard case ArchiveFailure.passwordRequired = error else { return XCTFail("Unexpected \(error)") }
                }
                XCTAssertThrowsError(try engine.test(archive, cancellation: ArchiveCancellation(), password: "incorrect")) { error in
                    guard case ArchiveFailure.wrongPassword = error else { return XCTFail("Unexpected \(error)") }
                }
            }
            var snapshot: ArchiveSnapshot? = try engine.inspect(archive, cancellation: ArchiveCancellation(), password: options.0)
            XCTAssertEqual(snapshot?.entries.count, 4)
            let spool = try XCTUnwrap(snapshot?.unlocked?.directory)
            XCTAssertEqual((try fm.attributesOfItem(atPath: spool.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            let result = try engine.extract(snapshot!, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("資料 🐈/hello.txt")), bytes)
            XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("資料 🐈/zero")).count, 0)
            let ids = snapshot!.index.entryIDs(for: ["資料 🐈/hello.txt"])
            let selected = try engine.extract(snapshot!, ids: ids, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: selected.appendingPathComponent("資料 🐈/hello.txt")), bytes)
            XCTAssertFalse(fm.fileExists(atPath: selected.appendingPathComponent("資料 🐈/zero").path))
            snapshot = nil
            XCTAssertFalse(fm.fileExists(atPath: spool.path))
        }
    }
    func testMagicDetectionChangedSourceAndCancellation() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("hello")
        try Data(repeating: 7, count: 1_000_000).write(to: source)
        let archive = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Protected", format: .sevenZip, password: "secret"), cancellation: ArchiveCancellation(), progress: { _ in })
        let renamed = root.appendingPathComponent("renamed.bin")
        try fm.moveItem(at: archive, to: renamed)
        let engine = LibArchiveEngine()
        let snapshot = try engine.inspect(renamed, cancellation: ArchiveCancellation(), password: "secret")
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try engine.inspect(renamed, cancellation: token, password: "secret"))
        XCTAssertThrowsError(try engine.extract(snapshot, ids: nil, into: root, cancellation: token, progress: { _ in }))
        try Data("changed".utf8).write(to: renamed)
        XCTAssertThrowsError(try engine.extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in }))
        let cancel = ArchiveCancellation()
        XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Cancelled", format: .sevenZip, password: "secret"), cancellation: cancel, progress: { _ in cancel.cancel() }))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Cancelled.7z").path))
        XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "ZIP", password: "secret"), cancellation: ArchiveCancellation(), progress: { _ in }))
        for password in ["", "bad\0password", String(repeating: "a", count: 1025)] {
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "Invalid", format: .sevenZip, password: password), cancellation: ArchiveCancellation(), progress: { _ in }))
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-create-") })
    }
}
