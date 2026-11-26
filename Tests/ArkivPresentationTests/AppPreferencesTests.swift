import Foundation
import XCTest
@testable import ArkivPresentation

final class AppPreferencesTests: XCTestCase {
    private func isolated() throws -> (UserDefaults, () -> Void) {
        let name = "Arkiv.Settings.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    func testDarkDefaultAndAllAppearanceChoicesPersistInIsolatedStore() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, .dark)
        for choice in AppAppearance.allCases {
            preferences.appearance = choice
            XCTAssertEqual(AppPreferences(defaults: defaults).appearance, choice)
        }
    }

    func testNewInstallDefaults() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.accent, .arkiv, "The original Arkiv accent is the default")
        XCTAssertEqual(preferences.density, .standard)
        XCTAssertFalse(preferences.alternatingRows)
        XCTAssertTrue(preferences.isDefault)
    }

    /// A build 30701 install stored only `Arkiv.Appearance`. Its choice must
    /// survive unchanged, the new keys must take their defaults, and reading
    /// must not write anything.
    func testMigrationFromPreRedesignPreferencesKeepsTheStoredAppearance() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        defaults.set("light", forKey: "Arkiv.Appearance")
        defaults.set(true, forKey: "Arkiv.Browser.Columns.v1.size.hidden")
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("Arkiv.") }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, .light)
        XCTAssertEqual(preferences.accent, .arkiv)
        XCTAssertEqual(preferences.density, .standard)
        XCTAssertFalse(preferences.alternatingRows)
        let after = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("Arkiv.") }
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after), "Reading preferences never rewrites them")
        XCTAssertTrue(BrowserColumnPreferences(defaults: defaults).isHidden("size"), "Column choices are untouched")
    }

    func testMalformedStoredValuesFallBackWithoutBeingDiscarded() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        defaults.set("sepia", forKey: "Arkiv.Appearance")
        defaults.set(42, forKey: "Arkiv.Accent")
        defaults.set("enormous", forKey: "Arkiv.Browser.Density")
        defaults.set("yes please", forKey: "Arkiv.Browser.AlternatingRows")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, .dark)
        XCTAssertEqual(preferences.accent, .arkiv)
        XCTAssertEqual(preferences.density, .standard)
        XCTAssertFalse(preferences.alternatingRows)
        XCTAssertEqual(defaults.string(forKey: "Arkiv.Appearance"), "sepia", "Unknown values are left for a future version")
    }

    func testEveryChoicePersistsAndNotifies() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        var notifications = 0
        let token = NotificationCenter.default.addObserver(forName: .arkivAppearancePreferencesDidChange, object: preferences, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        for accent in AppAccent.allCases {
            preferences.accent = accent
            XCTAssertEqual(AppPreferences(defaults: defaults).accent, accent)
        }
        for density in BrowserDensity.allCases {
            preferences.density = density
            XCTAssertEqual(AppPreferences(defaults: defaults).density, density)
        }
        preferences.alternatingRows = true
        XCTAssertTrue(AppPreferences(defaults: defaults).alternatingRows)
        XCTAssertEqual(notifications, AppAccent.allCases.count + BrowserDensity.allCases.count + 1)
        XCTAssertFalse(preferences.isDefault)
    }

    func testRestoreDefaultsResetsOnlyAppearanceKeys() throws {
        let (defaults, cleanup) = try isolated(); defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        preferences.appearance = .light; preferences.accent = .jade
        preferences.density = .compact; preferences.alternatingRows = true
        defaults.set(["id": "folio", "version": 1], forKey: "Arkiv.DocumentIconTheme")
        BrowserColumnPreferences(defaults: defaults).setWidth(240, for: "size")
        preferences.restoreAppearanceDefaults()
        XCTAssertTrue(preferences.isDefault)
        XCTAssertEqual(preferences.appearance, .dark)
        XCTAssertEqual(defaults.dictionary(forKey: "Arkiv.DocumentIconTheme")?["id"] as? String, "folio", "The document icon theme is not an appearance default")
        XCTAssertEqual(BrowserColumnPreferences(defaults: defaults).width("size", fallback: 110, minimum: 80), 240)
    }

    func testDensityMetricsAreOrderedAndFitTheirArtwork() {
        let metrics = BrowserDensity.allCases.map { ($0.rowHeight, $0.iconSize) }
        XCTAssertEqual(metrics.map(\.0), metrics.map(\.0).sorted())
        for (row, icon) in metrics { XCTAssertLessThanOrEqual(icon + 4, row, "Icons keep vertical breathing room") }
        XCTAssertEqual(BrowserDensity.standard.rowHeight, 26, "Standard keeps the existing 26 pt rows")
    }
}
