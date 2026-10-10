import Foundation
import CArkiv
import ArkivFinderIntegration

public enum FinderAction: String, CaseIterable, Sendable {
    case open, extractHere, extractFolder, extractTo
}

public struct FinderRequest: Sendable {
    public let action: FinderAction
    public let archive: URL
    public init(action: FinderAction, urls: [URL]) throws {
        guard urls.count == 1 else { throw ArchiveFailure.message("Select exactly one ZIP, 7z, or TAR archive for Arkiv's Finder actions.") }
        let url = urls[0]
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil,
              ["zip", "7z", "tar"].contains(url.lastPathComponent.split(separator: ".").last?.lowercased() ?? "") else {
            throw ArchiveFailure.message("Finder actions support local ZIP, 7z, and uncompressed TAR files only.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ArchiveFailure.message("Select a regular archive file, not a folder or symbolic link.")
        }
        self.action = action; archive = url.standardizedFileURL
    }
    public var parent: URL { archive.deletingLastPathComponent() }
    public var folderName: String { FinderHandoff.folderName(for: archive) }
}

public struct FinderExtractionFailure: Error, LocalizedError {
    public let recoveryURL: URL
    public let publishedCount: Int
    public let reason: String
    public var errorDescription: String? {
        "\(reason) Nothing was overwritten. \(publishedCount) top-level items were placed in the destination. Remaining extracted files are in \(recoveryURL.path)."
    }
}

/// Finder is only a routing surface. The same engine performs all inspection and extraction.
public struct FinderExtractor {
    private let engine = LibArchiveEngine()
    public init() {}
    public func extract(_ request: FinderRequest, destination: URL? = nil, password: String? = nil,
                        cancellation: ArchiveCancellation,
                        progress: @escaping @Sendable (ArchiveProgress) -> Void) throws -> URL {
        guard request.action != .open else { throw ArchiveFailure.message("Open requests must go to the archive browser.") }
        let parent: URL
        if request.action == .extractTo {
            guard let destination, destination.isFileURL else { throw ArchiveFailure.message("Choose a destination folder.") }
            parent = destination
        } else { parent = request.parent }
        let snapshot = try engine.inspect(request.archive, cancellation: cancellation, password: password)
        let staging = try engine.extract(snapshot, ids: nil, into: parent, cancellation: cancellation, progress: progress)
        for attempt in 1...1000 {
            let name = request.folderName + (attempt == 1 ? "" : " (\(attempt))")
            var error = [CChar](repeating: 0, count: 256)
            var published = 0
            let here = request.action == .extractHere
            let result = arkiv_publish_extracted(parent.path, staging.lastPathComponent, name,
                here ? 1 : 0, cancellation.pointer, &published, &error, error.count)
            if result == 0 {
                return here ? parent : parent.appendingPathComponent(name, isDirectory: true)
            }
            if result == 3 && !here { continue }
            if result == 2 && published == 0 {
                try? FileManager.default.removeItem(at: staging)
                throw ArchiveFailure.cancelled
            }
            throw FinderExtractionFailure(recoveryURL: staging, publishedCount: published,
                reason: result == 2 ? "Extraction was cancelled during placement." : String(cString: error))
        }
        throw FinderExtractionFailure(recoveryURL: staging, publishedCount: 0,
            reason: "No unused archive folder name was available.")
    }
}
