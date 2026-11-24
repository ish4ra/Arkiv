import AppKit
import ArkivCore

/// Everything the theme manager needs from outside, so tests can supply
/// isolated keys, folders and a mocked network.
public struct ThemeEnvironment {
    public var store: ThemeStore
    public var verifier: ThemeCatalogVerifier
    public var catalogURL: URL?
    public var hosts: ThemeHostPolicy
    public var configuration: () -> URLSessionConfiguration

    public init(store: ThemeStore, verifier: ThemeCatalogVerifier, catalogURL: URL?, hosts: ThemeHostPolicy = .github,
                configuration: @escaping () -> URLSessionConfiguration = ThemeEnvironment.ephemeralConfiguration) {
        self.store = store; self.verifier = verifier; self.catalogURL = catalogURL; self.hosts = hosts; self.configuration = configuration
    }

    public static func ephemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// Public configuration embedded at build time (scripts/update-metadata.py).
    /// Without a theme key, downloads stay disabled; installed themes still work.
    public static func standard(bundle: Bundle = .main) -> ThemeEnvironment {
        let key = (bundle.object(forInfoDictionaryKey: "ArkivDocumentIconThemePublicEDKey") as? String).flatMap { Data(base64Encoded: $0) }
        let url = (bundle.object(forInfoDictionaryKey: "ArkivDocumentIconThemeCatalogURL") as? String).flatMap(URL.init(string:))
        let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        return ThemeEnvironment(store: .shared, verifier: ThemeCatalogVerifier(publicKeys: key.map { [$0] } ?? [], appBuild: build),
                                catalogURL: url?.scheme == "https" ? url : nil)
    }
}

public enum ThemeCatalogStatus: Equatable {
    case notConfigured
    case idle
    case loading
    case current
    /// The last verified catalogue is shown because the network request failed.
    case offline(String)
    case failed(String)
}

/// What Settings shows for one theme.
public enum ThemeEntryStatus: Equatable {
    case bundled
    case available
    case downloading(Double)
    case installing
    case installed
    case updateAvailable
    case unavailable(String)
}

/// One row in Settings: the bundled default, a catalogue theme, or an
/// installed theme no longer listed (it keeps working offline).
public struct ThemeEntry: Equatable {
    public let id: String
    public let name: String
    public let familyName: String
    public let kind: ThemeKind?
    public let summary: String
    public let variantOf: String?
    public let catalog: CatalogTheme?
    public let installed: InstalledTheme?
    public let status: ThemeEntryStatus
    public let isSelected: Bool
    public var downloadSize: Int? { catalog?.pack.size }
    public var installedSize: Int? { installed?.installedSize ?? catalog?.pack.installedSize }
    public var coverage: [DocumentIconName] {
        let names = catalog?.coverage ?? installed.map { Array($0.manifest.icons.keys) } ?? DocumentIconName.allCases.map(\.rawValue)
        return DocumentIconName.allCases.filter { names.contains($0.rawValue) }
    }
    /// Compound-suffix and volume artwork this theme has for Arkiv's own windows.
    public var extrasCoverage: [DocumentIconExtra] {
        let names = catalog?.extras ?? installed.map { Array($0.manifest.extras.keys) } ?? DocumentIconExtra.allCases.map(\.rawValue)
        return DocumentIconExtra.allCases.filter { names.contains($0.rawValue) }
    }
    /// Everything the Settings preview shows for this theme.
    public var previewArtwork: [DocumentIconArtwork] { coverage.map(DocumentIconArtwork.icon) + extrasCoverage.map(DocumentIconArtwork.extra) }
}

@MainActor
public final class DocumentIconThemeManager {
    public let environment: ThemeEnvironment
    public let provider: DocumentIconProvider
    public private(set) var catalog: VerifiedCatalog?
    public private(set) var catalogStatus: ThemeCatalogStatus
    public private(set) var installed: [InstalledTheme] = []
    public private(set) var lastError: [String: String] = [:]
    /// Called on the main thread whenever anything Settings shows changes.
    public var onChange: (() -> Void)?

    private var operations: [String: Task<Void, Never>] = [:]
    private var progress: [String: Double] = [:]
    private var installing: Set<String> = []
    private var previewTasks: [String: Task<[DocumentIconArtwork: NSImage], Never>] = [:]
    private let previews = NSCache<NSString, NSImage>()
    private var refreshTask: Task<Void, Never>?
    private var active = false
    private let validator = ThemePackValidator()

