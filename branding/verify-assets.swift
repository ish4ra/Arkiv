// Run on macOS: swift branding/verify-assets.swift branding
import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets: [(String, Int)] = [
    ("Arko-AppIcon-1024.png", 1024), ("Arko-AppIcon-512.png", 512),
    ("Arko-AppIcon-256.png", 256), ("Arko-AppIcon-128.png", 128),
    ("Arko-Mark-Transparent-1024.png", 1024), ("Arko-Mark-Transparent-512.png", 512)
]
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "ArkoBranding", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
for (name, size) in assets {
    let data = try Data(contentsOf: directory.appendingPathComponent(name))
    try require(data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "\(name): not a PNG")
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw NSError(domain: "ArkoBranding", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(name): cannot decode PNG"])
    }
    try require(bitmap.pixelsWide == size && bitmap.pixelsHigh == size, "\(name): incorrect dimensions")
    try require(bitmap.hasAlpha, "\(name): missing alpha channel")
    for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
        try require(bitmap.colorAt(x: x, y: y)?.alphaComponent == 0, "\(name): corner is not transparent")
    }
    var hasOpaque = false, hasPartialAlpha = false
    scan: for y in 0..<size {
        for x in 0..<size {
            let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
            hasOpaque = hasOpaque || alpha == 1
            hasPartialAlpha = hasPartialAlpha || (alpha > 0 && alpha < 1)
            if hasOpaque && hasPartialAlpha { break scan }
        }
    }
    try require(hasOpaque && hasPartialAlpha, "\(name): missing artwork or antialiased transparency")
    print("\(name): \(size) × \(size), transparent corners, opaque artwork, partial alpha verified")
}
for size in [1024, 512] {
    let app = try Data(contentsOf: directory.appendingPathComponent("Arko-AppIcon-\(size).png"))
    let mark = try Data(contentsOf: directory.appendingPathComponent("Arko-Mark-Transparent-\(size).png"))
    try require(app == mark, "\(size): mark must be byte-identical to the app-icon export")
}
