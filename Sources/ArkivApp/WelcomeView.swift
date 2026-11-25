import AppKit
import ArkivThemes

/// The window before an archive is open: identity and the two primary
/// actions on the left, recent archives (or a drop zone) on the right, and one
/// quiet footer line. Static drawing only; nothing animates.
///
/// Recent archives come from NSDocumentController through RecentArchives;
/// nothing here stores history of its own. Missing files are left out.
final class WelcomeView: ArkivCanvasView {
    static let maximumRecents = 6
    var onOpen: (() -> Void)?
    var onCreate: (() -> Void)?
    var onOpenURLs: (([URL]) -> Void)?
    var onAppearance: (() -> Void)?
    /// Supplies recent archives; call reloadRecents() after replacing it.
    var recentURLs: () -> [URL] = { [] }
    var documentIcons: DocumentIconProvider = .shared

    let iconView = NSImageView(image: NSApp.applicationIconImage)
    let openButton = NSButton(title: "Open Archive…", target: nil, action: nil)
    let createButton = NSButton(title: "Create Archive…", target: nil, action: nil)
    let appearanceButton = NSButton(title: "Appearance…", target: nil, action: nil)
    let recentHeading = NSTextField(labelWithString: "Recent Archives")
    private(set) var recentButtons: [NSButton] = []
    private let recentStack = NSStackView()
    let dropZone = WelcomeDropZone()
    private var dropTargeted = false { didSet { needsDisplay = true; dropZone.targeted = dropTargeted } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 920, height: 520))
        setAccessibilityElement(false)
        registerForDraggedTypes([.fileURL])
        build()
        reloadRecents()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func build() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let title = NSTextField(labelWithString: "Arkiv")
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.setAccessibilityRole(.staticText)
        let tagline = NSTextField(wrappingLabelWithString: "Browse, extract and create archives — without unpacking everything first.")
        tagline.font = .systemFont(ofSize: 13); tagline.textColor = .secondaryLabelColor
        tagline.preferredMaxLayoutWidth = 260
        tagline.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true

        for (button, symbol, action, tip) in [(openButton, "folder", #selector(open(_:)), "Choose an archive to browse (⌘O)"),
                                             (createButton, "plus.rectangle.on.folder", #selector(create(_:)), "Choose files and folders for a new archive (⇧⌘N)")] {
            button.target = self; button.action = action
            button.bezelStyle = .rounded; button.controlSize = .large
            button.image = ArkivStyle.symbol(symbol, "", pointSize: 13)
            button.imagePosition = .imageLeading
            button.toolTip = tip
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        }
        openButton.keyEquivalent = "\r"
        createButton.widthAnchor.constraint(equalTo: openButton.widthAnchor).isActive = true

        let identity = NSStackView(views: [iconView, title, tagline, openButton, createButton])
        identity.orientation = .vertical; identity.alignment = .leading; identity.spacing = 8
        identity.setCustomSpacing(14, after: iconView)
        identity.setCustomSpacing(2, after: title)
        identity.setCustomSpacing(22, after: tagline)

        recentHeading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        recentHeading.textColor = .secondaryLabelColor
        recentStack.orientation = .vertical; recentStack.alignment = .leading; recentStack.spacing = 2
        recentStack.setAccessibilityElement(true)
        recentStack.setAccessibilityRole(.list)
        recentStack.setAccessibilityLabel("Recent archives")
        let recents = NSStackView(views: [recentHeading, recentStack, dropZone])
        recents.orientation = .vertical; recents.alignment = .leading; recents.spacing = 8
        recents.translatesAutoresizingMaskIntoConstraints = false
        for view in [recentStack, dropZone] { view.widthAnchor.constraint(equalTo: recents.widthAnchor).isActive = true }
        dropZone.heightAnchor.constraint(equalToConstant: 168).isActive = true

        let columns = NSStackView(views: [identity, recents])
        columns.orientation = .horizontal; columns.alignment = .top; columns.spacing = 44
        columns.translatesAutoresizingMaskIntoConstraints = false
        // 300 pt when there is room; narrower (never below 220 pt) at the minimum window width.
        let preferred = recents.widthAnchor.constraint(equalToConstant: 300)
        preferred.priority = .defaultHigh
        preferred.isActive = true
        recents.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        addSubview(columns)

        let hint = NSTextField(labelWithString: "Drop archives anywhere in this window to open them.   ⌘O Open   ⇧⌘N Create   ⌘, Settings")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize); hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        appearanceButton.target = self; appearanceButton.action = #selector(appearance(_:))
        appearanceButton.isBordered = false
        appearanceButton.image = ArkivStyle.symbol("paintpalette", "", pointSize: 12)
        appearanceButton.imagePosition = .imageLeading
        appearanceButton.contentTintColor = .secondaryLabelColor
        appearanceButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        appearanceButton.toolTip = "Open Settings → Appearance"
        appearanceButton.setAccessibilityLabel("Appearance settings")
        let footer = NSStackView(views: [hint, NSView(), appearanceButton])
        footer.orientation = .horizontal; footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footer)

        NSLayoutConstraint.activate([
            columns.centerXAnchor.constraint(equalTo: centerXAnchor),
            columns.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            columns.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            columns.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            columns.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ArkivStyle.gutter),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ArkivStyle.gutter),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            footer.topAnchor.constraint(greaterThanOrEqualTo: columns.bottomAnchor, constant: 12),
        ])
    }

    // MARK: Recent archives

    func reloadRecents() {
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var seen = Set<String>()
        let urls = recentURLs().filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key), FileManager.default.fileExists(atPath: url.path) else { return false }
            seen.insert(key); return true
        }.prefix(Self.maximumRecents)
        recentButtons = urls.map(makeRecentButton)
        recentButtons.forEach { recentStack.addArrangedSubview($0); $0.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true }
        recentStack.isHidden = recentButtons.isEmpty
        recentHeading.isHidden = recentButtons.isEmpty
        dropZone.isHidden = !recentButtons.isEmpty
    }

    private func makeRecentButton(_ url: URL) -> NSButton {
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let button = NSButton(title: url.lastPathComponent, target: self, action: #selector(openRecent(_:)))
        let title = NSMutableAttributedString(string: url.lastPathComponent, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(string: "   " + folder, attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = .left
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        button.attributedTitle = title
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.image = recentIcon(url)
        button.imageHugsTitle = true
        button.toolTip = url.path
        button.setAccessibilityLabel("Open \(url.lastPathComponent), in \(folder)")
        button.identifier = NSUserInterfaceItemIdentifier(url.path)
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private func recentIcon(_ url: URL) -> NSImage {
        if let themed = documentIcons.icon(forFileName: url.lastPathComponent, points: 16) { return themed }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    // MARK: Actions

    @objc func open(_ sender: Any?) { onOpen?() }
    @objc func create(_ sender: Any?) { onCreate?() }
    @objc func appearance(_ sender: Any?) { onAppearance?() }
    @objc private func openRecent(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpenURLs?([URL(fileURLWithPath: path)])
    }
    func setEnabled(_ enabled: Bool) {
        ([openButton, createButton] + recentButtons).forEach { $0.isEnabled = enabled }
    }

    // MARK: Drop to open

    static func droppedArchives(_ pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            var directory: ObjCBool = false
            return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onOpenURLs != nil, openButton.isEnabled, !Self.droppedArchives(sender.draggingPasteboard).isEmpty else { return [] }
        dropTargeted = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropTargeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropTargeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTargeted = false
        let urls = Self.droppedArchives(sender.draggingPasteboard)
        guard !urls.isEmpty, let onOpenURLs else { return false }
        onOpenURLs(urls)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard dropTargeted else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: 12, yRadius: 12)
        path.lineWidth = 3
        NSColor.selectedContentBackgroundColor.setStroke(); path.stroke()
    }
}

/// Shown instead of the recent list when there is no history: what can be
/// dropped, and which formats Arkiv opens.
final class WelcomeDropZone: NSView {
    var targeted = false { didSet { needsDisplay = true } }
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let image = NSImageView(image: ArkivStyle.symbol("arrow.down.doc", "", pointSize: 28, weight: .light) ?? NSImage())
        image.contentTintColor = .tertiaryLabelColor
        image.setAccessibilityElement(false)
        let title = NSTextField(labelWithString: "Drop an archive here")
        title.font = .systemFont(ofSize: 13, weight: .medium); title.textColor = .secondaryLabelColor
        let formats = NSTextField(labelWithString: "ZIP · 7z · RAR · TAR · GZ · BZ2 · XZ · ZST")
        formats.font = .systemFont(ofSize: NSFont.smallSystemFontSize); formats.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [image, title, formats])
        stack.orientation = .vertical; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Drop an archive here to open it. Supported: ZIP, 7z, RAR, TAR, GZ, BZ2, XZ and ZST.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        path.lineWidth = targeted ? 2 : 1.25
        path.setLineDash([5, 4], count: 2, phase: 0)
        (targeted ? NSColor.selectedContentBackgroundColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }
}
