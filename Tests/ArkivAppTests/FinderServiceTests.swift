import AppKit
import XCTest
@testable import ArkivApp
import ArkivCore
import ArkivFinderIntegration

final class FinderServiceTests: XCTestCase {
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

    func testURLCannotClaimTrustedFinderIdentity() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("Example.zip")
            try Data().write(to: archive)
            let provider = FinderServiceProvider { _ in XCTFail("Must not open") }
            for command in [FinderCommand.extractHere, .extractFolder, .extractTo] {
                let legitimate = try FinderHandoff(command: command, archive: archive).url
                var consentCount = 0
                // Even an exact extension-generated URL is unauthenticated at receipt.
                try provider.receive(legitimate) { _ in consentCount += 1; return false }
                XCTAssertEqual(consentCount, 1)
                for claim in ["trusted=true", "source=finder-sync", "bundle=xyz.isharalakshan.arkiv.finder-sync"] {
                    let forged = URL(string: legitimate.absoluteString + "&" + claim)!
                    XCTAssertThrowsError(try provider.receive(forged) { _ in
                        XCTFail("Unrecognized authentication claims must be rejected"); return true
                    })
                }
                XCTAssertFalse(provider.isBusy)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Example.zip"])
            }
        }
    }

    func testAuthenticatedAndUnauthenticatedConsentPolicy() {
        for action in [FinderAction.extractHere, .extractFolder, .extractTo] {
            XCTAssertTrue(FinderServiceProvider.requiresConsent(action, authenticatedFinder: false))
            XCTAssertFalse(FinderServiceProvider.requiresConsent(action, authenticatedFinder: true))
        }
        XCTAssertFalse(FinderServiceProvider.requiresConsent(.open, authenticatedFinder: false))
        // Extract To's chooser is always in start(), independent of this URL consent gate.
    }

    func testAuthenticationBindsOSTokenToExactURLAndRejectsBrokeredEvents() {
        let url = URL(string: "arkiv-finder://action/v1?command=extractHere")!
        let token = Data(repeating: 1, count: 32)
        // Read-only OS event attributes cannot reliably be forged in a synthetic
        // descriptor. Test the extracted identity gate, and genuine code identity
        // separately with the signed macOS diagnostic's real kernel audit token.
        XCTAssertFalse(FinderEventAuthenticator.isTrusted(url, event: nil) { _ in XCTFail("Missing event"); return true })
        XCTAssertTrue(FinderEventAuthenticator.validateIdentity(url, eventURL: url.absoluteString,
            sender: token, actual: token) { $0 == token })
        XCTAssertFalse(FinderEventAuthenticator.validateIdentity(url, eventURL: url.absoluteString,
            sender: token, actual: token) { _ in false })
        XCTAssertFalse(FinderEventAuthenticator.validateIdentity(url, eventURL: url.absoluteString + "&trusted=true",
            sender: token, actual: nil) { _ in XCTFail("Wrong URL"); return true })
        XCTAssertFalse(FinderEventAuthenticator.validateIdentity(url, eventURL: url.absoluteString,
            sender: token, actual: Data(repeating: 2, count: 32)) { _ in XCTFail("Broker mismatch"); return true })
        XCTAssertFalse(FinderEventAuthenticator.validateIdentity(url, eventURL: url.absoluteString,
            sender: Data(), actual: nil) { _ in XCTFail("Missing token"); return true })
        XCTAssertFalse(FinderEventAuthenticator.matchesCode(Data(), at: URL(fileURLWithPath: "/missing")))
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

    func testFinderURLRoutesOpenAndCancelledExtractionDoesNotWrite() async throws {
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
            try provider.receive(open.url) { _ in XCTFail("Open does not require extraction consent"); return false }
            XCTAssertEqual(opened, archive)
            for command in [FinderCommand.extractHere, .extractFolder, .extractTo] {
                var asked = false
                try provider.receive(FinderHandoff(command: command, archive: archive).url) { request in
                    asked = true
                    XCTAssertEqual(request.archive, archive)
                    return false
                }
                XCTAssertTrue(asked)
                XCTAssertFalse(provider.isBusy)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Example.zip"])
            }
            let link = root.appendingPathComponent("link.zip")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archive)
            XCTAssertThrowsError(try provider.receive(FinderHandoff(command: .extractHere, archive: link).url) { _ in
                XCTFail("Invalid requests must fail before consent"); return true
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
