import AppKit
import ArkivThemes
import ArkivPresentation

/// Settings → Document Icons: the theme gallery.
///
/// * A banner names the theme in use and offers Restore Default.
/// * The list groups themes by family under fixed (non-floating) headings;
///   each family's variations fold under their parent theme. A filter field
///   narrows the list.
/// * The detail shows the theme's real artwork on a uniform grid: the 11
///   Finder formats, then the compound-suffix and volume icons Arkiv draws in
///   its own windows.
///
/// Native AppKit only. The catalogue is requested when this pane is shown or
/// on Refresh Catalogue, never at launch. List thumbnails use only artwork
/// already on this Mac; full previews download only for the theme being
/// shown, and are released when the pane closes.
@MainActor
final class DocumentIconThemePane: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum Row: Equatable {
        case group(String)
        case theme(ThemeEntry)
        /// "Show/Hide N variations" under a parent theme.
        case variations(parent: String, count: Int, expanded: Bool)
    }

    let manager: DocumentIconThemeManager
    /// Asks before removing the theme in use; replaced in tests.
    var confirmRemoval: (ThemeEntry, NSWindow?, @escaping (Bool) -> Void) -> Void = DocumentIconThemePane.askBeforeRemoving
    /// Called when the theme in use changes (Settings updates its summary).
    var onCurrentThemeChange: (() -> Void)?

    let table = NSTableView()
    let filterField = NSSearchField()
    private(set) var rows: [Row] = []
    private(set) var shownID: String = DocumentIconThemeID.bundled
    private(set) var expandedParents: Set<String> = []
    // Banner
    let currentIcon = NSImageView()
    let currentLabel = NSTextField(labelWithString: "")
    let currentDetail = NSTextField(labelWithString: "")
    // Detail
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
    /// Compound-suffix and split-volume artwork Arkiv uses in its own windows.
    private(set) var extraPreviewViews: [DocumentIconExtra: NSImageView] = [:]
    private var extraCaptions: [DocumentIconExtra: NSTextField] = [:]
    let extrasHeading = NSTextField(wrappingLabelWithString: "Inside Arkiv only: .tar.gz, .tar.bz2, .tar.xz, .tar.zst, .tzst and split 7z volumes. Finder shows the family icon for these names. Dimmed artwork is not part of this theme; Arkiv uses the system icon (formats) or the family icon (extras) instead.")
    private var previewTask: Task<Void, Never>?
    private(set) var previewsShownFor: String?
    private var active = false
    private var lastSelection: ThemeSelection?

    static let listWidth: CGFloat = 232
    static let previewColumn: CGFloat = 58

    init(manager: DocumentIconThemeManager) {
        self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: 670, height: 588))
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
        for view in extraPreviewViews.values { view.image = nil }
        manager.onChange = nil
        manager.deactivate()
    }

    // MARK: Layout

    private func build() {
        // Banner: the theme in use.
        currentIcon.imageScaling = .scaleProportionallyUpOrDown
        currentIcon.setAccessibilityElement(false)
        currentIcon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        currentIcon.heightAnchor.constraint(equalToConstant: 36).isActive = true
        currentLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        currentLabel.lineBreakMode = .byTruncatingTail
        currentDetail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        currentDetail.textColor = .secondaryLabelColor
        let currentTexts = NSStackView(views: [currentLabel, currentDetail])
        currentTexts.orientation = .vertical; currentTexts.alignment = .leading; currentTexts.spacing = 1
        let banner = NSStackView(views: [currentIcon, currentTexts, NSView(), restoreButton])
        banner.orientation = .horizontal; banner.alignment = .centerY; banner.spacing = 12
        banner.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        banner.translatesAutoresizingMaskIntoConstraints = false
        let bannerCard = ArkivCardView()
        bannerCard.translatesAutoresizingMaskIntoConstraints = false
        bannerCard.addSubview(banner)
        pinEdges(banner, to: bannerCard)
        bannerCard.setAccessibilityElement(true)
        bannerCard.setAccessibilityRole(.group)
        bannerCard.setAccessibilityLabel("Theme in use")

        // List.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("theme"))
        column.title = "Theme"
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        // Fixed headings: floating group rows drew over the rows beneath them.
        table.floatsGroupRows = false
        table.backgroundColor = .clear
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(rowClicked(_:))
        table.setAccessibilityLabel("Document icon themes")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        filterField.placeholderString = "Filter themes"
        filterField.controlSize = .small
        filterField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        filterField.delegate = self
        filterField.setAccessibilityLabel("Filter themes by name or family")
        filterField.translatesAutoresizingMaskIntoConstraints = false
        let listCard = ArkivCardView()
        listCard.translatesAutoresizingMaskIntoConstraints = false
        listCard.addSubview(filterField); listCard.addSubview(scroll)
        NSLayoutConstraint.activate([
            filterField.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 8),
            filterField.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -8),
            filterField.topAnchor.constraint(equalTo: listCard.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: listCard.bottomAnchor, constant: -4),
            listCard.widthAnchor.constraint(equalToConstant: Self.listWidth),
        ])

        // Detail.
        nameLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.preferredMaxLayoutWidth = 370
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.preferredMaxLayoutWidth = 370
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true
        progress.setAccessibilityLabel("Download progress")
        for (button, action) in [(downloadButton, #selector(download(_:))), (cancelButton, #selector(cancelDownload(_:))),
                                 (applyButton, #selector(apply(_:))), (removeButton, #selector(remove(_:))),
                                 (restoreButton, #selector(restoreDefault(_:))), (refreshButton, #selector(refresh(_:)))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        refreshButton.controlSize = .small
        refreshButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        applyButton.keyEquivalent = "\r"
        ArkivStyle.stylePrimary(applyButton, accent: AppPreferencesAccess.accent)
        downloadButton.image = ArkivStyle.symbol("arrow.down.circle", "Download")
        downloadButton.imagePosition = .imageLeading

        let previewGrid = makePreviewGrid()
        let extrasGrid = makeExtrasGrid()
        extrasHeading.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        extrasHeading.textColor = .tertiaryLabelColor
        extrasHeading.preferredMaxLayoutWidth = 350
        let extrasTitle = NSTextField(labelWithString: "Inside Arkiv only")
        extrasTitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        extrasTitle.textColor = .secondaryLabelColor
        let separator = NSBox(); separator.boxType = .separator
        let previewStack = NSStackView(views: [previewGrid, separator, extrasTitle, extrasGrid, extrasHeading])
        previewStack.orientation = .vertical; previewStack.alignment = .leading; previewStack.spacing = 8
        previewStack.setCustomSpacing(12, after: previewGrid)
        previewStack.setCustomSpacing(6, after: extrasGrid)
        previewStack.edgeInsets = NSEdgeInsets(top: 14, left: 13, bottom: 12, right: 13)
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalTo: previewStack.widthAnchor, constant: -26).isActive = true
        let previewCard = ArkivCardView()
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(previewStack)
        pinEdges(previewStack, to: previewCard)
        previewCard.setAccessibilityElement(true)
        previewCard.setAccessibilityRole(.group)
        previewCard.setAccessibilityLabel("Theme artwork preview")

        let actions = NSStackView(views: [downloadButton, applyButton, removeButton, progress, cancelButton])
        actions.spacing = 8
        let detail = NSStackView(views: [nameLabel, detailLabel, actions, summaryLabel, previewCard, sizeLabel, statusLabel])
        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 8
        detail.setCustomSpacing(2, after: nameLabel)
        detail.setCustomSpacing(12, after: detailLabel)
        detail.setCustomSpacing(12, after: summaryLabel)
        detail.setCustomSpacing(10, after: previewCard)
        detail.setCustomSpacing(4, after: sizeLabel)
        detail.translatesAutoresizingMaskIntoConstraints = false
        for view in [nameLabel, detailLabel, summaryLabel, statusLabel] {
            view.widthAnchor.constraint(lessThanOrEqualTo: detail.widthAnchor).isActive = true
        }
        previewCard.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true

        let body = NSStackView(views: [listCard, detail])
        body.orientation = .horizontal; body.alignment = .top; body.spacing = 18
        body.translatesAutoresizingMaskIntoConstraints = false
        listCard.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true

        catalogLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        catalogLabel.textColor = .secondaryLabelColor
        catalogLabel.maximumNumberOfLines = 2
        catalogLabel.preferredMaxLayoutWidth = 470
        catalogLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [refreshButton, catalogLabel])
        footer.orientation = .horizontal; footer.spacing = 10; footer.alignment = .centerY

        let finder = NSTextField(wrappingLabelWithString: "Downloaded themes apply inside Arkiv: archive contents, the window title, the path bar, recent archives and Archive Info. Finder keeps Arkiv’s bundled Seal Dark document icons, and only when Arkiv is the default app for a file type. An optional Quick Look thumbnail setting is planned for Finder; it is being evaluated as a prototype. Arkiv never modifies its app bundle, your archives or your default apps.")
        finder.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        finder.textColor = .tertiaryLabelColor
        finder.preferredMaxLayoutWidth = 614

        let stack = NSStackView(views: [bannerCard, body, footer, finder])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.setCustomSpacing(14, after: bannerCard)
        stack.setCustomSpacing(6, after: footer)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            body.heightAnchor.constraint(equalToConstant: 398),
        ])
        for view in [bannerCard, body, footer, finder] as [NSView] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    private func pinEdges(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    /// One fixed column width for every icon, so spacing is uniform whatever
    /// the caption (the old grid sized columns by caption and spread out).
    private func previewCell(_ size: CGFloat, caption text: String, accessibility: String) -> (NSView, NSImageView, NSTextField) {
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: size).isActive = true
        image.heightAnchor.constraint(equalToConstant: size).isActive = true
        image.setAccessibilityLabel(accessibility)
        let caption = NSTextField(labelWithString: text)
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        let cell = NSStackView(views: [image, caption])
        cell.orientation = .vertical; cell.spacing = 3; cell.alignment = .centerX
        cell.widthAnchor.constraint(equalToConstant: Self.previewColumn).isActive = true
        caption.widthAnchor.constraint(lessThanOrEqualToConstant: Self.previewColumn).isActive = true
        return (cell, image, caption)
    }

    private func makePreviewGrid() -> NSGridView {
        let grid = NSGridView(numberOfColumns: 6, rows: 0)
        grid.rowSpacing = 10; grid.columnSpacing = 0
        var cells: [NSView] = []
        for name in DocumentIconName.allCases {
            let (cell, image, caption) = previewCell(48, caption: name.label, accessibility: "\(name.label) document icon")
            previewViews[name] = image; previewCaptions[name] = caption
            cells.append(cell)
        }
        stride(from: 0, to: cells.count, by: 6).forEach { start in
            _ = grid.addRow(with: Array(cells[start..<min(start + 6, cells.count)]))
        }
        return grid
    }

    private func makeExtrasGrid() -> NSGridView {
        let grid = NSGridView(numberOfColumns: DocumentIconExtra.allCases.count, rows: 0)
        grid.columnSpacing = 0
        var cells: [NSView] = []
        for extra in DocumentIconExtra.allCases {
            let (cell, image, caption) = previewCell(34, caption: extra.label, accessibility: "\(extra.label) document icon inside Arkiv")
            extraPreviewViews[extra] = image; extraCaptions[extra] = caption
            cells.append(cell)
        }
        _ = grid.addRow(with: cells)
        return grid
    }

    // MARK: Rows

    /// Bundled default first, then families in catalogue order. Each family
    /// lists its themes; a theme's variations fold under a toggle row and
    /// follow it when expanded. A filter (name or family, any case) shows
    /// every match flat, variations included.
    static func rows(for entries: [ThemeEntry], expanded: Set<String> = [], filter: String = "") -> [Row] {
        guard let bundled = entries.first(where: { $0.status == .bundled }) else { return [] }
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ entry: ThemeEntry) -> Bool {
            query.isEmpty || entry.name.localizedCaseInsensitiveContains(query) || entry.familyName.localizedCaseInsensitiveContains(query)
        }
        var result: [Row] = matches(bundled) ? [.group("Included with Arkiv"), .theme(bundled)] : []
        var families: [String] = []
        for entry in entries where entry.status != .bundled && !families.contains(entry.familyName) { families.append(entry.familyName) }
        for family in families {
            let members = entries.filter { $0.status != .bundled && $0.familyName == family }
            var familyRows: [Row] = []
            if !query.isEmpty {
                familyRows = members.filter { $0.kind != .variation && matches($0) }.map(Row.theme)
                    + members.filter { $0.kind == .variation && matches($0) }.map(Row.theme)
            } else {
                let parents = members.filter { $0.kind != .variation }
                let parentIDs = Set(parents.map(\.id))
                for parent in parents {
                    familyRows.append(.theme(parent))
                    let children = members.filter { $0.kind == .variation && $0.variantOf == parent.id }
                    guard !children.isEmpty else { continue }
                    let open = expanded.contains(parent.id)
                    familyRows.append(.variations(parent: parent.id, count: children.count, expanded: open))
                    if open { familyRows += children.map(Row.theme) }
                }
                // Variations whose parent is not listed stay visible.
                familyRows += members.filter { $0.kind == .variation && !parentIDs.contains($0.variantOf ?? "") }.map(Row.theme)
            }
            if !familyRows.isEmpty { result.append(.group(family)); result += familyRows }
        }
        return result
    }

    func reload() {
        rows = Self.rows(for: manager.entries, expanded: expandedParents, filter: filterField.stringValue)
        table.reloadData()
        if let index = rowIndex(of: shownID) {
            if table.selectedRow != index {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                table.scrollRowToVisible(index)
            }
        } else if !rows.contains(where: { if case .theme = $0 { return true }; return false }) {
            table.deselectAll(nil)
        }
        if manager.entry(shownID) == nil { shownID = DocumentIconThemeID.bundled }
        updateBanner()
        updateDetail()
        updateCatalogStatus()
    }

    private func rowIndex(of id: String) -> Int? {
        rows.firstIndex { if case .theme(let e) = $0 { return e.id == id } else { return false } }
    }

    var shownEntry: ThemeEntry? { manager.entry(shownID) }

    func show(_ id: String) {
        guard let entry = manager.entry(id) else { return }
        if entry.kind == .variation, let parent = entry.variantOf, !expandedParents.contains(parent) {
            expandedParents.insert(parent)
            rows = Self.rows(for: manager.entries, expanded: expandedParents, filter: filterField.stringValue)
            table.reloadData()
        }
        shownID = id
        if let index = rowIndex(of: id) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        updateDetail()
    }

    func toggleVariations(of parent: String) {
        if expandedParents.contains(parent) { expandedParents.remove(parent) } else { expandedParents.insert(parent) }
        reload()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    @objc private func rowClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard rows.indices.contains(row), case .variations(let parent, _, _) = rows[row] else { return }
        toggleVariations(of: parent)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { if case .group = rows[row] { return true }; return false }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { if case .theme = rows[row] { return true }; return false }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] { case .group: return 26; case .variations: return 22; case .theme: return 40 }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .group(let title):
            return ThemeGroupHeaderView(title: title)
        case .theme(let entry):
            return ThemeRowView(entry: entry, thumbnail: manager.localThumbnail(for: entry.id))
        case .variations(_, let count, let expanded):
            return ThemeVariationsToggleView(count: count, expanded: expanded)
        }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ArchiveRowView()
        view.accent = ArkivStyle.customAccent(AppPreferencesAccess.accent)
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < rows.count, case .theme(let entry) = rows[table.selectedRow] else { return }
        if entry.id != shownID { shownID = entry.id; updateDetail() }
    }

    // MARK: Banner

    private func updateBanner() {
        let selection = manager.provider.effectiveSelection
        let inUse = manager.entries.first { $0.isSelected } ?? manager.entry(DocumentIconThemeID.bundled)
        currentLabel.stringValue = "In use: " + (inUse?.name ?? "Seal Dark")
        var detail = [inUse?.familyName ?? "C · Seal"]
        detail.append(selection == .bundled ? "Included with Arkiv" : "Downloaded · works offline")
        if manager.provider.damagedTheme != nil { detail.append("A damaged theme was replaced by Seal Dark") }
        currentDetail.stringValue = detail.joined(separator: " · ")
        currentIcon.image = manager.provider.icon(.zip, points: 32)
        restoreButton.isEnabled = selection != ThemeSelection.bundled
        if lastSelection != nil && lastSelection != selection { onCurrentThemeChange?() }
        lastSelection = selection
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
        let sizeSuffix = entry.downloadSize.map { " (\(Self.describe($0)))" } ?? ""
        downloadButton.title = (entry.status == .updateAvailable ? "Update" : "Download") + sizeSuffix
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
        statusLabel.textColor = manager.lastError[entry.id] != nil ? .systemRed : entry.status == .installed ? ArkivStyle.success : .secondaryLabelColor
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
            previewCaptions[name]?.stringValue = name.label
            previewCaptions[name]?.toolTip = covered.contains(name) ? nil : "\(name.label): not in this theme; the system icon is used"
            view.alphaValue = covered.contains(name) ? 1 : 0.3
        }
        let extras = Set(entry.extrasCoverage)
        for (extra, view) in extraPreviewViews {
            view.image = nil
            // A theme without the dedicated artwork uses its family icon inside Arkiv.
            extraCaptions[extra]?.stringValue = extra.label
            extraCaptions[extra]?.toolTip = extras.contains(extra) ? nil : "\(extra.label): not in this theme; the family icon is used"
            view.alphaValue = extras.contains(extra) ? 1 : 0.3
        }
        guard active else { return }
        let id = entry.id
        previewTask = Task { [weak self] in
            guard let self else { return }
            let images = await self.manager.previews(for: id)
            guard !Task.isCancelled, self.shownID == id else { return }
            for (name, view) in self.previewViews { view.image = images[.icon(name)] }
            for (extra, view) in self.extraPreviewViews { view.image = images[.extra(extra)] }
            if images.isEmpty, entry.catalog != nil, entry.installed == nil {
                self.statusLabel.stringValue += " Preview unavailable while offline."
            } else if let row = self.rowIndex(of: id) {
                // The list thumbnail can now come from the verified preview.
                self.table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
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
        alert.alertStyle = .warning
        alert.messageText = "Remove “\(entry.name)”?"
        alert.informativeText = "This theme is in use. Arkiv will switch to Seal Dark, then delete the downloaded files. You can download it again later."
        let remove = alert.addButton(withTitle: "Remove")
        remove.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if let window { alert.beginSheetModal(for: window) { completion($0 == .alertFirstButtonReturn) } }
        else { completion(alert.runModal() == .alertFirstButtonReturn) }
    }
}

