// Prints how this Mac types each archive suffix and which bundle declares each
// compressed-TAR alias type, and fails if macOS no longer declares a type that
// one of Arkiv's alias document icons is attached to. Arkiv never declares
// generic volume suffixes (.001, .z01, .r00); they are listed only to record
// what Finder does with them.
import Foundation
import UniformTypeIdentifiers

let extensions = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz", "xz", "txz", "zst", "tzst", "001", "z01", "r00"]
for ext in extensions {
    guard let type = UTType(filenameExtension: ext) else { print(".\(ext): no type"); continue }
    let parents = type.supertypes.map(\.identifier).filter { $0.contains("archive") || $0.contains("gnu") || $0.contains("zstd") }.sorted()
    print(".\(ext): \(type.identifier) declared=\(type.isDeclared) dynamic=\(type.isDynamic) conformsTo=\(parents)")
}

// Which bundle declares each alias type, from the LaunchServices database.
let aliases = ["org.gnu.gnu-zip-tar-archive": ["tgz"], "public.tar-bzip2-archive": ["tbz2", "tbz"], "org.tukaani.tar-xz-archive": ["txz"]]
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
var declarers: [String: [String]] = [:]
if FileManager.default.isExecutableFile(atPath: lsregister) {
    func run(_ arguments: [String]) -> String {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: lsregister); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output
    }
    var dump = run(["-dump", "Type"])
    if !dump.contains("type id:") { dump = run(["-dump"]) }
    for block in dump.components(separatedBy: "\n----") {
        guard let id = aliases.keys.first(where: { block.contains("type id:") && block.range(of: "type id:\\s+\($0)\\s", options: .regularExpression) != nil }) else { continue }
        let bundle = block.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("bundle:") } ?? "bundle: ?"
        declarers[id, default: []].append(bundle.trimmingCharacters(in: .whitespaces))
    }
}
var failures: [String] = []
for (id, exts) in aliases.sorted(by: { $0.key < $1.key }) {
    print("\(id) declared by: \(declarers[id]?.joined(separator: "; ") ?? "(not found in LaunchServices dump)")")
    for ext in exts where UTType(filenameExtension: ext)?.identifier != id || UTType(id)?.isDeclared != true {
        failures.append(".\(ext) does not resolve to a declared \(id)")
    }
}
if !failures.isEmpty { fatalError("Alias document icons would be inert: " + failures.joined(separator: ", ")) }
print("Document type diagnostics complete")
