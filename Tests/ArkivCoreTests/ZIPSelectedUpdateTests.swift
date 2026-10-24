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
