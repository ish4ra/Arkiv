import AppKit
import UniformTypeIdentifiers
import ArkivCore
import ArkivPresentation
import ArkivThemes

/// Keep the context menu attached to the row under the pointer without losing a multi-selection.
final class ArchiveTableView: NSTableView {
    var previewKeyHandler: ((NSEvent) -> Bool)?
    static func isPreviewDismissKey(_ event: NSEvent) -> Bool {
        event.type == .keyDown && (event.keyCode == 49 || event.keyCode == 53)
            && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
    override func keyDown(with event: NSEvent) {
        if previewKeyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        if clicked >= 0, !selectedRowIndexes.contains(clicked) {
            selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        } else if clicked < 0 { deselectAll(nil) }
        return super.menu(for: event)
    }
}

/// Selection as a rounded, inset highlight in Arkiv's accent (or the macOS
/// accent). Inactive windows use the system's unemphasized colour, and text
/// switches to the emphasized style exactly as with the stock row view.
final class ArchiveRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("ArkivRow")
    /// nil follows the macOS accent colour.
    var accent: NSColor? { didSet { if isSelected { needsDisplay = true } } }
    /// For previews: draw the selection as in a focused window.
    var alwaysEmphasized = false
    override var isEmphasized: Bool {
        get { alwaysEmphasized || super.isEmphasized }
        set { super.isEmphasized = newValue }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let color = isEmphasized ? (accent ?? .selectedContentBackgroundColor) : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        let rect = bounds.insetBy(dx: 5, dy: bounds.height > 22 ? 1 : 0.5)
        NSBezierPath(roundedRect: rect, xRadius: ArkivStyle.selectionRadius, yRadius: ArkivStyle.selectionRadius).fill()
    }
}

final class ArchiveCellView: NSTableCellView {
    static let numericColumns: Set<String> = ["size", "packed", "ratio"]
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let column: String
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?
    init(column: String) {
        self.column = column
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(column)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = Self.numericColumns.contains(column) ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
        label.alignment = Self.numericColumns.contains(column) ? .right : .left
        // Metadata reads as secondary, like Finder; the name stays primary.
        label.textColor = column == "name" ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label); textField = label
        var constraints = [label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)]
        if column == "name" {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(false)
            addSubview(icon); imageView = icon
            let width = icon.widthAnchor.constraint(equalToConstant: 16), height = icon.heightAnchor.constraint(equalToConstant: 16)
            iconWidth = width; iconHeight = height
            constraints += [icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor), width, height,
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6))
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// The document icon size Arkiv requests for the name column.
    private(set) var iconSize: CGFloat = 16

    func configure(_ row: BrowserRow, column: String, searching: Bool, documentIcons: DocumentIconProvider = .shared,
                   density: BrowserDensity = .standard) {
        let size = CGFloat(density.iconSize)
        let fontSize = CGFloat(density.fontSize)
        if Self.numericColumns.contains(column) {
            if label.font?.pointSize != fontSize - 1 { label.font = .monospacedDigitSystemFont(ofSize: fontSize - 1, weight: .regular) }
        } else if label.font?.pointSize != fontSize { label.font = .systemFont(ofSize: fontSize) }
        switch column {
        case "size": label.stringValue = row.size.flatMap { $0 >= 0 ? ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) : nil } ?? "—"
        case "packed", "ratio", "modified", "method", "encrypted", "crc", "attributes": label.stringValue = BrowserPresentation.metadataText(row,column:column)
        case "type": label.stringValue = BrowserPresentation.packageKind(row) ?? (row.isDirectory ? "Folder" : "File")
        default:
            label.stringValue = searching ? row.path : row.name
            if iconSize != size { iconSize = size; iconWidth?.constant = size; iconHeight?.constant = size }
            icon.image = Self.icon(for: row, points: size, documentIcons: documentIcons)
        }
        toolTip = column == "name" ? row.path : label.stringValue
    }

    /// Archives inside the archive use the selected document icon theme;
    /// every other entry keeps its system icon.
    static func icon(for row: BrowserRow, points: CGFloat, documentIcons: DocumentIconProvider) -> NSImage {
        let type: UTType
        if BrowserPresentation.packageKind(row) != nil {
            type = UTType(filenameExtension: (row.name as NSString).pathExtension.lowercased()) ?? .bundle
        } else {
            type = row.isDirectory ? .folder : UTType(filenameExtension: (row.name as NSString).pathExtension) ?? .data
        }
        let themed = row.isDirectory || BrowserPresentation.packageKind(row) != nil ? nil : documentIcons.icon(forFileName: row.name, points: points)
        return themed ?? NSWorkspace.shared.icon(for: type)
    }
}
