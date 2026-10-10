import Foundation
import XCTest
@testable import ArkivFinderIntegration

final class FinderActionRelayTests: XCTestCase {
    func testAllScalarActionsRouteWithoutRepresentedObject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("日本語 & #?%.zip")
        try Data().write(to: archive)
        let app = URL(fileURLWithPath: "/Applications/Arkiv.app", isDirectory: true)
        let ext = app.appendingPathComponent("Contents/PlugIns/ArkivFinderSync.appex", isDirectory: true)
        var received: [FinderCommand] = []
        let relay = FinderActionRelay(home: root, extensionURL: ext,
            identifier: { candidate in XCTAssertEqual(candidate, app); return "xyz.isharalakshan.arkiv" },
            transport: { url, target, completion in
                XCTAssertEqual(target, app)
                do {
                    let request = try FinderHandoff(url: url)
                    XCTAssertEqual(request.archive, archive)
                    received.append(request.command)
                } catch { XCTFail("Invalid routed URL: \(error)") }
                completion(nil)
            }, failure: { XCTFail("Unexpected failure: \($0)") })
        for command in FinderCommand.allCases { relay.perform(tag: command.menuTag, selectedURLs: [archive]) }
        XCTAssertEqual(received, FinderCommand.allCases)
    }

    func testEveryPreflightFailureIsSurfacedAndNeverLaunches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("a.tar")
        try Data().write(to: archive)
        let ext = URL(fileURLWithPath: "/Applications/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex")
        var failures = 0
        func relay(home: URL?, bundle: URL = ext, identifier: String? = "xyz.isharalakshan.arkiv") -> FinderActionRelay {
            FinderActionRelay(home: home, extensionURL: bundle, identifier: { _ in identifier },
                transport: { _, _, _ in XCTFail("Must not launch") }, failure: { _ in failures += 1 })
        }
        relay(home: root).perform(tag: 99, selectedURLs: [archive])
        relay(home: nil).perform(tag: 1, selectedURLs: [archive])
        relay(home: root).perform(tag: 1, selectedURLs: [])
        relay(home: root).perform(tag: 1, selectedURLs: [archive, archive])
        relay(home: root, bundle: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")).perform(tag: 1, selectedURLs: [archive])
        relay(home: root, identifier: nil).perform(tag: 1, selectedURLs: [archive])
        XCTAssertEqual(failures, 6)
    }

    func testTransportFailureIsSurfacedWithUnderlyingError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("a.zip")
        try Data().write(to: archive)
        var reported: NSError?
        let relay = FinderActionRelay(home: root,
            extensionURL: URL(fileURLWithPath: "/Applications/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex"),
            identifier: { _ in "xyz.isharalakshan.arkiv" },
            transport: { _, _, completion in completion(NSError(domain: NSOSStatusErrorDomain, code: -10814)) },
            failure: { reported = $0 as NSError })
        relay.perform(tag: 1, selectedURLs: [archive])
        XCTAssertEqual(reported?.domain, NSOSStatusErrorDomain)
        XCTAssertEqual(reported?.code, -10814)
    }
}
