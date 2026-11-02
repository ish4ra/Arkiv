import AppKit
import XCTest
import ArkivPresentation
@testable import ArkivApp

private final class SettingsUpdaterDriver: NSObject, UpdaterMenuDriver {
    var automaticallyChecksForUpdates = true
    var checkTarget: AnyObject { self }
    var checkAction: Selector { #selector(check(_:)) }
    var checks = 0
    @objc func check(_ sender: Any?) { checks += 1 }
}

final class SettingsTests: XCTestCase {
    @MainActor
    func testReusableSettingsMenuAppearanceAndExistingActions() async throws {
        _ = NSApplication.shared
        let name = "Arkiv.Settings.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let oldAppearance = NSApp.appearance
        let oldMenu = NSApp.mainMenu
        let oldWindowsMenu = NSApp.windowsMenu
        defer {
            defaults.removePersistentDomain(forName: name)
            NSApp.appearance = oldAppearance
            NSApp.mainMenu = oldMenu; NSApp.windowsMenu = oldWindowsMenu
        }
        let preferences = AppPreferences(defaults: defaults)
        preferences.appearance.apply()
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        let driver = SettingsUpdaterDriver()
        let updates = UpdateController(publicKey: { Data(repeating: 1, count: 32).base64EncodedString() }, makeDriver: { driver })
        var clears = 0, finderShows = 0
        let recents = RecentArchives(urls: { [] }, note: { _ in XCTFail("Must not record history") }, clear: { clears += 1 })
        let delegate = AppDelegate(updates: updates, launchArguments: ["Arkiv", "--finder-action"], presentFinderSetup: {}, recents: recents, preferences: preferences)
        delegate.buildMenus()
        let menu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        let item = try XCTUnwrap(menu.items.first { $0.title == "Settings…" })
        XCTAssertEqual(item.keyEquivalent, ",")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        XCTAssertTrue(NSApp.sendAction(item.action!, to: item.target, from: item))
        let first = try XCTUnwrap(delegate.settings.window)
        defer { first.close() }
        delegate.showSettings(nil)
        XCTAssertTrue(first === delegate.settings.window)
        first.close(); delegate.showSettings(nil)
        XCTAssertTrue(first === delegate.settings.window)

        let controller = SettingsWindowController(preferences: preferences, recents: recents, updates: updates, showFinder: { finderShows += 1 })
        defer { controller.close() }
        controller.present()
        let owned = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        owned.isReleasedWhenClosed = false
        defer { owned.close() }
        for (choice, expected) in [(AppAppearance.dark, NSAppearance.Name.darkAqua), (.light, .aqua)] {
            controller.appearancePicker.selectItem(at: AppAppearance.allCases.firstIndex(of: choice)!)
            controller.changeAppearance(nil)
            XCTAssertEqual(preferences.appearance, choice)
            XCTAssertEqual(NSApp.appearance?.name, expected)
            XCTAssertEqual(owned.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
        }
        controller.appearancePicker.selectItem(at: 0)
        controller.changeAppearance(nil)
        XCTAssertNil(NSApp.appearance)
        controller.clearRecents(nil); XCTAssertEqual(clears, 1)
        controller.openFinder(nil); XCTAssertEqual(finderShows, 1)
        controller.checkUpdates(nil); XCTAssertEqual(driver.checks, 1)
        controller.automaticChecks.state = .off
        controller.changeAutomaticChecks(nil)
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        driver.automaticallyChecksForUpdates = true
        controller.refresh()
        XCTAssertEqual(controller.automaticChecks.state, .on)
        XCTAssertTrue(controller.automaticChecks.isEnabled)
        let automaticMenuItem = try XCTUnwrap(menu.items.first { $0.title == "Automatically Check for Updates" })
        XCTAssertTrue(NSApp.sendAction(automaticMenuItem.action!, to: automaticMenuItem.target, from: automaticMenuItem))
        XCTAssertEqual(controller.automaticChecks.state, .off, "Menu changes must update the already-open Settings window")
    }

    @MainActor
    func testKeylessSettingsDoesNotInventAutomaticCheckPreference() async {
        _ = NSApplication.shared
        let updates = UpdateController(publicKey: { nil }, makeDriver: { XCTFail("Keyless build"); return SettingsUpdaterDriver() })
        updates.start()
        XCTAssertNil(updates.automaticChecks)
        updates.automaticChecks = true
        XCTAssertNil(updates.automaticChecks)
    }
}
