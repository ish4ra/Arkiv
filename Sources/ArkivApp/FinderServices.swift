import AppKit
import ArkivCore
import ArkivFinderIntegration

/// One main-app routing/operation owner shared by Services and Finder Sync.
/// Services and validated URL handoffs share the same safe extractor.
final class FinderServiceProvider: NSObject {
    private let openArchive: (URL) -> Void
    private(set) var isBusy = false
    private var operation: FinderOperationWindow?
    private let worker = DispatchQueue(label: "xyz.isharalakshan.arkiv.finder", qos: .userInitiated)
    init(openArchive: @escaping (URL) -> Void) { self.openArchive = openArchive }

    static func request(from pasteboard: NSPasteboard, userData: String?) throws -> FinderRequest {
        guard let value = userData, let action = FinderAction(rawValue: value) else {
            throw ArchiveFailure.message("Unknown Arkiv Finder action.")
        }
        let urls: [URL]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [:]), !objects.isEmpty {
            urls = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
            guard urls.count == objects.count, pasteboard.pasteboardItems?.count == objects.count else { throw ArchiveFailure.message("Invalid Finder selection.") }
        } else if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            guard paths.allSatisfy({ $0.hasPrefix("/") }) else { throw ArchiveFailure.message("Finder paths must be absolute.") }
            urls = paths.map { URL(fileURLWithPath: $0) }
        } else { throw ArchiveFailure.message("Select one ZIP or TAR file in Finder.") }
        return try FinderRequest(action: action, urls: urls)
    }

    @objc func performFinderAction(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        // AppKit invokes Services selectors on the application's main thread.
        guard Thread.isMainThread else { error.pointee = "Arkiv could not receive this Finder request."; return }
        do {
            let request = try Self.request(from: pasteboard, userData: userData)
            try perform(request)
        } catch let failure { error.pointee = failure.localizedDescription as NSString }
    }

    /// No engine work or writes happen until the main app has validated the request.
    func perform(_ request: FinderRequest) throws {
        guard Thread.isMainThread else { throw FinderHandoffError.invalidRequest }
        if request.action == .open {
            NSApp.activate(ignoringOtherApps: true)
            openArchive(request.archive)
            return
        }
        guard !isBusy else { throw ArchiveFailure.message("Arkiv is already handling a Finder extraction. Wait or cancel it before starting another.") }
        isBusy = true
        DispatchQueue.main.async { [self] in self.start(request) }
    }

    /// The development channel intentionally accepts allowlisted URL actions
    /// without sender authentication. Parsing and source validation still apply.
    /// A routing sink supports read-only packaged diagnostics without extraction.
    func receive(_ url: URL, dispatch: ((FinderRequest) throws -> Void)? = nil) throws {
        let handoff = try FinderHandoff(url: url)
        guard let action = FinderAction(rawValue: handoff.command.rawValue) else { throw FinderHandoffError.invalidRequest }
        let request = try FinderRequest(action: action, urls: [handoff.archive])
        if let dispatch { try dispatch(request) }
        else { try perform(FinderRequest(action: action, urls: [handoff.archive])) }
    }

    /// Nearby extractions appear naturally in the existing Finder directory.
    /// Only an explicitly chosen destination warrants a success reveal.
    static func showExtractionResult(_ output: URL, action: FinderAction,
                                     reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }) {
        guard action == .extractTo else { return }
        reveal([output])
    }

    static func requiresDestinationSelection(_ action: FinderAction) -> Bool { action == .extractTo }

    private func start(_ request: FinderRequest) {
        NSApp.activate(ignoringOtherApps: true)
        var destination: URL?
        if Self.requiresDestinationSelection(request.action) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
            panel.prompt = "Extract"
            panel.message = "Create a separate folder for \(request.archive.lastPathComponent). Existing items are never replaced."
            guard panel.runModal() == .OK, let url = panel.url else { isBusy = false; return }
            destination = url
        }
        let operation = FinderOperationWindow(archive: request.archive)
        self.operation = operation
        operation.showWindow(nil)
        let token = operation.cancellation
        let parent = destination
        worker.async { [self] in
            // The callback is serial on this worker; throttle updates without touching AppKit here.
            let throttle = FinderProgressThrottle()
            let result = Result {
                try FinderExtractor().extract(request, destination: parent, cancellation: token) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak operation] in
                        operation?.showProgress(progress)
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                self.isBusy = false
                operation.finish(); operation.close(); self.operation = nil
                ExtractionFeedback.completed(result)
                switch result {
                case .success(let output): Self.showExtractionResult(output, action: request.action)
                case .failure(let failure):
                    if case ArchiveFailure.cancelled = failure { return }
                    if let recovery = failure as? FinderExtractionFailure {
                        let alert = NSAlert()
                        alert.messageText = "Finder extraction stopped"
                        alert.informativeText = recovery.localizedDescription
                        alert.addButton(withTitle: "OK")
                        alert.addButton(withTitle: "Show Extracted Files")
                        if alert.runModal() == .alertSecondButtonReturn {
                            NSWorkspace.shared.activateFileViewerSelecting([recovery.recoveryURL])
                        }
                    } else { NSAlert(error: failure).runModal() }
                }
            }
        }
    }
}

private final class FinderProgressThrottle: @unchecked Sendable {
    private var last = Date.distantPast
    func shouldUpdate() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return false }
        last = now; return true
    }
}

private final class FinderOperationWindow: NSWindowController, NSWindowDelegate {
    let cancellation = ArchiveCancellation()
    private var running = true
    private var cancelling = false
    private let status = NSTextField(labelWithString: "Validating and extracting…")
    init(archive: URL) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 140),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Arkiv — Extracting"
        window.tabbingMode = .disallowed; window.isReleasedWhenClosed = false
        window.delegate = self; window.center()
        let name = NSTextField(labelWithString: archive.lastPathComponent)
        name.font = .systemFont(ofSize: 13, weight: .semibold); name.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .small
        spinner.startAnimation(nil)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelOperation(_:)))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let footer = NSStackView(views: [spinner, status, cancel]); footer.spacing = 10
        let content = NSStackView(views: [name, footer]); content.orientation = .vertical
        content.alignment = .leading; content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = content
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func cancelOperation(_ sender: Any?) { cancelling = true; cancellation.cancel(); status.stringValue = "Cancelling…" }
    func showProgress(_ progress: ArchiveProgress) {
        guard running && !cancelling else { return }
        status.stringValue = "\(progress.files) entries · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .file))"
    }
    func finish() { running = false }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if running { cancelOperation(nil); return false }
        return true
    }
}
