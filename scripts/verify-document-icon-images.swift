import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let url = root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let data = try? Data(contentsOf: url), let image = NSBitmapImageRep(data: data),
              image.pixelsWide == size * scale, image.pixelsHigh == size * scale, image.hasAlpha,
              let corner = image.colorAt(x: 0, y: 0), corner.alphaComponent < 0.01,
              let center = image.colorAt(x: size * scale / 2, y: size * scale / 2), center.alphaComponent > 0.99
        else { fatalError("Invalid document icon representation: \(url.lastPathComponent)") }
    }
}
print("Document icon dimensions and transparency verified")
