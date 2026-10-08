// Original Arkiv "Tension Seal" artwork. No third-party assets or symbols.
import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
func render(_ pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    // A sculpted open ceramic clasp surrounding three compressed, folded ribbons.
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -20); shadow.set()
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 710, y: 864))
    body.curve(to: NSPoint(x: 154, y: 548), controlPoint1: NSPoint(x: 330, y: 958), controlPoint2: NSPoint(x: 108, y: 782))
    body.curve(to: NSPoint(x: 350, y: 164), controlPoint1: NSPoint(x: 120, y: 316), controlPoint2: NSPoint(x: 220, y: 162))
    body.curve(to: NSPoint(x: 827, y: 264), controlPoint1: NSPoint(x: 510, y: 116), controlPoint2: NSPoint(x: 792, y: 144))
    body.curve(to: NSPoint(x: 740, y: 367), controlPoint1: NSPoint(x: 892, y: 360), controlPoint2: NSPoint(x: 813, y: 415))
    body.curve(to: NSPoint(x: 393, y: 349), controlPoint1: NSPoint(x: 610, y: 313), controlPoint2: NSPoint(x: 458, y: 274))
    body.curve(to: NSPoint(x: 384, y: 655), controlPoint1: NSPoint(x: 320, y: 430), controlPoint2: NSPoint(x: 320, y: 588))
    body.curve(to: NSPoint(x: 683, y: 683), controlPoint1: NSPoint(x: 453, y: 726), controlPoint2: NSPoint(x: 569, y: 720))
    body.curve(to: NSPoint(x: 710, y: 864), controlPoint1: NSPoint(x: 805, y: 647), controlPoint2: NSPoint(x: 826, y: 837))
    body.close()
    NSGradient(starting: color(0.44, 0.23, 0.28), ending: color(0.19, 0.10, 0.17))!.draw(in: body, angle: -70)
    NSShadow().set()
    // Warm folded lamellae are the storage motif, not a folder, box, or zipper.
    for (i, y) in [418.0, 503.0, 588.0].enumerated() {
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 430, y: y - 31))
        ribbon.curve(to: NSPoint(x: 850, y: y + 3), controlPoint1: NSPoint(x: 560, y: y - 55), controlPoint2: NSPoint(x: 745, y: y + 34))
        ribbon.curve(to: NSPoint(x: 821, y: y + 74), controlPoint1: NSPoint(x: 916, y: y - 5), controlPoint2: NSPoint(x: 922, y: y + 67))
        ribbon.curve(to: NSPoint(x: 430, y: y + 38), controlPoint1: NSPoint(x: 706, y: y + 104), controlPoint2: NSPoint(x: 566, y: y + 15))
        ribbon.close()
        let shade = CGFloat(i) * 0.035
        NSGradient(starting: color(0.99, 0.81 + shade, 0.45 + shade), ending: color(0.77, 0.43, 0.22))!.draw(in: ribbon, angle: -90)
    }
    let seal = NSBezierPath(ovalIn: NSRect(x: 219, y: 457, width: 110, height: 110))
    NSGradient(starting: color(0.81, 0.94, 0.83), ending: color(0.29, 0.61, 0.51))!.draw(in: seal, angle: -80)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
for size in [16, 32, 128, 256, 512] {
    try render(size, to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
