import Foundation

public extension Notification.Name {
    /// Posted on the main thread when the selected document icon theme changes.
    static let arkivDocumentIconThemeDidChange = Notification.Name("ArkivDocumentIconThemeDidChange")
}

public enum ThemeSelection: Equatable, Sendable {
    case bundled
    case installed(id: String, version: Int)
}

public struct InstalledTheme: Equatable, Sendable {
    public let id: String
    public let version: Int
    public let name: String
    public let directory: URL
    public let manifest: ThemeManifest
    public var installedSize: Int { manifest.files.reduce(0) { $0 + $1.size } }
}

/// Optional themes live outside the signed app bundle:
///
///     ~/Library/Application Support/Arkiv/DocumentIconThemes/
///         catalog.json          last verified catalogue envelope
///         <id>/<version>/       installed, verified, read-only
///         .staging/<uuid>/      in-progress work; never read as a theme
///         .trash/<uuid>/        replaced or removed themes awaiting deletion
///
/// Previews of themes that are not installed are cached under
/// ~/Library/Caches/Arkiv/DocumentIconThemePreviews and may be purged by macOS.
public final class ThemeStore: @unchecked Sendable {
    public let root: URL
    public let previewRoot: URL
    private let defaults: UserDefaults
    private let lock = NSLock()
    private enum Key {
        static let selection = "Arkiv.DocumentIconTheme"
        static let catalogVersion = "Arkiv.DocumentIconThemeCatalogVersion"
    }

