import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPModificationTimeTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func dos(year: UInt32 = 2024, month: UInt32 = 1, day: UInt32 = 2,
                     hour: UInt32 = 3, minute: UInt32 = 4, second: UInt32 = 6) -> UInt32 {
        ((year-1980)<<25) | (month<<21) | (day<<16) | (hour<<11) | (minute<<5) | (second/2)
    }
    private func le(_ value: UInt32, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0*8)) } }
    private func ut(_ seconds: UInt32) -> [UInt8] { [0x55,0x54,5,0,1] + le(seconds,4) }
    private func fixture(local: [UInt8] = [], central: [UInt8] = [], time: UInt32? = nil,
                         localTime: UInt32? = nil, _ body: (URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let name = Array("資料 🐘.txt".utf8), timestamp = time ?? dos()
        var bytes: [UInt8] = [80,75,3,4]
        for value: UInt32 in [20,0x800,0] { bytes += le(value,2) }
        bytes += le(localTime ?? timestamp,4)
        bytes += Array(repeating: 0, count: 12)
        bytes += le(UInt32(name.count),2)
        bytes += le(UInt32(local.count),2)
        bytes += name; bytes += local
        let offset = bytes.count
        var h: [UInt8] = [80,75,1,2]
        for value: UInt32 in [0x0314,20,0x800,0] { h += le(value,2) }
        h += le(timestamp,4)
        h += Array(repeating: 0, count: 12)
        h += le(UInt32(name.count),2)
        h += le(UInt32(central.count),2)
        h += Array(repeating: 0, count: 6)
        h += le(0o100644 << 16,4)
        h += le(0,4)
        h += name; h += central
        bytes += h
        bytes += [80,75,5,6]
        bytes += Array(repeating: 0, count: 4)
        bytes += le(1,2); bytes += le(1,2)
        bytes += le(UInt32(h.count),4)
        bytes += le(UInt32(offset),4)
        bytes += le(0,2)
        let url = root.appendingPathComponent("time.zip")
        try Data(bytes).write(to: url)
        try body(url, LibArchiveEngine().inspect(url, cancellation: ArchiveCancellation()))
    }
    func testExtendedUTCAndPrecisionPolicy() throws {
        for fields in [(ut(1700000000),ut(1700000000)), (ut(1700000000),[]), ([],ut(1700000000))] {
            try fixture(local: fields.0, central: fields.1) { _, snapshot in
                let stamp = try XCTUnwrap(ZIPMetadataReader().modificationTime(for: "資料 🐘.txt", in: snapshot))
                XCTAssertEqual(stamp.origin, .extendedUTC)
                XCTAssertEqual(stamp.date.timeIntervalSince1970, 1700000000)
                XCTAssertEqual(stamp.precision, 1)
                for delta in [-100.0, 0, 0.99] {
                    XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive: stamp, localModificationTime: stamp.date.addingTimeInterval(delta), localIsRegularFile: true), .keep)
                }
                XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive: stamp, localModificationTime: stamp.date.addingTimeInterval(1), localIsRegularFile: true), .replace)
                XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive: stamp, localModificationTime: stamp.date.addingTimeInterval(5), localIsRegularFile: false), .ineligible)
            }
        }
    }
    func testDOSExplicitZoneTwoSecondPrecisionAndDST() throws {
        try fixture { _, snapshot in
            let reader = ZIPMetadataReader()
            XCTAssertNil(reader.modificationTime(for: "資料 🐘.txt", in: snapshot), "DOS must not assume the host's zone")
            let time = try XCTUnwrap(reader.modificationTime(for: "資料 🐘.txt", in: snapshot, dosTimeZone: utc))
            XCTAssertEqual(time.precision,2)
            XCTAssertEqual(time.date,ISO8601DateFormatter().date(from:"2024-01-02T03:04:06Z"))
            for delta in [-2.0,0,1,1.999] {
                XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive: time, localModificationTime: time.date.addingTimeInterval(delta), localIsRegularFile: true), .keep)
            }
            XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive: time, localModificationTime: time.date.addingTimeInterval(2), localIsRegularFile: true), .replace)
        }
        let zone = try XCTUnwrap(TimeZone(identifier:"America/New_York"))
        XCTAssertNil(ZIPModificationTime.dos(dos(month:3,day:10,hour:2,minute:30,second:0),timeZone:zone))
        XCTAssertNil(ZIPModificationTime.dos(dos(month:11,day:3,hour:1,minute:30,second:0),timeZone:zone))
        XCTAssertNil(ZIPModificationTime.dos(dos(month:2,day:30),timeZone:utc))
        XCTAssertNil(ZIPModificationTime.dos(0,timeZone:utc))
    }
    func testMissingConflictingDuplicateAndUnsupportedMetadata() throws {
        let cases: [([UInt8],[UInt8])] = [
            (ut(100),ut(101)), (ut(100)+ut(100),ut(100)),
            ([0x55,0x54,1,0,0],[]), (ut(UInt32.max),ut(UInt32.max)),
            ([0x0a,0,4,0,0,0,0,0],[]), (ut(100),[0x55,0x54,6,0,1,100,0,0,0,0])
        ]
        for fields in cases {
            try fixture(local: fields.0, central: fields.1) { _, snapshot in
                XCTAssertNil(ZIPMetadataReader().modificationTime(for:"資料 🐘.txt",in:snapshot,dosTimeZone:utc))
            }
        }
        try fixture(time:0) { _, snapshot in
            XCTAssertNil(ZIPMetadataReader().modificationTime(for:"資料 🐘.txt",in:snapshot,dosTimeZone:utc))
        }
        try fixture(localTime: dos(second:8)) { _, snapshot in
            XCTAssertNil(ZIPMetadataReader().modificationTime(for:"資料 🐘.txt",in:snapshot,dosTimeZone:utc))
        }
        XCTAssertEqual(ZIPReplaceOlderPolicy.decide(archive:nil,localModificationTime:Date(),localIsRegularFile:true),.ineligible)
    }
    func testCreatorRoundTripStaleArchiveAndSourceRevalidation() throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let file = root.appendingPathComponent("資料 🐘.txt"), date = Date(timeIntervalSince1970:1700000000)
        try Data("hello".utf8).write(to:file)
        try fm.setAttributes([.modificationDate:date],ofItemAtPath:file.path)
        let source = try ZIPUpdateSource(file)
        XCTAssertEqual(source.modificationTime,date); try source.revalidate()
        let archive = try ArchiveCreator().create(.init(sources:[file],destination:root,name:"roundtrip"),cancellation:ArchiveCancellation(),progress:{ _ in })
        let snapshot = try LibArchiveEngine().inspect(archive,cancellation:ArchiveCancellation())
        let time = try XCTUnwrap(ZIPMetadataReader().modificationTime(for:file.lastPathComponent,in:snapshot))
        XCTAssertEqual(time.date,date); XCTAssertEqual(time.origin,.extendedUTC)
        try fm.setAttributes([.modificationDate:date.addingTimeInterval(10)],ofItemAtPath:file.path)
        XCTAssertThrowsError(try source.revalidate())
        let newSource = try ZIPUpdateSource(file)
        try Data("hello".utf8).write(to:file,options:.atomic)
        try fm.setAttributes([.modificationDate:newSource.modificationTime],ofItemAtPath:file.path)
        XCTAssertThrowsError(try newSource.revalidate(),"Restoring mtime must not hide identity changes")
        XCTAssertThrowsError(try ZIPUpdateSource(root))
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at:link,withDestinationURL:file)
        XCTAssertThrowsError(try ZIPUpdateSource(link))
        try Data("changed".utf8).write(to:archive,options:.atomic)
        XCTAssertNil(ZIPMetadataReader().modificationTime(for:file.lastPathComponent,in:snapshot))
    }
}
