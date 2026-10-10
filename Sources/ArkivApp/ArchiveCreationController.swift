import AppKit
import ArkivCore
import ArkivFinderIntegration

/// Owns creation UI/operation lifetime; all archive work is delegated to Core.
final class ArchiveCreationController {
    private(set) var isBusy = false
    private var setup: CreateArchiveSheet?
    private var operation: FinderOperationWindow?
    private let worker = DispatchQueue(label: "xyz.isharalakshan.arkiv.create", qos: .userInitiated)

    func present(_ sources: [URL], parent: NSWindow?, encrypted: Bool = false) {
        guard !isBusy else { NSAlert(error: ArchiveFailure.message("An archive is already being created. Wait or cancel it first.")).runModal(); return }
        if let setup { setup.window?.makeKeyAndOrderFront(nil); return }
        let sheet = CreateArchiveSheet(sources: sources, encrypted: encrypted)
        setup = sheet
        sheet.complete = { [weak self] destination, name, compression, format, password, encryptFilenames in
            guard let self else { return }
            self.setup = nil
            guard let destination else { return }
            do { try self.compress(sources, destination: destination, name: name, compression: compression, format: format, password: password, encryptFilenames: encryptFilenames) }
            catch { NSAlert(error: error).runModal() }
        }
        sheet.present(parent: parent)
    }

    func compress(_ sources: [URL], destination: URL? = nil, name: String? = nil, compression: ZIPCompression = .deflate, format: ArchiveFormat = .zip, password: String? = nil, encryptFilenames: Bool = true) throws {
        guard !isBusy else { throw ArchiveFailure.message("An archive is already being created. Wait or cancel it first.") }
        guard let first = sources.first else { throw ArchiveFailure.message("Select files or folders to compress.") }
        let destination = destination ?? first.deletingLastPathComponent()
        let name = name ?? CreationHandoff.baseName(for: sources)
        let request = ArchiveCreationRequest(sources: sources, destination: destination, name: name, compression: compression, format: format, password: password, encryptFilenames: encryptFilenames)
        isBusy = true
        let operation = FinderOperationWindow(archive: destination.appendingPathComponent(name + (format == .sevenZip ? ".7z" : ".zip")), verb: "Compressing")
        self.operation = operation
        operation.showWindow(nil) // nonactivating panel: Finder retains focus
        let cancellation = operation.cancellation
        worker.async { [self] in
            // ProgressReceiver invokes its closure serially on this worker.
            let throttle = CreationProgressThrottle()
            let result = Result {
                try ArchiveCreator().create(request, cancellation: cancellation) { progress in
                    guard throttle.shouldUpdate() else { return }
                    DispatchQueue.main.async { [weak operation] in operation?.showProgress(progress) }
                }
            }
            DispatchQueue.main.async { [self] in
                isBusy = false
                operation.finish(); operation.close(); self.operation = nil
                ExtractionFeedback.completed(result)
                if case .failure(let error) = result {
                    if case ArchiveFailure.cancelled = error { return }
                    NSApp.activate(ignoringOtherApps: true)
                    NSAlert(error: error).runModal()
                }
                // No reveal, browser opening, or activation after successful creation.
            }
        }
    }
}

private final class CreationProgressThrottle: @unchecked Sendable {
    private var last = Date.distantPast
    func shouldUpdate() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return false }
        last = now; return true
    }
}

private final class CreateArchiveSheet: NSWindowController, NSWindowDelegate {
    var complete: ((URL?, String, ZIPCompression, ArchiveFormat, String?, Bool) -> Void)?
    private let name = NSTextField(string: "")
    private let location = NSTextField(labelWithString: "")
    private let compression = NSPopUpButton()
    private let format = NSPopUpButton()
    private let encryption = NSButton(checkboxWithTitle: "Protect with AES-256 password", target: nil, action: nil)
    private let passwords = PasswordEntryView(confirm: true)
    private let filenames = NSButton(checkboxWithTitle: "Encrypt filenames", target: nil, action: nil)
    private let encryptionNote = NSTextField(wrappingLabelWithString: "ZIP encryption is unavailable. Choose 7z for AES-256.")
    private var selectedFormat: ArchiveFormat { format.indexOfSelectedItem == 1 ? .sevenZip : .zip }
    private var destination: URL
    private var finished = false

