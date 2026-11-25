import AppKit
import ArkivPresentation

/// Grouped-form building blocks shared by every Settings pane: a small
/// heading, a rounded card of rows separated by hairlines, and an optional
/// footnote. Plain AppKit views; no custom framework.
enum SettingsForm {
    /// Width of a section card inside a pane.
    static let cardWidth: CGFloat = 612
    static let rowInset: CGFloat = 14

    static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.setAccessibilityRole(.staticText)
        return label
    }

    static func note(_ text: String, width: CGFloat = cardWidth - 2 * rowInset) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.preferredMaxLayoutWidth = width
        return field
    }

    /// One labelled row: title (and optional detail) leading, control trailing.
    static func row(_ title: String, detail: String? = nil, control: NSView?, detailLabel: NSTextField? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        let texts = NSStackView(views: [titleLabel])
        texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
        let controlWidth = control.map { max($0.fittingSize.width, $0.intrinsicContentSize.width) } ?? 0
        let textWidth = cardWidth - 2 * rowInset - (control == nil ? 0 : controlWidth + 16)
        if let detail = detailLabel ?? detail.map({ note($0) }) {
            detail.preferredMaxLayoutWidth = max(160, textWidth)
            texts.addArrangedSubview(detail)
        }
        texts.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(texts)
        var constraints = [
            texts.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowInset),
            texts.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 9),
            texts.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ]
        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(control)
            constraints += [
                control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -rowInset),
                control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 7),
                texts.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            ]
        } else {
            constraints.append(texts.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -rowInset))
        }
        NSLayoutConstraint.activate(constraints)
        row.setAccessibilityElement(false)
        return row
    }

    /// A card of rows with hairline separators between them.
    static func card(_ rows: [NSView]) -> ArkivCardView {
        let card = ArkivCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for (index, row) in rows.enumerated() {
            row.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                row.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? card.topAnchor, constant: previous == nil ? 2 : 1),
            ])
            if index > 0, let previous {
                let line = NSBox(); line.boxType = .separator
                line.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(line)
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: rowInset),
                    line.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -rowInset),
                    line.topAnchor.constraint(equalTo: previous.bottomAnchor),
                ])
            }
            previous = row
        }
        if let previous { previous.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2).isActive = true }
        card.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        return card
    }

    /// Heading, card and footnote as one block.
    static func section(_ title: String?, _ rows: [NSView], footnote: String? = nil) -> NSStackView {
        var views: [NSView] = []
        if let title { views.append(heading(title)) }
        views.append(card(rows))
        if let footnote {
            let label = note(footnote, width: cardWidth - 8)
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        return stack
    }

    /// A vertical, top-aligned, scrolling pane body.
    static func scrollingPane(_ sections: [NSView]) -> NSScrollView {
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 22
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 24, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        return scroll
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Round accent swatches, like the macOS accent picker. Each swatch is a
/// focusable radio button with its colour's name as its accessibility label.
final class AccentPicker: NSStackView {
    var onChange: ((AppAccent) -> Void)?
    private(set) var swatches: [AccentSwatch] = []
    var selection: AppAccent = .arkiv {
        didSet { swatches.forEach { $0.isSelectedSwatch = $0.accent == selection } }
    }
    init() {
        super.init(frame: .zero)
        orientation = .horizontal; spacing = 10
        for accent in AppAccent.allCases {
            let swatch = AccentSwatch(accent: accent)
            swatch.target = self; swatch.action = #selector(choose(_:))
            swatches.append(swatch)
            addArrangedSubview(swatch)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Accent colour")
        selection = .arkiv
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func choose(_ sender: AccentSwatch) {
        selection = sender.accent
        onChange?(sender.accent)
    }
}

final class AccentSwatch: NSButton {
    let accent: AppAccent
    var isSelectedSwatch = false { didSet { needsDisplay = true; setAccessibilityValue(isSelectedSwatch ? 1 : 0) } }
    init(accent: AppAccent) {
        self.accent = accent
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        title = ""; isBordered = false; setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        toolTip = accent.title
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(accent.title)
        focusRingType = .default
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 26) }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        if accent == .system {
            // macOS's "multicolour" convention for "follow the system".
            NSGradient(colors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple])?.draw(in: circle, angle: -45)
        } else {
            ArkivStyle.color(for: accent).setFill(); circle.fill()
        }
        NSColor.black.withAlphaComponent(0.15).setStroke(); circle.lineWidth = 1; circle.stroke()
        if isSelectedSwatch {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.75).setStroke(); ring.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2.5, y: bounds.midY - 2.5, width: 5, height: 5))
            NSColor.white.setFill(); dot.fill()
        }
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
}
