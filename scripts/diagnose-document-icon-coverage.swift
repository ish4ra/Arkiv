// Read-only document-icon coverage diagnostic for Finder.
//
//   swift scripts/diagnose-document-icon-coverage.swift [--app /Applications/Arkiv.app] [--file <archive>]...
//
// For every archive suffix Arkiv knows (including case variants, compound
// suffixes such as .tar.xz, split-7z volumes and unrelated numeric suffixes)
// it creates an empty sample file in a new private temporary folder and
// reports:
//   * the type macOS gives the suffix, and the content type of the actual file
//   * whether Arkiv's Info.plist attaches a document icon to that type
//   * the default handler, and whether Arkiv is registered as a handler at all
//   * whether the icon Icon Services returns (what Finder and Get Info draw) is
//     Arkiv's bundled icon for that type
// --file adds the same report for existing files, which are only read.
//
// It never registers apps, changes default applications, resets caches or
// writes to anything but its own temporary folder.
//
// --ci-default-handler-experiment exists only for the throwaway CI runner
// (it refuses to run unless GITHUB_ACTIONS=true): it registers the app,
// temporarily makes Arkiv the default for ZIP and XZ, repeats the icon check
// and restores the previous defaults. It shows which part of Finder's icon
// choice depends on the default handler.
import AppKit
import CoreServices
import UniformTypeIdentifiers

let bundleID = "xyz.isharalakshan.arkiv"
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> [String] {
    var values: [String] = []
    while let i = args.firstIndex(of: name), i + 1 < args.count { values.append(args[i + 1]); args.removeSubrange(i...(i + 1)) }
    return values
}
let experiment = args.contains("--ci-default-handler-experiment")
args.removeAll { $0 == "--ci-default-handler-experiment" }
let appArg = option("--app").first
let files = option("--file")

guard let app = appArg.map({ URL(fileURLWithPath: $0) }) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
      let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
    print("Arkiv.app not found; pass --app /path/to/Arkiv.app"); exit(1)
}
print("Arkiv: \(app.path) build \(info["CFBundleVersion"] ?? "?")")
let registered = (LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL]) ?? []
print("Arkiv copies registered with LaunchServices: \(registered.map(\.path))")

// Document types: content type -> icon file.
var iconForType: [String: String] = [:]
for type in info["CFBundleDocumentTypes"] as? [[String: Any]] ?? [] {
    for uti in type["LSItemContentTypes"] as? [String] ?? [] { iconForType[uti] = type["CFBundleTypeIconFile"] as? String }
}
let imported = (info["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []).compactMap { $0["UTTypeIdentifier"] as? String }

func pixels(_ image: NSImage, _ side: Int = 64) -> [UInt8] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: side * side * 4))
}
/// Mean absolute RGBA difference at 64 px; 0 means identical.
func difference(_ a: NSImage, _ b: NSImage) -> Double {
    let x = pixels(a), y = pixels(b)
    return Double(zip(x, y).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(x.count)
}
let bundledIcons: [String: NSImage] = Dictionary(uniqueKeysWithValues: Set(iconForType.values).compactMap { name in
    NSImage(contentsOf: app.appendingPathComponent("Contents/Resources").appendingPathComponent(name)).map { (name, $0) }
})

let samples = ["archive.zip", "ARCHIVE.ZIP", "archive.7z", "archive.rar", "archive.tar", "archive.gz", "archive.bz2", "archive.xz",
               "Archive.XZ", "archive.zst", "archive.tgz", "archive.tar.gz", "archive.TAR.GZ", "archive.tbz2", "archive.tbz",
               "archive.tar.bz2", "archive.txz", "archive.tar.xz", "Archive.Tar.Xz", "Sparkle-2.10.0.tar.xz", "archive.tzst",
               "archive.tar.zst", "archive.7z.001", "archive.7z.002", "archive.001", "archive.part1.rar", "archive.r00",
               "archive.z01", "archive.zip.001"]
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arkiv-icon-coverage-" + UUID().uuidString)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sampleURLs = samples.map { name -> URL in
    let url = folder.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data())
    return url
}