    public static func standardRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Arkiv/DocumentIconThemes", isDirectory: true)
    }
    public static func standardPreviewRoot() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return base.appendingPathComponent("Arkiv/DocumentIconThemePreviews", isDirectory: true)
    }
    public static let shared = ThemeStore(root: standardRoot(), previewRoot: standardPreviewRoot(), defaults: .standard)

    public init(root: URL, previewRoot: URL, defaults: UserDefaults) {
        self.root = root.standardizedFileURL; self.previewRoot = previewRoot.standardizedFileURL; self.defaults = defaults
    }

    var staging: URL { root.appendingPathComponent(".staging", isDirectory: true) }
    var trash: URL { root.appendingPathComponent(".trash", isDirectory: true) }
    var catalogFile: URL { root.appendingPathComponent("catalog.json") }

    // MARK: Selection

    /// Never touches the file system; resolving it is the icon provider's job.
    public var selection: ThemeSelection {
        get {
            guard let value = defaults.dictionary(forKey: Key.selection), let id = value["id"] as? String,
                  let version = value["version"] as? Int, ThemeText.validID(id), version > 0 else { return .bundled }
            return .installed(id: id, version: version)
        }
        set {
            switch newValue {
            case .bundled: defaults.removeObject(forKey: Key.selection)
            case .installed(let id, let version): defaults.set(["id": id, "version": version], forKey: Key.selection)
            }
        }
    }

    // MARK: Layout and recovery

    /// Creates the folders and removes leftovers of interrupted work. Called
    /// when the theme pane opens or a download starts, never at launch.
    public func prepare() throws {
        let manager = FileManager.default
        lock.lock(); defer { lock.unlock() }
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for folder in [staging, trash] {
            if manager.fileExists(atPath: folder.path) { try Self.removeTree(folder) }
            try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        try manager.createDirectory(at: previewRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// A private folder for one download and its validation.
    func makeStagingDirectory() throws -> URL {
        let manager = FileManager.default
        if !manager.fileExists(atPath: staging.path) {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let directory = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory
    }

    public func directory(id: String, version: Int) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent(String(version), isDirectory: true)
    }

    /// Installed themes whose manifest is structurally valid. Damaged folders
    /// are skipped, so they can never be selected or drawn.
    public func installedThemes() -> [InstalledTheme] {
        let manager = FileManager.default
        guard let ids = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        var result = [InstalledTheme]()
        for id in ids.sorted() where ThemeText.validID(id) && id != DocumentIconThemeID.bundled {
            let themeRoot = root.appendingPathComponent(id, isDirectory: true)
            guard (try? manager.attributesOfItem(atPath: themeRoot.path))?[.type] as? FileAttributeType == .typeDirectory,
                  let versions = try? manager.contentsOfDirectory(atPath: themeRoot.path) else { continue }
            for text in versions {
                guard let version = Int(text), version > 0, String(version) == text,
                      let theme = loadInstalled(id: id, version: version) else { continue }
                result.append(theme)
            }
        }
        return result
    }

    public func loadInstalled(id: String, version: Int) -> InstalledTheme? {
        let directory = directory(id: id, version: version)
        // Neither the theme folder nor its version folder may be a link.
        guard (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(id).path))?[.type] as? FileAttributeType == .typeDirectory,
              let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let data = try? ThemePackValidator.read(directory.appendingPathComponent("theme.json"), limit: ThemeLimits.manifestBytes),
              let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: data),
              manifest.id == id, manifest.version == version,
              (try? ThemePackValidator.check(manifest, against: nil)) != nil,
              let files = try? ThemePackValidator.regularFiles(in: directory),
              Set(files.keys) == Set(manifest.files.map(\.path)).union(["theme.json"]),
              manifest.files.allSatisfy({ files[$0.path] == $0.size }) else { return nil }
        return InstalledTheme(id: id, version: version, name: manifest.name, directory: directory, manifest: manifest)
    }

    /// Publishes a validated directory with one atomic rename. An existing
    /// folder for the same version is moved aside first, then deleted, so a
    /// reader sees either the old or the new complete theme, never a mixture.
    func publish(_ validated: URL, id: String, version: Int) throws -> InstalledTheme {
        let manager = FileManager.default
        lock.lock(); defer { lock.unlock() }
        let parent = root.appendingPathComponent(id, isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory(id: id, version: version)
        var aside: URL?
        if manager.fileExists(atPath: destination.path) {
            try manager.createDirectory(at: trash, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let moved = trash.appendingPathComponent(UUID().uuidString, isDirectory: true)
            guard rename(destination.path, moved.path) == 0 else { throw ThemeError.packRejected("the previous copy could not be replaced.") }
            aside = moved
        }
        guard rename(validated.path, destination.path) == 0 else {
            if let aside { _ = rename(aside.path, destination.path) }
            throw ThemeError.packRejected("it could not be installed.")
        }
        if let aside { try? Self.removeTree(aside) }
        guard let theme = loadInstalledUnlocked(id: id, version: version) else {
            throw ThemeError.packRejected("it could not be read after installation.")
        }
        return theme
    }
    private func loadInstalledUnlocked(id: String, version: Int) -> InstalledTheme? { loadInstalled(id: id, version: version) }

    /// Removes every installed version of `id`. The caller makes sure it is not selected.
    func remove(id: String) throws {
        let manager = FileManager.default
        lock.lock(); defer { lock.unlock() }
        guard ThemeText.validID(id), id != DocumentIconThemeID.bundled else { throw ThemeError.notInstalled }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        guard manager.fileExists(atPath: folder.path) else { throw ThemeError.notInstalled }
        try manager.createDirectory(at: trash, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let moved = trash.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard rename(folder.path, moved.path) == 0 else { throw ThemeError.packRejected("it could not be removed.") }
        try Self.removeTree(moved)
    }

    /// Removes older versions after a newer one of the same theme is installed.
    func removeVersions(of id: String, except keep: Int) {
        let folder = root.appendingPathComponent(id, isDirectory: true)
        for text in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where text != String(keep) {
            try? Self.removeTree(folder.appendingPathComponent(text, isDirectory: true))
        }
    }

    /// Validated files are read-only; restore write permission so they can be deleted.
    static func removeTree(_ url: URL) throws {
        let manager = FileManager.default
        if let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
            for case let item as URL in enumerator {
                if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: item.path)
            }
        }
        try manager.removeItem(at: url)
    }

    // MARK: Last-known-good catalogue

    var highestCatalogVersion: Int {
        get { defaults.integer(forKey: Key.catalogVersion) }
        set { defaults.set(newValue, forKey: Key.catalogVersion) }
    }

    func cachedCatalogEnvelope() -> Data? {
        try? ThemePackValidator.read(catalogFile, limit: ThemeLimits.catalogBytes)
    }

    func saveCatalog(_ catalog: VerifiedCatalog) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try catalog.envelope.write(to: catalogFile, options: .atomic)
        highestCatalogVersion = max(highestCatalogVersion, catalog.catalog.catalogVersion)
    }

    func discardCachedCatalog() { try? FileManager.default.removeItem(at: catalogFile) }

    // MARK: Preview cache

    func previewDirectory(id: String, version: Int) -> URL {
        previewRoot.appendingPathComponent("\(id)-\(version)", isDirectory: true)
    }

    func publishPreview(_ validated: URL, id: String, version: Int) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: previewRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = previewDirectory(id: id, version: version)
        if manager.fileExists(atPath: destination.path) { try Self.removeTree(destination) }
        guard rename(validated.path, destination.path) == 0 else { throw ThemeError.packRejected("its preview could not be stored.") }
        return destination
    }
}
