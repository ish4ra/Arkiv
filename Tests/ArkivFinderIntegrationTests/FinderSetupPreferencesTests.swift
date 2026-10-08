import Foundation
import XCTest
@testable import ArkivFinderIntegration

final class FinderSetupPreferencesTests: XCTestCase {
    func testNotNowPersistsAcrossLaunchesButDoesNotPretendEnabled() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = FinderSetupPreferences(defaults: defaults)
        XCTAssertTrue(first.shouldPresent(enabled: false))
        first.dismiss()
        XCTAssertFalse(FinderSetupPreferences(defaults: defaults).shouldPresent(enabled: false))
    }

    func testEnabledAndLaterDisabledDoNotNagAgain() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = FinderSetupPreferences(defaults: defaults)
        XCTAssertFalse(first.shouldPresent(enabled: true))
        XCTAssertFalse(FinderSetupPreferences(defaults: defaults).shouldPresent(enabled: false))
    }

    func testCorrectSettingsPathsForSupportedVersions() {
        for version in [13, 14] {
            XCTAssertTrue(FinderSetupPreferences.manualPath(majorVersion: version).contains("Privacy & Security"))
            XCTAssertTrue(FinderSetupPreferences.manualPath(majorVersion: version).contains("Finder Extensions"))
        }
        for version in [15, 26] {
            XCTAssertTrue(FinderSetupPreferences.manualPath(majorVersion: version).contains("Login Items & Extensions"))
            XCTAssertTrue(FinderSetupPreferences.manualPath(majorVersion: version).contains("→ Extensions → Finder"))
        }
    }
}
