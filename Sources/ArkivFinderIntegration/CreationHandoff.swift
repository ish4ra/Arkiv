import Foundation

public enum CreationCommand: String, Sendable {
    case addArchive, zip
    public var menuTag: Int { self == .addArchive ? 10 : 11 }
    public init?(menuTag: Int) {
        switch menuTag { case 10: self = .addArchive; case 11: self = .zip; default: return nil }
    }
}

public struct CreationHandoff: Sendable {
    public let command: CreationCommand
    public let sources: [URL]
    public init(command: CreationCommand, sources: [URL]) throws {
        self.sources = try Self.validate(sources)
        self.command = command
    }
    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == FinderHandoff.scheme, parts.host == "create", parts.path == "/v1",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count >= 2, items.count <= 129,
              items.allSatisfy({ $0.name == "command" || $0.name == "file" }),
              items.filter({ $0.name == "command" }).count == 1,
              let raw = items.first(where: { $0.name == "command" })?.value,
              let command = CreationCommand(rawValue: raw) else { throw FinderHandoffError.invalidRequest }
        let files = items.filter { $0.name == "file" }
        let urls = files.compactMap { $0.value.flatMap(URL.init(string:)) }
        guard files.count == urls.count else { throw FinderHandoffError.invalidRequest }
        try self.init(command: command, sources: urls)
    }
    public var url: URL {
        var parts = URLComponents()
        parts.scheme = FinderHandoff.scheme; parts.host = "create"; parts.path = "/v1"
        parts.queryItems = [URLQueryItem(name: "command", value: command.rawValue)] + sources.map { URLQueryItem(name: "file", value: $0.absoluteString) }
        return parts.url!
    }
    public static func validate(_ urls: [URL]) throws -> [URL] {
        guard !urls.isEmpty, urls.count <= 128 else { throw FinderHandoffError.invalidRequest }
        var normalized: [URL] = []
        for url in urls {
            guard url.isFileURL, [nil, "", "localhost"].contains(url.host), url.user == nil,
                  url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
                  url.path.hasPrefix("/"), !url.path.contains("\0"), !url.absoluteString.lowercased().contains("%00"),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeRegular || type == .typeDirectory else { throw FinderHandoffError.invalidRequest }
            normalized.append(url.standardizedFileURL)
        }
        guard Set(normalized).count == normalized.count,
              let parent = normalized.first?.deletingLastPathComponent(),
              normalized.allSatisfy({ $0.deletingLastPathComponent() == parent }) else { throw FinderHandoffError.invalidRequest }
        return normalized
    }
    public static func selection(_ urls: [URL], within home: URL) -> [URL]? {
        guard let sources = try? validate(urls), home.isFileURL else { return nil }
        let root = home.resolvingSymlinksInPath().pathComponents
        guard root.count > 1, sources.allSatisfy({
            let path = $0.resolvingSymlinksInPath().pathComponents
            return path.count > root.count && Array(path.prefix(root.count)) == root
        }) else { return nil }
        // Bound the final URL too, so huge selections fail visibly before launch.
        guard let request = try? CreationHandoff(command: .zip, sources: sources),
              request.url.absoluteString.utf8.count <= 32_768 else { return nil }
        return sources
    }
    public static func baseName(for sources: [URL]) -> String {
        guard let first = sources.first else { return "Archive" }
        let directory = (try? FileManager.default.attributesOfItem(atPath: first.path)[.type] as? FileAttributeType) == .typeDirectory
        let raw = sources.count == 1 ? (directory ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent) : first.deletingLastPathComponent().lastPathComponent
        // Reuse the established filename sanitizer (expects a four-byte suffix).
        return FinderHandoff.folderName(for: URL(fileURLWithPath: raw + ".zip"))
    }
}
