import Foundation
import XCTest
@testable import ArkivFinderIntegration

final class CreationHandoffTests: XCTestCase {
    func testNamesAndMultiSelectionRoundtrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("my 日本語 🦊.txt")
        let folder = root.appendingPathComponent("Subs")
        try Data("hello".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertEqual(CreationHandoff.baseName(for: [file]), "my 日本語 🦊")
        XCTAssertEqual(CreationHandoff.baseName(for: [folder]), "Subs")
        XCTAssertEqual(CreationHandoff.baseName(for: [file, folder]), root.lastPathComponent)
        for command in [CreationCommand.addArchive, .zip, .sevenZip, .password] {
            let request = try CreationHandoff(command: command, sources: [file, folder])
            let decoded = try CreationHandoff(url: request.url)
            XCTAssertEqual(decoded.command, command); XCTAssertEqual(decoded.sources, request.sources)
            XCTAssertEqual(CreationCommand(menuTag: command.menuTag), command)
            XCTAssertThrowsError(try CreationHandoff(url: URL(string: request.url.absoluteString + "&destination=/tmp")!))
            XCTAssertThrowsError(try CreationHandoff(url: URL(string: request.url.absoluteString + "&command=zip")!))
            XCTAssertThrowsError(try FinderHandoff(url: request.url))
            XCTAssertThrowsError(try CreationHandoff(url: URL(string: request.url.absoluteString + "&password=not-allowed")!))
        }
        XCTAssertEqual(CreationHandoff.selection([file, folder], within: root), [file, folder].map(\.standardizedFileURL))
        XCTAssertNil(CreationHandoff.selection([file], within: folder))
        XCTAssertThrowsError(try CreationHandoff(command: .zip, sources: [file, file]))
        XCTAssertThrowsError(try CreationHandoff(command: .zip, sources: []))
        XCTAssertThrowsError(try CreationHandoff(command: .zip, sources: [root, file]))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try CreationHandoff(command: .zip, sources: [link]))
    }

    func testSevenZipArchiveEligibilityAndFolderName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("日本語 name.7z")
        try Data().write(to: archive)
        XCTAssertEqual(FinderHandoff.folderName(for: archive), "日本語 name")
        XCTAssertEqual(FinderHandoff.selection([archive], within: root), archive.standardizedFileURL)
    }

    func testCreationRelayPreservesAllSelectedItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [root.appendingPathComponent("a.txt"), root.appendingPathComponent("b.txt")]
        for file in files { try Data().write(to: file) }
        var received = 0
        let relay = FinderActionRelay(home: root, extensionURL: URL(fileURLWithPath: "/Applications/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex"),
            identifier: { _ in "xyz.isharalakshan.arkiv" }, transport: { url, _, finish in
                XCTAssertEqual(try? CreationHandoff(url: url).sources, files)
                received += 1; finish(nil)
            }, failure: { XCTFail("Unexpected routing error: \($0)") })
        for command in [CreationCommand.zip, .sevenZip, .password, .addArchive] {
            relay.perform(tag: command.menuTag, selectedURLs: files)
        }
        XCTAssertEqual(received, 4)
    }
}
