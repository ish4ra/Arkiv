import AppKit
import ArkivThemes

/// Settings → Appearance → Document Icon Theme.
///
/// Native AppKit only. The catalogue is requested when this pane is shown or
/// the user clicks Refresh, never at launch. Previews are the themes' own
/// artwork (bundled ICNS, installed files or the signed preview pack), loaded
/// for the theme being shown only and released when the pane closes.
@MainActor
final class DocumentIconThemePane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum Row: Equatable {
        case group(String)
        case theme(ThemeEntry)
    }

    let manager: DocumentIconThemeManager
    /// Asks before removing the theme in use; replaced in tests.
    var confirmRemoval: (ThemeEntry, NSWindow?, @escaping (Bool) -> Void) -> Void = DocumentIconThemePane.askBeforeRemoving

    let table = NSTableView()
    private(set) var rows: [Row] = []
    private(set) var shownID: String = DocumentIconThemeID.bundled
    let nameLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let summaryLabel = NSTextField(wrappingLabelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let catalogLabel = NSTextField(wrappingLabelWithString: "")
    let progress = NSProgressIndicator()
    let downloadButton = NSButton(title: "Download", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    let restoreButton = NSButton(title: "Restore Default", target: nil, action: nil)
    let refreshButton = NSButton(title: "Refresh Catalogue", target: nil, action: nil)
    private(set) var previewViews: [DocumentIconName: NSImageView] = [:]
    private var previewCaptions: [DocumentIconName: NSTextField] = [:]
    private var previewTask: Task<Void, Never>?
    private(set) var previewsShownFor: String?
    private var active = false

    init(manager: DocumentIconThemeManager) {
        self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: 760, height: 500))
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    // MARK: Lifecycle

    func activate() {
        guard !active else { return }
        active = true
        manager.onChange = { [weak self] in self?.reload() }
        manager.activate()
        reload()
    }

    func deactivate() {
        guard active else { return }
        active = false
        previewTask?.cancel(); previewTask = nil
        previewsShownFor = nil
        for view in previewViews.values { view.image = nil }
        manager.onChange = nil
        manager.deactivate()
    }

    // MARK: Layout

    private func build() {
        let title = NSTextField(labelWithString: "Document Icon Theme")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let intro = note("Choose the artwork Arkiv uses for archive documents. Seal Dark is included with Arkiv; other themes are optional downloads.")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("theme"))
        column.title = "Theme"
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 34
        table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Document icon themes")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 250).isActive = true

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        detailLabel.textColor = .secondaryLabelColor
        summaryLabel.textColor = .secondaryLabelColor
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 180).isActive = true
        progress.setAccessibilityLabel("Download progress")

        for (button, action) in [(downloadButton, #selector(download(_:))), (cancelButton, #selector(cancelDownload(_:))),
                                 (applyButton, #selector(apply(_:))), (removeButton, #selector(remove(_:))),
                                 (restoreButton, #selector(restoreDefault(_:))), (refreshButton, #selector(refresh(_:)))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        applyButton.keyEquivalent = "\r"

        let grid = NSGridView(numberOfColumns: 6, rows: 0)
        grid.rowSpacing = 6; grid.columnSpacing = 10
        var cells: [NSView] = []
        for name in DocumentIconName.allCases {
            let image = NSImageView()
            image.imageScaling = .scaleProportionallyUpOrDown
            image.translatesAutoresizingMaskIntoConstraints = false
            image.widthAnchor.constraint(equalToConstant: 56).isActive = true
            image.heightAnchor.constraint(equalToConstant: 56).isActive = true
            image.setAccessibilityLabel("\(name.label) document icon")
            let caption = NSTextField(labelWithString: name.label)
            caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            caption.textColor = .secondaryLabelColor
            caption.alignment = .center
            let cell = NSStackView(views: [image, caption])
            cell.orientation = .vertical; cell.spacing = 2
            previewViews[name] = image; previewCaptions[name] = caption
            cells.append(cell)
        }
        stride(from: 0, to: cells.count, by: 6).forEach { start in
            _ = grid.addRow(with: Array(cells[start..<min(start + 6, cells.count)]))
        }

        let actions = NSStackView(views: [downloadButton, applyButton, removeButton, progress, cancelButton])
        actions.spacing = 8
        let detail = NSStackView(views: [nameLabel, detailLabel, summaryLabel, grid, sizeLabel, actions, statusLabel])
        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 10
        detail.setCustomSpacing(4, after: nameLabel)
        detail.setCustomSpacing(16, after: summaryLabel)
        detail.setCustomSpacing(14, after: grid)
        for view in [summaryLabel, statusLabel] { view.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }

        let body = NSStackView(views: [scroll, detail])
        body.alignment = .top; body.spacing = 20
        body.distribution = .fill
        scroll.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true

        let footer = NSStackView(views: [refreshButton, catalogLabel, NSView(), restoreButton])
        footer.spacing = 10
        catalogLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        catalogLabel.textColor = .secondaryLabelColor
        catalogLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let finder = note("Downloaded themes apply inside Arkiv: archive contents, the window title and Archive Info. Finder and Quick Look keep Arkiv’s bundled Seal Dark document icons until a safe, supported way to change them is available. Arkiv never modifies its app bundle, your archives or your default apps.")

        let stack = NSStackView(views: [title, intro, body, footer, finder])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.setCustomSpacing(4, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            body.heightAnchor.constraint(equalToConstant: 330),
        ])
        for view in [intro, body, footer, finder] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return field
    }

    // MARK: Rows

    /// Bundled default first, then families in catalogue order; variations
    /// follow the themes of their family.
    static func rows(for entries: [ThemeEntry]) -> [Row] {
        guard let bundled = entries.first(where: { $0.status == .bundled }) else { return [] }
        var result: [Row] = [.group("Included with Arkiv"), .theme(bundled)]
        var families: [String] = []
        for entry in entries where entry.status != .bundled && !families.contains(entry.familyName) { families.append(entry.familyName) }
        for family in families {
            let members = entries.filter { $0.status != .bundled && $0.familyName == family }
            result.append(.group(family))
            result += members.filter { $0.kind != .variation }.map(Row.theme)
            result += members.filter { $0.kind == .variation }.map(Row.theme)
        }
        return result
    }

    func reload() {
        rows = Self.rows(for: manager.entries)
        table.reloadData()
        let index = rows.firstIndex { if case .theme(let e) = $0 { return e.id == shownID } else { return false } }
            ?? rows.firstIndex { if case .theme = $0 { return true } else { return false } }
        if let index {
            if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            if case .theme(let entry) = rows[index] { shownID = entry.id }
        }
        updateDetail()
        updateCatalogStatus()
    }

    var shownEntry: ThemeEntry? {
        for row in rows { if case .theme(let entry) = row, entry.id == shownID { return entry } }
        return nil
    }

    func show(_ id: String) {
        guard let index = rows.firstIndex(where: { if case .theme(let e) = $0 { return e.id == id } else { return false } }) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        shownID = id
        updateDetail()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { if case .group = rows[row] { return true }; return false }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !self.tableView(tableView, isGroupRow: row) }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { if case .group = rows[row] { return 22 }; return 36 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .group(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        case .theme(let entry):
            return ThemeRowView(entry: entry)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < rows.count, case .theme(let entry) = rows[table.selectedRow] else { return }
        if entry.id != shownID { shownID = entry.id; updateDetail() }
    }

    // MARK: Detail

    static func describe(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    func updateDetail() {
        guard let entry = shownEntry else { return }
        nameLabel.stringValue = entry.name
        var detail = [entry.familyName]
        if let kind = entry.kind { detail.append(kind.displayName) }
        let entries = manager.entries
        let parentName: String? = entry.variantOf.flatMap { parent in entries.first(where: { $0.id == parent })?.name }
        if let parentName { detail.append("Variation of \(parentName)") }
        if entry.isSelected { detail.append("In use") }
        detailLabel.stringValue = detail.joined(separator: " · ")
        var summary = entry.summary
        if let changes = entry.catalog?.variation?.changes, !changes.isEmpty {
            let parent = parentName ?? "the parent theme"
            summary += " Changed artwork: \(changes.joined(separator: ", ")). Every other format uses \(parent)’s artwork."
        }
        if entry.catalog?.isPartial == true {
            summary += " Formats without artwork use the system’s generic icon."
        }
        summaryLabel.stringValue = summary

        switch entry.status {
        case .bundled: sizeLabel.stringValue = "Included with Arkiv"
        default:
            var parts: [String] = []
            if let size = entry.downloadSize { parts.append("Download \(Self.describe(size))") }
            if let size = entry.installedSize { parts.append("Installed \(Self.describe(size))") }
            sizeLabel.stringValue = parts.joined(separator: " · ")
        }

        let busy: Bool
        switch entry.status {
        case .downloading(let value): busy = true; progress.doubleValue = value
        case .installing: busy = true; progress.isIndeterminate = true; progress.startAnimation(nil)
        default: busy = false
        }
        if case .downloading = entry.status { progress.isIndeterminate = false }
        if !busy { progress.stopAnimation(nil) }
        progress.isHidden = !busy
        cancelButton.isHidden = !busy
        cancelButton.isEnabled = { if case .downloading = entry.status { return true } else { return false } }()
        let installedHere = entry.installed != nil
        downloadButton.isHidden = entry.status == .bundled || busy || (installedHere && entry.status != .updateAvailable)
        downloadButton.title = entry.status == .updateAvailable ? "Update" : "Download"
        downloadButton.isEnabled = entry.catalog != nil && { if case .unavailable = entry.status { return false } else { return true } }()
        applyButton.isHidden = !(entry.status == .bundled || installedHere)
        applyButton.isEnabled = !entry.isSelected && !busy
        applyButton.title = entry.isSelected ? "In Use" : "Apply"
        removeButton.isHidden = entry.status == .bundled || !installedHere
        removeButton.isEnabled = !busy
        restoreButton.isEnabled = manager.provider.effectiveSelection != ThemeSelection.bundled

        var status: [String] = []
        switch entry.status {
        case .bundled: status.append(entry.isSelected ? "Seal Dark is in use. It is always available and cannot be removed." : "Always available. Choose Apply or Restore Default to use it.")
        case .available: status.append("Not downloaded.")
        case .downloading(let value): status.append("Downloading… \(Int(value * 100))%")
        case .installing: status.append("Verifying and installing…")
        case .installed: status.append(entry.isSelected ? "Installed and in use. Works offline." : "Installed. Works offline.")
        case .updateAvailable: status.append("A newer version is available. The installed version keeps working until the update is verified.")
        case .unavailable(let reason): status.append(reason + ".")
        }
        if let error = manager.lastError[entry.id] { status.append(error) }
        if manager.provider.damagedTheme == entry.id { status.append("This theme’s files are damaged, so Arkiv is using Seal Dark. Remove it and download it again.") }
        statusLabel.stringValue = status.joined(separator: " ")
        statusLabel.textColor = manager.lastError[entry.id] == nil ? .secondaryLabelColor : .systemRed
        loadPreviews(for: entry)
    }

    private func loadPreviews(for entry: ThemeEntry) {
        let key = "\(entry.id)/\(entry.installed?.version ?? 0)/\(entry.status == .available)"
        guard previewsShownFor != key else { return }
        previewsShownFor = key
        manager.cancelPreviews(except: entry.id)
        previewTask?.cancel()
        let covered = Set(entry.coverage)
        for (name, view) in previewViews {
            view.image = nil
            previewCaptions[name]?.stringValue = covered.contains(name) ? name.label : "\(name.label) · system"
            view.alphaValue = covered.contains(name) ? 1 : 0.35
        }
        guard active else { return }
        let id = entry.id
        previewTask = Task { [weak self] in
            guard let self else { return }
            let images = await self.manager.previews(for: id)
            guard !Task.isCancelled, self.shownID == id else { return }
            for (name, view) in self.previewViews { view.image = images[name] }
            if images.isEmpty, entry.catalog != nil, entry.installed == nil {
                self.statusLabel.stringValue += " Preview unavailable while offline."
            }
        }
    }

    /// Awaitable for tests and screenshots.
    func waitForPreviews() async { await previewTask?.value }

    private func updateCatalogStatus() {
        refreshButton.isEnabled = manager.catalogStatus != .notConfigured && manager.catalogStatus != .loading
        switch manager.catalogStatus {
        case .notConfigured: catalogLabel.stringValue = "Theme downloads are not configured in this build. Installed themes keep working."
        case .idle: catalogLabel.stringValue = ""
        case .loading: catalogLabel.stringValue = "Checking for themes…"
        case .current: catalogLabel.stringValue = "Catalogue verified. \(manager.catalog?.catalog.themes.count ?? 0) themes available."
        case .offline(let reason): catalogLabel.stringValue = "Offline: showing the last verified catalogue. \(reason)"
        case .failed(let reason): catalogLabel.stringValue = reason
        }
    }

    // MARK: Actions

    @objc func download(_ sender: Any?) { manager.download(shownID) }
    @objc func cancelDownload(_ sender: Any?) { manager.cancel(shownID) }
    @objc func refresh(_ sender: Any?) { manager.refreshCatalog() }
    @objc func restoreDefault(_ sender: Any?) { manager.restoreDefault() }
    @objc func apply(_ sender: Any?) {
        do { try manager.apply(shownID) } catch { statusLabel.stringValue = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
    @objc func remove(_ sender: Any?) {
        guard let entry = shownEntry, entry.installed != nil else { return }
        let perform = { [weak self] in
            guard let self else { return }
            do { try self.manager.remove(entry.id) } catch { self.statusLabel.stringValue = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
        if entry.isSelected {
            confirmRemoval(entry, window) { confirmed in if confirmed { perform() } }
        } else { perform() }
    }

    static func askBeforeRemoving(_ entry: ThemeEntry, _ window: NSWindow?, _ completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(entry.name)”?"
        alert.informativeText = "This theme is in use. Arkiv will switch to Seal Dark, then delete the downloaded files. You can download it again later."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if let window { alert.beginSheetModal(for: window) { completion($0 == .alertFirstButtonReturn) } }
        else { completion(alert.runModal() == .alertFirstButtonReturn) }
    }
}

/// One theme row: name and a text status (never colour alone).
final class ThemeRowView: NSTableCellView {
    init(entry: ThemeEntry) {
        super.init(frame: .zero)
        let name = NSTextField(labelWithString: entry.name)
        name.lineBreakMode = .byTruncatingTail
        let status = NSTextField(labelWithString: Self.status(entry))
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, status])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 0
        let mark = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "In use") ?? NSImage())
        mark.isHidden = !entry.isSelected
        mark.contentTintColor = .controlAccentColor
        let row = NSStackView(views: [text, NSView(), mark])
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let indent: CGFloat = entry.kind == .variation ? 14 : 2
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = name
        setAccessibilityLabel("\(entry.name), \(Self.status(entry))")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    static func status(_ entry: ThemeEntry) -> String {
        var parts: [String] = []
        if entry.isSelected { parts.append("In use") }
        switch entry.status {
        case .bundled: parts.append("Bundled")
        case .available: parts.append("Available" + (entry.downloadSize.map { " · " + DocumentIconThemePane.describe($0) } ?? ""))
        case .downloading(let value): parts.append("Downloading \(Int(value * 100))%")
        case .installing: parts.append("Installing")
        case .installed: parts.append("Installed")
        case .updateAvailable: parts.append("Update available")
        case .unavailable(let reason): parts.append(reason)
        }
        if entry.kind == .variation { parts.append("Variation") }
        return parts.joined(separator: " · ")
    }
}