func report(_ url: URL, label: String) -> (verdict: String, arkivIcon: Bool) {
    let ext = url.pathExtension
    let byExtension = UTType(filenameExtension: ext)
    let content = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
    let typeID = content?.identifier ?? byExtension?.identifier ?? "none"
    let compound = url.lastPathComponent.lowercased().components(separatedBy: ".").dropFirst().suffix(2).joined(separator: ".")
    let compoundType = compound.contains(".") ? UTType(filenameExtension: compound)?.identifier ?? "none" : "-"
    let iconFile = iconForType[typeID]
    let handler = NSWorkspace.shared.urlForApplication(toOpen: url)
    let handlers = NSWorkspace.shared.urlsForApplications(toOpen: url)
    let arkivIsHandler = handlers.contains { Bundle(url: $0)?.bundleIdentifier == bundleID }
    let arkivIsDefault = handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == bundleID
    let shown = NSWorkspace.shared.icon(forFile: url.path)
    var arkivIcon = false, diff = "-"
    if let iconFile, let bundled = bundledIcons[iconFile] {
        let d = difference(shown, bundled)
        diff = String(format: "%.2f", d)
        arkivIcon = d < 1.0
    }
    let verdict: String
    switch (iconFile != nil, arkivIsHandler, arkivIsDefault, arkivIcon) {
    case (_, _, _, true): verdict = "Arkiv icon shown"
    case (false, _, _, _): verdict = typeID.hasPrefix("dyn.") ? "no declared type (Arkiv does not claim it)" : "type not claimed by Arkiv"
    case (true, false, _, _): verdict = "Arkiv claims the type but is not registered as a handler here"
    case (true, true, false, _): verdict = "Arkiv registered, but another app is the default handler, so Finder shows that app's icon"
    case (true, true, true, false): verdict = "Arkiv is the default handler but Icon Services returned another icon (cached?)"
    }
    print("\(label)  ext=.\(ext) type=\(byExtension?.identifier ?? "none") fileType=\(content?.identifier ?? "none") compoundTag[\(compound)]=\(compoundType)"
        + " arkivIcon=\(iconFile ?? "none")\(imported.contains(typeID) ? " (imported)" : "") default=\(handler?.lastPathComponent ?? "none")"
        + " arkivHandler=\(arkivIsHandler) diff=\(diff) -> \(verdict)")
    return (verdict, arkivIcon)
}

print("\n== Sample files (empty, in \(folder.path))")
for url in sampleURLs { _ = report(url, label: url.lastPathComponent) }
if !files.isEmpty {
    print("\n== Your files (read only)")
    for path in files {
        let url = URL(fileURLWithPath: path)
        _ = report(url, label: path)
        if let item = MDItemCreate(nil, path as CFString),
           let type = MDItemCopyAttribute(item, kMDItemContentType) as? String { print("  Spotlight content type: \(type)") }
        let finderInfo = url.withUnsafeFileSystemRepresentation { p -> Int in p.map { getxattr($0, "com.apple.FinderInfo", nil, 0, 0, 0) } ?? -1 }
        print("  per-file custom icon data (com.apple.FinderInfo): \(finderInfo > 0 ? "present" : "none")")
    }
}

if experiment {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
        print("--ci-default-handler-experiment changes default apps and runs only on a CI runner"); exit(2)
    }
    print("\n== CI experiment: Arkiv as the default handler (throwaway runner only)")
    let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    let register = Process(); register.executableURL = URL(fileURLWithPath: lsregister); register.arguments = ["-f", app.path]
    try? register.run(); register.waitUntilExit()
    let types = ["public.zip-archive", "org.tukaani.xz-archive"]
    var previous: [String: String] = [:]
    for type in types {
        previous[type] = LSCopyDefaultRoleHandlerForContentType(type as CFString, .all)?.takeRetainedValue() as String?
        let status = LSSetDefaultRoleHandlerForContentType(type as CFString, .all, bundleID as CFString)
        print("\(type): previous default \(previous[type] ?? "none"), set Arkiv -> status \(status)")
    }
    let watched = sampleURLs.filter { ["archive.zip", "archive.xz", "archive.tar.xz", "Sparkle-2.10.0.tar.xz", "archive.txz"].contains($0.lastPathComponent) }
    for _ in 0..<20 where !watched.prefix(2).allSatisfy({ NSWorkspace.shared.urlForApplication(toOpen: $0).flatMap { Bundle(url: $0)?.bundleIdentifier } == bundleID }) {
        Thread.sleep(forTimeInterval: 0.5)
    }
    for url in watched { _ = report(url, label: "after: " + url.lastPathComponent) }
    for type in types {
        if let old = previous[type] { _ = LSSetDefaultRoleHandlerForContentType(type as CFString, .all, old as CFString) }
    }
    print("Previous defaults restored")
}
try? FileManager.default.removeItem(at: folder)
print("\nDiagnostic complete. Nothing outside \(folder.path) was changed\(experiment ? " except the CI-only experiment above" : "").")
