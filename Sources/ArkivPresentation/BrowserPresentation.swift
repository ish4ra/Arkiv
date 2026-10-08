import Foundation
import ArkivCore

public struct ArchiveWindowState {
    public let id: UUID
    public let archiveURL: URL?
    public let isAvailable: Bool
    public init(id: UUID, archiveURL: URL?, isAvailable: Bool) {
        self.id = id; self.archiveURL = archiveURL; self.isAvailable = isAvailable
    }
}

public enum BrowserPresentation {
    public static func window(for url: URL, preferred: UUID?, among windows: [ArchiveWindowState]) -> UUID? {
        let normalized = url.standardizedFileURL
        if let existing = windows.first(where: { $0.archiveURL?.standardizedFileURL == normalized }) {
            return existing.id
        }
        let empty = windows.filter { $0.archiveURL == nil && $0.isAvailable }
        return empty.first(where: { $0.id == preferred })?.id ?? empty.first?.id
    }
    public static func selection(_ paths: Set<String>, in rows: [BrowserRow]) -> IndexSet {
        IndexSet(rows.indices.filter { paths.contains(rows[$0].path) })
    }
    // A folder's recursive size is not part of the browser model. Do not imply it is zero.
    public static func selectedSize(_ rows: [BrowserRow]) -> Int64? {
        guard !rows.isEmpty else { return nil }
        var total: Int64 = 0
        for row in rows {
            guard let size = row.size, size >= 0 else { return nil }
            let sum = total.addingReportingOverflow(size)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }
    public static func sorted(_ rows: [BrowserRow], by key: String, ascending: Bool) -> [BrowserRow] {
        rows.sorted { lhs, rhs in
            if key == "name", lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            var comparison: ComparisonResult
            switch key {
            case "size":
                let left = lhs.size ?? -1, right = rhs.size ?? -1
                comparison = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
            case "type" where lhs.isDirectory != rhs.isDirectory:
                comparison = lhs.isDirectory ? .orderedAscending : .orderedDescending
            default: comparison = lhs.name.localizedStandardCompare(rhs.name)
            }
            if comparison == .orderedSame { comparison = lhs.path.localizedStandardCompare(rhs.path) }
            if comparison == .orderedSame { comparison = lhs.path.compare(rhs.path) }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
