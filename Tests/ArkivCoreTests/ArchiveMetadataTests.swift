import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ArchiveMetadataTests: XCTestCase {
    func testCreatedFormatsEncryptionAndSolid() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let a = root.appendingPathComponent("資料.txt"), b = root.appendingPathComponent("second")
        try Data(repeating:65,count:10000).write(to:a); try Data(repeating:66,count:20000).write(to:b)
        for format: ArchiveFormat in [.zip,.sevenZip] {
            for mode in 0..<(format == .zip ? 1 : 4) {
                let password = mode > 1 ? "test secret" : nil
                let archive = try ArchiveCreator().create(.init(sources:[a,b],destination:root,name:"meta",format:format,password:password,encryptFilenames:mode==3,sevenZipOptions:format == .sevenZip ? .init(solid:mode==0 ? .off : .on()) : nil),cancellation:ArchiveCancellation(),progress:{ _ in })
                let snapshot = try LibArchiveEngine().inspect(archive,cancellation:ArchiveCancellation(),password:password)
                let m = try XCTUnwrap(snapshot.metadata)
                XCTAssertEqual(m.url,archive); XCTAssertEqual(m.physicalSize,UInt64(try Data(contentsOf:archive).count))
                XCTAssertEqual(m.fileCount,2); XCTAssertEqual(m.folderCount,0); XCTAssertEqual(m.unpackedSize,30000)
                XCTAssertEqual(m.sizeRatio!,Double(m.physicalSize)/30000,accuracy:0.00001)
                XCTAssertNil(m.multipart)
                if format == .sevenZip {
                    XCTAssertEqual(m.format,"7z"); XCTAssertEqual(m.solid,mode != 0)
                    XCTAssertEqual(m.dataEncrypted,password != nil); XCTAssertEqual(m.headersEncrypted,mode==3)
                    XCTAssertTrue(m.compressionMethods?.contains("LZMA2") == true)
                } else {
                    XCTAssertTrue(m.format?.contains("ZIP") == true)
                    XCTAssertNil(m.solid); XCTAssertNil(m.dataEncrypted); XCTAssertNil(m.compressionMethods)
                }
            }
        }
    }
    func testTarAndEmptyZIP() throws {
        let fixture = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/links-and-special.tar")
        let tar = try LibArchiveEngine().inspect(fixture,cancellation:ArchiveCancellation())
        let m = try XCTUnwrap(tar.metadata)
        XCTAssertTrue(m.format?.lowercased().contains("tar") == true)
        XCTAssertEqual(m.fileCount,tar.entries.filter { $0.kind == .file }.count)
        XCTAssertNil(m.solid); XCTAssertNil(m.compressionMethods); XCTAssertNil(m.headersEncrypted)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try Data([0x50,0x4b,0x05,0x06]+Array(repeating:UInt8(0),count:18)).write(to:url)
        let empty = try XCTUnwrap(LibArchiveEngine().inspect(url,cancellation:ArchiveCancellation()).metadata)
        XCTAssertEqual(empty.fileCount,0); XCTAssertEqual(empty.folderCount,0)
        XCTAssertEqual(empty.unpackedSize,0); XCTAssertNil(empty.sizeRatio)
        XCTAssertTrue(empty.format?.contains("ZIP") == true)
    }
    func testEmptyUnknownAndExplicitFolderCounts() {
        let url = URL(fileURLWithPath:"/unknown")
        let empty = ArchiveMetadata(url:url,physicalSize:22,entries:[],format:nil)
        XCTAssertEqual(empty.unpackedSize,0); XCTAssertNil(empty.sizeRatio); XCTAssertNil(empty.format)
        let links = ArchiveMetadata(url:url,physicalSize:100,entries:[.init(id:0,path:"implicit/file",size:4,kind:.file),.init(id:1,path:"empty/",size:0,kind:.directory),.init(id:2,path:"link",size:0,kind:.symbolicLink)],format:"tar")
        XCTAssertEqual(links.fileCount,1); XCTAssertEqual(links.folderCount,1)
        XCTAssertNil(links.unpackedSize); XCTAssertNil(links.sizeRatio); XCTAssertNil(links.headersEncrypted)
    }
}