    public init(environment: ThemeEnvironment, provider: DocumentIconProvider) {
        self.environment = environment; self.provider = provider
        catalogStatus = environment.verifier.isConfigured && environment.catalogURL != nil ? .idle : .notConfigured
        previews.countLimit = 160
        previews.totalCostLimit = 24 << 20
    }

    private var store: ThemeStore { environment.store }

    // MARK: Pane lifecycle

    /// The theme pane became visible: recover interrupted work, read the
    /// installed themes and the last verified catalogue, then refresh it.
    public func activate(refresh: Bool = true) {
        guard !active else { return }
        active = true
        if operations.isEmpty { try? store.prepare() }
        reloadInstalled()
        loadCachedCatalog()
        if refresh { refreshCatalog() }
        changed()
    }

    /// The pane closed: stop preview work and release preview images.
    /// Downloads the user started keep running until done or cancelled.
    public func deactivate() {
        active = false
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        previews.removeAllObjects()
        refreshTask?.cancel(); refreshTask = nil
        if catalogStatus == .loading { catalogStatus = catalog == nil ? .idle : .current }
    }

    // MARK: Catalogue

    private func loadCachedCatalog() {
        guard catalog == nil, environment.verifier.isConfigured, let data = store.cachedCatalogEnvelope() else { return }
        do {
            let verified = try environment.verifier.verify(data, previous: nil)
            guard verified.catalog.catalogVersion >= store.highestCatalogVersion else { throw ThemeError.rollback(cached: store.highestCatalogVersion, received: verified.catalog.catalogVersion) }
            catalog = verified
        } catch {
            store.discardCachedCatalog()
        }
    }

