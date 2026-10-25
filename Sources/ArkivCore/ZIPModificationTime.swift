import Foundation
import CArkiv

/// A timestamp denotes [date, date + precision), not an exact instant.
public struct ZIPModificationTime: Equatable, Sendable {
    public enum Origin: Equatable, Sendable { case extendedUTC, dos(timeZone: String) }
    public let date: Date
    public let precision: TimeInterval
    public let origin: Origin

    static func dos(_ packed: UInt32, timeZone: TimeZone) -> ZIPModificationTime? {
        let time = packed & 0xffff, day = packed >> 16
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: Int(day >> 9) + 1980, month: Int((day >> 5) & 15),
                                        day: Int(day & 31), hour: Int(time >> 11),
                                        minute: Int((time >> 5) & 63), second: Int(time & 31) * 2)
        guard let tentative = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: tentative) == components else { return nil }
        // Strict matching rejects nonexistent spring-forward times; two distinct
        // matches mean a repeated autumn hour, not a unique canonical instant.
        let before = tentative.addingTimeInterval(-172800)
        guard let first = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last),
              first == last else { return nil }
        return ZIPModificationTime(date: first, precision: 2, origin: .dos(timeZone: timeZone.identifier))
    }
}

public enum ZIPReplaceOlderPolicy {
    public enum Decision: Equatable, Sendable { case replace, keep, ineligible }
    /// A decision is advisory only. A future transaction must revalidate the pinned
    /// local source and archive immediately before commit, even after `.replace`.
    public static func decide(archive: ZIPModificationTime?, localModificationTime: Date?,
                              localIsRegularFile: Bool) -> Decision {
        guard localIsRegularFile, let archive, let localModificationTime,
              localModificationTime.timeIntervalSince1970.isFinite else { return .ineligible }
        return localModificationTime >= archive.date.addingTimeInterval(archive.precision) ? .replace : .keep
    }
}

public struct ZIPMetadataReader: Sendable {
    public init() {}
    /// DOS has no zone. Callers must explicitly supply a known origin zone to use
    /// that fallback; the machine's current zone is never silently assumed.
    public func modificationTime(for path: String, in snapshot: ArchiveSnapshot,
                                 dosTimeZone: TimeZone? = nil) -> ZIPModificationTime? {
        guard snapshot.unlocked == nil,
              (try? SourceStamp(snapshot.url)) == snapshot.stamp,
              snapshot.entries.enumerated().allSatisfy({ $0.element.id == Int64($0.offset) }),
              snapshot.entries.filter({ $0.path == path && $0.kind == .file }).count == 1,
              let entry = snapshot.entries.first(where: { $0.path == path }),
              (try? ArchiveAdditionUpdater.validateSevenPaths(snapshot)) != nil else { return nil }
        let url = canonicalZIPSource(snapshot.url)
        var error = [CChar](repeating: 0, count: 256)
        guard let transaction = arkiv_zip_begin(url.path, &error, error.count) else { return nil }
        defer { arkiv_zip_end(transaction) }
        var value: Int64 = 0
        let kind = arkiv_zip_modification_time(transaction, Int(entry.id), snapshot.entries.count, path, &value)
        guard (try? SourceStamp(snapshot.url)) == snapshot.stamp else { return nil }
        if kind == 1 { return ZIPModificationTime(date: Date(timeIntervalSince1970: Double(value)), precision: 1, origin: .extendedUTC) }
        if kind == 2, let dosTimeZone { return .dos(UInt32(value), timeZone: dosTimeZone) }
        return nil
    }
}

/// Operation-local source identity/time for future update-by-date preparation.
/// Retains a no-follow regular-file descriptor, never a persisted authorization.
public final class ZIPUpdateSource {
    private let pin: OpaquePointer
    public let modificationTime: Date
    public init(_ url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil,
              let pin = arkiv_file_pin_begin(canonicalZIPSource(url).path) else {
            throw ArchiveFailure.message("Choose a local regular source file.")
        }
        var seconds: Int64 = 0, nanos: Int32 = 0
        guard arkiv_file_pin_mtime(pin, &seconds, &nanos) != 0 else {
            arkiv_file_pin_end(pin)
            throw ArchiveFailure.message("Source changed while reading its modification time.")
        }
        self.pin = pin
        modificationTime = Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000)
    }
    public func revalidate() throws {
        guard arkiv_file_pin_valid(pin) != 0 else { throw ArchiveFailure.message("Source identity or time changed. Prepare the update again.") }
    }
    deinit { arkiv_file_pin_end(pin) }
}

private func canonicalZIPSource(_ url: URL) -> URL {
    let url = url.standardizedFileURL
    #if os(macOS)
    if url.path.hasPrefix("/var/") || url.path.hasPrefix("/tmp/") { return URL(fileURLWithPath: "/private" + url.path) }
    #endif
    return url
}
