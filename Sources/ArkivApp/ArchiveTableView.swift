import AppKit
import UniformTypeIdentifiers
import ArkivCore

/// Keep the context menu attached to the row under the pointer without losing a multi-selection.
final class ArchiveTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        if clicked >= 0, !selectedRowIndexes.contains(clicked) {
            selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        } else if clicked < 0 { deselectAll(nil) }
        return super.menu(for: event)
    }
}

final class ArchiveCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    init(column: String) {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(column)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = column == "size" ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
        label.alignment = column == "size" ? .right : .left
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label); textField = label
        var constraints = [label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)]
        if column == "name" {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            addSubview(icon); imageView = icon
            constraints += [icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6))
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func configure(_ row: BrowserRow, column: String, searching: Bool) {
        switch column {
        case "size": label.stringValue = row.size.flatMap { $0 >= 0 ? ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) : nil } ?? "—"
        case "type": label.stringValue = row.isDirectory ? "Folder" : "File"
        default:
            label.stringValue = searching ? row.path : row.name
            let type = row.isDirectory ? UTType.folder : UTType(filenameExtension: (row.name as NSString).pathExtension) ?? .data
            icon.image = NSWorkspace.shared.icon(for: type)
        }
        toolTip = column == "name" ? row.path : label.stringValue
    }
}
