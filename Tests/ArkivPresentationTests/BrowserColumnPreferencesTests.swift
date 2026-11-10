import Foundation
import XCTest
@testable import ArkivPresentation

final class BrowserColumnPreferencesTests: XCTestCase {
    func testPersistenceNameInvariantAndInvalidWidths() throws {
        let suite = "Arkiv.Columns.Tests.\(UUID())"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let p = BrowserColumnPreferences(defaults: store)
        XCTAssertFalse(p.isHidden("size"))
        p.setHidden(true, for: "name")
        p.setHidden(true, for: "size")
        p.setWidth(245, for: "size")
        let reopened = BrowserColumnPreferences(defaults: store)
        XCTAssertFalse(reopened.isHidden("name"))
        XCTAssertTrue(reopened.isHidden("size"))
        XCTAssertEqual(reopened.width("size", fallback: 110, minimum: 80), 245)
        for width in [Double.nan, .infinity, -1, 2000] { p.setWidth(width, for: "size") }
        XCTAssertEqual(reopened.width("size", fallback: 110, minimum: 80), 245)
        store.set(-10, forKey: "Arkiv.Browser.Columns.v1.size.width")
        XCTAssertEqual(reopened.width("size", fallback: 110, minimum: 80), 110)
    }
}
