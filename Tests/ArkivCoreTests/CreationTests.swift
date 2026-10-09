import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class CreationTests: XCTestCase {
    func testRoundTripStoreAndDeflateWithCollision() throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let sources = root.appendingPathComponent("sources")
        let output = root.appendingPathComponent("output")
        let folder = sources.appendingPathComponent("資料 🐈")
        try manager.createDirectory(at: folder.appendingPathComponent("empty/nested"), withIntermediateDirectories: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: false)
        let data = Data((0..<100_000).map { UInt8($0 % 251) })
        try data.write(to: folder.appendingPathComponent("hello world.txt"))
        let lone = sources.appendingPathComponent("solo.txt")
        try Data("solo".utf8).write(to: lone)
        for compression in [ZIPCompression.store, .deflate] {
            let archive = try ArchiveCreator().create(.init(sources: [folder, lone], destination: output, name: "Result", compression: compression), cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(archive.lastPathComponent, compression == .store ? "Result.zip" : "Result (2).zip")
            let engine = LibArchiveEngine()
            let snapshot = try engine.inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertEqual(snapshot.entries.count, 5)
            let extracted = try engine.extract(snapshot, ids: nil, into: output, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("資料 🐈/hello world.txt")), data)
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("solo.txt")), Data("solo".utf8))
            var directory: ObjCBool = false
            XCTAssertTrue(manager.fileExists(atPath: extracted.appendingPathComponent("資料 🐈/empty/nested").path, isDirectory: &directory))
            XCTAssertTrue(directory.boolValue)
        }
        XCTAssertFalse(try manager.contentsOfDirectory(atPath: output.path).contains { $0.hasPrefix(".arkiv-create-") })
    }
    func testRejectedSourcesAndCancellationLeaveNoOutput() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        let output = root.appendingPathComponent("output")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        try manager.createDirectory(at: output, withIntermediateDirectories: false)
        let file = folder.appendingPathComponent("file")
        try Data("content".utf8).write(to: file)
        let creator = ArchiveCreator()
        func create(_ sources: [URL], destination: URL? = nil, token: ArchiveCancellation = ArchiveCancellation()) throws {
            _ = try creator.create(.init(sources: sources, destination: destination ?? output, name: "Test"), cancellation: token, progress: { _ in })
        }
        XCTAssertThrowsError(try create([folder, file]))
        XCTAssertThrowsError(try create([file, file]))
        XCTAssertThrowsError(try create([folder], destination: folder))
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try create([file], token: token))
        try manager.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: file)
        XCTAssertThrowsError(try create([folder]))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: output.path), [])
    }
    func testCancellationDuringDataWrite() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("large")
        try Data(repeating: 1, count: 1_000_000).write(to: file)
        let token = ArchiveCancellation()
        XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [file], destination: root, name: "Cancelled"), cancellation: token, progress: { _ in token.cancel() }))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: root.path), ["large"])
    }
}
