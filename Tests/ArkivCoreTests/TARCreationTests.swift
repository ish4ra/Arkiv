import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class TARCreationTests: XCTestCase {
    func testAllFormatsRoundTripMetadataAndSharedWorkflows() throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("資料 🐈")
        try fm.createDirectory(at: folder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
        let filename = String(repeating: "a", count: 110) + " é.txt"
        let path = "資料 🐈/nested/" + filename
        let file = folder.appendingPathComponent("nested/" + filename)
        let data = Data((0..<150_000).map { UInt8($0 % 251) })
        try data.write(to: file)
        try Data().write(to: folder.appendingPathComponent("zero"))
        try fm.setAttributes([.posixPermissions: 0o751, .modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: file.path)
        let engine = LibArchiveEngine()
        for format in ArchiveFormat.allCases where format.tarCodec != nil {
            let request = ArchiveCreationRequest(sources: [folder], destination: root, name: "Result", format: format)
            let url = try ArchiveCreator().create(request, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(url.lastPathComponent, "Result" + format.fileExtension)
            let snapshot = try engine.inspect(url, cancellation: ArchiveCancellation())
            let entry = try XCTUnwrap(snapshot.entries.first { $0.path == path })
            XCTAssertEqual(entry.metadata.posixMode.map { $0 & 0o777 }, 0o751)
            XCTAssertNil(entry.metadata.crc32)
            let extracted = try engine.extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent(path)), data)
            XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("資料 🐈/nested/empty").path))
            let session = ArchiveOpenSession()
            let opened = try session.prepare(snapshot, path: path, cancellation: ArchiveCancellation(), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: opened.url), data)
            XCTAssertEqual(try engine.test(url, cancellation: ArchiveCancellation()).state, .warning)
            let drag = try ArchiveDragSession(snapshot: snapshot, paths: [path])
            let promised = root.appendingPathComponent(UUID().uuidString + ".txt")
            try drag.write(item: drag.items[0], to: promised)
            XCTAssertEqual(try Data(contentsOf: promised), data)
            XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-create-") })
        }
    }
    func testTARCreationRejectsUnsupportedOptionsAndCancels() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("source")
        try Data(repeating: 42, count: 1_000_000).write(to: file)
        for format in ArchiveFormat.allCases where format.tarCodec != nil {
            XCTAssertEqual(CompressionPreset.available(for: format), [.normal])
            for preset in CompressionPreset.allCases where preset != .normal {
                XCTAssertThrowsError(try preset.backend(for: format))
            }
            for request in [
                ArchiveCreationRequest(sources: [file], destination: root, name: "bad", format: format, password: "secret"),
                ArchiveCreationRequest(sources: [file], destination: root, name: "bad", format: format, sevenZipOptions: .init())
            ] {
                XCTAssertThrowsError(try ArchiveCreator().create(request, cancellation: ArchiveCancellation(), progress: { _ in }))
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [file], destination: root, name: "cancel", format: format), cancellation: token, progress: { _ in token.cancel() })) {
                guard case ArchiveFailure.cancelled = $0 else { return XCTFail("Expected cancellation: \($0)") }
            }
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), ["source"])
        }
    }
}
