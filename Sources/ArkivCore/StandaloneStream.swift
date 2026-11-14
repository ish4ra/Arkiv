import Foundation

/// An owned decoded regular file, not a fabricated container. No filesystem mode,
/// timestamp or embedded pathname is promoted to archive metadata.
struct StandaloneStream: Sendable {
    let spool: UnlockedArchive
    let stamp: SourceStamp
    let entry: ArchiveEntry

    static func outputName(for source: URL) throws -> String {
        let original = source.lastPathComponent
        let suffix = [".gz", ".bz2", ".xz"].first { original.lowercased().hasSuffix($0) }
        let name = suffix.map { String(original.dropLast($0.count)) } ?? original + ".decompressed"
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) }) else {
            throw ArchiveFailure.message("The compressed file does not have a safe output name. Rename the source file and reopen it.")
        }
        return name
    }
    static func codecName(_ codec: Int32) -> String {
        [1: "GZIP", 2: "BZIP2", 3: "XZ"][codec, default: "Unknown"]
    }
}
