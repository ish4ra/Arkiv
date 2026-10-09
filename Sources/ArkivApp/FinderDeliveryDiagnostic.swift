import AppKit
import ArkivCore

/// Read-only CI mode for testing actual Launch Services URL delivery to this app.
/// It cannot enable extraction: extraction dispatch is intercepted. No production IPC uses it.
final class FinderDeliveryDiagnostic {
    static let notification = Notification.Name("xyz.isharalakshan.arkiv.finder-delivery-diagnostic")
    private let nonce: String

    static func fromArguments(_ arguments: [String] = CommandLine.arguments) -> FinderDeliveryDiagnostic? {
        guard (arguments.count == 3 || (arguments.count == 4 && arguments[3] == "--finder-action")), arguments[1] == "--verify-finder-url-delivery",
              UUID(uuidString: arguments[2]) != nil else { return nil }
        return FinderDeliveryDiagnostic(nonce: arguments[2])
    }

    private init(nonce: String) {
        self.nonce = nonce
        // Stop the isolated read-only probe if its launcher disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { exit(1) }
    }

    func record(_ action: FinderAction) {
        recordCommand(action.rawValue)
    }
    func recordCommand(_ command: String, browserWindows: Int? = nil) {
        var info: [String: Any] = ["command": command]
        if let browserWindows { info["browserWindows"] = browserWindows }
        DistributedNotificationCenter.default().postNotificationName(Self.notification,
            object: nonce, userInfo: info, deliverImmediately: true)
    }
}
