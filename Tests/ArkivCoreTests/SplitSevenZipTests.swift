import Foundation
import XCTest
@testable import ArkivCore
#if os(Linux)
import Glibc
#endif
final class SplitSevenZipTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
    }
    var fixtures: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/split-sevenzip") }
    func testIndependentStoredAndLZMA2FirstAndLaterVolume() throws {
        for name in ["store", "lzma2"] {
            for number in ["001", "002"] {
                let snapshot = try LibArchiveEngine().inspect(fixtures.appendingPathComponent(name + ".7z." + number), cancellation:.init())
                XCTAssertEqual(snapshot.metadata?.multipart,true)
                XCTAssertTrue(snapshot.entries.contains { $0.path.contains("資料") })
                XCTAssertFalse(ArchiveAdditionUpdater().capability(for:snapshot).isAvailable)
            }
        }
    }

    private func copySet(_ name: String = "lzma2") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for file in try FileManager.default.contentsOfDirectory(at:fixtures,includingPropertiesForKeys:nil) where file.lastPathComponent.hasPrefix(name + ".7z.") {
            try FileManager.default.copyItem(at:file,to:root.appendingPathComponent(file.lastPathComponent))
        }
        return root
    }
    func testAllWorkflowsEncryptionAndOwnedLifetime() throws {
        let engine = LibArchiveEngine(), expected = Data((0..<8).flatMap { _ in (0...255).map(UInt8.init) })
        for name in ["store","lzma2","encrypted","data-encrypted"] {
            let root = try copySet(name); defer { try? FileManager.default.removeItem(at:root) }
            let url = root.appendingPathComponent(name + ".7z.002")
            let password = name.contains("encrypted") ? "fixture password" : nil
            if password != nil {
                XCTAssertThrowsError(try engine.inspect(url,cancellation:.init())) { guard case ArchiveFailure.passwordRequired = $0 else { return XCTFail("password expected") } }
                XCTAssertThrowsError(try engine.inspect(url,cancellation:.init(),password:"wrong"))
            }
            var snapshot: ArchiveSnapshot? = try engine.inspect(url,cancellation:.init(),password:password)
            let backing = try XCTUnwrap(snapshot?.splitSeven?.spool.url)
            XCTAssertEqual(snapshot?.metadata?.headersEncrypted,name == "encrypted")
            XCTAssertFalse(ArchiveAdditionUpdater().canAddEncrypted(try XCTUnwrap(snapshot)))
            XCTAssertNil(snapshot?.sevenEncryptionPolicy)
            XCTAssertEqual(try engine.test(url,cancellation:.init(),password:password).state,.ok)
            let file = try XCTUnwrap(snapshot?.entries.first { $0.path.contains("資料") })
            let out = try engine.extract(try XCTUnwrap(snapshot),ids:nil,into:root,cancellation:.init(),progress:{_ in})
            XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent(file.path)),expected)
            XCTAssertTrue(FileManager.default.fileExists(atPath:out.appendingPathComponent("tree/empty").path))
            let session = ArchiveOpenSession()
            var opened: ArchiveOpenedFile? = try session.prepare(try XCTUnwrap(snapshot),path:file.path,cancellation:.init())
            try session.validateForLaunch(try XCTUnwrap(opened),cancellation:.init())
            XCTAssertEqual(try Data(contentsOf:XCTUnwrap(opened).url),expected)
            var drag: ArchiveDragSession? = try ArchiveDragSession(snapshot:try XCTUnwrap(snapshot),paths:[file.path])
            let item = try XCTUnwrap(drag?.items.first); let target = root.appendingPathComponent("delivered.txt")
            try drag?.write(item:item,to:target); XCTAssertEqual(try Data(contentsOf:target),expected)
            snapshot=nil; drag=nil; session.close(); opened=nil
            XCTAssertFalse(FileManager.default.fileExists(atPath:backing.path))
        }
    }
    func testMissingCorruptAndUnsupportedInput() throws {
        let engine = LibArchiveEngine()
        for missing in ["001","002","004"] {
            let root = try copySet(); defer { try? FileManager.default.removeItem(at:root) }
            try FileManager.default.removeItem(at:root.appendingPathComponent("lzma2.7z."+missing))
            let url=root.appendingPathComponent("lzma2.7z.003")
            XCTAssertThrowsError(try engine.inspect(url,cancellation:.init()))
            let result=try engine.test(url,cancellation:.init())
            XCTAssertEqual(result.state,missing == "004" ? .corrupt : .missingVolume)
            if missing != "004" { XCTAssertTrue(result.detail.contains("lzma2.7z."+missing)) }
        }
        for action in ["corrupt","truncate","alias","symlink","hardlink"] {
            let root=try copySet();defer {try? FileManager.default.removeItem(at:root)}
            let part=root.appendingPathComponent("lzma2.7z.002"),original=try Data(contentsOf:part)
            switch action {
            case "corrupt": var data=original;data[10] ^= 0xff;try data.write(to:part)
            case "truncate": try original.dropLast().write(to:part)
            case "alias": try original.write(to:root.appendingPathComponent("lzma2.7z.02"))
            case "symlink": try FileManager.default.removeItem(at:part);try FileManager.default.createSymbolicLink(at:part,withDestinationURL:fixtures.appendingPathComponent("lzma2.7z.002"))
            default: try FileManager.default.linkItem(at:part,to:root.appendingPathComponent("alias"))
            }
            XCTAssertThrowsError(try engine.inspect(root.appendingPathComponent("lzma2.7z.001"),cancellation:.init()),action)
        }
    }
    func testStaleVolumesRejectExtractionOpenAndDrag() throws {
        let root=try copySet();defer {try? FileManager.default.removeItem(at:root)}
        let engine=LibArchiveEngine(),url=root.appendingPathComponent("lzma2.7z.001")
        let s=try engine.inspect(url,cancellation:.init()),file=try XCTUnwrap(s.entries.first { $0.kind == .file && $0.size>0 })
        let session=ArchiveOpenSession();defer {session.close()}
        let opened=try session.prepare(s,path:file.path,cancellation:.init())
        let drag=try ArchiveDragSession(snapshot:s,paths:[file.path])
        let part=root.appendingPathComponent("lzma2.7z.003");var data=try Data(contentsOf:part);data[0] ^= 1;try data.write(to:part)
        XCTAssertThrowsError(try engine.extract(s,ids:[file.id],into:root,cancellation:.init(),progress:{_ in}))
        XCTAssertThrowsError(try session.validateForLaunch(opened,cancellation:.init()))
        XCTAssertThrowsError(try drag.write(item:drag.items[0],to:root.appendingPathComponent("out")))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("out").path))
        let token=ArchiveCancellation();token.cancel()
        XCTAssertThrowsError(try engine.inspect(url,cancellation:token))
    }

    func testNestedArchiveChildSurvivesParentSessionClose() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let input=root.appendingPathComponent("inside.txt");try Data("nested payload".utf8).write(to:input)
        let inner=try ArchiveCreator().create(.init(sources:[input],destination:root,name:"inner"),cancellation:.init(),progress:{_ in})
        let outer=try ArchiveCreator().create(.init(sources:[inner],destination:root,name:"outer",format:.sevenZip),cancellation:.init(),progress:{_ in})
        let bytes=try Data(contentsOf:outer),partSize=(bytes.count+1)/2
        for i in 0..<2 {try bytes.subdata(in:(i*partSize)..<min((i+1)*partSize,bytes.count)).write(to:root.appendingPathComponent(String(format:"outer.7z.%03d",i+1)))}
        var parent: ArchiveSnapshot?=try LibArchiveEngine().inspect(root.appendingPathComponent("outer.7z.001"),cancellation:.init())
        let session=ArchiveOpenSession()
        var opened: ArchiveOpenedFile?=try session.prepare(try XCTUnwrap(parent),path:inner.lastPathComponent,cancellation:.init())
        var child: ArchiveOpenedFileLease?=try session.retainForArchive(try XCTUnwrap(opened),cancellation:.init())
        let childURL=try XCTUnwrap(child?.url)
        parent=nil;opened=nil;session.close()
        XCTAssertTrue(try XCTUnwrap(child).inspect(cancellation:.init()).entries.contains { $0.path == "inside.txt" })
        child=nil;XCTAssertFalse(FileManager.default.fileExists(atPath:childURL.path))
    }
}
