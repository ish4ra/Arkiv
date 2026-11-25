import AppKit
import FinderSync
import ArkivCore
import ArkivPresentation
import ArkivThemes

extension AppAppearance {
    /// nil opts back into the system appearance. This changes Arkiv only.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Settings: one reusable window with a sidebar (General, Appearance,
/// Document Icons, Updates) and a fixed size, so switching panes never
/// resizes or animates the window. The Document Icons pane and its theme
/// manager are created only when that pane is first shown.
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Pane: String, CaseIterable {
        case general, appearance, documentIcons, updates
        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .documentIcons: return "Document Icons"
            case .updates: return "Updates"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "paintpalette.fill"
            case .documentIcons: return "doc.on.doc.fill"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }
        var badge: NSColor {
            switch self {
            case .general: return ArkivStyle.srgb(0x8A8790)
            case .appearance: return ArkivStyle.color(for: .arkiv)
            case .documentIcons: return ArkivStyle.color(for: .brass)
            case .updates: return ArkivStyle.color(for: .jade)
            }
        }
    }
    static let contentSize = NSSize(width: 880, height: 640)
    static let sidebarWidth: CGFloat = 210

    private let preferences: AppPreferences
    private let recents: RecentArchives
    private let updates: UpdateController
    private let showFinder: () -> Void
    private let finderEnabled: () -> Bool
    private let currentThemeName: () -> String
    private let makeThemeManager: @MainActor () -> DocumentIconThemeManager
    private var themePaneStorage: DocumentIconThemePane?

    let sidebar = NSTableView()
    private let paneTitle = NSTextField(labelWithString: "")
    private let paneContainer = NSView()
    private var paneViews: [Pane: NSView] = [:]
    private(set) var selectedPane: Pane = .general

    // General
    let finderStatus = NSTextField(labelWithString: "")
    let recentSummary = NSTextField(labelWithString: "")
    // Appearance
    let appearancePicker = NSSegmentedControl(labels: AppAppearance.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    let accentPicker = AccentPicker()
    let accentName = NSTextField(labelWithString: "")
    let densityPicker = NSSegmentedControl(labels: BrowserDensity.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    let alternatingRows = NSSwitch()
    let customizeToolbarButton = NSButton(title: "Customize Toolbar…", target: nil, action: nil)
    let restoreDefaultsButton = NSButton(title: "Restore Defaults", target: nil, action: nil)
    let themeName = NSTextField(labelWithString: "")
    let preview: AppearancePreview
    // Updates
    let automaticChecks = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let updateStatus = NSTextField(wrappingLabelWithString: "")

    init(preferences: AppPreferences, recents: RecentArchives, updates: UpdateController, showFinder: @escaping () -> Void,
         themeManager: @escaping @MainActor () -> DocumentIconThemeManager = { DocumentIconThemeManager(environment: .standard(), provider: .shared) },
         finderEnabled: @escaping () -> Bool = { FIFinderSyncController.isExtensionEnabled },
         currentThemeName: @escaping () -> String = SettingsWindowController.installedThemeName,
         documentIcons: DocumentIconProvider = .shared) {
        self.preferences = preferences; self.recents = recents
        self.updates = updates; self.showFinder = showFinder
        self.makeThemeManager = themeManager
        self.finderEnabled = finderEnabled
        self.currentThemeName = currentThemeName
        preview = AppearancePreview(documentIcons: documentIcons)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        updates.onSettingsChange = { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange(_:)), name: .arkivDocumentIconThemeDidChange, object: nil)
        window.center()
        select(.general)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    static func installedThemeName() -> String {
        switch DocumentIconProvider.shared.effectiveSelection {
        case .bundled: return "Seal Dark (included with Arkiv)"
        case .installed(let id, let version): return ThemeStore.shared.loadInstalled(id: id, version: version)?.name ?? id
        }
    }

    // MARK: Presentation

    func present(pane: Pane? = nil) {
        if let pane { select(pane) }
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        activateThemePaneIfShown()
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh(); activateThemePaneIfShown() }
    func windowWillClose(_ notification: Notification) { themePaneStorage?.deactivate() }

    /// The document icon theme pane, created on first use.
    var themePane: DocumentIconThemePane {
        if let pane = themePaneStorage { return pane }
        let pane = DocumentIconThemePane(manager: makeThemeManager())
        themePaneStorage = pane
        pane.onCurrentThemeChange = { [weak self] in self?.refresh() }
        return pane
    }
    var isThemePaneLoaded: Bool { themePaneStorage != nil }

    /// Shows the Document Icons pane (creating its manager on first use).
    func showDocumentIcons() { select(.documentIcons) }
    /// Shows the Appearance pane.
    func showAppearance() { select(.appearance) }

    func select(_ pane: Pane) {
        if pane != .documentIcons { themePaneStorage?.deactivate() }
        selectedPane = pane
        if let row = Pane.allCases.firstIndex(of: pane), sidebar.selectedRow != row {
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        paneTitle.stringValue = pane.title
        window?.title = "Settings — " + pane.title
        let view = paneView(pane)
        paneContainer.subviews.filter { $0 !== view }.forEach { $0.removeFromSuperview() }
        if view.superview !== paneContainer {
            view.translatesAutoresizingMaskIntoConstraints = false
            paneContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
            ])
        }
        activateThemePaneIfShown()
    }
    private func activateThemePaneIfShown() {
        guard window?.isVisible == true, selectedPane == .documentIcons else { return }
        themePane.activate()
    }
    private func paneView(_ pane: Pane) -> NSView {
        if pane == .documentIcons { return themePane }
        if let view = paneViews[pane] { return view }
        let view: NSView
        switch pane {
        case .general: view = makeGeneral()
        case .appearance: view = makeAppearance()
        case .updates: view = makeUpdates()
        case .documentIcons: view = themePane
        }
        paneViews[pane] = view
        return view
    }

    // MARK: Layout

    private func makeContent() -> NSView {
        let root = NSView()
        let side = NSVisualEffectView()
        side.material = .sidebar; side.blendingMode = .behindWindow; side.state = .followsWindowActiveState
        side.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.backgroundColor = .clear
        sidebar.rowHeight = 32
        sidebar.intercellSpacing = NSSize(width: 0, height: 2)
        sidebar.dataSource = self; sidebar.delegate = self
        sidebar.setAccessibilityLabel("Settings sections")
        sidebar.allowsEmptySelection = false
        let scroll = NSScrollView()
        scroll.documentView = sidebar
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 52, left: 0, bottom: 12, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(scroll)

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        paneTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        paneTitle.translatesAutoresizingMaskIntoConstraints = false
        paneTitle.setAccessibilityRole(.staticText)
        paneContainer.translatesAutoresizingMaskIntoConstraints = false
        for view in [side, divider, paneTitle, paneContainer] as [NSView] { root.addSubview(view) }
        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            side.topAnchor.constraint(equalTo: root.topAnchor),
            side.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            scroll.leadingAnchor.constraint(equalTo: side.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: side.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: side.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: side.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: side.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            // The pane title sits on the traffic-light line, as in System Settings.
            paneTitle.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 28),
            paneTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 15),
            paneContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            paneContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            paneContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            root.heightAnchor.constraint(equalToConstant: Self.contentSize.height),
        ])
        return root
    }

    private func makeGeneral() -> NSView {
        finderStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        recentSummary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        recentSummary.textColor = .secondaryLabelColor
        let finder = SettingsForm.section("Finder", [
            SettingsForm.row("Arkiv Finder actions", control: button("Finder Integration…", #selector(openFinder(_:))), detailLabel: finderStatus),
        ], footnote: "Right-click files in Finder for Arkiv actions. Enable Arkiv Finder yourself in macOS extension settings; Arkiv cannot grant this approval. The direct Arkiv menu covers items in your home folder; elsewhere, use Finder’s Services submenu.")
        let history = SettingsForm.section("Recent Archives", [
            SettingsForm.row("Recent archives", control: button("Clear Recent Archives", #selector(clearRecents(_:))), detailLabel: recentSummary),
        ], footnote: "Clears File → Open Recent and the list in the welcome window. Archives on disk are not changed.")
        return SettingsForm.scrollingPane([finder, history])
    }

    private func makeAppearance() -> NSView {
        appearancePicker.target = self; appearancePicker.action = #selector(changeAppearance(_:))
        appearancePicker.setAccessibilityLabel("Appearance")
        densityPicker.target = self; densityPicker.action = #selector(changeDensity(_:))
        densityPicker.setAccessibilityLabel("Row density")
        alternatingRows.target = self; alternatingRows.action = #selector(changeAlternatingRows(_:))
        alternatingRows.setAccessibilityLabel("Alternating row backgrounds")
        accentPicker.onChange = { [weak self] accent in self?.changeAccent(accent) }
        accentName.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        accentName.textColor = .secondaryLabelColor
        let accentControl = NSStackView(views: [accentName, accentPicker])
        accentControl.spacing = 12
        customizeToolbarButton.target = self; customizeToolbarButton.action = #selector(customizeToolbar(_:))
        customizeToolbarButton.bezelStyle = .rounded
        restoreDefaultsButton.target = self; restoreDefaultsButton.action = #selector(restoreDefaults(_:))
        restoreDefaultsButton.bezelStyle = .rounded
        themeName.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        themeName.textColor = .secondaryLabelColor

        let previewBlock = NSStackView(views: [SettingsForm.heading("Preview"), preview])
        previewBlock.orientation = .vertical; previewBlock.alignment = .leading; previewBlock.spacing = 7
        preview.widthAnchor.constraint(equalToConstant: SettingsForm.cardWidth).isActive = true
        let look = SettingsForm.section("Look", [
            SettingsForm.row("Appearance", detail: "Dark is Arkiv’s default. System follows your Mac.", control: appearancePicker),
            SettingsForm.row("Accent colour", control: accentControl),
        ], footnote: "The accent colours selection highlights and primary buttons in Arkiv. Checkboxes, switches and other standard controls follow the macOS accent colour.")
        let browser = SettingsForm.section("Archive Browser", [
            SettingsForm.row("Row density", detail: "Comfortable also uses larger document icons.", control: densityPicker),
            SettingsForm.row("Alternating row backgrounds", control: alternatingRows),
            SettingsForm.row("Toolbar", detail: "Choose buttons and labels. Also in View → Customize Toolbar.", control: customizeToolbarButton),
        ])
        let icons = SettingsForm.section("Document Icons", [
            SettingsForm.row("Theme", control: button("Choose Theme…", #selector(chooseTheme(_:))), detailLabel: themeName),
        ])
        let footer = NSStackView(views: [NSView(), restoreDefaultsButton])
        footer.orientation = .horizontal
        footer.widthAnchor.constraint(equalToConstant: SettingsForm.cardWidth).isActive = true
        return SettingsForm.scrollingPane([previewBlock, look, browser, icons, footer])
    }

    private func makeUpdates() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let name = NSTextField(labelWithString: "Arkiv")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true
        let texts = NSStackView(views: [name, versionLabel])
        texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
        let check = button("Check for Updates…", #selector(checkUpdates(_:)))
        let identity = NSStackView(views: [icon, texts, NSView(), check])
        identity.orientation = .horizontal; identity.alignment = .centerY; identity.spacing = 12
        identity.edgeInsets = NSEdgeInsets(top: 12, left: SettingsForm.rowInset, bottom: 12, right: SettingsForm.rowInset)
        automaticChecks.target = self; automaticChecks.action = #selector(changeAutomaticChecks(_:))
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        updateStatus.preferredMaxLayoutWidth = SettingsForm.cardWidth - 8
        let section = SettingsForm.section(nil, [identity, SettingsForm.row("Automatic checks", control: automaticChecks)])
        section.addArrangedSubview(updateStatus)
        return SettingsForm.scrollingPane([section])
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    // MARK: State

    func refresh() {
        appearancePicker.selectedSegment = AppAppearance.allCases.firstIndex(of: preferences.appearance) ?? 2
        accentPicker.selection = preferences.accent
        accentName.stringValue = preferences.accent.title
        densityPicker.selectedSegment = BrowserDensity.allCases.firstIndex(of: preferences.density) ?? 1
        alternatingRows.state = preferences.alternatingRows ? .on : .off
        restoreDefaultsButton.isEnabled = !preferences.isDefault
        customizeToolbarButton.isEnabled = Self.customizableBrowserWindow() != nil
        customizeToolbarButton.toolTip = customizeToolbarButton.isEnabled ? nil : "Open an archive to customize its toolbar."
        preview.apply(density: preferences.density, accent: preferences.accent, alternatingRows: preferences.alternatingRows)
        automaticChecks.isEnabled = updates.automaticChecks != nil
        automaticChecks.state = updates.automaticChecks == true ? .on : .off
        updateStatus.stringValue = updates.automaticChecks == nil
            ? "Updates are not configured in this build. Install a build containing Arkiv’s update public key."
            : "Sparkle manages update checks and verifies signed updates. Automatic installation is not enabled by this setting."
        if window?.isVisible == true || paneViews[.general] != nil {
            let enabled = finderEnabled()
            finderStatus.stringValue = enabled ? "Enabled" : "Not enabled — approval is required in System Settings"
            finderStatus.textColor = enabled ? ArkivStyle.success : .secondaryLabelColor
            let count = recents.recentURLs.count
            recentSummary.stringValue = count == 0 ? "No recent archives" : count == 1 ? "1 archive in File → Open Recent" : "\(count) archives in File → Open Recent"
            themeName.stringValue = currentThemeName()
        }
    }
    @objc private func themeDidChange(_ notification: Notification) {
        if window?.isVisible == true { themeName.stringValue = currentThemeName() }
        preview.reloadIcons()
    }
    private static func customizableBrowserWindow() -> NSWindow? {
        let windows = [NSApp.mainWindow, NSApp.keyWindow].compactMap { $0 } + NSApp.orderedWindows
        return windows.first { ($0.windowController as? BrowserWindowController)?.browserToolbar === $0.toolbar }
    }

    // MARK: Actions

    @objc func changeAppearance(_ sender: Any?) {
        guard AppAppearance.allCases.indices.contains(appearancePicker.selectedSegment) else { return }
        preferences.appearance = AppAppearance.allCases[appearancePicker.selectedSegment]
        preferences.appearance.apply()
        refresh()
    }
    func changeAccent(_ accent: AppAccent) {
        preferences.accent = accent
        refresh()
    }
    @objc func changeDensity(_ sender: Any?) {
        guard BrowserDensity.allCases.indices.contains(densityPicker.selectedSegment) else { return }
        preferences.density = BrowserDensity.allCases[densityPicker.selectedSegment]
        refresh()
    }
    @objc func changeAlternatingRows(_ sender: Any?) {
        preferences.alternatingRows = alternatingRows.state == .on
        refresh()
    }
    @objc func restoreDefaults(_ sender: Any?) {
        preferences.restoreAppearanceDefaults()
        preferences.appearance.apply()
        refresh()
    }
    @objc func customizeToolbar(_ sender: Any?) {
        guard let window = Self.customizableBrowserWindow() else { return }
        window.makeKeyAndOrderFront(nil)
        window.runToolbarCustomizationPalette(sender)
    }
    @objc func chooseTheme(_ sender: Any?) { select(.documentIcons) }
    @objc func clearRecents(_ sender: Any?) { recents.clearMenu(sender); refresh() }
    @objc func checkUpdates(_ sender: Any?) { updates.checkForUpdates(sender) }
    @objc func changeAutomaticChecks(_ sender: Any?) {
        updates.automaticChecks = automaticChecks.state == .on
        refresh()
    }
    @objc func openFinder(_ sender: Any?) { showFinder() }

    // MARK: Sidebar

    func numberOfRows(in tableView: NSTableView) -> Int { Pane.allCases.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        SettingsSidebarCell(pane: Pane.allCases[row])
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ArchiveRowView()
        view.accent = ArkivStyle.customAccent(preferences.accent)
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard Pane.allCases.indices.contains(sidebar.selectedRow) else { return }
        let pane = Pane.allCases[sidebar.selectedRow]
        if pane != selectedPane { select(pane) }
    }
}

extension AppAppearance {
    var title: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
}

/// Sidebar row: a small coloured badge with a white symbol, then the title.
final class SettingsSidebarCell: NSTableCellView {
    init(pane: SettingsWindowController.Pane) {
        super.init(frame: .zero)
        let badge = ArkivCardView()
        badge.fill = pane.badge; badge.border = nil; badge.radius = 6
        badge.translatesAutoresizingMaskIntoConstraints = false
        let symbol = NSImageView(image: ArkivStyle.symbol(pane.symbol, pane.title, pointSize: 11, weight: .semibold) ?? NSImage())
        symbol.contentTintColor = .white
        symbol.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(symbol)
        let label = NSTextField(labelWithString: pane.title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge); addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            symbol.centerXAnchor.constraint(equalTo: badge.centerXAnchor), symbol.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel(pane.title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// A live, non-interactive preview of the archive browser built from the real
/// table cells and row view, so density, accent and alternating rows look
/// exactly as they will in archive windows.
final class AppearancePreview: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let card = ArkivCardView()
    private var height: NSLayoutConstraint!
    private let documentIcons: DocumentIconProvider
    private var density: BrowserDensity = .standard
    private var accent: AppAccent = .arkiv
    /// Built through the public index, exactly as an opened archive is.
    static let sampleRows: [BrowserRow] = {
        let entries: [(String, Int64, ArchiveEntry.Kind)] = [("Albums", 0, .directory), ("raw-backup.7z", 210_400_000, .file),
                       ("exports.tar.gz", 48_200_000, .file), ("fonts.zip", 3_100_000, .file), ("notes.txt", 2_048, .file)]
        let index = ArchiveIndex(entries: entries.enumerated().map { ArchiveEntry(id: Int64($0.offset), path: $0.element.0, size: $0.element.1, kind: $0.element.2) })
        return BrowserPresentation.sorted(index.children(of: ""), by: "name", ascending: true)
    }()
    static var selectedSampleRow: Int { sampleRows.firstIndex { $0.name == "raw-backup.7z" } ?? 0 }
    init(documentIcons: DocumentIconProvider) {
        self.documentIcons = documentIcons
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for (id, title, width) in [("name", "Name", 300.0), ("size", "Size", 110.0), ("type", "Kind", 150.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width
            column.headerCell.alignment = id == "size" ? .right : .left
            table.addTableColumn(column)
        }
        table.style = .fullWidth
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.dataSource = self; table.delegate = self
        table.backgroundColor = .textBackgroundColor
        table.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        card.translatesAutoresizingMaskIntoConstraints = false
        card.fill = .textBackgroundColor
        addSubview(card); card.addSubview(scroll)
        height = heightAnchor.constraint(equalToConstant: 160)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 1), scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 1), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            height,
        ])
        wantsLayer = true
        layer?.cornerRadius = ArkivStyle.cardRadius
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Preview of the archive browser with the chosen density, accent and row style")
        apply(density: .standard, accent: .arkiv, alternatingRows: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    /// Not interactive: clicks never change the preview's selection.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(density: BrowserDensity, accent: AppAccent, alternatingRows: Bool) {
        self.density = density; self.accent = accent
        table.rowHeight = CGFloat(density.rowHeight)
        table.usesAlternatingRowBackgroundColors = alternatingRows
        height.constant = CGFloat(density.rowHeight) * CGFloat(Self.sampleRows.count) + 30
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: Self.selectedSampleRow), byExtendingSelection: false)
    }
    func reloadIcons() { table.reloadData(); table.selectRowIndexes(IndexSet(integer: Self.selectedSampleRow), byExtendingSelection: false) }
    var selectionAccent: NSColor? { ArkivStyle.customAccent(accent) }

    func numberOfRows(in tableView: NSTableView) -> Int { Self.sampleRows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? "name"
        let cell = ArchiveCellView(column: id)
        cell.configure(Self.sampleRows[row], column: id, searching: false, documentIcons: documentIcons, density: density)
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ArchiveRowView()
        view.accent = selectionAccent
        view.alwaysEmphasized = true
        return view
    }
}
