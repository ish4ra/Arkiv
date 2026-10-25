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
        sheet.complete = { [weak self] destination, name, preset, format, password, encryptFilenames, options in
            guard let self else { return }
            self.setup = nil
            guard let destination else { return }
            do { try self.compress(sources, destination: destination, name: name, format: format, password: password, encryptFilenames: encryptFilenames, preset: preset, sevenZipOptions: options) }
            catch { NSAlert(error: error).runModal() }
        }
        sheet.present(parent: parent)
    }

    func compress(_ sources: [URL], destination: URL? = nil, name: String? = nil, compression: ZIPCompression? = nil, format: ArchiveFormat = .zip, password: String? = nil, encryptFilenames: Bool = true, preset: CompressionPreset? = nil, sevenZipOptions: SevenZipCreationOptions? = nil) throws {
        guard !isBusy else { throw ArchiveFailure.message("An archive is already being created. Wait or cancel it first.") }
        guard let first = sources.first else { throw ArchiveFailure.message("Select files or folders to compress.") }
        let destination = destination ?? first.deletingLastPathComponent()
        let name = name ?? CreationHandoff.baseName(for: sources)
        let request = ArchiveCreationRequest(sources: sources, destination: destination, name: name, compression: compression, format: format, password: password, encryptFilenames: encryptFilenames, preset: preset, sevenZipOptions: sevenZipOptions)
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

final class CreateArchiveSheet: NSWindowController, NSWindowDelegate {
    var complete: ((URL?, String, CompressionPreset, ArchiveFormat, String?, Bool, SevenZipCreationOptions?) -> Void)?
    private let sources: [URL]
    private let advancedToggle = NSButton()
    private let dictionary = NSPopUpButton()
    private let threads = NSPopUpButton()
    private let memory = NSTextField(wrappingLabelWithString: "")
    private let advanced = NSStackView()
    private let advancedFields = NSStackView()
    private let createButton = NSButton(title: "Create", target: nil, action: nil)
    private let sizeCancellation = ArchiveCancellation()
    private var sizeStarted = false
    private var inputSize: Result<UInt64, Error>?
    private var selectedPreset: CompressionPreset { CompressionPreset.available(for:selectedFormat)[compression.indexOfSelectedItem] }
    private var selectedOptions: SevenZipCreationOptions {
        SevenZipCreationOptions(dictionaryBytes:dictionary.indexOfSelectedItem == 0 ? nil : SevenZipCreationOptions.supportedDictionaryBytes[dictionary.indexOfSelectedItem-1],
                                threads:threads.indexOfSelectedItem == 0 ? nil : Int(threads.titleOfSelectedItem ?? ""))
    }
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
        self.sources = sources
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
        compression.setAccessibilityLabel("Compression")
        compression.target = self; compression.action = #selector(updateAdvanced)
        dictionary.addItems(withTitles:["Auto"] + SevenZipCreationOptions.supportedDictionaryBytes.map { "\($0 / 1024 / 1024) MiB" })
        threads.addItems(withTitles:["Auto"] + SevenZipCreationOptions.supportedThreads().map(String.init))
        dictionary.setAccessibilityLabel("Dictionary size"); threads.setAccessibilityLabel("Compression threads")
        dictionary.target = self; dictionary.action = #selector(updateAdvanced)
        threads.target = self; threads.action = #selector(updateAdvanced)
        threads.toolTip = "Auto retains the existing two-thread budget. The encoder may use fewer threads for small input."
        advancedToggle.setButtonType(.onOff); advancedToggle.bezelStyle = .disclosure
        advancedToggle.title = ""; advancedToggle.setAccessibilityLabel("Advanced compression")
        advancedToggle.target = self; advancedToggle.action = #selector(updateAdvanced)
        let disclosure = NSStackView(views:[advancedToggle,NSTextField(labelWithString:"Advanced")]); disclosure.spacing = 6
        let advancedGrid = NSGridView(views:[[NSTextField(labelWithString:"Dictionary:"),dictionary],[NSTextField(labelWithString:"Threads:"),threads]])
        advancedGrid.rowSpacing = 8; advancedGrid.columnSpacing = 12
        advancedFields.addArrangedSubview(advancedGrid)
        memory.font = .systemFont(ofSize:11); memory.textColor = .secondaryLabelColor
        advanced.orientation = .vertical; advanced.alignment = .leading; advanced.spacing = 8
        let advancedViews: [NSView] = [disclosure,advancedFields,memory]
        advancedViews.forEach { advanced.addArrangedSubview($0) }
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
        createButton.target = self; createButton.action = #selector(createArchive); createButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, createButton]); buttons.spacing = 8
        let hint = NSTextField(wrappingLabelWithString: "Existing files are never replaced. A numbered name is used if needed.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let content = NSStackView(views: [grid, advanced, hint, buttons]); content.orientation = .vertical
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
        let presets = CompressionPreset.available(for: selectedFormat)
        compression.addItems(withTitles: presets.map(\.title))
        compression.selectItem(at: presets.firstIndex(of: .normal)!)
        compression.toolTip = selectedFormat == .sevenZip ? "LZMA2 compression. Higher presets may need substantially more memory and time." : "Store uses no compression; other presets use Deflate."
        encryption.isEnabled = selectedFormat == .sevenZip
        encryptionNote.isHidden = selectedFormat == .sevenZip
        if selectedFormat == .zip { encryption.state = .off; passwords.clear() }
        changeEncryption()
        updateAdvanced()
    }
    @objc private func changeEncryption() {
        let enabled = selectedFormat == .sevenZip && encryption.state == .on
        passwords.isHidden = !enabled; filenames.isHidden = !enabled
        if !enabled { passwords.clear() }
        window?.contentView?.layoutSubtreeIfNeeded()
        if let content = window?.contentView { window?.setContentSize(content.fittingSize) }
    }
    @objc private func updateAdvanced() {
        advanced.isHidden = selectedFormat != .sevenZip
        advancedFields.isHidden = advancedToggle.state != .on
        createButton.isEnabled = true
        if selectedFormat == .sevenZip {
            if !sizeStarted {
                sizeStarted = true
                let inputs = sources, token = sizeCancellation
                DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                    let result = Result { try SevenZipCreationOptions.inputSize(sources:inputs,cancellation:token) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.finished else { return }
                        self.inputSize = result; self.updateAdvanced()
                    }
                }
            }
            if let inputSize {
                do {
                    let resolved = try selectedOptions.resolve(preset:selectedPreset,inputBytes:inputSize.get())
                    memory.stringValue = "Approximate compression memory: " + ByteCountFormatter.string(fromByteCount:Int64(resolved.estimatedMemoryBytes),countStyle:.memory) + " · 2 GiB ceiling. Rechecked before creation."
                } catch {
                    memory.stringValue = error.localizedDescription
                    createButton.isEnabled = false
                }
            } else {
                memory.stringValue = "Estimating compression memory…"
                createButton.isEnabled = false
            }
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        if let content = window?.contentView { window?.setContentSize(content.fittingSize) }
    }
    @objc private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { destination = url; location.stringValue = url.path }
    }
    @objc private func createArchive() {
        guard createButton.isEnabled else { return }
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
        finish(destination, value, CompressionPreset.available(for: selectedFormat)[compression.indexOfSelectedItem], password: password)
    }
    @objc private func cancelCreate() { finish(nil, "", .normal) }
    private func finish(_ destination: URL?, _ name: String, _ preset: CompressionPreset, password: String? = nil) {
        guard !finished else { return }; finished = true
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        sizeCancellation.cancel()
        passwords.clear()
        close(); complete?(destination, name, preset, selectedFormat, password, filenames.state == .on, selectedFormat == .sevenZip ? selectedOptions : nil)
    }
    deinit { sizeCancellation.cancel() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelCreate(); return false }
}
