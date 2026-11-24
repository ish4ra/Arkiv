import AppKit
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

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate {
    private let preferences: AppPreferences
    private let recents: RecentArchives
    private let updates: UpdateController
    private let showFinder: () -> Void
    private let makeThemeManager: @MainActor () -> DocumentIconThemeManager
    private var themePaneStorage: DocumentIconThemePane?
    private let tabs = NSTabView()
    static let appearanceTab = "Appearance"
    private static let compactSize = NSSize(width: 520, height: 330)
    private static let appearanceSize = NSSize(width: 820, height: 680)
    let appearancePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let automaticChecks = NSButton(checkboxWithTitle: "Automatically check for updates", target: nil, action: nil)
    private let updateStatus = NSTextField(wrappingLabelWithString: "")

    init(preferences: AppPreferences, recents: RecentArchives, updates: UpdateController, showFinder: @escaping () -> Void,
         themeManager: @escaping @MainActor () -> DocumentIconThemeManager = { DocumentIconThemeManager(environment: .standard(), provider: .shared) }) {
        self.preferences = preferences; self.recents = recents
        self.updates = updates; self.showFinder = showFinder
        self.makeThemeManager = themeManager
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        appearancePicker.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePicker.target = self; appearancePicker.action = #selector(changeAppearance(_:))
        appearancePicker.setAccessibilityLabel("Appearance")
        let appearanceRow = NSStackView(views: [NSTextField(labelWithString: "Appearance:"), appearancePicker])
        appearanceRow.spacing = 12
        addTab("General", to: tabs, views: [appearanceRow,
            note("Choose how Arkiv looks. System follows your Mac’s appearance."),
            button("Clear Recent Archives", #selector(clearRecents(_:))),
            note("Clears File → Open Recent. Archives on disk are not changed.")])
        automaticChecks.target = self; automaticChecks.action = #selector(changeAutomaticChecks(_:))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addTab("Updates", to: tabs, views: [NSTextField(labelWithString: "Arkiv \(version) (\(build))"),
            button("Check for Updates…", #selector(checkUpdates(_:))), automaticChecks, updateStatus])
        addTab("Finder Integration", to: tabs, views: [
            note("Get Arkiv actions when you right-click files in Finder. Enable Arkiv Finder yourself in macOS extension settings; Arkiv cannot grant this approval."),
            button("Finder Integration…", #selector(openFinder(_:))),
            note("The direct Arkiv menu covers items in your home folder. For other locations, use Finder’s Services submenu. The setup window shows current status and the manual settings path.")])
        // Appearance → Document Icon Theme. Its view and theme manager are created
        // only when the tab is first shown; nothing here runs at launch.
        let appearance = NSTabViewItem(identifier: Self.appearanceTab)
        appearance.label = Self.appearanceTab
        appearance.view = NSView()
        tabs.addTabViewItem(appearance)
        tabs.delegate = self
        updates.onSettingsChange = { [weak self] in self?.refresh() }
        window.center()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh(); activateThemePaneIfShown() }
    func windowWillClose(_ notification: Notification) { themePaneStorage?.deactivate() }

    /// The document icon theme pane, created on first use.
    var themePane: DocumentIconThemePane {
        if let pane = themePaneStorage { return pane }
        let pane = DocumentIconThemePane(manager: makeThemeManager())
        themePaneStorage = pane
        if let item = tabs.tabViewItems.first(where: { $0.identifier as? String == Self.appearanceTab }) { item.view = pane }
        return pane
    }
    var isThemePaneLoaded: Bool { themePaneStorage != nil }

    func showAppearance() {
        if let item = tabs.tabViewItems.first(where: { $0.identifier as? String == Self.appearanceTab }) { tabs.selectTabViewItem(item) }
    }

    func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if tabViewItem?.identifier as? String == Self.appearanceTab { _ = themePane }
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        let appearance = tabViewItem?.identifier as? String == Self.appearanceTab
        resize(to: appearance ? Self.appearanceSize : Self.compactSize)
        if appearance { activateThemePaneIfShown() } else { themePaneStorage?.deactivate() }
    }
    private func activateThemePaneIfShown() {
        guard window?.isVisible == true, tabs.selectedTabViewItem?.identifier as? String == Self.appearanceTab else { return }
        themePane.activate()
    }
    private func resize(to size: NSSize) {
        guard let window else { return }
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var origin = window.frame.origin
        origin.y += window.frame.height - frame.height
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: window.isVisible)
    }
    func refresh() {
        appearancePicker.selectItem(at: AppAppearance.allCases.firstIndex(of: preferences.appearance) ?? 2)
        automaticChecks.isEnabled = updates.automaticChecks != nil
        automaticChecks.state = updates.automaticChecks == true ? .on : .off
        updateStatus.stringValue = updates.automaticChecks == nil
            ? "Updates are not configured in this build. Install a build containing Arkiv’s update public key."
            : "Sparkle manages update checks and verifies signed updates. Automatic installation is not enabled by this setting."
    }
    @objc func changeAppearance(_ sender: Any?) {
        guard AppAppearance.allCases.indices.contains(appearancePicker.indexOfSelectedItem) else { return }
        preferences.appearance = AppAppearance.allCases[appearancePicker.indexOfSelectedItem]
        preferences.appearance.apply()
    }
    @objc func clearRecents(_ sender: Any?) { recents.clearMenu(sender) }
    @objc func checkUpdates(_ sender: Any?) { updates.checkForUpdates(sender) }
    @objc func changeAutomaticChecks(_ sender: Any?) {
        updates.automaticChecks = automaticChecks.state == .on
        refresh()
    }
    @objc func openFinder(_ sender: Any?) { showFinder() }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return field
    }
    private func addTab(_ title: String, to tabs: NSTabView, views: [NSView]) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let content = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        for view in views where view is NSTextField {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        item.view = content
        tabs.addTabViewItem(item)
    }
}
