import AppKit
import Quartz

/// Presentation is injectable: browser tests never create a system preview panel.
protocol ArchiveQuickLookPresenting: AnyObject {
    var isPresented: Bool { get }
    func present(_ url: URL, owner: NSWindowController) -> Bool
    func close()
    func acceptsControl() -> Bool
    func beginControl(_ panel: QLPreviewPanel)
    func endControl(_ panel: QLPreviewPanel)
}

final class ArchiveQuickLook: NSObject, ArchiveQuickLookPresenting, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private static weak var active: ArchiveQuickLook?
    private weak var owner: NSWindowController?
    private weak var panel: QLPreviewPanel?
    private var url: URL?
    var isPresented: Bool { url != nil && panel?.isVisible == true }

    func present(_ url: URL, owner: NSWindowController) -> Bool {
        Self.active?.close()
        self.owner = owner
        self.url = url
        Self.active = self
        guard let panel = QLPreviewPanel.shared() else { close(); return false }
        panel.updateController()
        guard panel.currentController as AnyObject? === owner else { close(); return false }
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }
    func acceptsControl() -> Bool { Self.active === self && url != nil }
    func beginControl(_ panel: QLPreviewPanel) {
        guard acceptsControl() else { return }
        self.panel = panel
        panel.dataSource = self
        panel.delegate = self
    }
    func endControl(_ panel: QLPreviewPanel) {
        // A late relinquish from another window must never clear its new owner.
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate as AnyObject? === self { panel.delegate = nil }
        self.panel = nil
        url = nil
        owner = nil
        if Self.active === self { Self.active = nil }
    }
    func close() {
        if let panel, panel.currentController as AnyObject? === owner {
            panel.orderOut(nil)
            endControl(panel)
            panel.updateController()
        } else {
            url = nil; owner = nil; panel = nil
            if Self.active === self { Self.active = nil }
        }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index == 0, let url else { return nil }
        return url as NSURL
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, ArchiveTableView.isPreviewDismissKey(event) else { return false }
        if !event.isARepeat { close() }
        return true
    }
}
