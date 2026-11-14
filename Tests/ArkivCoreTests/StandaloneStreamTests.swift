import Foundation
import XCTest
@testable import ArkivCore

final class StandaloneStreamTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures") }
    private let bytes = Data(String(repeating: "database content é 🐘\n", count: 10000).utf8)
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testIndependentStreamsMetadataExtractionOpenQuickLookAndDrag() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = LibArchiveEngine()
        for (ext, codec) in [("gz", "GZIP"), ("bz2", "BZIP2"), ("xz", "XZ")] {
            for name in ["資料 é 🐘.sql." + ext, "misleading.zip", "opaque.tar." + ext] {
                let archive = root.appendingPathComponent(name)
                try Data(contentsOf: fixtures.appendingPathComponent("standalone.sql." + ext)).write(to: archive)
                let expected = name == "misleading.zip" ? "misleading.zip.decompressed" : String(name.dropLast(ext.count + 1))
                let snapshot = try engine.inspect(archive, cancellation: .init())
                XCTAssertNotNil(snapshot.standalone)
                XCTAssertNil(snapshot.compressedTAR)
                XCTAssertEqual(snapshot.entries.count, 1)
                let entry = try XCTUnwrap(snapshot.entries.first)
                XCTAssertEqual(entry.path, expected); XCTAssertEqual(entry.kind, .file)
                XCTAssertEqual(entry.size, Int64(bytes.count))
                XCTAssertNil(entry.metadata.posixMode); XCTAssertNil(entry.metadata.modificationTime)
                XCTAssertNil(entry.metadata.crc32); XCTAssertNil(entry.metadata.packedSize)
                XCTAssertEqual(entry.metadata.compressionMethod, codec)
                XCTAssertEqual(snapshot.metadata?.format, codec)
                XCTAssertEqual(snapshot.metadata?.fileCount, 1); XCTAssertEqual(snapshot.metadata?.folderCount, 0)
                XCTAssertEqual(snapshot.metadata?.unpackedSize, UInt64(bytes.count))
                XCTAssertFalse(ArchiveZIPUpdater().canAdd(to: snapshot))
                XCTAssertFalse(ArchiveAdditionUpdater().capability(for: snapshot).isAvailable)
                XCTAssertEqual(snapshot.index.children(of: "").count, 1)
                for ids: [Int64]? in [nil, [0]] {
                    let folder = try engine.extract(snapshot, ids: ids, into: root, cancellation: .init(), progress: { _ in })
                    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(expected)), bytes)
                    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [expected])
                }
                let session = ArchiveOpenSession()
                let opened = try session.prepare(snapshot, path: expected, cancellation: .init())
                XCTAssertEqual(opened.url.lastPathComponent, expected)
                XCTAssertEqual(try Data(contentsOf: opened.url), bytes)
                try session.validateForLaunch(opened, cancellation: .init()) // also the Quick Look materialization/validation path
                session.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: opened.url.path))
                let drag = try ArchiveDragSession(snapshot: snapshot, paths: [expected])
                let destination = root.appendingPathComponent(UUID().uuidString)
                _ = try drag.write(item: drag.items[0], to: destination)
                XCTAssertEqual(try Data(contentsOf: destination), bytes)
                XCTAssertEqual(try engine.test(archive, cancellation: .init()).state, .ok)
            }
            let empty = try engine.inspect(fixtures.appendingPathComponent("standalone-empty." + ext), cancellation: .init())
            XCTAssertEqual(empty.entries.map(\.size), [0]); XCTAssertNil(empty.metadata?.sizeRatio)
            let tar = try engine.inspect(fixtures.appendingPathComponent("compressed.tar." + ext), cancellation: .init())
            XCTAssertNil(tar.standalone); XCTAssertNotNil(tar.compressedTAR)
            XCTAssertThrowsError(try engine.inspect(fixtures.appendingPathComponent("invalid-inner.tar." + ext), cancellation: .init()))
        }
    }
    func testNamesStaleSourcesCancellationAndOwnedCleanup() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = LibArchiveEngine()
        let packed = try Data(contentsOf: fixtures.appendingPathComponent("standalone-untrusted-name.gz"))
        let source = root.appendingPathComponent("safe.sql.gz")
        try packed.write(to: source)
        var snapshot: ArchiveSnapshot? = try engine.inspect(source, cancellation: .init())
        XCTAssertEqual(snapshot?.entries.first?.path, "safe.sql") // ignore unauthenticated embedded ../outside.txt
        let spool = try XCTUnwrap(snapshot?.standalone?.spool.url)
        let token = ArchiveCancellation(); token.cancel()
        XCTAssertThrowsError(try engine.extract(snapshot!, ids: nil, into: root, cancellation: token, progress: { _ in }))
        XCTAssertThrowsError(try engine.extract(snapshot!, ids: [1], into: root, cancellation: .init(), progress: { _ in }))
        try Data(packed.dropLast(5)).write(to: source)
        XCTAssertThrowsError(try engine.extract(snapshot!, ids: nil, into: root, cancellation: .init(), progress: { _ in }))
        XCTAssertEqual(try engine.test(source, cancellation: .init()).state, .corrupt)
        snapshot = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: spool.path))
        for name in [".gz", "..gz", "...gz", "unsafe:name.gz", "unsafe\\name.gz", "bad\nname.gz"] {
            XCTAssertThrowsError(try StandaloneStream.outputName(for: root.appendingPathComponent(name)))
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testCreationAllCodecsAndInputRestrictions() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("é 🐘.sql")
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let engine = LibArchiveEngine()
        for format: ArchiveFormat in [.gzip, .bzip2, .xz] {
            for data in [Data(), Data("hello".utf8), bytes] {
                try data.write(to: source)
                let url = try ArchiveCreator().create(.init(sources: [source], destination: root, name: "é 🐘.sql", format: format), cancellation: .init(), progress: { _ in })
                let snapshot = try engine.inspect(url, cancellation: .init())
                XCTAssertEqual(snapshot.entries.count, 1)
                let out = try engine.extract(snapshot, ids: nil, into: root, cancellation: .init(), progress: { _ in })
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent(snapshot.entries[0].path)), data)
                XCTAssertEqual(try engine.test(url, cancellation: .init()).state, .ok)
            }
            for sources in [[folder], [source, source]] {
                XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: sources, destination: root, name: "invalid", format: format), cancellation: .init(), progress: { _ in }))
            }
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "invalid", format: format, password: "secret"), cancellation: .init(), progress: { _ in }))
            XCTAssertThrowsError(try CompressionPreset.maximum.backend(for: format))
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "invalid", format: format, sevenZipOptions: .init()), cancellation: .init(), progress: { _ in }))
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources: [source], destination: root, name: "cancel", format: format), cancellation: token, progress: { _ in token.cancel() }))
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-create-") })
    }
}
