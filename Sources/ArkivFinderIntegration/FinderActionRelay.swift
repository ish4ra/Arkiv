import Foundation

extension FinderCommand {
    /// Scalar menu tags survive Finder's menu transport; representedObject is not IPC.
    public var menuTag: Int {
        switch self {
        case .open: return 1
        case .extractHere: return 2
        case .extractFolder: return 3
        case .extractTo: return 4
        }
    }

    public init?(menuTag: Int) {
        guard let command = Self.allCases.first(where: { $0.menuTag == menuTag }) else { return nil }
        self = command
    }
}

public enum FinderRelayError: Error, LocalizedError {
    case unknownAction, unavailableSelection, containingApp
    public var errorDescription: String? {
        switch self {
        case .unknownAction: return "Finder returned an unrecognized Arkiv action."
        case .unavailableSelection: return "Arkiv could not read the selected archive. Select one ZIP or uncompressed TAR in your home folder and try again."
        case .containingApp: return "Arkiv could not locate its containing application. Make sure Arkiv is installed in Applications."
        }
    }
}

/// No filesystem writes, extraction, shell, default-scheme lookup or permissions.
/// Dependencies are injectable so lost menu payloads and every failure are tested.
public final class FinderActionRelay {
    public typealias Transport = (URL, URL, @escaping (Error?) -> Void) -> Void
    private let home: URL?
    private let extensionURL: URL
    private let identifier: (URL) throws -> String?
    private let transport: Transport
    private let failure: (Error) -> Void

    public init(home: URL?, extensionURL: URL,
                identifier: @escaping (URL) throws -> String? = { app in
                    // Explicit I/O preserves the real sandbox/read error instead of
                    // Bundle's nil result hiding why identity lookup failed.
                    let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                    let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                    return info?["CFBundleIdentifier"] as? String
                },
                transport: @escaping Transport, failure: @escaping (Error) -> Void) {
        self.home = home; self.extensionURL = extensionURL
        self.identifier = identifier; self.transport = transport; self.failure = failure
    }

    public static func containingApp(for extensionURL: URL) throws -> URL {
        let url = extensionURL.standardizedFileURL
        let plugins = url.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard url.isFileURL, url.pathExtension == "appex", plugins.lastPathComponent == "PlugIns",
              contents.lastPathComponent == "Contents", app.pathExtension == "app" else {
            throw FinderRelayError.containingApp
        }
        return app
    }

    public func perform(tag: Int, selectedURLs: [URL]) {
        do {
            guard let command = FinderCommand(menuTag: tag) else { throw FinderRelayError.unknownAction }
            guard let home, let archive = FinderHandoff.selection(selectedURLs, within: home) else {
                throw FinderRelayError.unavailableSelection
            }
            let request = try FinderHandoff(command: command, archive: archive)
            let app = try Self.containingApp(for: extensionURL)
            guard try identifier(app) == "xyz.isharalakshan.arkiv" else { throw FinderRelayError.containingApp }
            transport(request.url, app) { [failure] error in
                if let error { failure(error) }
            }
        } catch { failure(error) }
    }
}
