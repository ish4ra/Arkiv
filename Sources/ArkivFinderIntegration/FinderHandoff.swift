import Foundation

/// The extension depends only on this routing module, never on the archive engine.
public enum FinderCommand: String, CaseIterable, Sendable {
    case open, extractHere, extractFolder, extractTo
}

public enum FinderHandoffError: Error, LocalizedError {
    case invalidRequest
    public var errorDescription: String? { "Select one local ZIP or uncompressed TAR archive for Arkiv." }
}

public struct FinderHandoff: Sendable {
    public static let scheme = "arkiv-finder"
    public let command: FinderCommand
    public let archive: URL

    public init(command: FinderCommand, archive: URL) throws {
        guard Self.isArchiveURL(archive) else { throw FinderHandoffError.invalidRequest }
        self.command = command
        self.archive = archive.standardizedFileURL
    }

    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == Self.scheme, parts.host == "action", parts.path == "/v1",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "command" }).count == 1,
              items.filter({ $0.name == "file" }).count == 1,
              let raw = items.first(where: { $0.name == "command" })?.value,
              let command = FinderCommand(rawValue: raw),
              let file = items.first(where: { $0.name == "file" })?.value,
              let archive = URL(string: file) else { throw FinderHandoffError.invalidRequest }
        try self.init(command: command, archive: archive)
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme; parts.host = "action"; parts.path = "/v1"
        parts.queryItems = [URLQueryItem(name: "command", value: command.rawValue),
                            URLQueryItem(name: "file", value: archive.absoluteString)]
        return parts.url!
    }

    public static func isArchiveURL(_ url: URL) -> Bool {
        url.isFileURL && [nil, "", "localhost"].contains(url.host) && url.user == nil && url.password == nil
            && url.port == nil && url.query == nil && url.fragment == nil && url.path.hasPrefix("/")
            && !url.path.contains("\0") && !url.absoluteString.lowercased().contains("%00") && ["zip", "tar"].contains(url.pathExtension.lowercased())
    }

    /// Menu eligibility only. The main app revalidates before invoking the engine.
    public static func selection(_ urls: [URL], within home: URL) -> URL? {
        guard urls.count == 1, isArchiveURL(urls[0]), home.isFileURL,
              home.pathComponents.count > 1 else { return nil }
        let archive = urls[0].standardizedFileURL
        let root = home.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let path = archive.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard path.count > root.count, Array(path.prefix(root.count)) == root,
              let attributes = try? FileManager.default.attributesOfItem(atPath: archive.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return archive
    }

    /// Shared with FinderRequest so menu and extraction use exactly the same name.
    public static func folderName(for archive: URL) -> String {
        let base = String(archive.lastPathComponent.dropLast(4))
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let clean = base.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var result = ""
        for character in clean {
            guard (result + String(character)).utf8.count <= 180 else { break }
            result.append(character)
        }
        return result.isEmpty ? "Archive" : result
    }
}
