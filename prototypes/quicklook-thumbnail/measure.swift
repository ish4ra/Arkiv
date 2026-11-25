// Prints "<file> meanR meanG meanB coverage" for each PNG in a folder
// (mean colour of non-transparent pixels; coverage = opaque share).
import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where name.hasSuffix(".png") {
    guard let rep = NSBitmapImageRep(data: (try? Data(contentsOf: folder.appendingPathComponent(name))) ?? Data()) else { continue }
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0, total = 0.0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) { for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
        total += 1
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
        r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
    } }
    print(name, String(format: "%.3f %.3f %.3f %.3f", r / max(n, 1), g / max(n, 1), b / max(n, 1), n / max(total, 1)))
}
