import Foundation

/// Versioned presentation preferences, with no archive paths or contents.
public final class BrowserColumnPreferences {
    private let defaults: UserDefaults
    private let prefix = "Arkiv.Browser.Columns.v1."
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func isHidden(_ id: String) -> Bool {
        id != "name" && defaults.bool(forKey: prefix + id + ".hidden")
    }
    public func setHidden(_ hidden: Bool, for id: String) {
        guard id != "name" else { return }
        defaults.set(hidden, forKey: prefix + id + ".hidden")
    }
    public func width(_ id: String, fallback: Double, minimum: Double) -> Double {
        guard let number = defaults.object(forKey: prefix + id + ".width") as? NSNumber else { return fallback }
        let value = number.doubleValue
        return value.isFinite && value >= minimum && value <= 1600 ? value : fallback
    }
    public func setWidth(_ width: Double, for id: String) {
        guard width.isFinite, width >= 40, width <= 1600 else { return }
        defaults.set(width, forKey: prefix + id + ".width")
    }
}
