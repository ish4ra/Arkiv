import AppKit
import FinderSync
import Darwin
import ArkivFinderIntegration

@objc
final class ArkivFinderSync: FIFinderSync {
    private let home: URL?

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
        guard menuKind == .contextualMenuForItems, let home,
              let archive = FinderHandoff.selection(FIFinderSyncController.default().selectedItemURLs() ?? [], within: home) else { return nil }
        let menu = NSMenu()
        let parent = NSMenuItem(title: "Arkiv", action: nil, keyEquivalent: "")
        let actions = NSMenu(title: "Arkiv")
        let titles = ["Open in Arkiv", "Extract Here", "Extract to “\(FinderHandoff.folderName(for: archive))/”", "Extract To…"]
        for (command, title) in zip(FinderCommand.allCases, titles) {
            let item = actions.addItem(withTitle: title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            // Snapshot the clicked menu's selection; do not re-read a later selection.
            item.representedObject = try? FinderHandoff(command: command, archive: archive).url
        }
        parent.submenu = actions; menu.addItem(parent)
        return menu
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let request = try? FinderHandoff(url: url), let home,
              FinderHandoff.selection([request.archive], within: home) != nil else { return }
        // Target our enclosing app explicitly rather than trusting scheme ownership.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app",
              Bundle(url: app)?.bundleIdentifier == "xyz.isharalakshan.arkiv" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            if error != nil { NSLog("Arkiv could not open its containing application. Use Arkiv Services as a fallback.") }
        }
    }
}
