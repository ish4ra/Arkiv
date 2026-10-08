import Foundation

/// User choice is independent of extension status. Never treats a settings click
/// as permission, and never re-prompts users who dismissed or previously enabled.
public final class FinderSetupPreferences {
    private let defaults: UserDefaults
    private let dismissedKey = "finderIntegration.setupDismissed.v1"
    private let enabledKey = "finderIntegration.wasEnabled.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func shouldPresent(enabled: Bool) -> Bool {
        record(enabled: enabled)
        return !enabled && !defaults.bool(forKey: dismissedKey) && !defaults.bool(forKey: enabledKey)
    }

    public func record(enabled: Bool) {
        if enabled { defaults.set(true, forKey: enabledKey) }
    }

    public func dismiss() { defaults.set(true, forKey: dismissedKey) }

    public static func manualPath(majorVersion: Int) -> String {
        if majorVersion >= 15 {
            return "System Settings → General → Login Items & Extensions\n→ Extensions → Finder → enable “Arkiv Finder”"
        }
        return "System Settings → Privacy & Security → Extensions\n→ Finder Extensions → enable “Arkiv Finder”"
    }
}
