import AppKit
import ArkivPresentation

/// Arkiv's design language in one place: the Tension Seal palette, the accent
/// resolved from preferences, and a few shared metrics. Native AppKit colours
/// do almost all of the work; brand colours are reserved for identity
/// surfaces (welcome canvas, selection, primary actions, status marks).
///
/// Exact brand values come from `scripts/render-icon.swift` (the authoritative
/// app icon renderer) and `design/readme/hero.html`.
enum ArkivStyle {
    static func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: Brand palette (exact)
    static let plum = srgb(0x703A47)          // clasp gradient start
    static let aubergine = srgb(0x301A2B)     // clasp gradient end
    static let midnight = srgb(0x0C060A)      // midnight plum
    static let brass = srgb(0xCDA66C)
    static let brassDeep = srgb(0x8C6538)
    static let jade = srgb(0x4A9C82)
    static let ivory = srgb(0xF5E9DE)

    /// Positive status (installed, verified, enabled): jade, darkened in Light
    /// for 4.5:1 text contrast.
    static let success = dynamic(light: srgb(0x2F7A64), dark: srgb(0x6CC0A2))
    /// Brass for small marks such as "in use", darkened in Light for contrast.
    static let mark = dynamic(light: srgb(0x87612F), dark: brass)

    // MARK: Accent
    /// Every value carries white text at 4.5:1 or better (selection, default buttons).
    static func color(for accent: AppAccent) -> NSColor { accentColors[accent] ?? .controlAccentColor }
    /// One instance per accent, so views can compare the colour they hold.
    private static let accentColors: [AppAccent: NSColor] = [
        .arkiv: dynamic(light: srgb(0x7E3F55), dark: srgb(0x8E4A61)),
        .jade: dynamic(light: srgb(0x2F7A64), dark: srgb(0x33806A)),
        .brass: dynamic(light: srgb(0x87612F), dark: srgb(0x957035)),
        .graphite: dynamic(light: srgb(0x5F5A64), dark: srgb(0x6E6873)),
        .system: .controlAccentColor,
    ]
    /// nil means "draw what macOS draws".
    static func customAccent(_ accent: AppAccent) -> NSColor? { accent == .system ? nil : color(for: accent) }

    /// A default (Return) button in Arkiv's accent. System accent leaves the
    /// button untouched so it follows macOS exactly.
    static func stylePrimary(_ button: NSButton, accent: AppAccent) {
        button.bezelColor = customAccent(accent)
    }

    // MARK: Canvas
    /// The welcome canvas: warm ivory in Light, a near-neutral plum black in
    /// Dark. Plain window background when the user asks for more contrast or
    /// less transparency.
    static var prefersPlainSurfaces: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    static let canvas = dynamic(light: srgb(0xF7F2EC), dark: srgb(0x18131A))
    static let canvasGlow = dynamic(light: srgb(0xE9D5B6, alpha: 0.55), dark: srgb(0x703A47, alpha: 0.42))
    static let card = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: NSColor.white.withAlphaComponent(0.05))
    static let cardBorder = dynamic(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.08))

    // MARK: Metrics
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 10
    static let selectionRadius: CGFloat = 5

    static func symbol(_ name: String, _ description: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }
}

/// A rounded, softly filled container used for grouped content (Settings
/// sections, previews, Archive Info). Drawn, not layered, so it follows the
/// appearance without extra work.
final class ArkivCardView: NSView {
    var fill: NSColor = ArkivStyle.card { didSet { needsDisplay = true } }
    var border: NSColor? = ArkivStyle.cardBorder { didSet { needsDisplay = true } }
    var radius: CGFloat = ArkivStyle.cardRadius { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
}

/// The welcome canvas: one static gradient, no animation, no layers.
class ArkivCanvasView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard !ArkivStyle.prefersPlainSurfaces else {
            NSColor.windowBackgroundColor.setFill(); bounds.fill(); return
        }
        ArkivStyle.canvas.setFill(); bounds.fill()
        // A soft glow behind the identity column; resolved per appearance.
        let glow = ArkivStyle.canvasGlow.usingColorSpace(.sRGB) ?? ArkivStyle.canvasGlow
        let gradient = NSGradient(colors: [glow, glow.withAlphaComponent(0)])
        let radius = max(bounds.width, bounds.height) * 0.62
        gradient?.draw(fromCenter: NSPoint(x: bounds.width * 0.3, y: bounds.height * 0.55), radius: 0,
                       toCenter: NSPoint(x: bounds.width * 0.3, y: bounds.height * 0.55), radius: radius, options: [])
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// The browser's bottom bar: path on the leading side, status on the trailing
/// side, as in Finder's path bar. Hidden (zero height) on the welcome canvas.
final class ArkivFooterBar: NSView {
    static let height: CGFloat = 28
    let stack = NSStackView()
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Path and status")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: isFlipped ? 0 : bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
