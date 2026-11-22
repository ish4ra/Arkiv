import Foundation
import XCTest
@testable import ArkivCore
#if os(Linux)
import Glibc
#endif
final class SplitCreationTests: XCTestCase {
    func testPolicyBoundaries() throws {
        XCTAssertEqual(try SevenZipSplitOptions(volumeBytes:100_000_000).volumeCount(archiveBytes:200_000_001),3)
        XCTAssertThrowsError(try SevenZipSplitOptions(volumeBytes:31).validate())
        XCTAssertThrowsError(try SevenZipSplitOptions(volumeBytes:100).volumeCount(archiveBytes:100))
        XCTAssertThrowsError(try SevenZipSplitOptions(volumeBytes:32).volumeCount(archiveBytes:32*129))
        XCTAssertThrowsError(try SevenZipSplitOptions(volumeBytes:100_000_000).volumeCount(archiveBytes:(4<<30)+1))
    }
    func testCreatedPartsEncryptionSolidAndRoundTrip() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);defer {try? fm.removeItem(at:root)}
        let tree=root.appendingPathComponent("資料 🐘"), empty=tree.appendingPathComponent("empty")
        try fm.createDirectory(at:empty,withIntermediateDirectories:true)
        let bytes=Data((0..<8192).map { UInt8(truncatingIfNeeded:$0) })
        try bytes.write(to:tree.appendingPathComponent("file.bin"));try Data().write(to:tree.appendingPathComponent("zero"))
        for mode in 0..<3 {
            let password=mode == 0 ? nil : "fixture password"
            let first=try ArchiveCreator().create(.init(sources:[tree],destination:root,name:"parts\(mode)",format:.sevenZip,password:password,encryptFilenames:mode==2,sevenZipOptions:.init(solid:mode==2 ? .on(blockBytes:nil):.off),split:.init(volumeBytes:128)),cancellation:.init(),progress:{_ in})
            XCTAssertEqual(first.lastPathComponent,"parts\(mode).7z.001")
            let engine=LibArchiveEngine(), later=first.deletingLastPathComponent().appendingPathComponent("parts\(mode).7z.002")
            let snapshot=try engine.inspect(later,cancellation:.init(),password:password)
            XCTAssertEqual(snapshot.metadata?.multipart,true)
            XCTAssertEqual(try engine.test(first,cancellation:.init(),password:password).state,.ok)
            if password != nil {XCTAssertThrowsError(try engine.inspect(first,cancellation:.init(),password:"wrong"))}
            let out=try engine.extract(snapshot,ids:nil,into:root,cancellation:.init(),progress:{_ in})
            XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent("資料 🐘/file.bin")),bytes)
            XCTAssertTrue(fm.fileExists(atPath:out.appendingPathComponent("資料 🐘/empty").path))
            XCTAssertFalse(ArchiveAdditionUpdater().capability(for:snapshot).isAvailable)
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:root.path).contains {$0.hasPrefix(".arkiv-")})
    }
    func testPublicationFailureCancellationMutationAndNoOverwrite() throws {
        let fm=FileManager.default
        for mode in ["collision","cancel","source","destination","lateCollision","extra","replaceFirst","changeFirst"] {
            let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let dest=root.appendingPathComponent("output"), moved=root.appendingPathComponent("moved")
            try fm.createDirectory(at:dest,withIntermediateDirectories:true);defer {try? fm.removeItem(at:root)}
            let source=root.appendingPathComponent("input"), first=dest.appendingPathComponent("result.7z.001"), second=dest.appendingPathComponent("result.7z.002")
            try Data((0..<4096).map{UInt8(truncatingIfNeeded:$0)}).write(to:source)
            if mode == "collision" {try Data("existing".utf8).write(to:second)}
            let token=ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources:[source],destination:dest,name:"result",format:.sevenZip,split:.init(volumeBytes:128)),cancellation:token,progress:{_ in
                // Trigger only after an actual exclusive final publication.
                guard FileManager.default.fileExists(atPath:first.path) else {return}
                if mode == "extra" {try? Data("foreign".utf8).write(to:dest.appendingPathComponent("result.7z.999"))}
                if mode == "replaceFirst" {try? FileManager.default.removeItem(at:first);try? Data("foreign".utf8).write(to:first)}
                if mode == "changeFirst" {if let h=try? FileHandle(forWritingTo:first){try? h.write(contentsOf:Data([0]));try? h.close()}}
                if mode == "cancel" {token.cancel()}
                if mode == "source" {try? Data("changed".utf8).write(to:source)}
                if mode == "lateCollision" {try? Data("foreign".utf8).write(to:second)}
                if mode == "destination", !FileManager.default.fileExists(atPath:moved.path) {
                    try? FileManager.default.moveItem(at:dest,to:moved)
                    try? FileManager.default.createDirectory(at:dest,withIntermediateDirectories:false)
                    try? Data("foreign".utf8).write(to:first)
                }
            }),mode)
            if mode == "destination" {
                XCTAssertEqual(try Data(contentsOf:first),Data("foreign".utf8))
                XCTAssertFalse(fm.fileExists(atPath:moved.appendingPathComponent(first.lastPathComponent).path))
                XCTAssertTrue(try fm.contentsOfDirectory(atPath:moved.path).isEmpty)
            } else if mode == "replaceFirst" {XCTAssertEqual(try Data(contentsOf:first),Data("foreign".utf8))}
            else {XCTAssertFalse(fm.fileExists(atPath:first.path),mode)}
            if mode == "collision" || mode == "lateCollision" {XCTAssertEqual(try Data(contentsOf:second),Data((mode == "collision" ? "existing":"foreign").utf8))}
            XCTAssertFalse(try fm.contentsOfDirectory(atPath:dest.path).contains{$0.hasPrefix(".arkiv-")})
        }
    }
    func testTwoPartsAndInvalidCreationAreNonDestructive() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
        let source=root.appendingPathComponent("file");try Data((0..<8192).map{UInt8(truncatingIfNeeded:$0)}).write(to:source)
        let plain=try ArchiveCreator().create(.init(sources:[source],destination:root,name:"plain",format:.sevenZip),cancellation:.init(),progress:{_ in})
        let original=try Data(contentsOf:plain), size=UInt64((original.count+1)/2)
        let first=try ArchiveCreator().create(.init(sources:[source],destination:root,name:"two",format:.sevenZip,split:.init(volumeBytes:size)),cancellation:.init(),progress:{_ in})
        let files=try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("two.7z.")}.sorted{$0.path<$1.path}
        XCTAssertEqual(files.count,2)
        let joined=try files.reduce(Data()){$0 + (try Data(contentsOf:$1))}
        XCTAssertEqual(joined,original)
        try fm.removeItem(at:files[1]);XCTAssertNotEqual(try LibArchiveEngine().test(first,cancellation:.init()).state,.ok)
        for format in [ArchiveFormat.zip,.sevenZip] {
            XCTAssertThrowsError(try ArchiveCreator().create(.init(sources:[source],destination:root,name:"invalid",format:format,split:.init(volumeBytes:100_000_000)),cancellation:.init(),progress:{_ in}))
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix("invalid")||$0.hasPrefix(".arkiv-")})
    }

}
