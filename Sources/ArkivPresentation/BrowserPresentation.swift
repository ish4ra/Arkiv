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
    /// Presentation only: packages remain directories for selection and extraction.
    public static func packageKind(_ row: BrowserRow) -> String? {
        guard row.isDirectory else { return nil }
        switch (row.name as NSString).pathExtension.lowercased() {
        case "app": return "Application"
        case "framework": return "Framework"
        case "bundle": return "Bundle"
        case "plugin": return "Plug-in"
        case "appex": return "App Extension"
        case "xpc": return "XPC Service"
        default: return nil
        }
    }
    public static func navigationPath(_ row: BrowserRow, showPackageContents: Bool = false) -> String? {
        guard row.isDirectory, packageKind(row) == nil || showPackageContents else { return nil }
        return row.path
    }

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
    public static func metadataText(_ row: BrowserRow, column: String) -> String {
        switch column {
        case "packed": return row.metadata.packedSize.map { ByteCountFormatter.string(fromByteCount:Int64(clamping:$0),countStyle:.file) } ?? ""
        case "ratio": return row.ratio.map { String(format:"%.1f%%",$0*100) } ?? ""
        case "modified": return row.metadata.modificationTime.map { DateFormatter.localizedString(from:$0,dateStyle:.medium,timeStyle:.short) } ?? ""
        case "method": return row.metadata.compressionMethod ?? ""
        case "encrypted": return row.metadata.encrypted.map { $0 ? "Yes" : "No" } ?? ""
        default: return ""
        }
    }
    private static func optionalCompare<T: Comparable>(_ a:T?, _ b:T?) -> ComparisonResult {
        switch (a,b) {
        case (nil,nil): return .orderedSame
        case (nil,_): return .orderedAscending
        case (_,nil): return .orderedDescending
        case (.some(let a),.some(let b)): return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        }
    }
    public static func sorted(_ rows: [BrowserRow], by key: String, ascending: Bool) -> [BrowserRow] {
        rows.sorted { lhs, rhs in
            if ["name","packed","ratio","modified","method","encrypted"].contains(key), lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            var comparison: ComparisonResult
            switch key {
            case "packed": comparison = optionalCompare(lhs.metadata.packedSize,rhs.metadata.packedSize)
            case "ratio": comparison = optionalCompare(lhs.ratio,rhs.ratio)
            case "modified": comparison = optionalCompare(lhs.metadata.modificationTime,rhs.metadata.modificationTime)
            case "method": comparison = optionalCompare(lhs.metadata.compressionMethod,rhs.metadata.compressionMethod)
            case "encrypted": comparison = optionalCompare(lhs.metadata.encrypted.map { $0 ? 1 : 0 },rhs.metadata.encrypted.map { $0 ? 1 : 0 })
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
