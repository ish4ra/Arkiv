import AppKit
import Quartz
import ArkivCore
import ArkivPresentation
import ArkivThemes

final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    var onClose: (() -> Void)?
    var recentArchiveURL: URL? { !isBusy && archiveSource == nil ? snapshot?.url : nil }
    var onAcceptedArchive: ((URL, Bool) -> Void)?
    var onOpen: (() -> Void)?
    var onOpenNestedArchive: ((ArchiveSnapshot, ArchiveOpenedFileLease) -> Void)?
    private var archiveSource: ArchiveOpenedFileLease?
    let windowID = UUID()
    private var pendingURL: URL?
    var archiveURL: URL? { snapshot?.url ?? pendingURL }
    var routingState: ArchiveWindowState {
        ArchiveWindowState(id: windowID, archiveURL: archiveURL,
            isAvailable: !isBusy && window?.attachedSheet == nil)
    }
    private(set) var isBusy = false
    private let table = ArchiveTableView()
    private let columnPreferences: BrowserColumnPreferences
    private var restoringColumns = true
    private var dragSession: ArchiveDragSession?
    private var dragIsActive = false
    private let dragQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "xyz.isharalakshan.arkiv.file-promises"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let welcome = WelcomeView()
    private let browserView = NSView()
    private let footer = ArkivFooterBar()
    let pathControl = NSPathControl()
    private var pathControlPaths: [String] = []
    private let noResults = NSTextField(labelWithString: "")
    private let noResultsIcon = NSImageView()
    private lazy var noResultsStack = NSStackView(views: [noResultsIcon, noResults])
    /// The archive-browsing toolbar; a second, empty toolbar keeps the
    /// title bar height identical while the welcome canvas is shown.
    let browserToolbar = NSToolbar(identifier: "ArkivBrowser.v2")
    private let welcomeToolbar = NSToolbar(identifier: "ArkivWelcome")
    private(set) var searchItem: NSSearchToolbarItem?
    /// Presentation preferences (density, accent, alternating rows). Set
    /// after creation; every window shares the app's instance.
    var preferences = AppPreferences() {
        didSet {
            NotificationCenter.default.removeObserver(self, name: .arkivAppearancePreferencesDidChange, object: oldValue)
            NotificationCenter.default.addObserver(self, selector: #selector(appearancePreferencesDidChange(_:)),
                                                   name: .arkivAppearancePreferencesDidChange, object: preferences)
        applyPresentation(density: preferences.density, accent: preferences.accent, alternatingRows: preferences.alternatingRows)
            applyPresentation(density: preferences.density, accent: preferences.accent, alternatingRows: preferences.alternatingRows)
        }
    }
    /// Recent archives for the welcome canvas (NSDocumentController history).
    var recentArchives: () -> [URL] {
        get { welcome.recentURLs }
        set { welcome.recentURLs = newValue; welcome.reloadRecents() }
    }
    /// Set by the app for windows opened from inside another archive.
    var nestedParentName: String? { didSet { updateSubtitle() } }
    var onOpenURLs: (([URL]) -> Void)?
    var onCreate: (() -> Void)?
    var onShowSettings: ((SettingsWindowController.Pane?) -> Void)?
    private var snapshot: ArchiveSnapshot?
    private var zipAdditionAvailable = false
    private var additionCapability: ArchiveAdditionCapability = .readOnly("Open an archive to add items.")
    private let modificationFeedback: (Result<URL, Error>) -> Void
    private var index: ArchiveIndex?
    private var rows: [BrowserRow] = []
    private var currentPath = ""
    private var back: [String] = []
    private var forward: [String] = []
    private var cancellation: ArchiveCancellation?
    private var openSession = ArchiveOpenSession()
    private var openSessionArchiveURL: URL?
    private var openRequest: UUID?
    private enum FilePurpose { case open, preview, automatic, archive }
    private var filePurpose: FilePurpose?
    private let quickLook: ArchiveQuickLookPresenting
    private var sessionEnded = false
    private let openFileLauncher: (URL) -> Bool
    // Injection keeps AppKit tests deterministic and never launches another app.
    private let prepareOpenFile: (ArchiveOpenSession, ArchiveSnapshot, String, ArchiveCancellation, @escaping @Sendable (ArchiveProgress) -> Void) throws -> ArchiveOpenedFile
    private let requestArchivePassword: (URL, Bool, NSWindow?, @escaping (String?) -> Void) -> Void
    private let engine = LibArchiveEngine()
    private let worker: DispatchQueue
    private let documentIcons: DocumentIconProvider
    private(set) var density: BrowserDensity
    private var accent: NSColor?

    init(worker: DispatchQueue = DispatchQueue(label: "xyz.isharalakshan.arkiv.archive", qos: .userInitiated),
         columnPreferences: BrowserColumnPreferences = BrowserColumnPreferences(),
         modificationFeedback: @escaping (Result<URL, Error>) -> Void = { ExtractionFeedback.completed($0) },
         quickLook: ArchiveQuickLookPresenting = ArchiveQuickLook(),
         openFileLauncher: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         prepareOpenFile: @escaping (ArchiveOpenSession, ArchiveSnapshot, String, ArchiveCancellation, @escaping @Sendable (ArchiveProgress) -> Void) throws -> ArchiveOpenedFile = {
             try $0.prepare($1, path: $2, cancellation: $3, progress: $4)
         },
         requestArchivePassword: @escaping (URL, Bool, NSWindow?, @escaping (String?) -> Void) -> Void = {
             ArchivePasswordPrompt.ask(archive: $0, retry: $1, parent: $2, completion: $3)
         },
         documentIcons: DocumentIconProvider = .shared) {
        self.worker = worker
        self.documentIcons = documentIcons
        self.columnPreferences = columnPreferences
        self.quickLook = quickLook
        self.modificationFeedback = modificationFeedback
        self.openFileLauncher = openFileLauncher
        self.prepareOpenFile = prepareOpenFile
        self.requestArchivePassword = requestArchivePassword
        density = .standard
        accent = ArkivStyle.customAccent(.arkiv)
        // The table scrolls under the translucent unified toolbar; the welcome
        // canvas runs up behind a transparent title bar.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Arkiv"
        window.minSize = NSSize(width: 640, height: 400)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        welcome.documentIcons = documentIcons
        welcome.reloadRecents()
        window.contentView = makeContent()
        NotificationCenter.default.addObserver(self, selector: #selector(documentIconThemeDidChange(_:)),
                                               name: .arkivDocumentIconThemeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appearancePreferencesDidChange(_:)),
                                               name: .arkivAppearancePreferencesDidChange, object: preferences)
        applyPresentation(density: preferences.density, accent: preferences.accent, alternatingRows: preferences.alternatingRows)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
                                               name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        browserToolbar.delegate = self
        browserToolbar.displayMode = .iconOnly
        browserToolbar.allowsUserCustomization = true
        browserToolbar.autosavesConfiguration = true
        welcomeToolbar.delegate = self
        welcomeToolbar.displayMode = .iconOnly
        welcomeToolbar.allowsUserCustomization = false
        applyWindowState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        quickLook.close(); openSession.close()
    }
    private func makeContent() -> NSView {
        table.previewKeyHandler = { [weak self] event in self?.handlePreviewKey(event) ?? false }
        table.usesAlternatingRowBackgroundColors = preferences.alternatingRows
        table.style = .fullWidth
        table.backgroundColor = .textBackgroundColor
        table.allowsMultipleSelection = true
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = CGFloat(density.rowHeight)
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(activateRow(_:))
        table.setAccessibilityLabel("Archive contents")
        for (id, title, width) in [("name", "Name", 340.0), ("size", "Size", 110.0), ("type", "Kind", 130.0), ("packed", "Packed Size", 110.0), ("ratio", "Ratio", 90.0), ("modified", "Modified", 175.0), ("method", "Method", 130.0), ("encrypted", "Encrypted", 90.0), ("crc", "CRC", 100.0), ("attributes", "Attributes", 110.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "name" ? 180 : 80
            column.resizingMask = [.userResizingMask]
            column.maxWidth = 1600
            column.width = columnPreferences.width(id, fallback: width, minimum: Double(column.minWidth))
            column.isHidden = columnPreferences.isHidden(id)
            column.headerCell.alignment = ["size","packed","ratio"].contains(id) ? .right : .left
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            column.headerToolTip = title
            table.addTableColumn(column)
        }
        let columns = NSMenu(title: "Columns")
        columns.autoenablesItems = false
        for column in table.tableColumns {
            let item = columns.addItem(withTitle: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = column.identifier.rawValue
            item.state = column.isHidden ? .off : .on
            item.isEnabled = column.identifier.rawValue != "name"
        }
        table.headerView?.menu = columns
        restoringColumns = false
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.menu = makeContextMenu()
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false

        search.placeholderString = "Search archive"
        search.delegate = self
        search.setAccessibilityLabel("Search archive paths")
        search.toolTip = "Search every path in this archive (⌘F)"
        search.sendsSearchStringImmediately = false

        pathControl.pathStyle = .standard
        pathControl.controlSize = .small
        pathControl.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathControl.focusRingType = .none
        pathControl.target = self; pathControl.action = #selector(pathControlClicked(_:))
        pathControl.setAccessibilityLabel("Current folder")
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)

        browserView.translatesAutoresizingMaskIntoConstraints = false
        browserView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: browserView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: browserView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: browserView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: browserView.bottomAnchor),
        ])
        noResults.font = .systemFont(ofSize: 13); noResults.textColor = .secondaryLabelColor
        noResultsIcon.contentTintColor = .tertiaryLabelColor
        noResultsIcon.setAccessibilityElement(false)
        noResultsStack.orientation = .vertical; noResultsStack.spacing = 8
        noResultsStack.translatesAutoresizingMaskIntoConstraints = false
        browserView.addSubview(noResultsStack)
        NSLayoutConstraint.activate([noResultsStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            noResultsStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: 20)])

        welcome.translatesAutoresizingMaskIntoConstraints = false
        welcome.onOpen = { [weak self] in self?.openArchive(nil) }
        welcome.onCreate = { [weak self] in self?.onCreate?() }
        welcome.onOpenURLs = { [weak self] urls in self?.openDropped(urls) }
        welcome.onAppearance = { [weak self] in self?.onShowSettings?(.appearance) }

        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        cancelButton.target = self; cancelButton.action = #selector(cancel(_:)); cancelButton.isHidden = true
        cancelButton.bezelStyle = .rounded; cancelButton.controlSize = .small
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.alignment = .right
        status.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(260), for: .horizontal)
        status.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        status.setAccessibilityLabel("Status")
        footer.stack.setViews([pathControl, status, spinner, cancelButton], in: .leading)
        footer.stack.setCustomSpacing(12, after: pathControl)

        let content = NSView()
        for view in [browserView, welcome, footer] as [NSView] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            welcome.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            welcome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            welcome.topAnchor.constraint(equalTo: content.topAnchor),
            welcome.bottomAnchor.constraint(equalTo: footer.topAnchor),
            browserView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            browserView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            browserView.topAnchor.constraint(equalTo: content.topAnchor),
            browserView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        footerHeight = footer.heightAnchor.constraint(equalToConstant: ArkivFooterBar.height)
        footerHeight?.isActive = true
        return content
    }
    private var footerHeight: NSLayoutConstraint?
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ symbol: String? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            if let symbol { item.image = ArkivStyle.symbol(symbol, title) }
        }
        add("Open", #selector(openSelectedFile(_:)), "arrow.up.forward.app")
        add("Open as Archive", #selector(openSelectedArchive(_:)), "archivebox")
        add("Quick Look", #selector(quickLookSelectedFile(_:)), "eye")
        add("Show Package Contents", #selector(showPackageContents(_:)), "shippingbox")
        menu.addItem(.separator())
        add("Extract Selected…", #selector(extractSelected(_:)), "arrow.down.doc")
        add("Copy Path", #selector(copyPath(_:)), "doc.on.doc")
        menu.addItem(.separator())
        add("Add Files…", #selector(addFiles(_:)), "doc.badge.plus")
        add("Add Folder…", #selector(addFolder(_:)), "folder.badge.plus")
        add("Replace File…", #selector(replaceSelected(_:)))
        add("New Folder…", #selector(newFolder(_:)))
        add("Replace Folder…", #selector(replaceSelectedFolder(_:)))
        add("Update Selected Files…", #selector(updateSelectedFiles(_:)))
        add("Update Folder…", #selector(updateSelectedFolder(_:)))
        add("Rename…", #selector(renameSelected(_:)), "pencil")
        menu.addItem(.separator())
        add("Delete…", #selector(deleteSelected(_:)), "trash")
        return menu
    }
    @objc func openArchive(_ sender: Any?) { onOpen?() }
    @objc func createArchive(_ sender: Any?) { onCreate?() }
    @objc func showSettings(_ sender: Any?) { onShowSettings?(nil) }
    private func openDropped(_ urls: [URL]) {
        guard !isBusy, window?.attachedSheet == nil else { return }
        if let onOpenURLs { onOpenURLs(urls) } else if let first = urls.first { load(first) }
    }
    /// Welcome canvas or archive browser. Same title-bar height in both, so
    /// nothing jumps when an archive opens.
    private var showsBrowser: Bool { snapshot != nil }
    private func applyWindowState() {
        guard let window else { return }
        let browsing = showsBrowser
        welcome.isHidden = browsing
        browserView.isHidden = !browsing
        footer.isHidden = !browsing && !isBusy
        footerHeight?.constant = footer.isHidden ? 0 : ArkivFooterBar.height
        pathControl.isHidden = !browsing
        let toolbar = browsing ? browserToolbar : welcomeToolbar
        if window.toolbar !== toolbar { window.toolbar = toolbar }
        window.titlebarAppearsTransparent = !browsing
        window.titleVisibility = browsing ? .visible : .hidden
        window.titlebarSeparatorStyle = browsing ? .automatic : .none
        if !browsing { window.title = "Arkiv"; window.subtitle = "" }
    }
    private func updateControls() {
        applyWindowState()
        welcome.setEnabled(!isBusy)
        updateToolbarState()
        window?.toolbar?.validateVisibleItems()
    }
    func load(_ url: URL, password: String? = nil, browsingFolder: String = "", selectingPath: String? = nil, selectingPaths: Set<String> = []) {
        guard !sessionEnded else { return }
        quickLook.close()
        if openRequest != nil {
            cancellation?.cancel(); openRequest = nil; filePurpose = nil; finish()
        }
        guard !isBusy else { return }
        if openSessionArchiveURL != url.standardizedFileURL {
            openSession.close(); openSession = ArchiveOpenSession()
            openSessionArchiveURL = url.standardizedFileURL
        }
        if !dragIsActive { dragSession = nil }
        pendingURL = url
        if archiveSource?.url.standardizedFileURL != url.standardizedFileURL { archiveSource = nil }
        let source = archiveSource
        let token = begin("Reading archive…")
        worker.async { [self] in
            let result = Result { try source?.inspect(cancellation: token, password: password)
                ?? self.engine.inspect(url, cancellation: token, password: password) }
            let capability = (try? result.get()).map { ArchiveAdditionUpdater().capability(for: $0) } ?? .readOnly("Open an archive to add items.")
            DispatchQueue.main.async { [self] in
                guard !self.sessionEnded else { return }
                self.pendingURL = nil
                self.finish()
                switch result {
                case .success(let value):
                    if !token.isCancelled { self.onAcceptedArchive?(url,source != nil) }
                    self.snapshot = value; self.index = value.index; self.zipAdditionAvailable = capability == .zip; self.additionCapability = capability
                    self.currentPath = value.index.row(at: browsingFolder)?.isDirectory == true ? browsingFolder : ""; self.back = []; self.forward = []
                    self.window?.title = url.lastPathComponent
                    self.window?.representedURL = url
                    self.updateSubtitle()
                    self.applyDocumentIcon()
                    self.reload()
                    let wanted = selectingPaths.union(selectingPath.map { [$0] } ?? [])
                    let selected = IndexSet(self.rows.indices.filter { wanted.contains(self.rows[$0].path) })
                    if !selected.isEmpty {
                        self.table.selectRowIndexes(selected, byExtendingSelection: false)
                        if let first = selected.first { self.table.scrollRowToVisible(first) }
                    }
                    self.window?.makeFirstResponder(self.table)
                case .failure(let error):
                    if ArchivePasswordPrompt.isPasswordFailure(error) {
                        requestArchivePassword(url, password != nil, self.window) { [weak self] supplied in
                            if let supplied { self?.load(url, password: supplied) }
                        }
                    } else { self.present(error) }
                }
            }
        }
    }
    /// Called only after nested preflight succeeds. The child owns its source and
    /// snapshots carry the same ownership into workers and file promises.
    func adoptNestedArchive(_ value: ArchiveSnapshot, source: ArchiveOpenedFileLease) {
        guard !sessionEnded, snapshot == nil, !isBusy else { return }
        archiveSource = source
        openSessionArchiveURL = value.url.standardizedFileURL
        snapshot = value; index = value.index
        additionCapability = ArchiveAdditionUpdater().capability(for: value)
        zipAdditionAvailable = additionCapability == .zip
        window?.title = value.url.lastPathComponent
        window?.representedURL = value.url
        updateSubtitle()
        applyDocumentIcon()
        reload()
        window?.makeFirstResponder(table)
    }
    private func begin(_ message: String) -> ArchiveCancellation {
        let token = ArchiveCancellation(); cancellation = token
        isBusy = true; search.isEnabled = false
        status.stringValue = message; spinner.startAnimation(nil); cancelButton.isHidden = false
        updateControls()
        return token
    }
    private func finish() {
        isBusy = false; cancellation = nil; search.isEnabled = true
        spinner.stopAnimation(nil); cancelButton.isHidden = true
        updateControls()
    }
    @objc func cancel(_ sender: Any?) { cancellation?.cancel(); status.stringValue = "Cancelling…" }
    @objc func focusSearch(_ sender: Any?) {
        if let searchItem, window?.toolbar === browserToolbar, browserToolbar.items.contains(where: { $0 === searchItem }) {
            searchItem.beginSearchInteraction()
        } else { window?.makeFirstResponder(search) }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard !isBusy, let snapshot, rows.indices.contains(row) else { return nil }
        if dragSession == nil {
            var paths = selectedPaths()
            if !paths.contains(rows[row].path) { paths = [rows[row].path] }
            dragSession = try? ArchiveDragSession(snapshot: snapshot, paths: paths)
        }
        guard let dragSession, let item = dragSession.items.first(where: { $0.path == rows[row].path }) else { return nil }
        return ArchiveDragPromiseProvider(session: dragSession, item: item, queue: dragQueue) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let report):
                self.status.stringValue = report.warnings.isEmpty ? "Dragged item extracted" : "Dragged item extracted with warnings"
                if let window = self.window { ExtractionFeedback.showWarnings(report, parent: window) }
            case .failure(let error): self.present(error)
            }
        }
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        dragIsActive = true
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty, let cancelledSession = dragSession {
            cancelledSession.requestCancellation()
            dragQueue.addOperation { cancelledSession.cancel() }
        }
        // Providers retain the session through promised writes, including after the browser closes.
        dragSession = nil; dragIsActive = false
    }
    func dropFolder(proposedRow: Int, operation: NSTableView.DropOperation) -> String? {
        guard canAddToZIP, window?.attachedSheet == nil else { return nil }
        if operation == .on, rows.indices.contains(proposedRow), rows[proposedRow].isDirectory {
            return rows[proposedRow].path
        }
        return currentPath
    }
    func droppedFiles(_ pasteboard: NSPasteboard) -> [URL] {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty,
              urls.allSatisfy({ url in
                  guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
                        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                        let kind = attributes[.type] as? FileAttributeType else { return false }
                  return kind == .typeRegular || kind == .typeDirectory
              }) else { return [] }
        return urls
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard !droppedFiles(info.draggingPasteboard).isEmpty,
              dropFolder(proposedRow: row, operation: operation) != nil,
              info.draggingSourceOperationMask.contains(.copy) else { return [] }
        if operation != .on || !rows.indices.contains(row) || !rows[row].isDirectory {
            tableView.setDropRow(-1, dropOperation: .on)
        }
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSourceOperationMask.contains(.copy) else { return false }
        return acceptFiles(info.draggingPasteboard, row: row, operation: operation)
    }
    func acceptFiles(_ pasteboard: NSPasteboard, row: Int, operation: NSTableView.DropOperation) -> Bool {
        let urls = droppedFiles(pasteboard)
        guard !urls.isEmpty, let folder = dropFolder(proposedRow: row, operation: operation) else { return false }
        addItems(urls, folder: folder)
        return true
    }
    private func selectedPaths() -> Set<String> {
        Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].path : nil })
    }
    @objc func testArchive(_ sender: Any?) {
        guard !isBusy, let url = snapshot?.url else { return }
        test(url)
    }
    private func test(_ url: URL, password: String? = nil) {
        let token = begin("Testing archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try engine.test(url, cancellation: token, password: password) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) tested"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                switch result {
                case .success(let value):
                    status.stringValue = "Test Archive — " + value.state.rawValue
                    let alert = NSAlert(); alert.messageText = status.stringValue; alert.informativeText = value.detail
                    alert.alertStyle = value.state == .ok ? .informational : .warning
                    let ok = value.state == .ok
                    let symbol = NSImage(systemSymbolName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", accessibilityDescription: ok ? "Passed" : "Problem found")
                    alert.icon = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [ok ? ArkivStyle.success : .systemOrange])))
                    if let window { alert.beginSheetModal(for: window) }
                case .failure(let error):
                    if ArchivePasswordPrompt.isPasswordFailure(error) {
                        ArchivePasswordPrompt.ask(archive: url, retry: password != nil, parent: window) { [weak self] supplied in
                            if let supplied { self?.test(url, password: supplied) }
                        }
                    } else { present(error) }
                }
            }
        }
    }
    private var canReplaceFile: Bool {
        guard canAddItems, window?.attachedSheet == nil, selectedPaths().count == 1,
              let path = selectedPaths().first else { return false }
        return snapshot?.entries.filter { $0.path == path && $0.kind == .file }.count == 1 && index?.row(at: path)?.isDirectory == false
    }
    @objc func replaceSelected(_ sender: Any?) {
        guard canReplaceFile, let window, let path = selectedPaths().first else { return }
        let panel = NSOpenPanel()
        panel.title = "Replace File"
        panel.message = "Choose a file to replace the contents of ‘\(path)’. Its archive name stays unchanged."
        panel.prompt = "Replace"
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let source = panel.url else { return }
            self?.replaceItem(path, with: source)
        }
    }
    func replaceItem(_ path: String, with source: URL) {
        guard canAddItems, let snapshot else { return }
        if ArchiveModificationUpdater().canReplaceEncrypted(snapshot) {
            requestArchivePassword(snapshot.url, false, window) { [weak self] password in
                guard let self, let password else { return }
                self.performReplacement(path, with: source, snapshot: snapshot, password: password)
            }
        } else { performReplacement(path, with: source, snapshot: snapshot, password: nil) }
    }
    private func performReplacement(_ path: String, with source: URL, snapshot: ArchiveSnapshot, password: String?) {
        guard !sessionEnded, canAddItems, self.snapshot?.url == snapshot.url else { return }
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        let token = begin("Replacing file in archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveModificationUpdater().replace(path: path, with: source, in: snapshot, password: password, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries verified"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, password: password, browsingFolder: folder, selectingPath: path)
                case .failure(let error): present(error)
                }
            }
        }
    }
    private var canUpdateSelectedFiles: Bool {
        guard canAddItems, case .zip = additionCapability, let snapshot else { return false }
        let paths = selectedPaths()
        return paths.count >= 2 && paths.allSatisfy { path in
            path.split(separator: "/").dropLast().joined(separator: "/") == currentPath &&
            snapshot.entries.first(where: { $0.path == path })?.kind == .file
        }
    }
    @objc func updateSelectedFiles(_ sender: Any?) {
        guard canUpdateSelectedFiles, let window, window.attachedSheet == nil else { return }
        let paths = selectedPaths()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Every selected file must have a regular source file with the same name in this folder. Other source files are ignored."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let source = panel.url else { return }
            DispatchQueue.main.async { self?.confirmSelectedFileUpdate(paths, from: source) }
        }
    }
    func confirmSelectedFileUpdate(_ paths: Set<String>, from source: URL) {
        guard canUpdateSelectedFiles, selectedPaths() == paths, let snapshot, let window,
              window.attachedSheet == nil else { return }
        let folder = currentPath
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update \(paths.count) selected files?"
        alert.informativeText = "Match each file by name. Replace All replaces every match; Replace Older replaces only definitively newer sources. Missing or invalid sources stop the whole update. Replace Older also stops on unreliable timestamps. Archive names stay unchanged."
        let policyPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 28), pullsDown: false)
        policyPicker.addItems(withTitles: ["Replace All", "Replace Older"])
        policyPicker.setAccessibilityLabel("Update policy")
        policyPicker.toolTip = "Replace Older skips equal or older sources and stops if an archive timestamp is unreliable."
        alert.accessoryView = policyPicker
        let button = alert.addButton(withTitle: "Update Files")
        button.hasDestructiveAction = true; button.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, !self.sessionEnded,
                  self.canUpdateSelectedFiles, self.selectedPaths() == paths else { return }
            let policy: ZIPSelectedUpdatePolicy = policyPicker.indexOfSelectedItem == 1 ? .replaceOlder : .replaceAll
            let token = self.begin("Updating selected files…")
            self.worker.async { [self] in
                let throttle = ProgressThrottle()
                let result = Result {
                    try ArchiveZIPUpdater().updateSelectedFilesReport(paths: paths, from: source, in: snapshot, policy: policy, cancellation: token) { progress in
                        guard throttle.shouldUpdate() else { return }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.isBusy else { return }
                            self.status.stringValue = "\(progress.files) entries · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) processed"
                        }
                    }
                }
                DispatchQueue.main.async { [self] in
                    self.finish()
                    switch result {
                    case .success(let report):
                        guard !report.updatedPaths.isEmpty else {
                            self.status.stringValue = "No selected files were newer. Archive unchanged."
                            return
                        }
                        self.modificationFeedback(.success(report.url))
                        self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                        self.search.stringValue = ""
                        self.load(report.url, browsingFolder: folder, selectingPaths: paths)
                    case .failure(let error):
                        self.modificationFeedback(.failure(error))
                        self.present(error)
                    }
                }
            }
        }
    }
    private var canReplaceFolder: Bool {
        guard canAddItems, case .zip = additionCapability, selectedPaths().count == 1,
              let path = selectedPaths().first else { return false }
        return index?.row(at: path)?.isDirectory == true
    }
    @objc func replaceSelectedFolder(_ sender: Any?) { chooseFolderSource(merge: false) }
    @objc func updateSelectedFolder(_ sender: Any?) { chooseFolderSource(merge: true) }
    private func chooseFolderSource(merge: Bool) {
        guard canReplaceFolder, let window, window.attachedSheet == nil,
              let path = selectedPaths().first else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = merge ? "Choose contents to merge. Archive-only items will be kept." : "Choose replacement contents. The archive folder keeps its existing name."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let source = panel.url else { return }
            // Present confirmation after AppKit has dismissed the chooser.
            DispatchQueue.main.async { self?.confirmFolderReplacement(path, with: source, merge: merge) }
        }
    }
    func confirmFolderReplacement(_ path: String, with source: URL, merge: Bool = false) {
        guard canReplaceFolder, selectedPaths().first == path, let snapshot, let window,
              window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(merge ? "Update" : "Replace") contents of ‘\(path.split(separator: "/").last ?? "")’?"
        alert.informativeText = merge ? "Matching files will receive the chosen folder’s contents, and new items will be added. Archive-only items will be kept. This does not compare modification dates." : "All existing contents will be replaced by the chosen folder’s contents. Items absent from the chosen folder will be removed. The archive folder’s name stays unchanged."
        let replace = alert.addButton(withTitle: merge ? "Update" : "Replace")
        replace.hasDestructiveAction = true
        replace.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performFolderReplacement(path, with: source, snapshot: snapshot, merge: merge)
        }
    }
    private func performFolderReplacement(_ path: String, with source: URL, snapshot: ArchiveSnapshot, merge: Bool) {
        guard !sessionEnded, canReplaceFolder, self.snapshot?.url == snapshot.url else { return }
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        let token = begin(merge ? "Updating folder in archive…" : "Replacing folder in archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                let report: @Sendable (ArchiveProgress) -> Void = { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) processed"
                    }
                }
                if merge {
                    return try ArchiveZIPUpdater().updateFolder(path: path, with: source, in: snapshot, cancellation: token, progress: report)
                }
                return try ArchiveZIPUpdater().replaceFolder(path: path, with: source, in: snapshot, cancellation: token, progress: report)
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, browsingFolder: folder, selectingPath: path)
                case .failure(let error): present(error)
                }
            }
        }
    }
    private var canCreateFolder: Bool {
        guard canAddItems, case .zip = additionCapability else { return false }
        return true
    }
    @objc func newFolder(_ sender: Any?) {
        guard canCreateFolder, let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Create an empty folder in the current archive directory."
        let field = NSTextField(string: "New Folder")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.setAccessibilityIdentifier("archiveNewFolderName")
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.createFolder(named: field.stringValue)
        }
        field.selectText(nil)
    }
    func createFolder(named name: String) {
        guard canCreateFolder, let snapshot else { return }
        let folder = currentPath
        let destination = folder.isEmpty ? name : folder + "/" + name
        let token = begin("Creating folder in archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveZIPUpdater().createFolder(named: name, in: snapshot, folder: folder, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries verified"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, browsingFolder: folder, selectingPath: destination)
                case .failure(let error): present(error)
                }
            }
        }
    }
    @objc func renameSelected(_ sender: Any?) {
        guard canRenameItems, let window, window.attachedSheet == nil,
              selectedPaths().count == 1, let path = selectedPaths().first,
              let row = index?.row(at: path) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename ‘\(row.name)’"
        alert.informativeText = "Enter a new name. The item stays in its current archive folder."
        let field = NSTextField(string: row.name)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.setAccessibilityIdentifier("archiveRenameName")
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.renameItem(path, to: field.stringValue)
        }
        field.selectText(nil)
    }
    func renameItem(_ path: String, to name: String) {
        guard canRenameItems, let snapshot else { return }
        if ArchiveModificationUpdater().canRenameEncrypted(snapshot) {
            requestArchivePassword(snapshot.url, false, window) { [weak self] password in
                guard let self, let password else { return }
                self.performRename(path, to: name, snapshot: snapshot, password: password)
            }
        } else { performRename(path, to: name, snapshot: snapshot, password: nil) }
    }
    private func performRename(_ path: String, to name: String, snapshot: ArchiveSnapshot, password: String?) {
        guard !sessionEnded, canRenameItems, self.snapshot?.url == snapshot.url else { return }
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        let destination = folder.isEmpty ? name : folder + "/" + name
        let token = begin("Renaming in archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveModificationUpdater().rename(path: path, to: name, in: snapshot, password: password, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries verified"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, password: password, browsingFolder: folder, selectingPath: destination)
                case .failure(let error): present(error)
                }
            }
        }
    }
    @objc func deleteSelected(_ sender: Any?) {
        guard canDeleteItems, let window, window.attachedSheet == nil else { return }
        let paths = selectedPaths()
        guard !paths.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete selected items from this archive?"
        alert.informativeText = "Selected folders and packages include all their contents. This cannot be undone."
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        // Let NSAlert assign its native Cancel/Escape behavior. Destructive
        // actions must not acquire the Return/default-button shortcut.
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.deleteItems(paths)
        }
    }
    /// Called only after the native destructive confirmation.
    func deleteItems(_ paths: Set<String>) {
        guard canDeleteItems, !paths.isEmpty, let snapshot else { return }
        if ArchiveModificationUpdater().canDeleteEncrypted(snapshot) {
            requestArchivePassword(snapshot.url, false, window) { [weak self] password in
                guard let self, let password else { return }
                self.performDeletion(paths, snapshot: snapshot, password: password)
            }
        } else { performDeletion(paths, snapshot: snapshot, password: nil) }
    }
    private func performDeletion(_ paths: Set<String>, snapshot: ArchiveSnapshot, password: String?) {
        guard !sessionEnded, canDeleteItems, self.snapshot?.url == snapshot.url else { return }
        var folder = currentPath
        let index = snapshot.index
        let deleted = Set(snapshot.entries.filter { entry in
            let path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return paths.contains { selected in
                path == selected || (index.row(at: selected)?.isDirectory == true && path.hasPrefix(selected + "/"))
            }
        }.map(\.id))
        while !folder.isEmpty && (index.entryIDs(for: [folder]).allSatisfy { deleted.contains($0) }) {
            folder = folder.split(separator: "/").dropLast().joined(separator: "/")
        }
        let parent = folder
        let token = begin("Deleting from archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveModificationUpdater().delete(paths: paths, from: snapshot, password: password, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries verified"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, password: password, browsingFolder: parent)
                case .failure(let error): present(error)
                }
            }
        }
    }
    @objc func addFiles(_ sender: Any?) { chooseAdditions(folder: false) }
    @objc func addFolder(_ sender: Any?) { chooseAdditions(folder: true) }
    private var canAddToZIP: Bool {
        guard !isBusy, zipAdditionAvailable, let snapshot else { return false }
        return FileManager.default.isWritableFile(atPath: snapshot.url.path)
            && FileManager.default.isWritableFile(atPath: snapshot.url.deletingLastPathComponent().path)
    }
    private var canRenameItems: Bool { canDeleteItems }
    private var canDeleteItems: Bool {
        if canAddItems { return true }
        guard !isBusy, let snapshot, ArchiveModificationUpdater().canDeleteEncrypted(snapshot) else { return false }
        return FileManager.default.isWritableFile(atPath: snapshot.url.path)
            && FileManager.default.isWritableFile(atPath: snapshot.url.deletingLastPathComponent().path)
    }
    private var canAddItems: Bool {
        guard !isBusy, let snapshot, additionCapability.isAvailable || ArchiveAdditionUpdater().canAddEncrypted(snapshot) else { return false }
        return FileManager.default.isWritableFile(atPath: snapshot.url.path)
            && FileManager.default.isWritableFile(atPath: snapshot.url.deletingLastPathComponent().path)
    }
    private func chooseAdditions(folder: Bool) {
        guard canAddItems, let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder; panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = !folder
        panel.prompt = "Add"
        panel.message = "Add \(folder ? "a folder" : "files") at the archive root. Existing names are never replaced."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.addItems(panel.urls)
        }
    }
    /// Shared by both native pickers; all transaction work stays in ArkivCore.
    func addItems(_ urls: [URL], folder: String = "") {
        guard canAddItems, !urls.isEmpty, let snapshot else { return }
        if ArchiveAdditionUpdater().canAddEncrypted(snapshot) {
            requestArchivePassword(snapshot.url, false, window) { [weak self] password in
                guard let self, let password else { return }
                self.performAddition(urls, folder: folder, snapshot: snapshot, password: password)
            }
        } else { performAddition(urls, folder: folder, snapshot: snapshot, password: nil) }
    }
    private func performAddition(_ urls: [URL], folder: String, snapshot: ArchiveSnapshot, password: String?) {
        guard !sessionEnded, canAddItems, self.snapshot?.url == snapshot.url else { return }
        let token = begin("Adding to archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveAdditionUpdater().add(sources: urls, to: snapshot, folder: folder, password: password, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isBusy else { return }
                        self.status.stringValue = "\(progress.files) entries · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) processed"
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                finish()
                modificationFeedback(result)
                switch result {
                case .success(let url):
                    // Publication is already complete. Refresh failures are read errors,
                    // not a failed transaction and never trigger another success sound.
                    self.snapshot = nil; self.index = nil; self.zipAdditionAvailable = false
                    search.stringValue = ""
                    load(url, password: password, browsingFolder: folder)
                case .failure(let error): present(error)
                }
            }
        }
    }
    @objc func extractSelected(_ sender: Any?) {
        guard let index else { return }
        let ids = index.entryIDs(for: selectedPaths())
        guard !ids.isEmpty else { return }
        extract(ids)
    }
    @objc func extractAll(_ sender: Any?) { extract(nil) }
    private func extract(_ ids: [Int64]?) {
        guard let snapshot, !isBusy, let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Extract Here"
        panel.message = "Arkiv creates a new folder here. Existing files are never replaced. Links are preserved; unsupported special files are reported."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let parent = panel.url, let self else { return }
            let token = self.begin("Extracting…")
            self.worker.async { [self] in
                // C callbacks run serially on this worker. Throttle main-thread traffic.
                let throttle = ProgressThrottle()
                let result = Result {
                    try self.engine.extractReporting(snapshot, ids: ids, into: parent, cancellation: token) { [weak self] progress in
                        guard throttle.shouldUpdate() else { return }
                        DispatchQueue.main.async {
                            guard let self, self.isBusy else { return }
                            self.status.stringValue = "\(progress.files) entries • \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) extracted"
                        }
                    }
                }
                DispatchQueue.main.async { [self] in
                    self.finish()
                    ExtractionFeedback.completed(result)
                    switch result {
                    case .success(let output):
                        self.status.stringValue = output.warnings.isEmpty ? "Extraction complete" : "Extraction completed with warnings"
                        if output.warnings.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([output.url]) }
                        ExtractionFeedback.showWarnings(output, parent: self.window)
                    case .failure(let error): self.present(error)
                    }
                }
            }
        }
    }
    private func present(_ error: Error) {
        status.stringValue = error.localizedDescription
        if case ArchiveFailure.cancelled = error { return }
        guard let window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
    private func navigate(_ path: String) {
        guard !isBusy else { return }
        back.append(currentPath); forward.removeAll(); currentPath = path
        search.stringValue = ""; reload(preservingSelection: false)
    }
    @objc func activateRow(_ sender: Any?) {
        activate(row: table.clickedRow)
    }
    func activate(row: Int) {
        guard !isBusy, !sessionEnded, rows.indices.contains(row) else { return }
        if let path = BrowserPresentation.navigationPath(rows[row]) { navigate(path) }
        else if !rows[row].isDirectory, table.selectedRowIndexes.count <= 1 {
            openFile(path: rows[row].path, purpose: .automatic)
        }
    }
    private var selectedRegularFile: ArchiveEntry? {
        let paths = selectedPaths()
        guard paths.count == 1, let path = paths.first, let snapshot else { return nil }
        return ArchiveOpenSession.regularEntry(in: snapshot, path: path)
    }
    @objc func openSelectedFile(_ sender: Any?) {
        guard let entry = selectedRegularFile else { return }
        openFile(path: entry.path)
    }
    @objc func openSelectedArchive(_ sender: Any?) {
        guard let entry = selectedRegularFile else { return }
        openFile(path: entry.path, purpose: .archive)
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook.acceptsControl() }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook.beginControl(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook.endControl(panel) }
    @objc func quickLookSelectedFile(_ sender: Any?) {
        if quickLook.isPresented { quickLook.close(); return }
        guard let entry = selectedRegularFile else { return }
        openFile(path: entry.path, purpose: .preview)
    }
    func handlePreviewKey(_ event: NSEvent) -> Bool {
        guard ArchiveTableView.isPreviewDismissKey(event) else { return false }
        if event.isARepeat { return quickLook.isPresented || filePurpose == .preview }
        if quickLook.isPresented { quickLook.close(); return true }
        if filePurpose == .preview, openRequest != nil {
            cancellation?.cancel(); openRequest = nil; filePurpose = nil; finish(); return true
        }
        guard event.keyCode == 49, !event.isARepeat, !isBusy, !sessionEnded,
              window?.attachedSheet == nil, selectedRegularFile != nil else { return false }
        quickLookSelectedFile(nil)
        return true
    }
    private func finishOpenRequest() {
        openRequest = nil; filePurpose = nil; finish()
    }
    private func openFile(path: String, purpose: FilePurpose = .open) {
        guard !isBusy, !sessionEnded, window?.attachedSheet == nil, let snapshot,
              ArchiveOpenSession.regularEntry(in: snapshot, path: path) != nil else { return }
        let token = begin(purpose == .preview ? "Preparing preview…" : "Opening file…")
        filePurpose = purpose
        let request = UUID(); openRequest = request
        let session = openSession
        let prepare = prepareOpenFile
        worker.async { [weak self] in
            let throttle = ProgressThrottle()
            let result = Result { () throws -> (ArchiveOpenedFile, Bool) in
                let file = try prepare(session, snapshot, path, token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.openRequest == request, !self.sessionEnded else { return }
                        self.status.stringValue = "\(purpose == .preview ? "Preparing preview" : "Opening file") • \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) extracted"
                    }
                }
                do {
                    let archive = (purpose == .automatic || purpose == .archive)
                        ? try LibArchiveEngine().isArchiveCandidate(file.url, cancellation: token) : false
                    return (file, archive)
                } catch { session.discard(file); throw error }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.openRequest == request, !self.sessionEnded else {
                    if case .success(let value) = result { session.discard(value.0) }
                    return
                }
                switch result {
                case .success(let (file, archive)):
                    do {
                        try session.validateForLaunch(file, cancellation: token)
                        if archive {
                            let source = try session.retainForArchive(file, cancellation: token)
                            self.inspectNested(source, file: file, session: session, request: request, token: token)
                            return
                        }
                        self.finishOpenRequest()
                        if purpose == .archive {
                            throw ArchiveFailure.message("This file is not a supported archive. Use Open to open it with its default application.")
                        }
                        if purpose == .preview {
                            guard self.quickLook.present(file.url, owner: self) else {
                                throw ArchiveFailure.message("macOS could not preview this file.")
                            }
                            self.status.stringValue = "Previewing \(file.url.lastPathComponent)"
                            return
                        }
                        guard self.openFileLauncher(file.url) else {
                            throw ArchiveFailure.message("macOS could not open this file with its default application.")
                        }
                        self.status.stringValue = "Opened \(file.url.lastPathComponent) • Changes to this copy are not saved to the archive"
                    } catch { session.discard(file); self.finishOpenRequest(); self.present(error) }
                case .failure(let error): self.finishOpenRequest(); self.present(error)
                }
            }
        }
    }
    private func inspectNested(_ source: ArchiveOpenedFileLease, file: ArchiveOpenedFile,
                               session: ArchiveOpenSession, request: UUID, token: ArchiveCancellation,
                               password: String? = nil) {
        status.stringValue = "Reading nested archive…"
        worker.async { [weak self] in
            let result = Result { try source.inspect(cancellation: token, password: password) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.openRequest == request, !self.sessionEnded else { return }
                do {
                    try session.validateForLaunch(file, cancellation: token)
                    switch result {
                    case .success(let value):
                        guard let open = self.onOpenNestedArchive else {
                            throw ArchiveFailure.message("Cannot open another archive window.")
                        }
                        self.finishOpenRequest()
                        open(value, source)
                        self.status.stringValue = "Opened \(source.url.lastPathComponent) in a new window • Changes are not saved to the outer archive"
                    case .failure(let error):
                        if ArchivePasswordPrompt.isPasswordFailure(error) {
                            self.requestArchivePassword(source.url, password != nil, self.window) { [weak self] supplied in
                                guard let self, self.openRequest == request, !self.sessionEnded else { return }
                                if let supplied, !token.isCancelled {
                                    self.inspectNested(source, file: file, session: session, request: request, token: token, password: supplied)
                                } else { self.finishOpenRequest() }
                            }
                        } else { throw error }
                    }
                } catch { self.finishOpenRequest(); self.present(error) }
            }
        }
    }
    /// Called both for window closure and application termination. In-flight Open
    /// work cannot launch after this boundary; cleanup waits for the writer.
    func endArchiveSession() {
        quickLook.close()
        let nestedOpening = filePurpose == .automatic || filePurpose == .archive
        sessionEnded = true; openRequest = nil; filePurpose = nil
        if nestedOpening, let sheet = window?.attachedSheet { window?.endSheet(sheet, returnCode: .abort) }
        cancellation?.cancel(); openSession.close()
        snapshot = nil; index = nil; archiveSource = nil; dragSession = nil
    }
    private var selectedPackage: BrowserRow? {
        guard table.selectedRowIndexes.count == 1, rows.indices.contains(table.selectedRow),
              BrowserPresentation.packageKind(rows[table.selectedRow]) != nil else { return nil }
        return rows[table.selectedRow]
    }
    @objc func showPackageContents(_ sender: Any?) {
        guard let row = selectedPackage,
              let path = BrowserPresentation.navigationPath(row, showPackageContents: true) else { return }
        navigate(path)
    }
    @objc func goUp(_ sender: Any?) { if !currentPath.isEmpty { navigate(currentPath.split(separator: "/").dropLast().joined(separator: "/")) } }
    @objc func goBack(_ sender: Any?) {
        guard !isBusy, let path = back.popLast() else { return }
        forward.append(currentPath); currentPath = path; search.stringValue = ""; reload(preservingSelection: false)
    }
    @objc func goForward(_ sender: Any?) {
        guard !isBusy, let path = forward.popLast() else { return }
        back.append(currentPath); currentPath = path; search.stringValue = ""; reload(preservingSelection: false)
    }
    /// The title-bar proxy icon follows the selected document icon theme.
    /// Formats without Arkiv artwork keep the icon macOS supplies.
    func applyDocumentIcon() {
        guard let url = window?.representedURL, let button = window?.standardWindowButton(.documentIconButton) else { return }
        if let image = documentIcons.icon(forFileName: url.lastPathComponent, points: 16) { button.image = image }
        else { window?.representedURL = nil; window?.representedURL = url }
    }
    /// A theme change redraws only what shows document icons: the title-bar
    /// proxy icon, the Name column of visible rows, the path bar's archive
    /// item, the welcome list and an open Archive Info sheet. The archive is
    /// not reread and selection, scrolling and sorting are untouched.
    @objc private func documentIconThemeDidChange(_ notification: Notification) {
        applyDocumentIcon()
        reloadNameColumn()
        updatePathControl()
        if snapshot == nil { welcome.reloadRecents() }
        archiveInspector?.refreshIcon()
    }
    private func reloadNameColumn() {
        let column = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        let visible = table.rows(in: table.visibleRect)
        guard column >= 0, visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)), columnIndexes: IndexSet(integer: column))
    }
    /// Density, accent and alternating rows apply to every open window at once.
    @objc private func appearancePreferencesDidChange(_ notification: Notification) {
        guard let changed = notification.object as? AppPreferences else { return }
        applyPresentation(density: changed.density, accent: changed.accent, alternatingRows: changed.alternatingRows)
    }
    func applyPresentation(density: BrowserDensity, accent: AppAccent, alternatingRows: Bool) {
        let densityChanged = density != self.density
        self.density = density
        self.accent = ArkivStyle.customAccent(accent)
        ArkivStyle.stylePrimary(welcome.openButton, accent: accent)
        table.usesAlternatingRowBackgroundColors = alternatingRows
        if densityChanged {
            table.rowHeight = CGFloat(density.rowHeight)
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
        table.enumerateAvailableRowViews { rowView, row in
            (rowView as? ArchiveRowView)?.accent = self.accent
            if densityChanged {
                for column in 0..<rowView.numberOfColumns {
                    if let cell = rowView.view(atColumn: column) as? ArchiveCellView, self.rows.indices.contains(row),
                       let id = cell.identifier?.rawValue {
                        cell.configure(self.rows[row], column: id, searching: !self.search.stringValue.isEmpty, documentIcons: self.documentIcons, density: density)
                    }
                }
            }
        }
        table.needsDisplay = true
    }
    @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) { welcome.needsDisplay = true }
    /// Title shows the archive; the subtitle carries its identity.
    func updateSubtitle() {
        guard let window else { return }
        guard let snapshot else { window.subtitle = ""; return }
        var parts: [String] = []
        if let parent = nestedParentName { parts.append("Inside \(parent)") }
        let metadata = snapshot.metadata
        if let format = metadata?.format { parts.append(format) }
        let files = metadata?.fileCount ?? snapshot.entries.filter { $0.kind == .file }.count
        parts.append(files == 1 ? "1 file" : "\(Self.number(files)) files")
        if let size = metadata?.physicalSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file))
        }
        window.subtitle = parts.joined(separator: " · ")
    }
    private static func number<T: BinaryInteger>(_ value: T) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: Int64(value)), number: .decimal)
    }
    /// Archive name, then each folder; clicking an item navigates there.
    private func updatePathControl() {
        guard let snapshot else { pathControl.pathItems = []; pathControlPaths = []; return }
        var items: [NSPathControlItem] = []
        var paths: [String] = []
        let root = NSPathControlItem()
        root.title = snapshot.url.lastPathComponent
        root.image = documentIcons.icon(forFileName: snapshot.url.lastPathComponent, points: 16) ?? NSWorkspace.shared.icon(for: .archive)
        items.append(root); paths.append("")
        if !search.stringValue.isEmpty {
            let results = NSPathControlItem()
            results.title = "Search results"
            results.image = ArkivStyle.symbol("magnifyingglass", "Search results", pointSize: 11)
            items.append(results); paths.append(currentPath)
        } else {
            var partial: [Substring] = []
            for component in currentPath.split(separator: "/") {
                partial.append(component)
                let item = NSPathControlItem()
                item.title = String(component)
                item.image = Self.folderIcon
                items.append(item); paths.append(partial.joined(separator: "/"))
            }
        }
        pathControl.pathItems = items
        pathControlPaths = paths
        pathControl.toolTip = snapshot.url.lastPathComponent + ": /" + currentPath
    }
    private static let folderIcon: NSImage = {
        let image = NSWorkspace.shared.icon(for: .folder)
        image.size = NSSize(width: 16, height: 16)
        return image
    }()
    @objc func pathControlClicked(_ sender: Any?) {
        guard let item = pathControl.clickedPathItem, let index = pathControl.pathItems.firstIndex(where: { $0 === item }),
              pathControlPaths.indices.contains(index) else { return }
        let path = pathControlPaths[index]
        if path != currentPath || !search.stringValue.isEmpty { navigate(path) }
    }
    private var archiveInspector: ArchiveInspector?
    @objc func showInfo(_ sender: Any?) {
        guard let metadata = snapshot?.metadata, let window, window.attachedSheet == nil else { return }
        let icons = documentIcons
        let inspector = ArchiveInspector(metadata: metadata, iconProvider: { icons.icon(forFileName: metadata.url.lastPathComponent, points: 64) })
        archiveInspector = inspector
        if let panel = inspector.window {
            window.beginSheet(panel) { [weak self] _ in self?.archiveInspector = nil }
        }
    }
    @objc func copyPath(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedPaths().sorted().joined(separator: "\n"), forType: .string)
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    private func reload(preservingSelection: Bool = true) {
        let paths = preservingSelection ? selectedPaths() : []
        rows = search.stringValue.isEmpty ? index?.children(of: currentPath) ?? [] : index?.search(search.stringValue) ?? []
        sortRows()
        updatePathControl()
        table.reloadData()
        table.selectRowIndexes(BrowserPresentation.selection(paths, in: rows), byExtendingSelection: false)
        if !preservingSelection { table.scroll(.zero) }
        noResults.stringValue = !search.stringValue.isEmpty ? "No matching entries"
            : snapshot?.entries.isEmpty == true ? "This archive is empty" : "This folder is empty"
        noResultsIcon.image = ArkivStyle.symbol(!search.stringValue.isEmpty ? "magnifyingglass" : snapshot?.entries.isEmpty == true ? "archivebox" : "folder",
                                                "", pointSize: 30, weight: .light)
        noResultsStack.isHidden = !rows.isEmpty
        updateStatus(); updateControls()
    }
    private func updateStatus() {
        guard !isBusy, let snapshot else { return }
        var text = rows.count == 1 ? "1 item" : "\(Self.number(rows.count)) items"
        if !search.stringValue.isEmpty { text += " found" }
        text += " · \(Self.number(snapshot.entries.count)) in archive"
        let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        if !selected.isEmpty {
            text += " · \(Self.number(selected.count)) selected"
            if let bytes = BrowserPresentation.selectedSize(selected) {
                text += " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
            }
        }
        status.stringValue = text
        status.toolTip = text
    }
    @objc func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != "name",
              let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) else { return }
        column.isHidden.toggle()
        columnPreferences.setHidden(column.isHidden, for: id)
        sender.state = column.isHidden ? .off : .on
    }
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !restoringColumns, let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              table.tableColumns.contains(where: { $0 === column }) else { return }
        columnPreferences.setWidth(Double(column.width), for: column.identifier.rawValue)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { if !dragIsActive { dragSession = nil }; updateStatus(); updateToolbarState(); window?.toolbar?.validateVisibleItems() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? ArchiveCellView ?? ArchiveCellView(column: id.rawValue)
        cell.configure(rows[row], column: id.rawValue, searching: !search.stringValue.isEmpty, documentIcons: documentIcons, density: density)
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: ArchiveRowView.identifier, owner: self) as? ArchiveRowView ?? {
            let view = ArchiveRowView(); view.identifier = ArchiveRowView.identifier; return view
        }()
        view.accent = accent
        return view
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let paths = selectedPaths()
        sortRows(); table.reloadData()
        table.selectRowIndexes(BrowserPresentation.selection(paths, in: rows), byExtendingSelection: false)
        updateStatus()
    }
    private func sortRows() {
        guard let sort = table.sortDescriptors.first else { return }
        rows = BrowserPresentation.sorted(rows, by: sort.key ?? "name", ascending: sort.ascending)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(quickLookSelectedFile(_:)): return quickLook.isPresented || (!sessionEnded && !isBusy && window?.attachedSheet == nil && selectedRegularFile != nil)
        case #selector(openSelectedFile(_:)), #selector(openSelectedArchive(_:)): return !sessionEnded && !isBusy && window?.attachedSheet == nil && selectedRegularFile != nil
        case #selector(showPackageContents(_:)): return !isBusy && selectedPackage != nil
        case #selector(replaceSelected(_:)): return canReplaceFile
        case #selector(updateSelectedFiles(_:)): return canUpdateSelectedFiles && window?.attachedSheet == nil
        case #selector(replaceSelectedFolder(_:)), #selector(updateSelectedFolder(_:)): return canReplaceFolder && window?.attachedSheet == nil
        case #selector(newFolder(_:)): return canCreateFolder && window?.attachedSheet == nil
        case #selector(renameSelected(_:)): return canRenameItems && window?.attachedSheet == nil && selectedPaths().count == 1
        case #selector(deleteSelected(_:)): return canDeleteItems && window?.attachedSheet == nil && !selectedPaths().isEmpty
        case #selector(addFiles(_:)), #selector(addFolder(_:)):
            menuItem.toolTip = canAddItems ? nil : additionCapability.reason
            return canAddItems && window?.attachedSheet == nil
        case #selector(copyPath(_:)), #selector(extractSelected(_:)): return !isBusy && !selectedPaths().isEmpty
        case #selector(testArchive(_:)), #selector(extractAll(_:)), #selector(showInfo(_:)): return !isBusy && snapshot != nil
        case #selector(goUp(_:)): return !isBusy && !currentPath.isEmpty
        case #selector(goBack(_:)): return !isBusy && !back.isEmpty
        case #selector(goForward(_:)): return !isBusy && !forward.isEmpty
        case #selector(focusSearch(_:)): return !isBusy && snapshot != nil
        case #selector(showSettings(_:)): return true
        case #selector(createArchive(_:)): return onCreate != nil
        default: return !isBusy
        }
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let menu = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
        return validateMenuItem(menu)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if openRequest != nil { endArchiveSession(); return true }
        if isBusy { cancel(nil); return false }
        return true
    }
    func windowWillClose(_ notification: Notification) { endArchiveSession(); onClose?() }
    func windowDidBecomeKey(_ notification: Notification) { if snapshot == nil && !isBusy { welcome.reloadRecents() } }
    // MARK: Toolbar

    enum ToolbarID {
        static let navigation = NSToolbarItem.Identifier("navigation")
        static let up = NSToolbarItem.Identifier("up")
        static let open = NSToolbarItem.Identifier("open")
        static let extract = NSToolbarItem.Identifier("extract")
        static let all = NSToolbarItem.Identifier("all")
        static let add = NSToolbarItem.Identifier("add")
        static let quickLook = NSToolbarItem.Identifier("quicklook")
        static let test = NSToolbarItem.Identifier("test")
        static let info = NSToolbarItem.Identifier("info")
        static let search = NSToolbarItem.Identifier("search")
        static let create = NSToolbarItem.Identifier("create")
        static let settings = NSToolbarItem.Identifier("settings")
    }
    /// Navigation sits beside the title; actions are grouped by what they do
    /// (open, extract, edit, inspect) and search ends the row. Settings is
    /// available from the customization palette rather than by default:
    /// macOS already gives it a menu item and ⌘, in every window.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        guard toolbar === browserToolbar else { return [] }
        return [ToolbarID.navigation, .flexibleSpace, ToolbarID.open, .space, ToolbarID.extract, ToolbarID.all, .space,
                ToolbarID.add, ToolbarID.test, ToolbarID.info, ToolbarID.search]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        guard toolbar === browserToolbar else { return [] }
        return [ToolbarID.navigation, ToolbarID.up, ToolbarID.open, ToolbarID.create, ToolbarID.extract, ToolbarID.all, ToolbarID.add,
                ToolbarID.quickLook, ToolbarID.test, ToolbarID.info, ToolbarID.search, ToolbarID.settings, .space, .flexibleSpace]
    }
    private static let toolbarDefinitions: [String: (label: String, symbol: String, action: Selector, tip: String)] = [
        "up": ("Enclosing Folder", "arrow.up", #selector(BrowserWindowController.goUp(_:)), "Go to the enclosing folder (⌘↑)"),
        "open": ("Open", "folder", #selector(BrowserWindowController.openArchive(_:)), "Open another archive (⌘O)"),
        "create": ("Create", "plus.rectangle.on.folder", #selector(BrowserWindowController.createArchive(_:)), "Create a new archive (⇧⌘N)"),
        "extract": ("Extract", "arrow.down.doc", #selector(BrowserWindowController.extractSelected(_:)), "Extract selected files and folders (⌘E)"),
        "all": ("Extract All", "square.and.arrow.down.on.square", #selector(BrowserWindowController.extractAll(_:)), "Extract the entire archive (⇧⌘E)"),
        "quicklook": ("Quick Look", "eye", #selector(BrowserWindowController.quickLookSelectedFile(_:)), "Preview the selected file (Space)"),
        "test": ("Test", "checkmark.shield", #selector(BrowserWindowController.testArchive(_:)), "Test archive data and integrity (⌘T)"),
        "info": ("Info", "info.circle", #selector(BrowserWindowController.showInfo(_:)), "Show archive information (⌘I)"),
        "settings": ("Settings", "gearshape", #selector(BrowserWindowController.showSettings(_:)), "Open Arkiv Settings (⌘,)"),
    ]
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case ToolbarID.navigation:
            let back = makeToolbarItem(NSToolbarItem.Identifier("back"), label: "Back", symbol: "chevron.left", action: #selector(goBack(_:)), tip: "Go back (⌘[)")
            let forward = makeToolbarItem(NSToolbarItem.Identifier("forward"), label: "Forward", symbol: "chevron.right", action: #selector(goForward(_:)), tip: "Go forward (⌘])")
            let group = NSToolbarItemGroup(itemIdentifier: id)
            group.subitems = [back, forward]
            group.label = "Back/Forward"; group.paletteLabel = "Back/Forward"
            group.isNavigational = true
            return group
        case ToolbarID.add:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Add"; item.paletteLabel = "Add"
            item.image = ArkivStyle.symbol("plus", "Add")
            item.toolTip = "Add files or folders to this archive"
            let menu = NSMenu()
            for (title, action) in [("Add Files…", #selector(addFiles(_:))), ("Add Folder…", #selector(addFolder(_:))), ("New Folder…", #selector(newFolder(_:)))] {
                menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
            }
            item.menu = menu
            item.showsIndicator = true
            item.autovalidates = false
            item.isEnabled = canAddItems || canCreateFolder
            return item
        case ToolbarID.search:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField = search
            item.label = "Search"; item.paletteLabel = "Search"
            item.toolTip = search.toolTip
            item.preferredWidthForSearchField = 200
            item.resignsFirstResponderWithCancel = true
            searchItem = item
            return item
        default:
            guard let definition = Self.toolbarDefinitions[id.rawValue] else { return nil }
            return makeToolbarItem(id, label: definition.label, symbol: definition.symbol, action: definition.action, tip: definition.tip)
        }
    }
    private func makeToolbarItem(_ id: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector, tip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label; item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self; item.action = action
        item.isBordered = true
        return item
    }
    /// Items without their own action (the Add menu) are enabled explicitly.
    private func updateToolbarState() {
        for item in browserToolbar.items where item.itemIdentifier == ToolbarID.add {
            item.isEnabled = canAddItems || canCreateFolder
        }
    }
}
private final class ProgressThrottle: @unchecked Sendable {
    // Called only by a single synchronous engine operation.
    private var last = Date.distantPast
    func shouldUpdate() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) > 0.1 else { return false }
        last = now; return true
    }
}
