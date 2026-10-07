import Foundation

public struct ArchiveEntry: Equatable, Sendable {
    public enum Kind: Sendable { case file, directory, unsupported }
    public let id: Int64
    public let path: String
    public let size: Int64
    public let kind: Kind
    public init(id: Int64, path: String, size: Int64, kind: Kind) {
        self.id = id; self.path = path; self.size = size; self.kind = kind
    }
}
public struct BrowserRow: Sendable {
    public let path: String
    public let name: String
    public let size: Int64?
    public let isDirectory: Bool
}
public struct ArchiveIndex: Sendable {
    private let entries: [ArchiveEntry]
    private let rows: [String: BrowserRow]
    private let folders: [String: [BrowserRow]]
    public init(entries: [ArchiveEntry]) {
        self.entries = entries
        var rows: [String: BrowserRow] = [:]
        for entry in entries {
            let parts = entry.path.split(separator: "/").map(String.init)
            for end in 1...max(1, parts.count) {
                guard !parts.isEmpty else { break }
                let path = parts.prefix(end).joined(separator: "/")
                let directory = end < parts.count || entry.kind == .directory
                if rows[path] == nil || !directory {
                    rows[path] = BrowserRow(path: path, name: parts[end - 1],
                        size: directory ? nil : entry.size, isDirectory: directory)
                }
            }
        }
        self.rows = rows
        var folders: [String: [BrowserRow]] = [:]
        for row in rows.values {
            let parent = row.path.split(separator: "/").dropLast().joined(separator: "/")
            folders[parent, default: []].append(row)
        }
        self.folders = folders.mapValues { $0.sorted(by: Self.order) }
    }
    private static func order(_ lhs: BrowserRow, _ rhs: BrowserRow) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.path < rhs.path
    }
    public func children(of path: String) -> [BrowserRow] { folders[path] ?? [] }
    public func entryIDs(for paths: Set<String>) -> [Int64] {
        entries.filter { entry in
            let path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return paths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }.map(\.id).sorted()
    }
    public func search(_ query: String) -> [BrowserRow] {
        rows.values.filter { $0.path.localizedCaseInsensitiveContains(query) }.sorted(by: Self.order)
    }
}