/// Read-only access to the accent for panes that do not own preferences.
enum AppPreferencesAccess {
    static var accent: AppAccent { AppPreferences().accent }
}

/// A family heading in the theme list: fixed, never floating.
final class ThemeGroupHeaderView: NSTableCellView {
    init(title: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label); textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// "Show 2 variations" under a parent theme.
final class ThemeVariationsToggleView: NSTableCellView {
    init(count: Int, expanded: Bool) {
        super.init(frame: .zero)
        let text = expanded ? "Hide variations" : (count == 1 ? "Show 1 variation" : "Show \(count) variations")
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let chevron = NSImageView(image: ArkivStyle.symbol(expanded ? "chevron.down" : "chevron.right", "", pointSize: 9, weight: .semibold) ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor
        let stack = NSStackView(views: [chevron, label])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 42),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// One theme row: thumbnail, name and a text status (never colour alone).
final class ThemeRowView: NSTableCellView {
    init(entry: ThemeEntry, thumbnail: NSImage? = nil) {
        super.init(frame: .zero)
        let image = NSImageView()
        image.image = thumbnail ?? ArkivStyle.symbol("doc", "", pointSize: 18, weight: .light)
        image.contentTintColor = thumbnail == nil ? .tertiaryLabelColor : nil
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityElement(false)
        image.translatesAutoresizingMaskIntoConstraints = false
        imageView = image
        let name = NSTextField(labelWithString: entry.name)
        name.lineBreakMode = .byTruncatingTail
        name.font = .systemFont(ofSize: NSFont.systemFontSize)
        let status = NSTextField(labelWithString: Self.status(entry))
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [name, status])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 0
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let markSymbol: String? = entry.isSelected ? "checkmark.circle.fill" : (entry.installed != nil || entry.status == .bundled) ? "internaldrive" : nil
        let mark = NSImageView(image: markSymbol.flatMap { ArkivStyle.symbol($0, entry.isSelected ? "In use" : "On this Mac", pointSize: 12) } ?? NSImage())
        mark.contentTintColor = entry.isSelected ? ArkivStyle.mark : .tertiaryLabelColor
        mark.isHidden = markSymbol == nil
        mark.translatesAutoresizingMaskIntoConstraints = false
        for view in [image, text, mark] as [NSView] { addSubview(view) }
        let indent: CGFloat = entry.kind == .variation ? 16 : 4
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 28), image.heightAnchor.constraint(equalToConstant: 28),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 6),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = name
        setAccessibilityLabel("\(entry.name), \(Self.status(entry))")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    static func status(_ entry: ThemeEntry) -> String {
        var parts: [String] = []
        if entry.isSelected { parts.append("In use") }
        switch entry.status {
        case .bundled: parts.append("Included")
        case .available: parts.append(entry.downloadSize.map { DocumentIconThemePane.describe($0) } ?? "Available")
        case .downloading(let value): parts.append("Downloading \(Int(value * 100))%")
        case .installing: parts.append("Installing")
        case .installed: parts.append("Downloaded")
        case .updateAvailable: parts.append("Update available")
        case .unavailable(let reason): parts.append(reason)
        }
        if entry.kind == .variation { parts.append("Variation") }
        return parts.joined(separator: " · ")
    }
}
