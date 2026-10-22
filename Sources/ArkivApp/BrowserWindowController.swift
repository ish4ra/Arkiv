import AppKit
import Quartz
import ArkivCore
import ArkivPresentation

final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    var onClose: (() -> Void)?
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
    private var dragSession: ArchiveDragSession?
    private var dragIsActive = false
    private let dragQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "xyz.isharalakshan.arkiv.file-promises"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let search = NSSearchField()
    private let pathLabel = NSTextField(labelWithString: "Open an archive to begin")
    private let status = NSTextField(labelWithString: "ZIP and TAR • Browse before extracting")
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let emptyView = NSView()
    private let browserView = NSView()
    private let footer = NSStackView()
    private let emptyOpenButton = NSButton(title: "Open Archive…", target: nil, action: nil)
    private let noResults = NSTextField(labelWithString: "")
    private var navigationButtons: [NSButton] = []
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
    private let worker = DispatchQueue(label: "xyz.isharalakshan.arkiv.archive", qos: .userInitiated)

    init(modificationFeedback: @escaping (Result<URL, Error>) -> Void = { ExtractionFeedback.completed($0) },
         quickLook: ArchiveQuickLookPresenting = ArchiveQuickLook(),
         openFileLauncher: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         prepareOpenFile: @escaping (ArchiveOpenSession, ArchiveSnapshot, String, ArchiveCancellation, @escaping @Sendable (ArchiveProgress) -> Void) throws -> ArchiveOpenedFile = {
             try $0.prepare($1, path: $2, cancellation: $3, progress: $4)
         },
         requestArchivePassword: @escaping (URL, Bool, NSWindow?, @escaping (String?) -> Void) -> Void = {
             ArchivePasswordPrompt.ask(archive: $0, retry: $1, parent: $2, completion: $3)
         }) {
        self.quickLook = quickLook
        self.modificationFeedback = modificationFeedback
        self.openFileLauncher = openFileLauncher
        self.prepareOpenFile = prepareOpenFile
        self.requestArchivePassword = requestArchivePassword
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Arkiv"
        window.minSize = NSSize(width: 640, height: 360)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = makeContent()
        let toolbar = NSToolbar(identifier: "ArkivBrowser")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func makeContent() -> NSView {
        table.previewKeyHandler = { [weak self] event in self?.handlePreviewKey(event) ?? false }
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain
        table.backgroundColor = .textBackgroundColor
        table.allowsMultipleSelection = true
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(activateRow(_:))
        table.setAccessibilityLabel("Archive contents")
        for (id, title, width) in [("name", "Name", 500.0), ("size", "Size", 110.0), ("type", "Kind", 130.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "name" ? 180 : 80
            column.resizingMask = [.autoresizingMask, .userResizingMask]
            column.headerCell.alignment = id == "size" ? .right : .left
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openSelectedFile(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open as Archive", action: #selector(openSelectedArchive(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quick Look", action: #selector(quickLookSelectedFile(_:)), keyEquivalent: "").target = self
        let contents = menu.addItem(withTitle: "Show Package Contents", action: #selector(showPackageContents(_:)), keyEquivalent: "")
        contents.target = self
        let extract = menu.addItem(withTitle: "Extract Selected…", action: #selector(extractSelected(_:)), keyEquivalent: "")
        extract.target = self
        let copy = menu.addItem(withTitle: "Copy Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(.separator())
        for (title, action) in [("Add Files…", #selector(addFiles(_:))), ("Add Folder…", #selector(addFolder(_:)))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        menu.addItem(withTitle: "Replace File…", action: #selector(replaceSelected(_:)), keyEquivalent: "").target = self
        let rename = menu.addItem(withTitle: "Rename…", action: #selector(renameSelected(_:)), keyEquivalent: "")
        rename.target = self
        let delete = menu.addItem(withTitle: "Delete…", action: #selector(deleteSelected(_:)), keyEquivalent: "")
        delete.target = self
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        search.placeholderString = "Search archive"
        search.controlSize = .small
        search.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        search.delegate = self
        search.setAccessibilityLabel("Search archive paths")
        search.toolTip = "Search all paths in this archive (⌘F)"
        search.widthAnchor.constraint(equalToConstant: 180).isActive = true
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.setAccessibilityLabel("Current folder")
        let definitions: [(String, String, Selector)] = [
            ("Back (⌘[)", "chevron.left", #selector(goBack(_:))),
            ("Forward (⌘])", "chevron.right", #selector(goForward(_:))),
            ("Up to parent folder (⌘↑)", "arrow.up", #selector(goUp(_:)))
        ]
        navigationButtons = definitions.map { title, symbol, action in
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
            button.bezelStyle = .texturedRounded; button.controlSize = .small
            button.toolTip = title; button.setAccessibilityLabel(title)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            return button
        }
        let navigation = NSStackView(views: navigationButtons + [pathLabel, search])
        navigation.spacing = 6; navigation.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        let separator = NSBox(); separator.boxType = .separator
        let browser = NSStackView(views: [navigation, separator, scroll])
        browser.orientation = .vertical; browser.alignment = .leading; browser.spacing = 0
        for child in [navigation, separator, scroll] { child.widthAnchor.constraint(equalTo: browser.widthAnchor).isActive = true }
        pin(browser, inside: browserView)
        noResults.font = .systemFont(ofSize: 13); noResults.textColor = .secondaryLabelColor
        noResults.translatesAutoresizingMaskIntoConstraints = false
        browserView.addSubview(noResults)
        NSLayoutConstraint.activate([noResults.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            noResults.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)])

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let title = NSTextField(labelWithString: "Arkiv")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let description = NSTextField(labelWithString: "Browse an archive and choose what to extract.")
        description.font = .systemFont(ofSize: 13); description.textColor = .secondaryLabelColor
        emptyOpenButton.target = self; emptyOpenButton.action = #selector(openArchive(_:))
        emptyOpenButton.bezelStyle = .rounded
        emptyOpenButton.toolTip = "Choose an archive to browse (⌘O)"
        let hint = NSTextField(labelWithString: "⌘O to open an archive")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let welcome = NSStackView(views: [icon, title, description, emptyOpenButton, hint])
        welcome.orientation = .vertical; welcome.alignment = .centerX; welcome.spacing = 10
        welcome.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(welcome)
        NSLayoutConstraint.activate([welcome.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            welcome.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor)])
        let body = NSView()
        pin(browserView, inside: body); pin(emptyView, inside: body)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        cancelButton.target = self; cancelButton.action = #selector(cancel(_:)); cancelButton.isHidden = true
        cancelButton.bezelStyle = .rounded; cancelButton.controlSize = .small
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(status); footer.addArrangedSubview(spinner); footer.addArrangedSubview(cancelButton)
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        let content = NSStackView(views: [body, footer])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 0
        for child in [body, footer] { child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        updateControls()
        return content
    }
    private func pin(_ child: NSView, inside parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)])
    }
    @objc func openArchive(_ sender: Any?) { onOpen?() }
    private func updateControls() {
        emptyView.isHidden = snapshot != nil
        browserView.isHidden = snapshot == nil
        footer.isHidden = snapshot == nil && !isBusy
        emptyOpenButton.isEnabled = !isBusy
        for button in navigationButtons {
            button.isEnabled = validateMenuItem(NSMenuItem(title: "", action: button.action, keyEquivalent: ""))
        }
        window?.toolbar?.validateVisibleItems()
    }
    func load(_ url: URL, password: String? = nil, browsingFolder: String = "", selectingPath: String? = nil) {
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
                    self.snapshot = value; self.index = value.index; self.zipAdditionAvailable = capability == .zip; self.additionCapability = capability
                    self.currentPath = value.index.row(at: browsingFolder)?.isDirectory == true ? browsingFolder : ""; self.back = []; self.forward = []
                    self.window?.title = url.lastPathComponent
                    self.window?.representedURL = url
                    self.reload()
                    if let selectingPath, let row = self.rows.firstIndex(where: { $0.path == selectingPath }) {
                        self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        self.table.scrollRowToVisible(row)
                    }
                    self.window?.makeFirstResponder(self.table)
                case .failure(let error):
                    if ArchivePasswordPrompt.isPasswordFailure(error) {
                        ArchivePasswordPrompt.ask(archive: url, retry: password != nil, parent: self.window) { [weak self] supplied in
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
    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
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
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        let token = begin("Replacing file in archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveModificationUpdater().replace(path: path, with: source, in: snapshot, cancellation: token) { progress in
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
                    load(url, browsingFolder: folder, selectingPath: path)
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
        guard !isBusy, additionCapability.isAvailable, let snapshot else { return false }
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
        let token = begin("Adding to archive…")
        worker.async { [self] in
            let throttle = ProgressThrottle()
            let result = Result {
                try ArchiveAdditionUpdater().add(sources: urls, to: snapshot, folder: folder, cancellation: token) { progress in
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
                    load(url, browsingFolder: folder)
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
    deinit { quickLook.close(); openSession.close() }
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
    @objc func showInfo(_ sender: Any?) {
        guard let snapshot, let window else { return }
        let alert = NSAlert()
        alert.messageText = snapshot.url.lastPathComponent
        alert.informativeText = "\(snapshot.entries.count) entries\nBackend: \(LibArchiveEngine.version)\n\nExtraction limit: 100,000 entries / 20 GiB. ZIP and 7z creation are available from File → Create Archive. 7z supports AES-256. Add Files/Add Folder, Delete, Rename, and Replace File are available for supported writable ZIPs. Other modification is unavailable."
        alert.beginSheetModal(for: window)
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
        pathLabel.stringValue = currentPath.isEmpty ? (snapshot?.url.lastPathComponent ?? "") : "/" + currentPath
        pathLabel.toolTip = (snapshot?.url.lastPathComponent ?? "") + ": /" + currentPath
        table.reloadData()
        table.selectRowIndexes(BrowserPresentation.selection(paths, in: rows), byExtendingSelection: false)
        if !preservingSelection { table.scroll(.zero) }
        noResults.stringValue = search.stringValue.isEmpty ? "This folder is empty" : "No matching entries"
        noResults.isHidden = !rows.isEmpty
        updateStatus(); updateControls()
    }
    private func updateStatus() {
        guard !isBusy, let snapshot else { return }
        var text = "\(rows.count) shown · \(snapshot.entries.count) archive entries"
        let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        if !selected.isEmpty {
            text += " · \(selected.count) selected"
            if let bytes = BrowserPresentation.selectedSize(selected) {
                text += " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
            }
        }
        status.stringValue = text
        status.toolTip = text
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { if !dragIsActive { dragSession = nil }; updateStatus(); window?.toolbar?.validateVisibleItems() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? ArchiveCellView ?? ArchiveCellView(column: id.rawValue)
        cell.configure(rows[row], column: id.rawValue, searching: !search.stringValue.isEmpty)
        return cell
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
        case #selector(renameSelected(_:)): return canRenameItems && window?.attachedSheet == nil && selectedPaths().count == 1
        case #selector(deleteSelected(_:)): return canDeleteItems && window?.attachedSheet == nil && !selectedPaths().isEmpty
        case #selector(addFiles(_:)), #selector(addFolder(_:)):
            menuItem.toolTip = additionCapability.reason
            return canAddItems && window?.attachedSheet == nil
        case #selector(copyPath(_:)), #selector(extractSelected(_:)): return !isBusy && !selectedPaths().isEmpty
        case #selector(testArchive(_:)), #selector(extractAll(_:)), #selector(showInfo(_:)): return !isBusy && snapshot != nil
        case #selector(goUp(_:)): return !isBusy && !currentPath.isEmpty
        case #selector(goBack(_:)): return !isBusy && !back.isEmpty
        case #selector(goForward(_:)): return !isBusy && !forward.isEmpty
        case #selector(focusSearch(_:)): return !isBusy && snapshot != nil
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
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("open"), .flexibleSpace, NSToolbarItem.Identifier("extract"), NSToolbarItem.Identifier("all"), NSToolbarItem.Identifier("test"), NSToolbarItem.Identifier("info")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let definitions: [String: (String, String, Selector)] = [
            "open": ("Open Archive", "folder", #selector(openArchive(_:))),
            "extract": ("Extract Selected", "arrow.down.doc", #selector(extractSelected(_:))),
            "all": ("Extract All", "square.and.arrow.down", #selector(extractAll(_:))),
            "test": ("Test Archive", "checkmark.shield", #selector(testArchive(_:))),
            "info": ("Info", "info.circle", #selector(showInfo(_:)))
        ]
        guard let (title, symbol, action) = definitions[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = title; item.paletteLabel = title
        let tips = ["open": "Open an archive (⌘O)", "extract": "Extract selected files and folders (⌘E)",
            "all": "Extract the entire archive (⇧⌘E)", "info": "Show archive information (⌘I)"]
        item.toolTip = tips[id.rawValue]
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self; item.action = action
        return item
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
