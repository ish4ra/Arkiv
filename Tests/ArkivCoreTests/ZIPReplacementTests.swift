import XCTest
#if os(Linux)
import Glibc
#endif
@testable import ArkivCore

final class ZIPReplacementTests: XCTestCase {
    func testReplaceMethodsSizesUnicodeAndRegressions() throws {
        #if os(Linux)
        setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let target = root.appendingPathComponent("folder/資料 🐘.txt")
        let source = root.appendingPathComponent("different.txt")
        try Data("original".utf8).write(to: target)
        try Data("keep".utf8).write(to: root.appendingPathComponent("keep"))
        for compression: ZIPCompression in [.store, .deflate] {
            let archive = try ArchiveCreator().create(.init(sources: [root.appendingPathComponent("folder"), root.appendingPathComponent("keep")], destination: root, name: "archive", compression: compression), cancellation: ArchiveCancellation(), progress: { _ in })
            for bytes in [Data(), Data("small".utf8), Data(repeating: 77, count: 100000)] {
                try bytes.write(to: source)
                let snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
                try ArchiveZIPUpdater().replace(path: "folder/資料 🐘.txt", with: source, in: snapshot, cancellation: ArchiveCancellation())
                let fresh = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
                XCTAssertEqual(fresh.entries.map(\.path), snapshot.entries.map(\.path))
                XCTAssertEqual(try LibArchiveEngine().test(archive, cancellation: ArchiveCancellation()).state, .ok)
                let output = try LibArchiveEngine().extract(fresh, ids: nil, into: root, cancellation: ArchiveCancellation(), progress: { _ in })
                XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("folder/資料 🐘.txt")), bytes)
                XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("keep")), Data("keep".utf8))
            }
            var snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            let before = try Data(contentsOf: archive)
            for (path, input) in [("folder", source), ("missing", source), ("keep", root), ("keep", archive)] {
                XCTAssertThrowsError(try ArchiveZIPUpdater().replace(path: path, with: input, in: snapshot, cancellation: ArchiveCancellation()))
                XCTAssertEqual(try Data(contentsOf: archive), before)
            }
            let link = root.appendingPathComponent("link")
            try manager.createSymbolicLink(at: link, withDestinationURL: source)
            XCTAssertThrowsError(try ArchiveZIPUpdater().replace(path: "keep", with: link, in: snapshot, cancellation: ArchiveCancellation()))
            try manager.removeItem(at: link)
            try Data(repeating: 42, count: 200000).write(to: source)
            XCTAssertThrowsError(try ArchiveZIPUpdater().replace(path: "keep", with: source, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in
                if let handle = try? FileHandle(forWritingTo: source) {
                    try? handle.truncate(atOffset: 0)
                    try? handle.close()
                }
            }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try Data("restored".utf8).write(to: source)
            let token = ArchiveCancellation()
            XCTAssertThrowsError(try ArchiveZIPUpdater().replace(path: "keep", with: source, in: snapshot, cancellation: token, progress: { _ in token.cancel() }))
            XCTAssertEqual(try Data(contentsOf: archive), before)
            try ArchiveZIPUpdater().add(sources: [source], to: snapshot, cancellation: ArchiveCancellation())
            snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            try ArchiveZIPUpdater().rename(path: "different.txt", to: "renamed", in: snapshot, cancellation: ArchiveCancellation())
            snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            try ArchiveZIPUpdater().delete(paths: ["renamed"], from: snapshot, cancellation: ArchiveCancellation())
            snapshot = try LibArchiveEngine().inspect(archive, cancellation: ArchiveCancellation())
            XCTAssertThrowsError(try ArchiveZIPUpdater().replace(path: "keep", with: source, in: snapshot, cancellation: ArchiveCancellation(), progress: { _ in try? Data("changed".utf8).write(to: archive, options: .atomic) }))
            XCTAssertEqual(try Data(contentsOf: archive), Data("changed".utf8))
            XCTAssertFalse(try manager.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".arkiv-") })
        }
    }
}
