import AppKit
import FinderSync
import ArkivFinderIntegration

/// A modeless native management window, separate from the archive browser.
final class FinderSetupWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: FinderSetupPreferences
    private let enabledProvider: () -> Bool
    private let settingsAction: () -> Void
    private(set) var isEnabled = false
    private let headline = NSTextField(labelWithString: "Enable Finder Integration")
    private let status = NSTextField(labelWithString: "Disabled — approval is required in System Settings")
    private let later = NSButton(title: "Not Now", target: nil, action: nil)

    init(preferences: FinderSetupPreferences = FinderSetupPreferences(),
         enabled: @escaping () -> Bool = { FIFinderSyncController.isExtensionEnabled },
         openSettings: @escaping () -> Void = { FIFinderSyncController.showExtensionManagementInterface() }) {
        self.preferences = preferences
        enabledProvider = enabled
        settingsAction = openSettings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Finder Integration"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @discardableResult func presentIfNeeded() -> Bool {
        refresh()
        guard preferences.shouldPresent(enabled: isEnabled) else { return false }
        showSetup()
        return true
    }

    func showSetup() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called on every application activation, including returning from Settings.
    func refresh() {
        isEnabled = enabledProvider()
        preferences.record(enabled: isEnabled)
        headline.stringValue = isEnabled ? "Arkiv Finder Enabled" : "Enable Finder Integration"
        status.stringValue = isEnabled ? "Enabled — Finder integration is ready" : "Disabled — approval is required in System Settings"
        status.textColor = isEnabled ? .systemGreen : .secondaryLabelColor
        later.title = isEnabled ? "Done" : "Not Now"
    }

    @objc func openExtensionSettings(_ sender: Any?) {
        settingsAction()
        // Opening Settings is not evidence that the extension was enabled.
    }

    @objc func dismissSetup(_ sender: Any?) {
        preferences.dismiss()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window is the same respectful dismissal as Not Now.
        preferences.dismiss()
    }

    private func buildContent() {
        guard let window, let content = window.contentView else { return }
        headline.font = .systemFont(ofSize: 20, weight: .semibold)
        let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Arkiv")
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let heading = NSStackView(views: [icon, headline]); heading.spacing = 12
        let description = text("Get Arkiv actions directly in Finder when you right-click archives.")
        let benefits = NSStackView(views: ["Open in Arkiv", "Extract Here", "Extract to Folder", "Extract To…"].map { text("• " + $0) })
        benefits.orientation = .vertical; benefits.alignment = .leading; benefits.spacing = 4
        status.font = .systemFont(ofSize: 12, weight: .medium)
        let separator = NSBox(); separator.boxType = .separator
        let manualTitle = NSTextField(labelWithString: "Enable manually in System Settings")
        manualTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let path = text(FinderSetupPreferences.manualPath(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion))
        let note = text("If the button opens a different pane, follow the path above. macOS requires your approval; Arkiv cannot enable this permission for you.", secondary: true)
        let fallback = text("Services fallback remains available in Finder → Services. Its visibility is controlled separately in Keyboard Shortcuts → Services.", secondary: true)
        later.target = self; later.action = #selector(dismissSetup(_:)); later.bezelStyle = .rounded
        later.keyEquivalent = "\u{1b}"
        let settings = NSButton(title: "Open Extension Settings…", target: self, action: #selector(openExtensionSettings(_:)))
        settings.bezelStyle = .rounded; settings.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, later, settings]); buttons.spacing = 8
        let stack = NSStackView(views: [heading, description, benefits, status, separator, manualTitle, path, note, fallback, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        for label in [description, path, note, fallback] {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let size = stack.fittingSize
        window.setContentSize(NSSize(width: 540, height: max(480, size.height + 48)))
    }

    private func text(_ value: String, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: secondary ? 12 : 13)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.isSelectable = true
        label.preferredMaxLayoutWidth = 492
        return label
    }
}
