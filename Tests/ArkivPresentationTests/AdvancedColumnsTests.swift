import XCTest
import ArkivCore
@testable import ArkivPresentation
final class AdvancedColumnsTests: XCTestCase {
    func testStoredCRCAndModeFormattingAndSorting() {
        let rows = ArchiveIndex(entries:[
            .init(id:0,path:"a",size:1,kind:.file,metadata:.init(crc32:0x123abc,posixMode:0o100755)),
            .init(id:1,path:"b",size:1,kind:.file),
            .init(id:2,path:"c",size:1,kind:.file,metadata:.init(crc32:0,storedAttributes:0x20))]).children(of:"")
        XCTAssertEqual(BrowserPresentation.metadataText(rows[0],column:"crc"),"00123ABC")
        XCTAssertEqual(BrowserPresentation.metadataText(rows[0],column:"attributes"),"rwxr-xr-x")
        XCTAssertEqual(BrowserPresentation.metadataText(rows[1],column:"crc"),"")
        XCTAssertEqual(BrowserPresentation.metadataText(rows[2],column:"crc"),"00000000")
        XCTAssertEqual(BrowserPresentation.metadataText(rows[2],column:"attributes"),"0x0020")
        for key in ["crc","attributes"] {
            XCTAssertEqual(BrowserPresentation.sorted(rows,by:key,ascending:true).map(\.name),["b","c","a"])
            XCTAssertEqual(BrowserPresentation.sorted(rows,by:key,ascending:false).map(\.name),["a","c","b"])
        }
    }
    func testMetadataRowsFormattingAndNilSort() {
        let metadata = ArchiveEntryMetadata(packedSize:20,modificationTime:Date(timeIntervalSince1970:100),compressionMethod:"Store",encrypted:false)
        let index = ArchiveIndex(entries:[.init(id:0,path:"folder/a",size:100,kind:.file,metadata:metadata),.init(id:1,path:"folder/b",size:50,kind:.file)])
        XCTAssertNil(index.row(at:"folder")?.metadata.packedSize)
        let rows = index.children(of:"folder")
        let a = rows.first { $0.name == "a" }!
        XCTAssertEqual(BrowserPresentation.metadataText(a,column:"ratio"),"20.0%")
        XCTAssertEqual(BrowserPresentation.metadataText(a,column:"encrypted"),"No")
        XCTAssertFalse(BrowserPresentation.metadataText(a,column:"modified").isEmpty)
        for key in ["packed","ratio","modified","method","encrypted"] {
            XCTAssertEqual(BrowserPresentation.sorted(rows,by:key,ascending:true).map(\.name),["b","a"])
            XCTAssertEqual(BrowserPresentation.sorted(rows,by:key,ascending:false).map(\.name),["a","b"])
            XCTAssertEqual(BrowserPresentation.metadataText(rows.first { $0.name == "b" }!,column:key),"")
        }
        XCTAssertEqual(index.search("a").first?.metadata,metadata)
    }
}
