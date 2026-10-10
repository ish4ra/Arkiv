import AppKit
import FinderSync
import Darwin
import ArkivFinderIntegration

@objc
final class ArkivFinderSync: FIFinderSync {
    private let home: URL?
    private lazy var relay = FinderActionRelay(home: home,
        extensionURL: Bundle(for: ArkivFinderSync.self).bundleURL,
        transport: { url, app, completion in
            let configuration = NSWorkspace.OpenConfiguration()
            let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "command" }?.value
            configuration.activates = ["open", "extractTo", "addArchive", "password"].contains(command ?? "")
            configuration.arguments = ["--finder-action"]
            configuration.addsToRecentItems = false
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { application, error in
                if let error { completion(error) }
                else if application == nil {
                    completion(NSError(domain: "ArkivFinderHandoff", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "macOS did not return a running Arkiv application."]))
                } else { completion(nil) }
            }
        }, failure: { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Couldn’t send the Finder action to Arkiv"
                let detail = error as NSError
                alert.informativeText = "\(error.localizedDescription)\n\nOpen Arkiv manually to create or extract an archive. Finder → Services also provides extraction actions.\n\nDiagnostic: \(detail.domain) (\(detail.code))"
                alert.addButton(withTitle: "OK")
                alert.window.level = .floating
                alert.window.center()
                alert.window.orderFrontRegardless()
                alert.runModal()
            }
        })

    override init() {
        // NSHomeDirectory in a sandbox points to its container, not the user's home.
        // getpwuid is the public POSIX account API. No filesystem enumeration occurs.
        if let path = getpwuid(getuid())?.pointee.pw_dir {
            let url = URL(fileURLWithPath: String(cString: path), isDirectory: true)
            home = url.pathComponents.count > 1 ? url : nil
        } else { home = nil }
        super.init()
        FIFinderSyncController.default().directoryURLs = home.map { Set([$0]) } ?? []
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, let home else { return nil }
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let archive = FinderHandoff.selection(selected, within: home)
        let sources = CreationHandoff.selection(selected, within: home)
        guard archive != nil || sources != nil else { return nil }
        let menu = NSMenu()
        let parent = NSMenuItem(title: "Arkiv", action: nil, keyEquivalent: "")
        let actions = NSMenu(title: "Arkiv")
        actions.autoenablesItems = false
        if let archive {
            let titles = ["Open in Arkiv", "Extract Here", "Extract to “\(FinderHandoff.folderName(for: archive))/”", "Extract To…"]
            for (command, title) in zip(FinderCommand.allCases, titles) {
                let item = actions.addItem(withTitle: title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self; item.tag = command.menuTag
            }
        } else if let sources {
            for (command, title) in [(CreationCommand.addArchive, "Add to Archive…"),
                                     (.zip, "Compress to “\(CreationHandoff.baseName(for: sources)).zip”"),
                                     (.sevenZip, "Compress to “\(CreationHandoff.baseName(for: sources)).7z”"),
                                     (.password, "Compress with Password…")] {
                let item = actions.addItem(withTitle: title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self; item.tag = command.menuTag
            }
        }
        parent.submenu = actions; menu.addItem(parent)
        return menu
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        // Apple documents selectedItemURLs as valid inside an action callback.
        // Resolve it now, then pass a value snapshot through asynchronous delivery.
        relay.perform(tag: sender.tag,
                      selectedURLs: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }
}
