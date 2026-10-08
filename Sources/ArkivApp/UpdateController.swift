import AppKit
import Sparkle

/// Sparkle owns transport, signature verification, installation and relaunch.
/// A keyless developer checkout must not accidentally trust a different publisher.
final class UpdateController: NSObject, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func addMenuItems(to menu: NSMenu) {
        let check = menu.addItem(withTitle: "Check for Updates…", action: #selector(unconfigured(_:)), keyEquivalent: "")
        if let controller {
            check.target = controller
            check.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        } else {
            check.target = self
        }
        let automatic = menu.addItem(withTitle: "Automatically Check for Updates", action: #selector(toggleAutomatic(_:)), keyEquivalent: "")
        automatic.target = self
    }

    @objc private func unconfigured(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Updates are not configured in this build"
        alert.informativeText = "Install a development build containing Arkiv’s update signing public key. See the updater setup documentation in the Arkiv repository."
        alert.runModal()
    }

    @objc private func toggleAutomatic(_ sender: Any?) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomatic(_:)) {
            menuItem.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
            return controller != nil
        }
        return true
    }
}
