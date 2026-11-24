import AppKit

/// Supplies document icons for Arkiv's own windows from the selected theme.
///
/// * Nothing is read until an icon is first requested, and only the
///   representations for the requested point size are loaded.
/// * Installed theme files are checked against their manifest's size and
///   SHA-256 each time they are read; a damaged theme falls back to the
///   bundled family and is reported through `damagedTheme`.
/// * Images live in a cost-bounded NSCache, emptied when the selection changes.
/// * Finder is unaffected: it keeps reading the ICNS files in Arkiv.app.
public final class DocumentIconProvider {
    public static let shared = DocumentIconProvider(store: .shared,
        bundledIcon: { Bundle.main.url(forResource: "Arkiv-\($0.rawValue)", withExtension: "icns") },
        bundledExtra: DocumentIconProvider.bundledExtraFolder)

    /// In-app-only artwork of the bundled Seal Dark family for compound
    /// suffixes and split 7z volumes (16 pt and 128 pt tiers). Finder never
    /// uses these: it cannot tell `.tar.xz` from `.xz`.
    public static func bundledExtraFolder(_ extra: DocumentIconExtra) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("DocumentIconsInApp/Arkiv-\(extra.rawValue)", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    /// Representations bundled for each in-app extra.
    public static let bundledExtraTiers = [16, 128]

    private let store: ThemeStore
    private let bundledIcon: (DocumentIconName) -> URL?
    private let bundledExtra: (DocumentIconExtra) -> URL?
    private let cache = NSCache<NSString, NSImage>()
    private var active: InstalledTheme?
    private var resolved = false
    public private(set) var damagedTheme: String?

    public init(store: ThemeStore, bundledIcon: @escaping (DocumentIconName) -> URL?,
                bundledExtra: @escaping (DocumentIconExtra) -> URL? = { _ in nil }) {
        self.store = store; self.bundledIcon = bundledIcon; self.bundledExtra = bundledExtra
        cache.countLimit = 96
        cache.totalCostLimit = 12 << 20
    }

    /// The theme being drawn, after falling back from a missing or damaged selection.
    public var effectiveSelection: ThemeSelection {
        resolve()
        return active.map { .installed(id: $0.id, version: $0.version) } ?? .bundled
    }

    /// Call after the stored selection changes; posts the change notification.
    public func selectionDidChange() {
        cache.removeAllObjects()
        active = nil; resolved = false; damagedTheme = nil
        NotificationCenter.default.post(name: .arkivDocumentIconThemeDidChange, object: self)
    }

    /// The selected theme's icon for an archive file name, or nil when Arkiv
    /// has no document icon for it (the caller keeps the system icon).
    public func icon(forFileName name: String, points: CGFloat = 16) -> NSImage? {
        DocumentIconArtwork.forFileName(name).flatMap { icon($0, points: points) }
    }

    /// Compound and volume artwork when the theme has it, otherwise the
    /// family's Finder icon (a theme without that icon keeps the system icon).
    public func icon(_ artwork: DocumentIconArtwork, points: CGFloat) -> NSImage? {
        switch artwork {
        case .icon(let name): return icon(name, points: points)
        case .extra(let extra): return extraIcon(extra, points: points) ?? icon(extra.fallback, points: points)
        }
    }

    private func extraIcon(_ extra: DocumentIconExtra, points: CGFloat) -> NSImage? {
        resolve()
        let key = "\(active?.id ?? DocumentIconThemeID.bundled)/extra/\(extra.rawValue)/\(points)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: NSImage?
        if let theme = active {
            guard let reps = theme.manifest.extras[extra.rawValue] else { return nil }
            image = load(reps, from: theme, tier: IconRepresentation.tier(for: points), points: points)
            if image == nil { markDamaged(theme); return extraIcon(extra, points: points) }
        } else {
            image = bundledExtra(extra).flatMap { Self.loadBundledExtra(from: $0, points: points) }
        }
        if let image { cache.setObject(image, forKey: key, cost: Int(points * points * 4 * 5)) }
        return image
    }

    /// The smallest bundled tier that covers `points`, at 1x and 2x.
    static func loadBundledExtra(from folder: URL, points: CGFloat, scales: [Int] = [1, 2]) -> NSImage? {
        let tier = bundledExtraTiers.first { CGFloat($0) >= points } ?? bundledExtraTiers.last!
        let image = NSImage(size: NSSize(width: points, height: points))
        for scale in scales {
            let rep = IconRepresentation(points: tier, scale: scale)
            guard let data = try? ThemePackValidator.read(folder.appendingPathComponent(rep.fileName), limit: ThemeLimits.fileBytes),
                  let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide == rep.pixels, bitmap.pixelsHigh == rep.pixels else { return nil }
            bitmap.size = NSSize(width: points, height: points)
            image.addRepresentation(bitmap)
        }
        return image
    }

    /// The bundled extra's own 128 px artwork, for the Settings preview.
    func bundledExtraPreview(_ extra: DocumentIconExtra) -> NSImage? {
        bundledExtra(extra).flatMap { Self.loadBundledExtra(from: $0, points: 128, scales: [1, 2]) }
    }

    /// nil when the active theme has no artwork for `name` (a partial theme)
    /// or the bundled resource is unavailable; callers then use the system icon.
    public func icon(_ name: DocumentIconName, points: CGFloat) -> NSImage? {
        resolve()
        let tier = IconRepresentation.tier(for: points)
        let key = "\(active?.id ?? DocumentIconThemeID.bundled)/\(name.rawValue)/\(tier)/\(points)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: NSImage?
        if let theme = active {
            guard let reps = theme.manifest.icons[name.rawValue] else { return nil }
            image = load(reps, from: theme, tier: tier, points: points)
            if image == nil { markDamaged(theme); return self.icon(name, points: points) }
        } else {
            image = bundledIcon(name).flatMap { NSImage(contentsOf: $0) }
            image?.size = NSSize(width: points, height: points)
        }
        if let image { cache.setObject(image, forKey: key, cost: Int(points * points * 4 * 5)) }
        return image
    }

    /// The installed theme's own 128 px artwork for a preview, verified like any other read.
    func previewImage(_ artwork: DocumentIconArtwork, theme: InstalledTheme) -> NSImage? {
        let reps: [String: String]?
        switch artwork {
        case .icon(let name): reps = theme.manifest.icons[name.rawValue]
        case .extra(let extra): reps = theme.manifest.extras[extra.rawValue]
        }
        guard let reps else { return nil }
        return load(reps, from: theme, tier: 128, points: 128, scales: [1])
    }

    private func resolve() {
        guard !resolved else { return }
        resolved = true
        if case .installed(let id, let version) = store.selection {
            active = store.loadInstalled(id: id, version: version)
            if active == nil { damagedTheme = id }
        }
    }

    private func markDamaged(_ theme: InstalledTheme) {
        damagedTheme = theme.id
        active = nil
        cache.removeAllObjects()
    }

    private func load(_ reps: [String: String], from theme: InstalledTheme, tier: Int, points: CGFloat, scales: [Int] = [1, 2]) -> NSImage? {
        let files = Dictionary(uniqueKeysWithValues: theme.manifest.files.map { ($0.path, $0) })
        let image = NSImage(size: NSSize(width: points, height: points))
        for scale in scales {
            let rep = IconRepresentation(points: tier, scale: scale)
            guard let path = reps[rep.fileName], let file = files[path],
                  let data = try? ThemePackValidator.read(theme.directory.appendingPathComponent(path), limit: ThemeLimits.fileBytes),
                  data.count == file.size, ThemeHash.sha256(data) == file.sha256,
                  let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide == rep.pixels, bitmap.pixelsHigh == rep.pixels else { return nil }
            bitmap.size = NSSize(width: points, height: points)
            image.addRepresentation(bitmap)
        }
        return image
    }
}
