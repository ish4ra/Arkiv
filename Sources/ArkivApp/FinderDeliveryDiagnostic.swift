import AppKit
import ArkivCore

/// Read-only CI mode for testing actual Launch Services URL delivery to this app.
/// It cannot enable extraction: consent is always refused. No production IPC uses it.
final class FinderDeliveryDiagnostic {
    static let notification = Notification.Name("xyz.isharalakshan.arkiv.finder-delivery-diagnostic")
    private let nonce: String
    private var commands: Set<String> = []

    static func fromArguments(_ arguments: [String] = CommandLine.arguments) -> FinderDeliveryDiagnostic? {
        guard arguments.count == 3, arguments[1] == "--verify-finder-url-delivery",
              UUID(uuidString: arguments[2]) != nil else { return nil }
        return FinderDeliveryDiagnostic(nonce: arguments[2])
    }

    private init(nonce: String) { self.nonce = nonce }

    func record(_ action: FinderAction) {
        commands.insert(action.rawValue)
        DistributedNotificationCenter.default().postNotificationName(Self.notification,
            object: nonce, userInfo: ["command": action.rawValue], deliverImmediately: true)
        if commands.count == FinderAction.allCases.count {
            // The isolated probe performs only browsing/validation, never extraction.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }
    }
}
