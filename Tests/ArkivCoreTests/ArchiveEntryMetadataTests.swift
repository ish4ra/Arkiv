import XCTest
@testable import ArkivCore

final class ArchiveEntryMetadataTests: XCTestCase {
    func testExistingInitializerKeepsUnknownEvidenceUnknown() {
        let entry = ArchiveEntry(id:0,path:"file.zip",size:100,kind:.file)
        XCTAssertNil(entry.metadata.packedSize)
        XCTAssertNil(entry.metadata.modificationTime)
        XCTAssertNil(entry.metadata.compressionMethod)
        XCTAssertNil(entry.metadata.encrypted)
        XCTAssertNil(entry.metadata.ratio(unpackedSize:100,kind:.file))
    }
    func testRatioEdgesAndNonRegularEntries() {
        let data = ArchiveEntryMetadata(packedSize:25)
        XCTAssertEqual(data.ratio(unpackedSize:100,kind:.file),0.25)
        XCTAssertEqual(data.ratio(unpackedSize:10,kind:.file),2.5)
        XCTAssertNil(data.ratio(unpackedSize:0,kind:.file))
        XCTAssertNil(data.ratio(unpackedSize:-1,kind:.file))
        for kind: ArchiveEntry.Kind in [.directory,.symbolicLink,.hardLink,.unsupported] {
            XCTAssertNil(data.ratio(unpackedSize:100,kind:kind))
        }
        XCTAssertEqual(ArchiveEntryMetadata(packedSize:0).ratio(unpackedSize:100,kind:.file),0)
    }
    func testEvidenceIsPreserved() {
        let time = Date(timeIntervalSince1970:1234567890)
        let metadata = ArchiveEntryMetadata(packedSize:123,modificationTime:time,compressionMethod:"Deflate",encrypted:false)
        let entry = ArchiveEntry(id:1,path:"資料.txt",size:456,kind:.file,metadata:metadata)
        XCTAssertEqual(entry.metadata,metadata)
        XCTAssertEqual(entry.metadata.modificationTime,time)
        XCTAssertEqual(entry.metadata.encrypted,false)
    }
}
