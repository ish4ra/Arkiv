import Foundation
import XCTest
@testable import ArkivPresentation

final class AppPreferencesTests: XCTestCase {
    func testDarkDefaultAndAllAppearanceChoicesPersistInIsolatedStore() throws {
        let name = "Arkiv.Settings.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, .dark)
        for choice in AppAppearance.allCases {
            preferences.appearance = choice
            XCTAssertEqual(AppPreferences(defaults: defaults).appearance, choice)
        }
    }
}
