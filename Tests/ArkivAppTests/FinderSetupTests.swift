import AppKit
import XCTest
import ArkivFinderIntegration
@testable import ArkivApp

final class FinderSetupTests: XCTestCase {
    func testSettingsClickDoesNotGrantPermissionAndRefreshReflectsActualStatus() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let name = UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            var enabled = false
            var openedSettings = false
            let controller = FinderSetupWindowController(preferences: FinderSetupPreferences(defaults: defaults),
                enabled: { enabled }, openSettings: { openedSettings = true })
            defer { controller.close() }
            XCTAssertFalse(controller.isEnabled)
            controller.openExtensionSettings(nil)
            XCTAssertTrue(openedSettings)
            XCTAssertFalse(controller.isEnabled)
            enabled = true
            controller.refresh()
            XCTAssertTrue(controller.isEnabled)
            enabled = false
            controller.refresh()
            XCTAssertFalse(controller.isEnabled)
            controller.dismissSetup(nil)
            XCTAssertFalse(controller.presentIfNeeded())
            controller.showSetup() // Manual management remains available after dismissal.
            XCTAssertTrue(controller.window?.isVisible == true)
        }
    }
}
