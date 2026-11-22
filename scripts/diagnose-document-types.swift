// Prints how this Mac types each archive suffix, and fails if the system no
// longer declares the .tgz type that Arkiv's TGZ document icon is attached to.
// Arkiv never declares generic volume suffixes (.001, .z01, .r00); they are
// listed only to record what Finder does with them.
import Foundation
import UniformTypeIdentifiers

let extensions = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz", "xz", "txz", "zst", "tzst", "001", "z01", "r00"]
for ext in extensions {
    guard let type = UTType(filenameExtension: ext) else { print(".\(ext): no type"); continue }
    let parents = type.supertypes.map(\.identifier).filter { $0.contains("archive") || $0.contains("gnu") || $0.contains("zstd") }.sorted()
    print(".\(ext): \(type.identifier) declared=\(type.isDeclared) dynamic=\(type.isDynamic) conformsTo=\(parents)")
}
guard let tgz = UTType(filenameExtension: "tgz"), tgz.identifier == "org.gnu.gnu-zip-tar-archive", tgz.isDeclared else {
    fatalError("macOS does not declare org.gnu.gnu-zip-tar-archive for .tgz; the TGZ document type would be inert")
}
print("Document type diagnostics complete")
