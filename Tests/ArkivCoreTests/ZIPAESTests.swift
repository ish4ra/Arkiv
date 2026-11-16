import Foundation
import XCTest
@testable import ArkivCore
#if os(Linux)
import Glibc
#endif
final class ZIPAESTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
    }
    private var fixtures: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/zip-aes") }
    func testEncryptedDirectoryNeverCreatesUsableSnapshotOrIntegritySuccess() throws {
        let engine = LibArchiveEngine(), url = fixtures.appendingPathComponent("encrypted-directory.zip")
        for password: String? in [nil, "wrong", "fixture password"] {
            XCTAssertThrowsError(try engine.inspect(url,cancellation:.init(),password:password)) { error in
                if case ArchiveFailure.passwordRequired = error { XCTFail("Reject unsupported directories before asking for a password") }
            }
            XCTAssertEqual(try engine.test(url,cancellation:.init(),password:password).state,.unsupportedMethod)
        }
    }
    func testPasswordAuthenticatedReadMetadataSelectiveOpenDragAndEditDenial() throws {
        let engine=LibArchiveEngine(),url=fixtures.appendingPathComponent("pyzipper-ae2-256-8.zip")
        XCTAssertThrowsError(try engine.inspect(url,cancellation:.init())) { guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("Expected password request") } }
        XCTAssertThrowsError(try engine.inspect(url,cancellation:.init(),password:"wrong")) { guard case ArchiveFailure.wrongPassword = $0 else { return XCTFail("Expected password retry") } }
        var snapshot: ArchiveSnapshot?=try engine.inspect(url,cancellation:.init(),password:"fixture password")
        let s=try XCTUnwrap(snapshot),entry=try XCTUnwrap(s.entries.first { $0.path.hasSuffix(".txt") && $0.size>100 })
        XCTAssertEqual(s.metadata?.format,"ZIP (WinZip AES)");XCTAssertEqual(s.metadata?.dataEncrypted,true);XCTAssertEqual(s.metadata?.headersEncrypted,false)
        XCTAssertEqual(entry.metadata.encrypted,true);XCTAssertEqual(entry.metadata.compressionMethod,"Deflate");XCTAssertNil(entry.metadata.crc32)
        XCTAssertFalse(ArchiveZIPUpdater().canAdd(to:s));XCTAssertFalse(ArchiveAdditionUpdater().capability(for:s).isAvailable)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let expected=Data(String(repeating:"authenticated content\n",count:2000).utf8)
        let out=try engine.extract(s,ids:[entry.id],into:root,cancellation:.init(),progress:{_ in})
        XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent(entry.path)),expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.appendingPathComponent("plain.txt").path))
        let session=ArchiveOpenSession();let opened=try session.prepare(s,path:entry.path,cancellation:.init())
        try session.validateForLaunch(opened,cancellation:.init());XCTAssertEqual(try Data(contentsOf:opened.url),expected)
        let drag=try ArchiveDragSession(snapshot:s,paths:[entry.path]);let delivered=root.appendingPathComponent("promise.txt")
        try drag.write(item:drag.items[0],to:delivered);XCTAssertEqual(try Data(contentsOf:delivered),expected)
        session.close();snapshot=nil
        XCTAssertEqual(try engine.test(url,cancellation:.init(),password:"fixture password").state,.ok)
    }
    func testCreationPresetsRoundTripAndNoOverwrite() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("資料 🐘.txt"),expected=Data(String(repeating:"encryption",count:1000).utf8)
        try expected.write(to:source)
        for preset in CompressionPreset.available(for:.zip) {
            let url=try ArchiveCreator().create(.init(sources:[source],destination:root,name:"secure",password:"fixture password",preset:preset),cancellation:.init(),progress:{_ in})
            let s=try LibArchiveEngine().inspect(url,cancellation:.init(),password:"fixture password")
            XCTAssertEqual(s.entries[0].metadata.encrypted,true)
            let out=try LibArchiveEngine().extract(s,ids:nil,into:root,cancellation:.init(),progress:{_ in})
            XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent(source.lastPathComponent)),expected)
        }
    }
    func testAuthenticatedSpoolLifetimeCancellationAndStaleSource() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("input.zip");try Data(contentsOf:fixtures.appendingPathComponent("pyzipper-ae1-256-0.zip")).write(to:url)
        let engine=LibArchiveEngine();var snapshot: ArchiveSnapshot?=try engine.inspect(url,cancellation:.init(),password:"fixture password")
        let backing=try XCTUnwrap(snapshot?.backingURL);XCTAssertNotEqual(backing,url)
        XCTAssertTrue(FileManager.default.fileExists(atPath:backing.path));snapshot=nil
        XCTAssertFalse(FileManager.default.fileExists(atPath:backing.path))
        let token=ArchiveCancellation();token.cancel()
        XCTAssertThrowsError(try engine.inspect(url,cancellation:token,password:"fixture password"))
        snapshot=try engine.inspect(url,cancellation:.init(),password:"fixture password")
        try Data("changed".utf8).write(to:url)
        XCTAssertThrowsError(try engine.extract(try XCTUnwrap(snapshot),ids:nil,into:root,cancellation:.init(),progress:{_ in}))
    }
}
