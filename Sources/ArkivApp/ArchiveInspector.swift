import AppKit
import ArkivCore

/// Snapshot-only inspector; showing it performs no extraction or password lookup.
///
/// A header with the archive's document icon (from the selected theme, and
/// redrawn when the theme changes while the sheet is open), its name and a
/// one-line summary; then every property in a single aligned grid on a card.
final class ArchiveInspector: NSWindowController {
    let iconView = NSImageView()
    private let iconProvider: () -> NSImage?

    convenience init(metadata: ArchiveMetadata, icon: NSImage? = nil) {
        self.init(metadata: metadata, iconProvider: { icon })
    }
    init(metadata: ArchiveMetadata, iconProvider: @escaping () -> NSImage?) {
        self.iconProvider = iconProvider
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Archive Info"

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        refreshIcon()
        let name = NSTextField(labelWithString: metadata.url.lastPathComponent)
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
        let summary = NSTextField(labelWithString: Self.summary(metadata))
        summary.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: NSFont.systemFontSize)
        let titles = NSStackView(views: [name, summary])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        let header = NSStackView(views: [iconView, titles])
        header.alignment = .centerY; header.spacing = 14

        let grid = NSGridView(views: Self.rows(metadata).map { title, value in
            let label = NSTextField(labelWithString: title)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(wrappingLabelWithString: value)
            field.isSelectable = true; field.setAccessibilityLabel(title)
            field.widthAnchor.constraint(lessThanOrEqualToConstant: 330).isActive = true
            return [label, field]
        })
        grid.rowSpacing = 7; grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let card = ArkivCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        let done = NSButton(title: "Done", target: self, action: #selector(dismissInspector))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), done])
        buttons.orientation = .horizontal
        let content = NSStackView(views: [header, card, buttons])
        content.orientation = .vertical
        content.alignment = .leading; content.spacing = 16
        content.setCustomSpacing(18, after: card)
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        card.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
        card.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        buttons.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
        panel.contentView = content; panel.setContentSize(content.fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    /// Called when the document icon theme changes while the sheet is open.
    func refreshIcon() {
        iconView.image = iconProvider() ?? NSWorkspace.shared.icon(for: .archive)
    }
    @objc private func dismissInspector() { if let window, let parent = window.sheetParent { parent.endSheet(window) }; close() }
    static func summary(_ m: ArchiveMetadata) -> String {
        var parts: [String] = []
        if let format = m.format { parts.append(format) }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(clamping: m.physicalSize), countStyle: .file))
        parts.append(m.fileCount == 1 ? "1 file" : "\(m.fileCount) files")
        if m.dataEncrypted == true || m.headersEncrypted == true { parts.append("Encrypted") }
        return parts.joined(separator: " · ")
    }
    static func rows(_ m: ArchiveMetadata) -> [(String,String)] {
        func size(_ bytes:UInt64) -> String { ByteCountFormatter.string(fromByteCount:Int64(clamping:bytes),countStyle:.file) + " (\(bytes) bytes)" }
        var rows = [("Name",m.url.lastPathComponent),("Path",m.url.path)]
        if let format = m.format { rows.append(("Format",format)) }
        rows += [("Archive size",size(m.physicalSize)),("Files",String(m.fileCount)),("Folder entries",String(m.folderCount))]
        if let total = m.unpackedSize { rows.append(("Unpacked size",size(total))) }
        if let ratio = m.sizeRatio { rows.append(("Archive / unpacked",String(format:"%.1f%% (includes overhead)",ratio*100))) }
        if let methods = m.compressionMethods { rows.append(("Methods",methods)) }
        for (name,value) in [("Solid",m.solid),("Data encrypted",m.dataEncrypted),("Filenames encrypted",m.headersEncrypted),("Multipart",m.multipart)] {
            if let value { rows.append((name,value ? "Yes" : "No")) }
        }
        return rows
    }
}
