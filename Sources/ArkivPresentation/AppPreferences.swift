import Foundation

public enum AppAppearance: String, CaseIterable {
    case system, light, dark
}

/// Application preferences only. Sparkle and NSDocumentController retain ownership
/// of update consent and recent documents respectively.
public final class AppPreferences {
    private let defaults: UserDefaults
    private enum Key { static let appearance = "Arkiv.Appearance" }
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var appearance: AppAppearance {
        get { defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }
}
