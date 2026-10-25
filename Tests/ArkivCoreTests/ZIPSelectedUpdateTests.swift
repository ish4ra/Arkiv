import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPSelectedUpdateTests: XCTestCase {
    private let paths: Set<String> = ["Folder/a.txt", "Folder/資料 🐘.txt"]
    private func fixture(_ body: (URL, URL, URL, ArchiveSnapshot) throws -> Void) throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Folder"), input = root.appendingPathComponent("input")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("old store".utf8).write(to: folder.appendingPathComponent("a.txt"))
        try Data("untouched".utf8).write(to: folder.appendingPathComponent("keep"))
        let zip = try ArchiveCreator().create(.init(sources: [folder], destination: root, name: "selected", compression: .store), cancellation: ArchiveCancellation(), progress: { _ in })
        let unicode = root.appendingPathComponent("資料 🐘.txt")
        try Data("old deflate".utf8).write(to: unicode)
        let engine = LibArchiveEngine(), updater = ArchiveZIPUpdater()
        try updater.add(sources: [unicode], to: engine.inspect(zip, cancellation: ArchiveCancellation()), folder: "Folder", cancellation: ArchiveCancellation())
        try Data("new".utf8).write(to: input.appendingPathComponent("a.txt"))
        try Data(repeating: 65, count: 100000).write(to: input.appendingPathComponent("資料 🐘.txt"))
        try Data("unselected".utf8).write(to: input.appendingPathComponent("not-added"))
        try body(root, zip, input, engine.inspect(zip, cancellation: ArchiveCancellation()))
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
    }
    private func records(_ url: URL) throws -> [String: Data] {
        let bytes = [UInt8](try Data(contentsOf: url))
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i+1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i+2) << 16 }
        let end = bytes.count - 22, central = u32(end+16)
        var cursor = central, rows = [(String, Int)]()
        for _ in 0..<u16(end+10) {
            let n = u16(cursor+28)
            rows.append((String(decoding: bytes[(cursor+46)..<(cursor+46+n)], as: UTF8.self),u32(cursor+42)))
            cursor += 46+n+u16(cursor+30)+u16(cursor+32)
        }
        return Dictionary(uniqueKeysWithValues: rows.enumerated().map { i,row in
            (row.0,Data(bytes[row.1..<(i+1 < rows.count ? rows[i+1].1 : central)]))
        })
    }
    func testReplaceOlderMixedTimesRawPreservationAndNoOp() throws {
        try fixture { root, archive, input, snapshot in
            let fm = FileManager.default, reader = ZIPMetadataReader(), updater = ArchiveZIPUpdater()
            try Data("not used".utf8).write(to: input.appendingPathComponent("keep"))
            let selected = paths.union(["Folder/keep"])
            let deltas = ["Folder/a.txt": 1.0, "Folder/資料 🐘.txt": 0.999, "Folder/keep": -10.0]
            for path in selected {
                let time = try XCTUnwrap(reader.modificationTime(for:path,in:snapshot))
                try fm.setAttributes([.modificationDate:time.date.addingTimeInterval(deltas[path]!)],ofItemAtPath:input.appendingPathComponent(String(path.split(separator:"/").last!)).path)
            }
            let before = try records(archive)
            let result = try updater.updateSelectedFilesReport(paths:selected,from:input,in:snapshot,policy:.replaceOlder,cancellation:ArchiveCancellation())
            XCTAssertEqual(result.updatedPaths,["Folder/a.txt"]); XCTAssertEqual(result.skippedCount,2)
            let after = try records(archive)
            for (name, record) in before where name != "Folder/a.txt" { XCTAssertEqual(after[name],record,"Skipped/unrelated raw record: " + name) }
            let engine = LibArchiveEngine(), fresh = try engine.inspect(archive,cancellation:ArchiveCancellation())
            XCTAssertEqual(try engine.test(archive,cancellation:ArchiveCancellation()).state,.ok)
            let out = try engine.extract(fresh,ids:nil,into:root,cancellation:ArchiveCancellation(),progress:{ _ in })
            XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent("Folder/a.txt")),Data("new".utf8))
            XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent("Folder/資料 🐘.txt")),Data("old deflate".utf8))
            for path in selected {
                let time = try XCTUnwrap(reader.modificationTime(for:path,in:fresh))
                try fm.setAttributes([.modificationDate:time.date],ofItemAtPath:input.appendingPathComponent(String(path.split(separator:"/").last!)).path)
            }
            let original = try Data(contentsOf:archive), stamp = try SourceStamp(archive)
            let noop = try updater.updateSelectedFilesReport(paths:selected,from:input,in:fresh,policy:.replaceOlder,cancellation:ArchiveCancellation())
            XCTAssertTrue(noop.updatedPaths.isEmpty); XCTAssertEqual(noop.skippedCount,3)
            XCTAssertEqual(try Data(contentsOf:archive),original); XCTAssertEqual(try SourceStamp(archive),stamp)
        }
    }
    func testReplaceOlderCancellationAndStaleSourcesAreAtomic() throws {
        try fixture { _, archive, input, snapshot in
            for path in paths {
                let time = try XCTUnwrap(ZIPMetadataReader().modificationTime(for:path,in:snapshot))
                try FileManager.default.setAttributes([.modificationDate:time.date.addingTimeInterval(10)],ofItemAtPath:input.appendingPathComponent(String(path.split(separator:"/").last!)).path)
            }
            let updater = ArchiveZIPUpdater(), before = try Data(contentsOf:archive)
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.updateSelectedFilesReport(paths:paths,from:input,in:snapshot,policy:.replaceOlder,cancellation:token,progress:{ _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf:archive),before)
            let a = input.appendingPathComponent("a.txt")
            XCTAssertThrowsError(try updater.updateSelectedFilesReport(paths:paths,from:input,in:snapshot,policy:.replaceOlder,cancellation:ArchiveCancellation(),progress:{ _ in
                try? Data("changed".utf8).write(to:a,options:.atomic)
            }))
            XCTAssertEqual(try Data(contentsOf:archive),before)
            XCTAssertThrowsError(try updater.updateSelectedFilesReport(paths:paths,from:input,in:snapshot,policy:.replaceOlder,cancellation:ArchiveCancellation(),progress:{ _ in
                try? Data("external".utf8).write(to:archive,options:.atomic)
            }))
            XCTAssertEqual(try Data(contentsOf:archive),Data("external".utf8))
        }
    }
    func testMixedMethodsSizesUnicodeAndOnlySelectedFiles() throws {
        try fixture { root, zip, input, original in
            let engine = LibArchiveEngine(), updater = ArchiveZIPUpdater()
            var snapshot = original
            for empty in [false, true] {
                if empty {
                    for path in paths { try Data().write(to: input.appendingPathComponent(String(path.split(separator: "/").last!))) }
                }
                try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: ArchiveCancellation())
                snapshot = try engine.inspect(zip, cancellation: ArchiveCancellation())
                XCTAssertEqual(snapshot.entries.map(\.path), original.entries.map(\.path))
                XCTAssertEqual(try engine.test(zip, cancellation: ArchiveCancellation()).state, .ok)
                let out = try engine.extract(snapshot, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                for path in paths {
                    XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent(path)), try Data(contentsOf: input.appendingPathComponent(String(path.split(separator: "/").last!))))
                }
                XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("Folder/keep")), Data("untouched".utf8))
                // Read central methods independently of the browser listing.
                let data = [UInt8](try Data(contentsOf: zip))
                func u16(_ i: Int) -> Int { Int(data[i]) | Int(data[i+1]) << 8 }
                var methods = [String: Int]()
                for i in 0..<(data.count-46) where Array(data[i..<i+4]) == [80,75,1,2] {
                    let n = u16(i+28)
                    methods[String(decoding: data[(i+46)..<(i+46+n)], as: UTF8.self)] = u16(i+10)
                }
                XCTAssertEqual(methods["Folder/a.txt"], 0)
                XCTAssertEqual(methods["Folder/資料 🐘.txt"], 8)
            }
        }
    }
    func testMissingInvalidCancellationAndChangedSourcesAreAtomic() throws {
        try fixture { root, zip, input, snapshot in
            let fm = FileManager.default, updater = ArchiveZIPUpdater(), before = try Data(contentsOf: zip)
            let a = input.appendingPathComponent("a.txt")
            try fm.removeItem(at: a)
            XCTAssertThrowsError(try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: ArchiveCancellation()))
            try fm.createSymbolicLink(at: a, withDestinationURL: input.appendingPathComponent("資料 🐘.txt"))
            XCTAssertThrowsError(try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: ArchiveCancellation()))
            try fm.removeItem(at: a)
            try Data("source".utf8).write(to: a)
            for selection: Set<String> in [["Folder/a.txt"], ["Folder", "Folder/a.txt"], ["missing", "Folder/a.txt"]] {
                XCTAssertThrowsError(try updater.updateSelectedFiles(paths: selection, from: input, in: snapshot, cancellation: ArchiveCancellation()))
            }
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: zip), before)
            XCTAssertThrowsError(try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("changed source".utf8).write(to: a, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: zip), before)
            XCTAssertThrowsError(try updater.updateSelectedFiles(paths: paths, from: input, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                try? Data("external archive edit".utf8).write(to: zip, options: .atomic)
            }))
            XCTAssertEqual(try Data(contentsOf: zip), Data("external archive edit".utf8))
        }
    }
}