    public func refreshCatalog() {
        guard environment.verifier.isConfigured, let url = environment.catalogURL else { catalogStatus = .notConfigured; changed(); return }
        guard refreshTask == nil else { return }
        catalogStatus = .loading
        changed()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.fetchCatalog(url)
            self.refreshTask = nil
            switch outcome {
            case .success(let verified):
                self.catalog = verified
                try? self.store.saveCatalog(verified)
                self.catalogStatus = .current
            case .failure(let error):
                if (error as? ThemeError) == .cancelled { break }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.catalogStatus = self.catalog != nil && !Self.isSecurityRejection(error) ? .offline(message) : .failed(message)
            }
            self.changed()
        }
    }

    /// Awaitable form for tests and the Refresh button.
    public func refreshCatalogAndWait() async {
        refreshCatalog()
        await refreshTask?.value
    }

    nonisolated static func isSecurityRejection(_ error: Error) -> Bool {
        switch error as? ThemeError {
        case .catalogRejected?, .rollback?, .requiresNewerArkiv?: return true
        default: return false
        }
    }

    private func fetchCatalog(_ url: URL) async -> Result<VerifiedCatalog, Error> {
        do {
            let directory = try store.makeStagingDirectory()
            defer { try? ThemeStore.removeTree(directory) }
            let download = ThemeDownload(url: url, destination: directory.appendingPathComponent("catalog.json"), expectedSize: nil,
                maximum: ThemeLimits.catalogBytes, sha256: nil, hosts: catalogHosts(url), configuration: environment.configuration())
            let result = try await download.run()
            let data = try Data(contentsOf: result.file)
            var previous = catalog
            if previous == nil, let cached = store.cachedCatalogEnvelope() { previous = try? environment.verifier.verify(cached, previous: nil) }
            let verified = try environment.verifier.verify(data, previous: previous)
            let floor = store.highestCatalogVersion
            if verified.catalog.catalogVersion < floor { throw ThemeError.rollback(cached: floor, received: verified.catalog.catalogVersion) }
            return .success(verified)
        } catch {
            return .failure(error)
        }
    }

    private func catalogHosts(_ url: URL) -> ThemeHostPolicy {
        ThemeHostPolicy(assetPrefix: environment.hosts.assetPrefix, redirectHosts: [url.host?.lowercased() ?? ""])
    }

    // MARK: Entries

    public var entries: [ThemeEntry] {
        let selection = provider.effectiveSelection
        var result = [ThemeEntry(id: DocumentIconThemeID.bundled, name: "Seal Dark", familyName: "C · Seal", kind: nil,
            summary: "The refined Seal Dark family included with Arkiv. It is always available and cannot be removed.",
            variantOf: nil, catalog: nil, installed: nil, status: .bundled, isSelected: selection == .bundled)]
        let byID = Dictionary(grouping: installed, by: \.id).mapValues { versions in versions.max(by: { $0.version < $1.version })! }
        var listed = Set<String>()
        for theme in catalog?.catalog.themes ?? [] {
            listed.insert(theme.id)
            let local = byID[theme.id]
            result.append(ThemeEntry(id: theme.id, name: theme.name, familyName: theme.familyName, kind: theme.kind, summary: theme.summary,
                variantOf: theme.variantOf, catalog: theme, installed: local, status: status(for: theme, installed: local),
                isSelected: local.map { selection == .installed(id: $0.id, version: $0.version) } ?? false))
        }
        for local in byID.values.sorted(by: { $0.name < $1.name }) where !listed.contains(local.id) {
            result.append(ThemeEntry(id: local.id, name: local.name, familyName: "Installed", kind: nil,
                summary: "Installed earlier. It is no longer listed in the catalogue but keeps working.", variantOf: nil,
                catalog: nil, installed: local, status: .installed,
                isSelected: selection == .installed(id: local.id, version: local.version)))
        }
        return result
    }

    private func status(for theme: CatalogTheme, installed local: InstalledTheme?) -> ThemeEntryStatus {
        if installing.contains(theme.id) { return .installing }
        if let value = progress[theme.id] { return .downloading(value) }
        if let local { return local.version < theme.version && theme.minimumAppBuild <= environment.verifier.appBuild ? .updateAvailable : .installed }
        if theme.minimumAppBuild > environment.verifier.appBuild { return .unavailable("Requires a newer Arkiv") }
        return .available
    }

    public func entry(_ id: String) -> ThemeEntry? { entries.first { $0.id == id } }

    private func reloadInstalled() { installed = store.installedThemes() }

    // MARK: Download and install

    /// Downloads, verifies and installs one theme. The current theme stays in
    /// use throughout; nothing is published unless every check passes.
    public func download(_ id: String) {
        guard operations[id] == nil, !installing.contains(id) else { lastError[id] = ThemeError.busy.errorDescription; changed(); return }
        guard let theme = catalog?.catalog.themes.first(where: { $0.id == id }) else { return }
        guard theme.minimumAppBuild <= environment.verifier.appBuild else { lastError[id] = ThemeError.requiresNewerArkiv.errorDescription; changed(); return }
        lastError[id] = nil
        progress[id] = 0
        changed()
        operations[id] = Task { [weak self] in
            guard let self else { return }
            let result = await self.install(theme)
            self.operations[id] = nil
            self.progress[id] = nil
            self.installing.remove(id)
            switch result {
            case .success(let installedTheme):
                let previouslySelected = self.store.selection
                self.reloadInstalled()
                if case .installed(let selectedID, let version) = previouslySelected, selectedID == id, version != installedTheme.version {
                    self.store.selection = .installed(id: id, version: installedTheme.version)
                    self.provider.selectionDidChange()
                }
                self.store.removeVersions(of: id, except: installedTheme.version)
                self.reloadInstalled()
            case .failure(let error):
                if (error as? ThemeError) != .cancelled {
                    self.lastError[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            self.changed()
        }
    }

    public func downloadAndWait(_ id: String) async {
        download(id)
        await operations[id]?.value
    }

    public func isBusy(_ id: String) -> Bool { operations[id] != nil || installing.contains(id) }

    public func cancel(_ id: String) {
        operations[id]?.cancel()
    }

    private func install(_ theme: CatalogTheme) async -> Result<InstalledTheme, Error> {
        do {
            let staging = try store.makeStagingDirectory()
            defer { try? ThemeStore.removeTree(staging) }
            let sink = ProgressSink(self), id = theme.id
            let download = ThemeDownload(url: theme.pack.url, destination: staging.appendingPathComponent("pack.zip"),
                expectedSize: theme.pack.size, maximum: ThemeLimits.packBytes, sha256: theme.pack.sha256,
                hosts: environment.hosts, configuration: environment.configuration(),
                progress: { value in Task { @MainActor in sink.manager?.updateProgress(id, value) } })
            let file = try await download.run().file
            try Task.checkCancellation()
            installing.insert(theme.id)
            progress[theme.id] = nil
            changed()
            let cancellation = ArchiveCancellation()
            let validator = self.validator, store = self.store
            let work = Task.detached(priority: .userInitiated) { () throws -> InstalledTheme in
                // Re-hash the staged file: it is what gets parsed.
                guard try ThemeHash.sha256(file: file) == theme.pack.sha256 else { throw ThemeError.checksumMismatch }
                let validated = try validator.validate(pack: file, mode: .theme(theme), staging: staging, cancellation: cancellation)
                if cancellation.isCancelled { throw ThemeError.cancelled }
                return try store.publish(validated, id: theme.id, version: theme.version)
            }
            return .success(try await withTaskCancellationHandler { try await work.value } onCancel: { cancellation.cancel(); work.cancel() })
        } catch is CancellationError {
            return .failure(ThemeError.cancelled)
        } catch {
            return .failure(error)
        }
    }

    /// Carries download progress from URLSession's queue to the main actor without retaining the manager.
    private final class ProgressSink: @unchecked Sendable {
        weak var manager: DocumentIconThemeManager?
        init(_ manager: DocumentIconThemeManager) { self.manager = manager }
    }

    fileprivate func updateProgress(_ id: String, _ value: Double) {
        guard progress[id] != nil else { return }
        progress[id] = min(max(value, 0), 1)
        changed()
    }

    // MARK: Selection and removal

    /// Applies an installed theme, or the bundled default.
    public func apply(_ id: String) throws {
        if id == DocumentIconThemeID.bundled { restoreDefault(); return }
        guard let theme = installed.filter({ $0.id == id }).max(by: { $0.version < $1.version }),
              store.loadInstalled(id: theme.id, version: theme.version) != nil else {
            reloadInstalled(); changed(); throw ThemeError.notInstalled
        }
        store.selection = .installed(id: theme.id, version: theme.version)
        provider.selectionDidChange()
        changed()
    }

    public func restoreDefault() {
        store.selection = .bundled
        provider.selectionDidChange()
        changed()
    }

    /// Removes a downloaded theme. If it is in use, Arkiv switches to the
    /// bundled default first, so nothing ever draws from a removed folder.
    public func remove(_ id: String) throws {
        guard id != DocumentIconThemeID.bundled else { return }
        guard !isBusy(id) else { throw ThemeError.busy }
        if case .installed(let selected, _) = store.selection, selected == id { restoreDefault() }
        defer { reloadInstalled(); changed() }
        try store.remove(id: id)
        previews.removeAllObjects()
    }

    // MARK: Previews (real artwork only)

    /// The theme's own 128 px artwork for each covered icon and in-app extra:
    /// bundled resources, installed files, or the verified preview pack listed
    /// in the catalogue. Loaded only for the theme being shown, and cancelled
    /// when the pane closes.
    public func previews(for id: String) async -> [DocumentIconArtwork: NSImage] {
        if let cached = cachedPreviews(id) { return cached }
        if let running = previewTasks[id] { return await running.value }
        let task = Task { [weak self] () -> [DocumentIconArtwork: NSImage] in
            guard let self else { return [:] }
            return await self.loadPreviews(id)
        }
        previewTasks[id] = task
        let images = await task.value
        previewTasks[id] = nil
        return images
    }

    public func cancelPreviews(except id: String?) {
        for (key, task) in previewTasks where key != id { task.cancel(); previewTasks[key] = nil }
    }

    private func cacheKey(_ id: String, _ artwork: DocumentIconArtwork) -> NSString { "\(id)/\(Self.previewName(artwork))" as NSString }

    /// `Arkiv-<name>.png`, as in preview packs.
    public static func previewName(_ artwork: DocumentIconArtwork) -> String {
        switch artwork {
        case .icon(let name): return "Arkiv-\(name.rawValue).png"
        case .extra(let extra): return "Arkiv-\(extra.rawValue).png"
        }
    }
    static func previewArtwork(named file: String) -> DocumentIconArtwork? {
        guard file.hasPrefix("Arkiv-"), file.hasSuffix(".png") else { return nil }
        let raw = String(file.dropFirst(6).dropLast(4))
        return DocumentIconName(rawValue: raw).map(DocumentIconArtwork.icon) ?? DocumentIconExtra(rawValue: raw).map(DocumentIconArtwork.extra)
    }

    private func cachedPreviews(_ id: String) -> [DocumentIconArtwork: NSImage]? {
        guard let entry = entry(id), !entry.previewArtwork.isEmpty else { return nil }
        var images = [DocumentIconArtwork: NSImage]()
        for artwork in entry.previewArtwork {
            guard let image = previews.object(forKey: cacheKey(id, artwork)) else { return nil }
            images[artwork] = image
        }
        return images
    }

    private func remember(_ images: [DocumentIconArtwork: NSImage], for id: String) -> [DocumentIconArtwork: NSImage] {
        for (artwork, image) in images { previews.setObject(image, forKey: cacheKey(id, artwork), cost: 128 * 128 * 4) }
        return images
    }

    private func loadPreviews(_ id: String) async -> [DocumentIconArtwork: NSImage] {
        guard let entry = entry(id) else { return [:] }
        if entry.status == .bundled {
            var images = [DocumentIconArtwork: NSImage]()
            for name in DocumentIconName.allCases {
                guard let image = providerBundledIcon(name).flatMap({ NSImage(contentsOf: $0) }) else { continue }
                image.size = NSSize(width: 128, height: 128)
                images[.icon(name)] = image
            }
            for extra in DocumentIconExtra.allCases {
                if let image = providerBundledExtra(extra).flatMap({ DocumentIconProvider.loadBundledExtra(from: $0, points: 128) }) {
                    images[.extra(extra)] = image
                }
            }
            return remember(images, for: id)
        }
        if let local = entry.installed {
            var images = [DocumentIconArtwork: NSImage]()
            for artwork in entry.previewArtwork { images[artwork] = provider.previewImage(artwork, theme: local) }
            return remember(images, for: id)
        }
        guard let theme = entry.catalog else { return [:] }
        let directory = store.previewDirectory(id: theme.id, version: theme.version)
        if let images = readPreviewCache(theme, directory) { return remember(images, for: id) }
        do {
            let staging = try store.makeStagingDirectory()
            defer { try? ThemeStore.removeTree(staging) }
            let file = try await ThemeDownload(url: theme.preview.url, destination: staging.appendingPathComponent("preview.zip"),
                expectedSize: theme.preview.size, maximum: ThemeLimits.previewBytes, sha256: theme.preview.sha256,
                hosts: environment.hosts, configuration: environment.configuration()).run().file
            try Task.checkCancellation()
            let validator = self.validator, store = self.store
            let published = try await Task.detached(priority: .utility) { () throws -> URL in
                let validated = try validator.validate(pack: file, mode: .preview(theme), staging: staging, cancellation: ArchiveCancellation())
                return try store.publishPreview(validated, id: theme.id, version: theme.version)
            }.value
            return remember(readPreviewCache(theme, published) ?? [:], for: id)
        } catch {
            return [:]
        }
    }

    /// Cached preview files are re-checked against the signed catalogue on every read.
    private func readPreviewCache(_ theme: CatalogTheme, _ directory: URL) -> [DocumentIconArtwork: NSImage]? {
        var images = [DocumentIconArtwork: NSImage]()
        for file in theme.preview.files {
            guard let artwork = Self.previewArtwork(named: file.name),
                  let data = try? ThemePackValidator.read(directory.appendingPathComponent(file.name), limit: ThemeLimits.fileBytes),
                  data.count == file.size, ThemeHash.sha256(data) == file.sha256,
                  let bitmap = NSBitmapImageRep(data: data) else { return nil }
            let image = NSImage(size: NSSize(width: 128, height: 128))
            bitmap.size = NSSize(width: 128, height: 128)
            image.addRepresentation(bitmap)
            images[artwork] = image
        }
        return images
    }

    /// How the bundled previews are located; replaced in tests.
    public var providerBundledIcon: (DocumentIconName) -> URL? = { Bundle.main.url(forResource: "Arkiv-\($0.rawValue)", withExtension: "icns") }
    public var providerBundledExtra: (DocumentIconExtra) -> URL? = DocumentIconProvider.bundledExtraFolder

    private func changed() { onChange?() }
}
