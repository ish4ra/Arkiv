import Foundation
import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore
final class RARCompatibilityTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/rar") }
    func testReadOnlyMetadataSelectiveOpenDragAndFullIntegrity() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let engine=LibArchiveEngine()
        for name in ["rar4-stored","rar4-normal","rar4-best","rar4-unicode","rar5-compressed","rar5-multiple","rar5-unicode"] {
            let url=fixtures.appendingPathComponent(name+".rar")
            let snapshot=try engine.inspect(url,cancellation:.init())
            XCTAssertTrue(snapshot.metadata?.format?.uppercased().hasPrefix("RAR") == true)
            XCTAssertEqual(snapshot.metadata?.multipart,false);XCTAssertEqual(snapshot.metadata?.dataEncrypted,false)
            XCTAssertFalse(ArchiveZIPUpdater().canAdd(to:snapshot));XCTAssertFalse(ArchiveAdditionUpdater().capability(for:snapshot).isAvailable)
            let entry=try XCTUnwrap(snapshot.entries.first { $0.kind == .file && $0.size>0 })
            XCTAssertNotNil(entry.metadata.packedSize);XCTAssertNotNil(entry.metadata.compressionMethod)
            XCTAssertNotNil(entry.metadata.crc32);XCTAssertNotNil(entry.metadata.modificationTime)
            XCTAssertNotNil(entry.metadata.posixMode ?? entry.metadata.storedAttributes)
            if ["rar5-compressed","rar5-multiple"].contains(name) {
                XCTAssertEqual(entry.metadata.compressionMethod,"RAR5 m5")
            }
            let all=try engine.extract(snapshot,ids:nil,into:root,cancellation:.init(),progress:{_ in})
            let expected=try Data(contentsOf:all.appendingPathComponent(entry.path))
            let selected=try engine.extract(snapshot,ids:[entry.id],into:root,cancellation:.init(),progress:{_ in})
            XCTAssertEqual(try Data(contentsOf:selected.appendingPathComponent(entry.path)),expected)
            let session=ArchiveOpenSession()
            let opened=try session.prepare(snapshot,path:entry.path,cancellation:.init())
            try session.validateForLaunch(opened,cancellation:.init())
            XCTAssertEqual(try Data(contentsOf:opened.url),expected)
            let drag=try ArchiveDragSession(snapshot:snapshot,paths:[entry.path]);let output=root.appendingPathComponent(UUID().uuidString)
            try drag.write(item:drag.items[0],to:output);XCTAssertEqual(try Data(contentsOf:output),expected)
            session.close();XCTAssertFalse(FileManager.default.fileExists(atPath:opened.url.path))
            XCTAssertEqual(try engine.test(url,cancellation:.init()).state,.ok)
        }
    }
    func testPolicyFailuresCancellationStaleSourceAndCleanup() throws {
        let engine=LibArchiveEngine()
        for name in ["rar4-encrypted-data","rar4-encrypted-header","rar5-solid","rar4-volume","rar5-volume"] {
            let url=fixtures.appendingPathComponent(name+".rar")
            XCTAssertThrowsError(try engine.inspect(url,cancellation:.init()))
            XCTAssertEqual(try engine.test(url,cancellation:.init()).state,name.contains("volume") ? .missingVolume : .unsupportedMethod)
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("input.rar"),data=try Data(contentsOf:fixtures.appendingPathComponent("rar4-stored.rar"))
        try data.write(to:url);let snapshot=try engine.inspect(url,cancellation:.init())
        let cancelled=ArchiveCancellation();cancelled.cancel()
        XCTAssertThrowsError(try engine.extract(snapshot,ids:nil,into:root,cancellation:cancelled,progress:{_ in}))
        var corrupt=data;let range=try XCTUnwrap(corrupt.range(of:Data("test text document".utf8)));corrupt[range.lowerBound] ^= 1
        try corrupt.write(to:url)
        XCTAssertThrowsError(try engine.extract(snapshot,ids:nil,into:root,cancellation:.init(),progress:{_ in}))
        let fresh=try engine.inspect(url,cancellation:.init())
        XCTAssertThrowsError(try engine.extract(fresh,ids:nil,into:root,cancellation:.init(),progress:{_ in}))
        XCTAssertEqual(try engine.test(url,cancellation:.init()).state,.crcError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["input.rar"])
    }
}
