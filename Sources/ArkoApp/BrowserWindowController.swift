import AppKit
import ArkoCore

final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    var onClose: (() -> Void)?
    private(set) var isBusy = false
    private let table = NSTableView()
    private let search = NSSearchField()
    private let pathLabel = NSTextField(labelWithString: "Open an archive to begin")
    private let status = NSTextField(labelWithString: "ZIP and TAR • Browse before extracting")
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var snapshot: ArchiveSnapshot?
    private var index: ArchiveIndex?
    private var rows: [BrowserRow] = []
    private var currentPath = ""
    private var back: [String] = []
    private var forward: [String] = []
    private var cancellation: ArchiveCancellation?
    private let engine = LibArchiveEngine()
    private let worker = DispatchQueue(label: "app.arko.archive", qos: .userInitiated)

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Arko"
        window.minSize = NSSize(width: 640, height: 360)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.contentView = makeContent()
        let toolbar = NSToolbar(identifier: "ArkoBrowser")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func makeContent() -> NSView {
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 24
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(activateRow(_:))
        table.setAccessibilityLabel("Archive contents")
        for (id, title, width) in [("name", "Name", 440.0), ("size", "Size", 120.0), ("type", "Kind", 160.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = 80
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        let menu = NSMenu()
        let extract = menu.addItem(withTitle: "Extract Selected…", action: #selector(extractSelected(_:)), keyEquivalent: "")
        extract.target = self
        let copy = menu.addItem(withTitle: "Copy Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        copy.target = self
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        search.placeholderString = "Search archive paths"
        search.delegate = self
        search.setAccessibilityLabel("Search archive paths")
        search.widthAnchor.constraint(equalToConstant: 230).isActive = true
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let navigation = NSStackView(views: [pathLabel, search])
        navigation.spacing = 12; navigation.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        cancelButton.target = self; cancelButton.action = #selector(cancel(_:)); cancelButton.isHidden = true
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [status, spinner, cancelButton])
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        let content = NSStackView(views: [navigation, scroll, footer])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 0
        for child in [navigation, scroll, footer] { child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return content
    }
    func load(_ url: URL) {
        guard !isBusy else { return }
        let token = begin("Reading archive…")
        worker.async { [self] in
            let result = Result { try self.engine.inspect(url, cancellation: token) }
            DispatchQueue.main.async { [self] in
                self.finish()
                switch result {
                case .success(let value):
                    self.snapshot = value; self.index = value.index
                    self.currentPath = ""; self.back = []; self.forward = []
                    self.window?.title = url.lastPathComponent
                    self.window?.representedURL = url
                    self.reload()
                case .failure(let error): self.present(error)
                }
            }
        }
    }
    private func begin(_ message: String) -> ArchiveCancellation {
        let token = ArchiveCancellation(); cancellation = token
        isBusy = true; search.isEnabled = false
        status.stringValue = message; spinner.startAnimation(nil); cancelButton.isHidden = false
        window?.toolbar?.validateVisibleItems()
        return token
    }
    private func finish() {
        isBusy = false; cancellation = nil; search.isEnabled = true
        spinner.stopAnimation(nil); cancelButton.isHidden = true
        window?.toolbar?.validateVisibleItems()
    }
    @objc func cancel(_ sender: Any?) { cancellation?.cancel(); status.stringValue = "Cancelling…" }
    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search) }
    private func selectedPaths() -> Set<String> {
        Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].path : nil })
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
        panel.message = "Arko creates a new folder here. Existing files are never replaced. Links and special files are rejected."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let parent = panel.url, let self else { return }
            let token = self.begin("Extracting…")
            self.worker.async { [self] in
                // C callbacks run serially on this worker. Throttle main-thread traffic.
                let throttle = ProgressThrottle()
                let result = Result {
                    try self.engine.extract(snapshot, ids: ids, into: parent, cancellation: token) { [weak self] progress in
                        guard throttle.shouldUpdate() else { return }
                        DispatchQueue.main.async {
                            guard let self, self.isBusy else { return }
                            self.status.stringValue = "\(progress.files) entries • \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file)) extracted"
                        }
                    }
                }
                DispatchQueue.main.async { [self] in
                    self.finish()
                    switch result {
                    case .success(let output):
                        self.status.stringValue = "Extraction complete"
                        NSWorkspace.shared.activateFileViewerSelecting([output])
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
        search.stringValue = ""; reload()
    }
    @objc func activateRow(_ sender: Any?) {
        guard rows.indices.contains(table.clickedRow), rows[table.clickedRow].isDirectory else { return }
        navigate(rows[table.clickedRow].path)
    }
    @objc func goUp(_ sender: Any?) { if !currentPath.isEmpty { navigate(currentPath.split(separator: "/").dropLast().joined(separator: "/")) } }
    @objc func goBack(_ sender: Any?) {
        guard !isBusy, let path = back.popLast() else { return }
        forward.append(currentPath); currentPath = path; search.stringValue = ""; reload()
    }
    @objc func goForward(_ sender: Any?) {
        guard !isBusy, let path = forward.popLast() else { return }
        back.append(currentPath); currentPath = path; search.stringValue = ""; reload()
    }
    @objc func showInfo(_ sender: Any?) {
        guard let snapshot, let window else { return }
        let alert = NSAlert()
        alert.messageText = snapshot.url.lastPathComponent
        alert.informativeText = "\(snapshot.entries.count) entries\nBackend: \(LibArchiveEngine.version)\n\nRead-only browser. Extraction limit: 100,000 entries / 20 GiB. Encryption, modification, and creation are not available in this milestone."
        alert.beginSheetModal(for: window)
    }
    @objc func copyPath(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedPaths().sorted().joined(separator: "\n"), forType: .string)
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    private func reload() {
        rows = search.stringValue.isEmpty ? index?.children(of: currentPath) ?? [] : index?.search(search.stringValue) ?? []
        sortRows()
        pathLabel.stringValue = snapshot == nil ? "Open an archive with ⌘O" : "/" + currentPath
        table.reloadData(); updateStatus()
        window?.toolbar?.validateVisibleItems()
    }
    private func updateStatus() {
        guard !isBusy else { return }
        status.stringValue = "\(table.selectedRowIndexes.count) selected • \(rows.count) shown • \(snapshot?.entries.count ?? 0) archive entries"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateStatus(); window?.toolbar?.validateVisibleItems() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let id = tableColumn?.identifier.rawValue ?? "name"
        let text: String
        switch id {
        case "size": text = entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        case "type": text = entry.isDirectory ? "Folder" : "File"
        default: text = search.stringValue.isEmpty ? entry.name : entry.path
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingMiddle
        cell.font = .systemFont(ofSize: NSFont.systemFontSize)
        return cell
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortRows(); table.reloadData()
    }
    private func sortRows() {
        guard let sort = table.sortDescriptors.first else { return }
        rows.sort { lhs, rhs in
            let comparison: ComparisonResult
            switch sort.key {
            case "size": comparison = (lhs.size ?? -1) == (rhs.size ?? -1) ? .orderedSame : (lhs.size ?? -1) < (rhs.size ?? -1) ? .orderedAscending : .orderedDescending
            case "type": comparison = lhs.isDirectory == rhs.isDirectory ? lhs.name.localizedStandardCompare(rhs.name) : lhs.isDirectory ? .orderedAscending : .orderedDescending
            default: comparison = lhs.name.localizedStandardCompare(rhs.name)
            }
            return sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(extractSelected(_:)): return !isBusy && !selectedPaths().isEmpty
        case #selector(extractAll(_:)), #selector(showInfo(_:)): return !isBusy && snapshot != nil
        case #selector(goUp(_:)): return !isBusy && !currentPath.isEmpty
        case #selector(goBack(_:)): return !isBusy && !back.isEmpty
        case #selector(goForward(_:)): return !isBusy && !forward.isEmpty
        default: return !isBusy
        }
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let menu = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
        return validateMenuItem(menu)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isBusy { cancel(nil); return false }
        return true
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("back"), NSToolbarItem.Identifier("up"), .flexibleSpace, NSToolbarItem.Identifier("extract"), NSToolbarItem.Identifier("all"), NSToolbarItem.Identifier("info")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let definitions: [String: (String, String, Selector)] = [
            "back": ("Back", "chevron.left", #selector(goBack(_:))),
            "up": ("Up", "arrow.up", #selector(goUp(_:))),
            "extract": ("Extract Selected", "arrow.down.doc", #selector(extractSelected(_:))),
            "all": ("Extract All", "square.and.arrow.down", #selector(extractAll(_:))),
            "info": ("Info", "info.circle", #selector(showInfo(_:)))
        ]
        guard let (title, symbol, action) = definitions[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = title; item.paletteLabel = title; item.toolTip = title
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
