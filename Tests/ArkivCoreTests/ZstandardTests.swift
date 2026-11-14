import Foundation
import XCTest
@testable import ArkivCore

final class ZstandardTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures") }
    func testOptionalChecksumAndUnknownSizeAreReportedHonestly() throws {
        let engine = LibArchiveEngine()
        for (name, checksum, state): (String, Bool, ArchiveIntegrityState) in [
            ("standalone.sql", true, .ok), ("zstd-no-checksum", false, .warning), ("zstd-unknown-size", true, .ok)
        ] {
            let url = fixtures.appendingPathComponent(name + ".zst")
            let snapshot = try engine.inspect(url, cancellation: .init())
            XCTAssertEqual(snapshot.streamChecksum, checksum)
            XCTAssertEqual(snapshot.entries.count, 1)
            XCTAssertEqual(snapshot.entries[0].size, Int64(Data(String(repeating: "database content é 🐘\n", count: 10000).utf8).count))
            XCTAssertNil(snapshot.entries[0].metadata.crc32)
            let result = try engine.test(url, cancellation: .init())
            XCTAssertEqual(result.state, state)
            if !checksum { XCTAssertTrue(result.detail.contains("no content checksum")) }
        }
        for name in ["zstd-large-window", "zstd-dictionary"] {
            let url = fixtures.appendingPathComponent(name + ".zst")
            XCTAssertThrowsError(try engine.inspect(url, cancellation: .init()))
            XCTAssertEqual(try engine.test(url, cancellation: .init()).state, .unsupportedMethod)
        }
        for name in [".zst", "..zst", "...zst", "../bad:name.zst", "bad\\name.zst", "bad\nname.zst"] {
            XCTAssertThrowsError(try StandaloneStream.outputName(for: URL(fileURLWithPath: "/tmp/" + name)))
        }
    }
}
