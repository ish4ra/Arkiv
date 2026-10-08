import Foundation
import XCTest
@testable import ArkivFinderIntegration

final class FinderHandoffTests: XCTestCase {
    func testEveryCommandRoundTripsUnicodeAndReservedCharacters() throws {
        let archive = URL(fileURLWithPath: "/Users/test/Downloads/日本語 & #?% + name.zip")
        for command in FinderCommand.allCases {
            let input = try FinderHandoff(command: command, archive: archive)
            let output = try FinderHandoff(url: input.url)
            XCTAssertEqual(output.command, command)
            XCTAssertEqual(output.archive, archive)
        }
    }

    func testMalformedAndAmbiguousHandoffsRejected() throws {
        let good = try FinderHandoff(command: .extractHere, archive: URL(fileURLWithPath: "/tmp/a.zip")).url.absoluteString
        for string in [good + "&command=open", good + "&extra=value", good + "#fragment",
                       good.replacingOccurrences(of: "/v1", with: "/v2"),
                       good.replacingOccurrences(of: "extractHere", with: "create"),
                       good.replacingOccurrences(of: "//action", with: "//attacker"),
                       good.replacingOccurrences(of: "//action", with: "//user@action"),
                       good.replacingOccurrences(of: "//action", with: "//action:123") ] {
            XCTAssertThrowsError(try FinderHandoff(url: XCTUnwrap(URL(string: string))))
        }
        XCTAssertThrowsError(try FinderHandoff(url: URL(string: "arkiv-finder://action/v1?command=open&file=" + String(repeating: "a", count: 33_000))!))
    }

    func testUnsupportedArchiveURLsRejected() {
        for value in ["https://host/a.zip", "file://remote/a.zip", "file:///tmp/a.tar.gz",
                      "file:///tmp/a.txt", "file:///tmp/a.zip?command=extractHere", "file:///tmp/a.zip#fragment",
                      "file:///tmp/a%00.zip"] {
            XCTAssertThrowsError(try FinderHandoff(command: .open, archive: URL(string: value)!), value)
        }
    }

    func testSelectionIsSingleRegularFileInsideHome() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let sibling = root.appendingPathComponent("home-other")
        for directory in [home, sibling] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        let zip = home.appendingPathComponent("archive.ZIP")
        let outside = sibling.appendingPathComponent("outside.tar")
        try Data().write(to: zip); try Data().write(to: outside)
        XCTAssertEqual(FinderHandoff.selection([zip], within: home), zip)
        XCTAssertNil(FinderHandoff.selection([], within: home))
        XCTAssertNil(FinderHandoff.selection([zip, zip], within: home))
        XCTAssertNil(FinderHandoff.selection([outside], within: home))
        XCTAssertNil(FinderHandoff.selection([zip], within: URL(fileURLWithPath: "/")))
        let link = home.appendingPathComponent("link.zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: zip)
        XCTAssertNil(FinderHandoff.selection([link], within: home))
        let folder = home.appendingPathComponent("folder.zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertNil(FinderHandoff.selection([folder], within: home))
    }

    func testFolderNameMatchesSafeDestinationRules() {
        XCTAssertEqual(FinderHandoff.folderName(for: URL(fileURLWithPath: "/tmp/example.zip")), "example")
        XCTAssertEqual(FinderHandoff.folderName(for: URL(fileURLWithPath: "/tmp/..zip")), "Archive")
        XCTAssertEqual(FinderHandoff.folderName(for: URL(fileURLWithPath: "/tmp/a:b\nc.tar")), "a_b_c")
        XCTAssertLessThanOrEqual(FinderHandoff.folderName(for: URL(fileURLWithPath: "/tmp/" + String(repeating: "界", count: 100) + ".zip")).utf8.count, 180)
    }
}
