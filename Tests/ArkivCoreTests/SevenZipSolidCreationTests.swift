import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class SevenZipSolidCreationTests: XCTestCase {
    func testPolicyAndMemoryAdmission() throws {
        let normal = try SevenZipCreationOptions().resolve(preset:.normal)
        XCTAssertEqual(normal.solid,.off)
        let solid = try SevenZipCreationOptions(solid:.on()).resolve(preset:.normal)
        XCTAssertEqual(solid.estimatedMemoryBytes,normal.estimatedMemoryBytes+16*1024*1024)
        XCTAssertEqual(SevenZipSolidPolicy.supportedBlockBytes,[16,64,256,1024].map { UInt64($0)*1024*1024 })
        for block in [UInt64(0),17<<20,2<<30,UInt64.max] {
            XCTAssertThrowsError(try SevenZipCreationOptions(solid:.on(blockBytes:block)).resolve(preset:.normal,inputBytes:100))
        }
        XCTAssertThrowsError(try SevenZipCreationOptions(dictionaryBytes:64<<20,threads:2,solid:.on()).resolve(preset:.normal))
        XCTAssertThrowsError(try SevenZipCreationOptions(solid:.on()).resolve(preset:.ultra,inputBytes:64<<20))
        XCTAssertNoThrow(try SevenZipCreationOptions(dictionaryBytes:64<<20,threads:1,solid:.on()).resolve(preset:.ultra))
    }
    func testSolidRoundTripsAndEditingRemainsReadOnly() throws {
        #if os(Linux)
        setlocale(LC_CTYPE,"C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("資料 🐘")
        try fm.createDirectory(at:folder.appendingPathComponent("empty"),withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let data = Data(repeating:83,count:200000)
        for name in ["one.txt","two.txt","three.txt"] { try data.write(to:folder.appendingPathComponent(name)) }
        try Data().write(to:folder.appendingPathComponent("zero"))
        let policies: [SevenZipSolidPolicy] = [.off,.on()] + SevenZipSolidPolicy.supportedBlockBytes.map { .on(blockBytes:$0) }
        let engine = LibArchiveEngine()
        for (i,solid) in policies.enumerated() {
            for encryption in 0...2 {
                let password: String? = encryption == 0 ? nil : "test secret"
                let options = SevenZipCreationOptions(dictionaryBytes:i % 2 == 0 ? nil : 1<<20,threads:i % 2 == 0 ? 1 : 2,solid:solid)
                let archive = try ArchiveCreator().create(.init(sources:[folder],destination:root,name:"solid",format:.sevenZip,password:password,encryptFilenames:encryption==2,preset:i % 2 == 0 ? .normal : .fastest,sevenZipOptions:options),cancellation:ArchiveCancellation(),progress:{ _ in })
                let snapshot = try engine.inspect(archive,cancellation:ArchiveCancellation(),password:password)
                let policy = try SevenZipPolicyInspector().inspect(snapshot,password:password,cancellation:ArchiveCancellation())
                XCTAssertEqual(policy.isSolid,solid.enabled,"Must be detected from actual upstream kpidSolid")
                XCTAssertEqual(policy.dataEncrypted,password != nil)
                XCTAssertEqual(policy.headersEncrypted,encryption==2)
                XCTAssertEqual(policy.supportedLayout,!solid.enabled)
                XCTAssertEqual(try engine.test(archive,cancellation:ArchiveCancellation(),password:password).state,.ok)
                let output = try engine.extract(snapshot,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{ _ in })
                for name in ["one.txt","two.txt","three.txt"] { XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/"+name)),data) }
                XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("資料 🐘/zero")),Data())
                XCTAssertTrue(fm.fileExists(atPath:output.appendingPathComponent("資料 🐘/empty").path))
                if solid.enabled {
                    let before = try Data(contentsOf:archive)
                    XCTAssertFalse(ArchiveAdditionUpdater().capability(for:snapshot).isAvailable)
                    XCTAssertFalse(ArchiveAdditionUpdater().canAddEncrypted(snapshot))
                    XCTAssertFalse(ArchiveModificationUpdater().canDeleteEncrypted(snapshot))
                    XCTAssertFalse(ArchiveModificationUpdater().canRenameEncrypted(snapshot))
                    XCTAssertFalse(ArchiveModificationUpdater().canReplaceEncrypted(snapshot))
                    XCTAssertThrowsError(try ArchiveAdditionUpdater().add(sources:[folder.appendingPathComponent("one.txt")],to:snapshot,password:password,cancellation:ArchiveCancellation()))
                    XCTAssertThrowsError(try ArchiveModificationUpdater().delete(paths:["資料 🐘/one.txt"],from:snapshot,password:password,cancellation:ArchiveCancellation()))
                    XCTAssertEqual(try Data(contentsOf:archive),before)
                }
            }
        }
        XCTAssertFalse(try fm.contentsOfDirectory(atPath:root.path).contains { $0.hasPrefix(".arkiv-") })
    }
}