    init(sources: [URL], encrypted: Bool) {
        destination = sources.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 340),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Create Archive"; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.tabbingMode = .disallowed; panel.center()
        name.stringValue = CreationHandoff.baseName(for: sources)
        name.setAccessibilityLabel("Archive name")
        location.stringValue = destination.path; location.lineBreakMode = .byTruncatingMiddle
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        compression.addItems(withTitles: ["Deflate — Normal", "Store — No compression"])
        compression.setAccessibilityLabel("Compression")
        format.addItems(withTitles: ["ZIP (.zip)", "7z (.7z)"])
        format.setAccessibilityLabel("Archive format")
        format.target = self; format.action = #selector(changeFormat)
        encryption.target = self; encryption.action = #selector(changeEncryption)
        filenames.state = .on
        encryptionNote.textColor = .secondaryLabelColor
        let passwordSection = NSStackView(views: [encryption, passwords, filenames, encryptionNote])
        passwordSection.orientation = .vertical; passwordSection.alignment = .leading; passwordSection.spacing = 8
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDestination))
        let destinationRow = NSStackView(views: [location, choose]); destinationRow.spacing = 8
        let selection = NSTextField(wrappingLabelWithString: sources.prefix(5).map(\.lastPathComponent).joined(separator: ", ") + (sources.count > 5 ? " … (\(sources.count) items)" : ""))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Items:"), selection],
            [NSTextField(labelWithString: "Name:"), name],
            [NSTextField(labelWithString: "Destination:"), destinationRow],
            [NSTextField(labelWithString: "Format:"), format],
            [NSTextField(labelWithString: "Compression:"), compression],
            [NSTextField(labelWithString: "Encryption:"), passwordSection]
        ])
        grid.rowSpacing = 12; grid.columnSpacing = 12
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelCreate)); cancel.keyEquivalent = "\u{1b}"
        let create = NSButton(title: "Create", target: self, action: #selector(createArchive)); create.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, create]); buttons.spacing = 8
        let hint = NSTextField(wrappingLabelWithString: "Existing files are never replaced. A numbered name is used if needed.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let content = NSStackView(views: [grid, hint, buttons]); content.orientation = .vertical
        content.alignment = .trailing; content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = content
        content.widthAnchor.constraint(equalToConstant: 510).isActive = true
        grid.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
        format.selectItem(at: encrypted ? 1 : 0)
        encryption.state = encrypted ? .on : .off
        changeFormat()
        panel.setContentSize(content.fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func present(parent: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if let parent { parent.beginSheet(window) }
        else { showWindow(nil); window.makeKeyAndOrderFront(nil) }
        window.makeFirstResponder(name)
    }
    @objc private func changeFormat() {
        compression.removeAllItems()
        compression.addItems(withTitles: selectedFormat == .sevenZip ? ["LZMA2 — Normal"] : ["Deflate — Normal", "Store — No compression"])
        encryption.isEnabled = selectedFormat == .sevenZip
        encryptionNote.isHidden = selectedFormat == .sevenZip
        if selectedFormat == .zip { encryption.state = .off; passwords.clear() }
        changeEncryption()
    }
    @objc private func changeEncryption() {
        let enabled = selectedFormat == .sevenZip && encryption.state == .on
        passwords.isHidden = !enabled; filenames.isHidden = !enabled
        if !enabled { passwords.clear() }
        window?.contentView?.layoutSubtreeIfNeeded()
        if let content = window?.contentView { window?.setContentSize(content.fittingSize) }
    }
    @objc private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { destination = url; location.stringValue = url.path }
    }
    @objc private func createArchive() {
        var value = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".zip") { value = String(value.dropLast(4)) }
        else if value.lowercased().hasSuffix(".7z") { value = String(value.dropLast(3)) }
        guard !value.isEmpty, value != ".", value != "..", !value.unicodeScalars.contains(where: { $0.value < 32 || "/\\:".unicodeScalars.contains($0) }), value.utf8.count <= 180 else {
            NSAlert(error: ArchiveFailure.message("Enter an archive name without colons, path separators or control characters (up to 180 UTF-8 bytes).")).runModal(); return
        }
        let password: String?
        do {
            password = encryption.state == .on ? try CreationPasswordPolicy.validate(passwords.value, confirmation: passwords.confirmedValue) : nil
        } catch { NSAlert(error: error).runModal(); return }
        finish(destination, value, compression.indexOfSelectedItem == 1 ? .store : .deflate, password: password)
    }
    @objc private func cancelCreate() { finish(nil, "", .deflate) }
    private func finish(_ destination: URL?, _ name: String, _ compression: ZIPCompression, password: String? = nil) {
        guard !finished else { return }; finished = true
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        passwords.clear()
        close(); complete?(destination, name, compression, selectedFormat, password, filenames.state == .on)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelCreate(); return false }
}
