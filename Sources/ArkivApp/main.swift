import AppKit
import ArkivCore
import ArkivPresentation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        if windows.isEmpty { newWindow(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func newWindow(_ sender: Any?) { makeWindow().showWindow(nil) }
    private func makeWindow() -> BrowserWindowController {
        let controller = BrowserWindowController()
        windows.append(controller)
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        controller.onOpen = { [weak self, weak controller] in self?.openArchive(controller) }
        return controller
    }
    @objc func openArchive(_ sender: Any?) {
        let preferred = (sender as? BrowserWindowController)?.windowID
            ?? windows.first(where: { $0.window === NSApp.keyWindow })?.windowID
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Open an archive to browse its contents."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { open(url, preferred: preferred) }
    }
    private func open(_ url: URL, preferred: UUID? = nil) {
        let preferred = preferred ?? windows.first(where: { $0.window === NSApp.keyWindow })?.windowID
        let id = BrowserPresentation.window(for: url, preferred: preferred, among: windows.map(\.routingState))
        let controller = windows.first(where: { $0.windowID == id }) ?? makeWindow()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if controller.archiveURL == nil { controller.load(url) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let controller = windows.last { controller.showWindow(nil) }
            else { newWindow(nil) }
        }
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if windows.contains(where: \.isBusy) {
            let alert = NSAlert()
            alert.messageText = "An archive operation is still running"
            alert.informativeText = "Cancel it and wait for cleanup before quitting."
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    private func buildMenus() {
        let main = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "About Arkiv", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Hide Arkiv", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(withTitle: "Quit Arkiv", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File")
        let new = file.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n"); new.target = self
        let open = file.addItem(withTitle: "Open Archive…", action: #selector(openArchive(_:)), keyEquivalent: "o"); open.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Extract Selected…", action: #selector(BrowserWindowController.extractSelected(_:)), keyEquivalent: "e")
        file.addItem(withTitle: "Extract All…", action: #selector(BrowserWindowController.extractAll(_:)), keyEquivalent: "E")
        file.addItem(withTitle: "Archive Info", action: #selector(BrowserWindowController.showInfo(_:)), keyEquivalent: "i")
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Find", action: #selector(BrowserWindowController.focusSearch(_:)), keyEquivalent: "f")
        let go = NSMenu(title: "Go")
        go.addItem(withTitle: "Back", action: #selector(BrowserWindowController.goBack(_:)), keyEquivalent: "[")
        go.addItem(withTitle: "Forward", action: #selector(BrowserWindowController.goForward(_:)), keyEquivalent: "]")
        go.addItem(withTitle: "Parent Folder", action: #selector(BrowserWindowController.goUp(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        for (title, menu) in [("Arkiv", application), ("File", file), ("Edit", edit), ("Go", go), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu; main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

NSWindow.allowsAutomaticWindowTabbing = false
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
