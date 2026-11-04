// Original Arkiv document family. Composes the unchanged Tension Seal export.
import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let mark = NSImage(contentsOfFile: "branding/Arkiv-Mark-Transparent-1024.png") else { fatalError("Missing original mark") }
for format in ["ZIP", "7z", "TAR", "RAR"] {
    let output = root.appendingPathComponent("Arkiv-\(format).iconset")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current?.imageInterpolation = .high
            (AffineTransform(scale: CGFloat(pixels) / 1024) as NSAffineTransform).concat()
            let paper = NSBezierPath()
            paper.move(to: NSPoint(x: 180, y: 76))
            paper.line(to: NSPoint(x: 844, y: 76))
            paper.line(to: NSPoint(x: 844, y: 748))
            paper.line(to: NSPoint(x: 656, y: 944))
            paper.line(to: NSPoint(x: 180, y: 944)); paper.close()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
            NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 1).setFill(); paper.fill()
            NSShadow().set()
            NSColor(srgbRed: 0.65, green: 0.60, blue: 0.61, alpha: 1).setStroke()
            paper.lineWidth = 5; paper.stroke()
            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 656, y: 944)); fold.line(to: NSPoint(x: 656, y: 748))
            fold.line(to: NSPoint(x: 844, y: 748)); fold.close()
            NSColor(srgbRed: 0.84, green: 0.81, blue: 0.81, alpha: 1).setFill(); fold.fill()
            // Same aspect ratio, full transparent canvas, no recoloring or tracing.
            mark.draw(in: NSRect(x: 230, y: 295, width: 570, height: 570))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: pixels <= 64 ? 224 : 148, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.30, green: 0.15, blue: 0.22, alpha: 1)]
            let label = format as NSString
            let extent = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: (1024 - extent.width) / 2, y: 135), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
}
