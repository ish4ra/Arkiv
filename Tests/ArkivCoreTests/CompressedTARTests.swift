import Foundation
import XCTest
import CArkiv
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore
private final class TARModeEvidence {
    var count = 0
    var mode: Int64 = -1
}
final class CompressedTARTests: XCTestCase {
    func testAllCodecsAliasesAndSharedWorkflows() throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let fixtures=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures")
        let engine=LibArchiveEngine()
        for (codec,aliases) in [("gz",["tar.gz","tgz"]),("bz2",["tar.bz2","tbz2"]),("xz",["tar.xz","txz"])] {
            let empty=try engine.inspect(fixtures.appendingPathComponent("empty.tar."+codec),cancellation:ArchiveCancellation())
            XCTAssertTrue(empty.entries.isEmpty)
            XCTAssertThrowsError(try engine.inspect(fixtures.appendingPathComponent("invalid-inner.tar."+codec),cancellation:ArchiveCancellation()))
            let data=try Data(contentsOf:fixtures.appendingPathComponent("compressed.tar."+codec))
            for ext in aliases + ["mislabelled.zip"] {
                let url=root.appendingPathComponent(UUID().uuidString+"."+ext)
                try data.write(to:url)
                let snapshot=try engine.inspect(url,cancellation:ArchiveCancellation())
                XCTAssertTrue(snapshot.metadata?.format?.contains("TAR") == true)
                let entry=try XCTUnwrap(snapshot.entries.first{$0.path=="folder/é 🐘.txt"})
                XCTAssertNil(entry.metadata.crc32)
                XCTAssertNotNil(entry.metadata.posixMode)
                // Check the C/Swift boundary independently of snapshot mapping.
                let evidence = TARModeEvidence()
                let status = arkiv_entry_metadata(snapshot.backingURL.path, { context, path, _, _, _, _, _, mode, _ in
                    let evidence = Unmanaged<TARModeEvidence>.fromOpaque(context!).takeUnretainedValue()
                    evidence.count += 1
                    if path.map({ String(cString: $0) }) == "folder/é 🐘.txt" { evidence.mode = mode }
                }, Unmanaged.passUnretained(evidence).toOpaque())
                print("::notice title=TAR metadata boundary::status=\(status), callbacks=\(evidence.count), fixtureMode=\(evidence.mode)")
                XCTAssertEqual(status, 0)
                XCTAssertEqual(evidence.mode & 0o777, 0o755)
                XCTAssertEqual(entry.metadata.posixMode.map { $0 & 0o777 }, 0o755)
                let backing = try XCTUnwrap(snapshot.compressedTAR?.url)
                XCTAssertEqual(backing.path, backing.resolvingSymlinksInPath().path)
                let output=try engine.extract(snapshot,ids:[entry.id],into:root,cancellation:ArchiveCancellation(),progress:{_ in})
                XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent(entry.path)),Data("hello".utf8))
                XCTAssertFalse(FileManager.default.fileExists(atPath:output.appendingPathComponent("nested.zip").path))
                let all=try engine.extract(snapshot,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{_ in})
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:all.appendingPathComponent("symbolic").path),"../outside")
                XCTAssertEqual(try Data(contentsOf:all.appendingPathComponent("hard")),Data("hello".utf8))
                XCTAssertEqual(try engine.test(url,cancellation:ArchiveCancellation()).state,.warning)
                let session=ArchiveOpenSession()
                let opened=try session.prepare(snapshot,path:entry.path,cancellation:ArchiveCancellation(),progress:{_ in})
                XCTAssertEqual(try Data(contentsOf:opened.url),Data("hello".utf8))
                let nested=try session.prepare(snapshot,path:"nested.zip",cancellation:ArchiveCancellation(),progress:{_ in})
                XCTAssertEqual(try engine.inspect(nested.url,cancellation:ArchiveCancellation()).entries.count,1)
                let drag=try ArchiveDragSession(snapshot:snapshot,paths:[entry.path])
                let promised=root.appendingPathComponent(UUID().uuidString+".txt")
                try drag.write(item:drag.items[0],to:promised)
                XCTAssertEqual(try Data(contentsOf:promised),Data("hello".utf8))
                try Data(data.dropLast(5)).write(to:url)
                XCTAssertThrowsError(try engine.inspect(url,cancellation:ArchiveCancellation()))
                XCTAssertThrowsError(try engine.extract(snapshot,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{_ in}))
            }
        }
    }
}
