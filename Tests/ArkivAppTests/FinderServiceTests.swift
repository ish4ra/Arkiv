import AppKit
import XCTest
@testable import ArkivApp
import ArkivCore
import ArkivFinderIntegration

final class FinderServiceTests: XCTestCase {
    func testColdFinderLaunchDoesNotCreateBrowser() {
        XCTAssertFalse(AppDelegate.shouldShowInitialBrowser(arguments: ["Arkiv", "--finder-action"], handledRequest: false))
        XCTAssertFalse(AppDelegate.shouldShowInitialBrowser(arguments: ["Arkiv"], handledRequest: true))
        XCTAssertTrue(AppDelegate.shouldShowInitialBrowser(arguments: ["Arkiv"], handledRequest: false))
    }

    func testNearbyExtractionDoesNotRevealOrNavigateFinder() async {
        await MainActor.run {
            let output = URL(fileURLWithPath: "/Users/test/Downloads/Compressed")
            var revealed: [[URL]] = []
            FinderServiceProvider.showExtractionResult(output, action: .extractHere) { revealed.append($0) }
            FinderServiceProvider.showExtractionResult(output.appendingPathComponent("Example"), action: .extractFolder) { revealed.append($0) }
            XCTAssertTrue(revealed.isEmpty, "Nearby extraction must leave Finder's current location alone")
            FinderServiceProvider.showExtractionResult(output, action: .extractTo) { revealed.append($0) }
            XCTAssertEqual(revealed, [[output]], "An explicitly chosen destination may be revealed")
        }
    }

    func testOnlyExtractToRequestsDestinationSelection() {
        XCTAssertFalse(FinderServiceProvider.requiresDestinationSelection(.extractHere))
        XCTAssertFalse(FinderServiceProvider.requiresDestinationSelection(.extractFolder))
        XCTAssertTrue(FinderServiceProvider.requiresDestinationSelection(.extractTo))
        XCTAssertFalse(FinderServiceProvider.requiresDestinationSelection(.test))
    }

    func testCompletionSoundOnlyPlaysOncePerSuccess() {
        var plays = 0
        let success: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/output"))
        ExtractionFeedback.completed(success) { plays += 1 }
        XCTAssertEqual(plays, 1)
        ExtractionFeedback.completed(Result<URL, Error>.failure(ArchiveFailure.cancelled)) { plays += 1 }
        ExtractionFeedback.completed(Result<URL, Error>.failure(ArchiveFailure.message("failure"))) { plays += 1 }
        XCTAssertEqual(plays, 1)
        ExtractionFeedback.completed(success) { plays += 1 }
        XCTAssertEqual(plays, 2)
    }

    func testMenuTransportCanDropRepresentedObjectWithoutDroppingAction() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("a.zip")
            try Data().write(to: archive)
            for command in FinderCommand.allCases {
                // Reproduce Finder's returned menu shape: scalar tag, no custom payload.
                let returnedItem = NSMenuItem(title: "Arkiv action", action: nil, keyEquivalent: "")
                returnedItem.tag = command.menuTag
                XCTAssertNil(returnedItem.representedObject)
                var delivered = false
                let relay = FinderActionRelay(home: root,
                    extensionURL: URL(fileURLWithPath: "/Applications/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex"),
                    identifier: { _ in "xyz.isharalakshan.arkiv" }, transport: { url, _, completion in
                        XCTAssertEqual(try? FinderHandoff(url: url).command, command)
                        delivered = true
                        completion(nil)
                    }, failure: { XCTFail("Unexpected relay failure: \($0)") })
                relay.perform(tag: returnedItem.tag, selectedURLs: [archive])
                XCTAssertTrue(delivered)
            }
        }
    }

    func testFinderURLsDispatchDirectlyWithoutConfirmationAndRejectInvalidSources() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.zip")
            try Data().write(to: archive)
            var opened: URL?
            let provider = FinderServiceProvider { opened = $0 }
            let open = try FinderHandoff(command: .open, archive: archive)
            try provider.receive(open.url)
            XCTAssertEqual(opened, archive)
            for command in [FinderCommand.extractHere, .extractFolder, .extractTo] {
                var dispatched = 0
                try provider.receive(FinderHandoff(command: command, archive: archive).url) { request in
                    dispatched += 1
                    XCTAssertEqual(request.archive, archive)
                }
                XCTAssertEqual(dispatched, 1)
                XCTAssertFalse(provider.isBusy)
                let malformed = URL(string: try FinderHandoff(command: command, archive: archive).url.absoluteString + "&output=/tmp/elsewhere")!
                XCTAssertThrowsError(try provider.receive(malformed) { _ in XCTFail("Arbitrary output must be rejected") })
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Example.zip"])
            }
            let link = root.appendingPathComponent("link.zip")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archive)
            XCTAssertThrowsError(try provider.receive(FinderHandoff(command: .extractHere, archive: link).url) { _ in
                XCTFail("Invalid requests must fail before dispatch")
            })
        }
    }

    func testServiceOpenRoutesFileURLAndRejectsMultiSelection() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.zip")
            try Data().write(to: archive)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            XCTAssertTrue(pasteboard.writeObjects([archive as NSURL]))
            var opened: URL?
            let provider = FinderServiceProvider { opened = $0 }
            XCTAssertTrue(provider.responds(to: NSSelectorFromString("performFinderAction:userData:error:")))
            var error: NSString?
            provider.performFinderAction(pasteboard, userData: "open", error: &error)
            XCTAssertNil(error)
            XCTAssertEqual(opened, archive)
            XCTAssertFalse(provider.isBusy)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([archive as NSURL, archive as NSURL]))
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "not-an-action"))
        }
    }
    func testLegacyFinderPasteboardAndUnsupportedSelections() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.TAR")
            try Data().write(to: archive)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.setPropertyList([archive.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            XCTAssertEqual(try FinderServiceProvider.request(from: pasteboard, userData: "extractFolder").archive, archive)
            pasteboard.clearContents()
            pasteboard.setString("/tmp/not-a-file.zip", forType: .string)
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(string: "https://example.com/a.zip")! as NSURL])
            XCTAssertThrowsError(try FinderServiceProvider.request(from: pasteboard, userData: "extractHere"))
        }
    }
}
