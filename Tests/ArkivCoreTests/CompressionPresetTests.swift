import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class CompressionPresetTests: XCTestCase {
    func testMappingsDefaultsAndInvalidCombinations() throws {
        XCTAssertEqual(try CompressionPreset.available(for:.zip).map { try $0.backend(for:.zip) }, [.zipStore,.zipDeflate(level:1),.zipDeflate(level:3),.zipDeflate(level:6),.zipDeflate(level:9)])
        XCTAssertEqual(try CompressionPreset.available(for:.sevenZip).map { try $0.backend(for:.sevenZip) }, [1,3,5,7,9].map { .sevenLZMA2(level:Int32($0)) })
        XCTAssertThrowsError(try CompressionPreset.ultra.backend(for:.zip))
        XCTAssertThrowsError(try CompressionPreset.store.backend(for:.sevenZip))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let file = root.appendingPathComponent("file")
        try Data("source".utf8).write(to:file)
        for format: ArchiveFormat in [.zip,.sevenZip] {
            let request = ArchiveCreationRequest(sources:[file],destination:root,name:"default",format:format)
            XCTAssertEqual(request.preset,.normal)
            XCTAssertEqual(request.compression,.deflate)
        }
        for request in [
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",format:.zip,preset:.ultra),
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",format:.sevenZip,preset:.store),
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",compression:.store,preset:.fast),
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",compression:.deflate,preset:.store)
        ] { XCTAssertThrowsError(try ArchiveCreator().create(request,cancellation:ArchiveCancellation(),progress:{ _ in })) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["file"])
    }
    func testEveryPresetRoundTripAndEncryption() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("資料 🐘")
        try fm.createDirectory(at:folder.appendingPathComponent("empty"),withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let content = Data(String(repeating:"A varied, compressible file 0123456789\n",count:1000).utf8)
        try content.write(to:folder.appendingPathComponent("file.txt"))
        try Data().write(to:folder.appendingPathComponent("zero"))
        let engine = LibArchiveEngine()
        for format: ArchiveFormat in [.zip,.sevenZip] {
            for preset in CompressionPreset.available(for:format) {
                for mode in (format == .zip ? [0] : [0,1,2]) {
                    let password: String? = mode == 0 ? nil : "test-only password"
                    let archive = try ArchiveCreator().create(.init(sources:[folder],destination:root,name:"preset",format:format,password:password,encryptFilenames:mode==2,preset:preset),cancellation:ArchiveCancellation(),progress:{ _ in })
                    if password != nil {
                        XCTAssertThrowsError(try engine.inspect(archive,cancellation:ArchiveCancellation(),password:"wrong"))
                    }
                    let snapshot = try engine.inspect(archive,cancellation:ArchiveCancellation(),password:password)
                    XCTAssertEqual(try engine.test(archive,cancellation:ArchiveCancellation(),password:password).state,.ok)
                    if format == .sevenZip {
                        let policy = try SevenZipPolicyInspector().inspect(snapshot,password:password,cancellation:ArchiveCancellation())
                        XCTAssertEqual(policy.dataEncrypted,password != nil)
                        XCTAssertEqual(policy.headersEncrypted,mode == 2)
                        XCTAssertTrue(policy.supportedLayout)
                        XCTAssertTrue(policy.allDataVerified)
                    }
                    let output = try engine.extract(snapshot,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{ _ in })
                    XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/file.txt")),content)
                    XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/zero")),Data())
                    XCTAssertTrue(fm.fileExists(atPath:output.appendingPathComponent("資料 🐘/empty").path))
                    if format == .zip {
                        let bytes = [UInt8](try Data(contentsOf:archive))
                        func u16(_ i: Int)->Int { Int(bytes[i]) | Int(bytes[i+1]) << 8 }
                        func u32(_ i: Int)->Int { u16(i) | u16(i+2) << 16 }
                        var cursor = u32(bytes.count-6), found = false
                        for _ in 0..<u16(bytes.count-12) {
                            let n = u16(cursor+28), name = String(decoding:bytes[(cursor+46)..<(cursor+46+n)],as:UTF8.self)
                            if name.hasSuffix("file.txt") {
                                found = true
                                XCTAssertEqual(u16(cursor+10),preset == .store ? 0 : 8)
                                if preset == .store {
                                    XCTAssertEqual(u32(cursor+20),content.count)
                                    let local = u32(cursor+42), start = local+30+u16(local+26)+u16(local+28)
                                    XCTAssertEqual(Data(bytes[start..<(start+content.count)]),content,"Store payload must be the original bytes")
                                }
                            }
                            cursor += 46+n+u16(cursor+30)+u16(cursor+32)
                        }
                        XCTAssertTrue(found)
                    }
                }
            }
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:root.path).contains { $0.hasPrefix(".arkiv-") })
    }
}
