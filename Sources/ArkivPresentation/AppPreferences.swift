import Foundation

public enum AppAppearance: String, CaseIterable {
    case system, light, dark
}

/// Accent used by Arkiv's own selection highlights and primary buttons.
/// `system` follows the macOS accent colour; the others are drawn from the
/// Tension Seal palette. Standard system controls (checkboxes, switches,
/// focus rings) always follow macOS.
public enum AppAccent: String, CaseIterable {
    case arkiv, jade, brass, graphite, system

    public var title: String {
        switch self {
        case .arkiv: return "Arkiv Wine"
        case .jade: return "Jade"
        case .brass: return "Brass"
        case .graphite: return "Graphite"
        case .system: return "System"
        }
    }
}

/// Archive table row density. The document icon size follows the density, so
/// rows and artwork stay in proportion without a separate setting. Compact and
/// Standard use 16 pt, the artwork's dedicated hand-tuned small tier.
public enum BrowserDensity: String, CaseIterable {
    case compact, standard, comfortable

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .comfortable: return "Comfortable"
        }
    }
    public var rowHeight: Double {
        switch self { case .compact: return 20; case .standard: return 26; case .comfortable: return 34 }
    }
    public var iconSize: Double {
        switch self { case .compact: return 16; case .standard: return 16; case .comfortable: return 24 }
    }
    public var fontSize: Double {
        switch self { case .compact: return 12; case .standard: return 13; case .comfortable: return 13 }
    }
}

public extension Notification.Name {
    /// Posted (object: the AppPreferences) after any appearance or browser
    /// presentation preference changes, so every open window updates at once.
    static let arkivAppearancePreferencesDidChange = Notification.Name("ArkivAppearancePreferencesDidChange")
}

/// Application preferences only. Sparkle and NSDocumentController retain ownership
/// of update consent and recent documents respectively.
///
/// Keys are stable. `Arkiv.Appearance` predates the redesign and keeps its
/// meaning and values; the newer keys are optional, so an existing install
/// keeps its appearance and gets the defaults for everything else. Unknown or
/// malformed stored values fall back to the default without being rewritten.
public final class AppPreferences {
    private let defaults: UserDefaults
    enum Key {
        static let appearance = "Arkiv.Appearance"
        static let accent = "Arkiv.Accent"
        static let density = "Arkiv.Browser.Density"
        static let alternatingRows = "Arkiv.Browser.AlternatingRows"
    }
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var appearance: AppAppearance {
        get { defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); changed() }
    }
    public var accent: AppAccent {
        get { defaults.string(forKey: Key.accent).flatMap(AppAccent.init(rawValue:)) ?? .arkiv }
        set { defaults.set(newValue.rawValue, forKey: Key.accent); changed() }
    }
    public var density: BrowserDensity {
        get { defaults.string(forKey: Key.density).flatMap(BrowserDensity.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Key.density); changed() }
    }
    public var alternatingRows: Bool {
        get { (defaults.object(forKey: Key.alternatingRows) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.alternatingRows); changed() }
    }
    /// True when every appearance preference already has its default value.
    public var isDefault: Bool {
        appearance == .dark && accent == .arkiv && density == .standard && !alternatingRows
    }
    /// Restore Defaults: removes the stored values (dark, Arkiv accent,
    /// standard density, plain rows). The document icon theme, recent
    /// archives, column layout and update consent are not touched.
    public func restoreAppearanceDefaults() {
        for key in [Key.appearance, Key.accent, Key.density, Key.alternatingRows] { defaults.removeObject(forKey: key) }
        changed()
    }
    private func changed() {
        NotificationCenter.default.post(name: .arkivAppearancePreferencesDidChange, object: self)
    }
}
