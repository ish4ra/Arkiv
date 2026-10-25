import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipCreationOptionsTests: XCTestCase {
    private let mib: UInt64 = 1024 * 1024
    func testCapabilitiesMemoryBoundariesAndPresetOverrides() throws {
        let auto = try SevenZipCreationOptions().resolve(preset:.normal)
        XCTAssertEqual(auto.dictionaryBytes,0); XCTAssertEqual(auto.threads,2)
        XCTAssertEqual(auto.estimatedMemoryBytes,1664*mib)
        XCTAssertEqual(SevenZipCreationOptions.supportedThreads(processorCount:1),[1,2])
        XCTAssertEqual(SevenZipCreationOptions.supportedThreads(processorCount:16),[1,2,3,4])
        XCTAssertEqual(SevenZipCreationOptions.supportedDictionaryBytes,[1,2,4,8,16,32,64].map { $0*mib })
        XCTAssertEqual(try SevenZipCreationOptions(dictionaryBytes:64*mib,threads:1).resolve(preset:.ultra).estimatedMemoryBytes,1632*mib)
        XCTAssertThrowsError(try SevenZipCreationOptions(dictionaryBytes:64*mib,threads:2).resolve(preset:.normal))
        XCTAssertEqual(try SevenZipCreationOptions(dictionaryBytes:16*mib,threads:4).resolve(preset:.normal,processorCount:4).estimatedMemoryBytes,1728*mib)
        XCTAssertThrowsError(try SevenZipCreationOptions(dictionaryBytes:32*mib,threads:4).resolve(preset:.normal,processorCount:4))
        XCTAssertNoThrow(try SevenZipCreationOptions().resolve(preset:.maximum,inputBytes:32*mib))
        XCTAssertThrowsError(try SevenZipCreationOptions().resolve(preset:.maximum,inputBytes:32*mib+1))
        XCTAssertThrowsError(try SevenZipCreationOptions().resolve(preset:.ultra))
        XCTAssertNoThrow(try SevenZipCreationOptions().resolve(preset:.ultra,inputBytes:4096))
        for preset in CompressionPreset.available(for:.sevenZip) {
            let settings = try SevenZipCreationOptions(dictionaryBytes:4*mib,threads:1).resolve(preset:preset)
            XCTAssertEqual(settings.dictionaryBytes,UInt32(4*mib)); XCTAssertEqual(settings.threads,1)
            XCTAssertEqual(settings.estimatedMemoryBytes,192*mib,"Dictionary override does not change the chosen preset/algorithm")
        }
        for options in [SevenZipCreationOptions(dictionaryBytes:0),.init(dictionaryBytes:3*mib),.init(dictionaryBytes:128*mib),.init(dictionaryBytes:UInt64.max),.init(threads:0),.init(threads:5),.init(threads:-1)] {
            XCTAssertThrowsError(try options.resolve(preset:.normal,inputBytes:100))
        }
        XCTAssertThrowsError(try SevenZipCreationOptions(threads:4).resolve(preset:.normal,inputBytes:100,processorCount:2))
        XCTAssertThrowsError(try SevenZipCreationOptions().resolve(preset:.store,inputBytes:100))
    }
    func testDictionaryThreadsAndEncryptedRoundTrips() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("資料 🐘")
        try fm.createDirectory(at:folder.appendingPathComponent("empty"),withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let data = Data(repeating:83,count:150000)
        try data.write(to:folder.appendingPathComponent("file"))
        try Data().write(to:folder.appendingPathComponent("zero"))
        XCTAssertEqual(try SevenZipCreationOptions.inputSize(sources:[folder],cancellation:ArchiveCancellation()),UInt64(data.count))
        var cases = SevenZipCreationOptions.supportedDictionaryBytes.map { SevenZipCreationOptions(dictionaryBytes:$0,threads:1) }
        cases += SevenZipCreationOptions.supportedThreads().map { .init(dictionaryBytes:mib,threads:$0) }
        cases += [.init(),.init(dictionaryBytes:4*mib)]
        let engine = LibArchiveEngine()
        for (i,options) in cases.enumerated() {
            let preset: CompressionPreset = i % 2 == 0 ? .ultra : .fastest
            let password: String? = i % 3 == 0 ? "test password" : nil
            let headers = i % 2 == 0
            let archive = try ArchiveCreator().create(.init(sources:[folder],destination:root,name:"advanced",format:.sevenZip,password:password,encryptFilenames:headers,preset:preset,sevenZipOptions:options),cancellation:ArchiveCancellation(),progress:{ _ in })
            let snapshot = try engine.inspect(archive,cancellation:ArchiveCancellation(),password:password)
            let policy = try SevenZipPolicyInspector().inspect(snapshot,password:password,cancellation:ArchiveCancellation())
            XCTAssertEqual(policy.dataEncrypted,password != nil)
            XCTAssertEqual(policy.headersEncrypted,password != nil && headers)
            XCTAssertTrue(policy.supportedLayout)
            XCTAssertEqual(try engine.test(archive,cancellation:ArchiveCancellation(),password:password).state,.ok)
            let output = try engine.extract(snapshot,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{ _ in })
            XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/file")),data)
            XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/zero")),Data())
            XCTAssertTrue(fm.fileExists(atPath:output.appendingPathComponent("資料 🐘/empty").path))
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    func testInvalidCreationAndSizeCancellationLeaveNoOutput() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let file = root.appendingPathComponent("file")
        try Data("input".utf8).write(to:file)
        for request in [
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",sevenZipOptions:.init()),
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",format:.sevenZip,sevenZipOptions:.init(dictionaryBytes:64*mib,threads:2)),
            ArchiveCreationRequest(sources:[file],destination:root,name:"bad",format:.sevenZip,sevenZipOptions:.init(threads:99))
        ] { XCTAssertThrowsError(try ArchiveCreator().create(request,cancellation:ArchiveCancellation(),progress:{ _ in })) }
        let token = ArchiveCancellation();token.cancel()
        XCTAssertThrowsError(try SevenZipCreationOptions.inputSize(sources:[file],cancellation:token))
        XCTAssertThrowsError(try ArchiveCreator().create(.init(sources:[file],destination:root,name:"cancelled",format:.sevenZip),cancellation:token,progress:{ _ in }))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:root.path),["file"])
    }
}
