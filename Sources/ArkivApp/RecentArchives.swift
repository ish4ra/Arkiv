import AppKit

/// AppKit owns persistent recent-document storage; injected closures keep tests
/// away from the user's actual history. No archive or password data is stored here.
final class RecentArchives: NSObject, NSMenuDelegate {
    private let urls: () -> [URL]
    private let note: (URL) -> Void
    private let clear: () -> Void
    var open: ((URL) -> Void)?
    let menu = NSMenu(title:"Open Recent")
    init(urls: @escaping () -> [URL] = { NSDocumentController.shared.recentDocumentURLs },
         note: @escaping (URL) -> Void = { NSDocumentController.shared.noteNewRecentDocumentURL($0) },
         clear: @escaping () -> Void = { NSDocumentController.shared.clearRecentDocuments(nil) }) {
        self.urls = urls; self.note = note; self.clear = clear
        super.init(); menu.delegate = self
    }
    static func eligible(_ url: URL, nested: Bool) -> Bool {
        guard !nested, url.isFileURL, url.query == nil, url.fragment == nil, url.host == nil || url.host == "" || url.host == "localhost" else { return false }
        return !url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.contains {
            $0.hasPrefix("xyz.isharalakshan.arkiv.open-v1-") || $0.hasPrefix("arkiv-unlocked-") || $0.hasPrefix(".arkiv-")
        }
    }
    func accepted(_ url: URL, nested: Bool = false) {
        guard Self.eligible(url,nested:nested) else { return }
        note(url)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in urls() where Self.eligible(url,nested:false) {
            let item = menu.addItem(withTitle:url.lastPathComponent,action:#selector(openRecent(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = url; item.toolTip = url.path
        }
        if menu.items.isEmpty { let item = menu.addItem(withTitle:"No Recent Archives",action:nil,keyEquivalent:""); item.isEnabled = false }
        menu.addItem(.separator())
        let item = menu.addItem(withTitle:"Clear Menu",action:#selector(clearMenu(_:)),keyEquivalent:"")
        item.target = self
    }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, Self.eligible(url,nested:false) else { return }
        // Missing/unreadable files intentionally take the same validation/error path.
        open?(url)
    }
    @objc func clearMenu(_ sender: Any?) { clear(); menuNeedsUpdate(menu) }
}
