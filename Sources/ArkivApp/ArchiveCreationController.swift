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
        sheet.complete = { [weak self] destination, name, preset, format, password, encryptFilenames, options, split in
            guard let self else { return }
            self.setup = nil
            guard let destination else { return }
            do { try self.compress(sources, destination: destination, name: name, format: format, password: password, encryptFilenames: encryptFilenames, preset: preset, sevenZipOptions: options, split: split) }
            catch { NSAlert(error: error).runModal() }
        }
        sheet.present(parent: parent)
    }

    func compress(_ sources: [URL], destination: URL? = nil, name: String? = nil, compression: ZIPCompression? = nil, format: ArchiveFormat = .zip, password: String? = nil, encryptFilenames: Bool = true, preset: CompressionPreset? = nil, sevenZipOptions: SevenZipCreationOptions? = nil, split: SevenZipSplitOptions? = nil) throws {
        guard !isBusy else { throw ArchiveFailure.message("An archive is already being created. Wait or cancel it first.") }
        guard let first = sources.first else { throw ArchiveFailure.message("Select files or folders to compress.") }
        let destination = destination ?? first.deletingLastPathComponent()
        let name = name ?? CreationHandoff.baseName(for: sources)
        let request = ArchiveCreationRequest(sources: sources, destination: destination, name: name, compression: compression, format: format, password: password, encryptFilenames: encryptFilenames, preset: preset, sevenZipOptions: sevenZipOptions, split: split)
        isBusy = true
        let operation = FinderOperationWindow(archive: destination.appendingPathComponent(name + format.fileExtension), verb: "Compressing")
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

/// Flipped so a form shorter than its scroll view stays pinned to the top.
private final class CreateArchiveFormView: NSView { override var isFlipped: Bool { true } }

/// One two-column grid holds every main and Advanced row, so labels share a trailing
/// edge and controls share a leading edge. Hidden rows collapse. The form scrolls
/// vertically when it is taller than the display; the buttons stay in a fixed footer.
final class CreateArchiveSheet: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    static let margin: CGFloat = 20
    static let controlWidth: CGFloat = 340
    static let popupMinimumWidth: CGFloat = 180
    static let customSplitIndex = 7
    static let singleCollisionHint = "Existing files are never replaced. If the archive name is taken, a numbered name such as “Name (2)” is used."
    static let splitCollisionHint = "Existing files are never replaced. If any numbered volume with this name already exists, creation stops. Split sets are never renamed."
    static let splitExplanation = "MB = 1,000,000 bytes; GB = 1,000,000,000 bytes. Requires 2–128 parts and at most 4 GiB in total. The encoded size is checked before any part is published."
    private static let footerSpacing: CGFloat = 12
    private static let formBottom: CGFloat = 8
    private static let minimumFormHeight: CGFloat = 160
    /// Test seam for small displays; nil uses the visible frame of the window's screen.
    var availableHeightOverride: CGFloat?

    var complete: ((URL?, String, CompressionPreset, ArchiveFormat, String?, Bool, SevenZipCreationOptions?, SevenZipSplitOptions?) -> Void)?
    private let sources: [URL]
    private let advancedToggle = NSButton()
    private let disclosure = NSStackView()
    private let dictionary = NSPopUpButton()
    private let threads = NSPopUpButton()
    private let split = NSPopUpButton()
    private let customSplit = NSTextField(string:"100000000")
    private let splitHint = NSTextField(wrappingLabelWithString:"")
    private func selectedSplit() throws -> SevenZipSplitOptions? {
        guard selectedFormat == .sevenZip, split.indexOfSelectedItem > 0 else {return nil}
        let bytes: UInt64
        if split.indexOfSelectedItem <= SevenZipSplitOptions.presets.count {
            bytes = SevenZipSplitOptions.presets[split.indexOfSelectedItem-1]
        } else {
            guard let value=UInt64(customSplit.stringValue), !customSplit.stringValue.isEmpty else {
                throw ArchiveFailure.message("Enter a whole number of bytes for the custom split size.")
            }
            bytes=value
        }
        let result=SevenZipSplitOptions(volumeBytes:bytes);try result.validate();return result
    }
    func controlTextDidChange(_ notification: Notification) {updateAdvanced()}
    private let solid = NSPopUpButton()
    private let solidBlock = NSPopUpButton()
    private let memory = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let createButton = NSButton(title: "Create", target: nil, action: nil)
    private let buttons = NSStackView()
    private let scroll = NSScrollView()
    private let document = CreateArchiveFormView()
    private var grid: NSGridView!
    private var scrollHeight: NSLayoutConstraint!
    private let sizeCancellation = ArchiveCancellation()
    private var sizeStarted = false
    private var inputSize: Result<UInt64, Error>?
    private var selectedPreset: CompressionPreset { CompressionPreset.available(for:selectedFormat)[compression.indexOfSelectedItem] }
    private var selectedOptions: SevenZipCreationOptions {
        SevenZipCreationOptions(dictionaryBytes:dictionary.indexOfSelectedItem == 0 ? nil : SevenZipCreationOptions.supportedDictionaryBytes[dictionary.indexOfSelectedItem-1],
                                threads:threads.indexOfSelectedItem == 0 ? nil : Int(threads.titleOfSelectedItem ?? ""),
                                solid:solid.indexOfSelectedItem == 0 ? .off : .on(blockBytes:solidBlock.indexOfSelectedItem == 0 ? nil : SevenZipSolidPolicy.supportedBlockBytes[solidBlock.indexOfSelectedItem-1]))
    }
    private let name = NSTextField(string: "")
    private let location = NSTextField(labelWithString: "")
    private let compression = NSPopUpButton()
    private let format = NSPopUpButton()
    private let encryption = NSButton(checkboxWithTitle: "Protect with AES-256 password", target: nil, action: nil)
    private let passwords = PasswordEntryView(confirm: true)
    private let filenames = NSButton(checkboxWithTitle: "Encrypt filenames", target: nil, action: nil)
    private let encryptionNote = NSTextField(wrappingLabelWithString: "ZIP uses WinZip AES-256. Filenames remain visible.")
    private var selectedFormat: ArchiveFormat { ArchiveFormat.allCases[format.indexOfSelectedItem] }
    private var destination: URL
    private var finished = false
    private var suggestedName: String

    private static func formLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.alignment = .right
        return label
    }
    private static func secondary(_ label: NSTextField) {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize); label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = controlWidth
    }

    init(sources: [URL], encrypted: Bool) {
        self.sources = sources
        suggestedName = CreationHandoff.baseName(for: sources)
        destination = sources.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Create Archive"; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.tabbingMode = .disallowed
        name.stringValue = CreationHandoff.baseName(for: sources)
        name.setAccessibilityLabel("Archive name")
        name.lineBreakMode = .byTruncatingTail; name.cell?.isScrollable = true; name.cell?.wraps = false
        location.stringValue = destination.path; location.toolTip = destination.path
        location.lineBreakMode = .byTruncatingMiddle; location.maximumNumberOfLines = 1
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        location.setContentHuggingPriority(.defaultLow, for: .horizontal)
        compression.setAccessibilityLabel("Compression")
        compression.target = self; compression.action = #selector(updateAdvanced)
        dictionary.addItems(withTitles:["Auto"] + SevenZipCreationOptions.supportedDictionaryBytes.map { "\($0 / 1024 / 1024) MiB" })
        threads.addItems(withTitles:["Auto"] + SevenZipCreationOptions.supportedThreads().map(String.init))
        dictionary.setAccessibilityLabel("Dictionary size"); threads.setAccessibilityLabel("Compression threads")
        dictionary.target = self; dictionary.action = #selector(updateAdvanced)
        threads.target = self; threads.action = #selector(updateAdvanced)
        solid.addItems(withTitles:["Off", "On"])
        solidBlock.addItems(withTitles:["Auto"] + SevenZipSolidPolicy.supportedBlockBytes.map { "\($0 / 1024 / 1024) MiB block" })
        solid.setAccessibilityLabel("Solid compression"); solidBlock.setAccessibilityLabel("Solid block size")
        solid.target = self; solid.action = #selector(updateAdvanced)
        solidBlock.target = self; solidBlock.action = #selector(updateAdvanced)
        solidBlock.toolTip = "Upstream grouping limit. One larger file can occupy a block alone. Solid archives cannot be edited in Arkiv."
        threads.toolTip = "Auto retains the existing two-thread budget. The encoder may use fewer threads for small input."
        advancedToggle.setButtonType(.onOff); advancedToggle.bezelStyle = .disclosure
        advancedToggle.title = ""; advancedToggle.setAccessibilityLabel("Advanced compression")
        advancedToggle.target = self; advancedToggle.action = #selector(updateAdvanced)
        disclosure.addArrangedSubview(advancedToggle); disclosure.addArrangedSubview(NSTextField(labelWithString:"Advanced"))
        disclosure.spacing = 6; disclosure.alignment = .centerY
        split.addItems(withTitles:["No splitting","100 MB","650 MB","700 MB","1 GB","2 GB","4 GB","Custom size"])
        split.setAccessibilityLabel("Split into volumes");split.target=self;split.action = #selector(updateAdvanced)
        customSplit.setAccessibilityLabel("Custom split size in bytes");customSplit.delegate=self
        customSplit.placeholderString = "Bytes per volume"
        customSplit.widthAnchor.constraint(equalToConstant: 160).isActive = true
        format.addItems(withTitles: ArchiveFormat.allCases.map(\.title))
        format.setAccessibilityLabel("Archive format")
        format.target = self; format.action = #selector(changeFormat)
        for popup in [format, compression, dictionary, threads, solid, solidBlock, split] {
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.popupMinimumWidth).isActive = true
        }
        encryption.target = self; encryption.action = #selector(changeEncryption)
        filenames.state = .on
        encryptionNote.textColor = .secondaryLabelColor; encryptionNote.preferredMaxLayoutWidth = Self.controlWidth
        for label in [splitHint, memory, hint] { Self.secondary(label) }
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDestination))
        choose.setContentCompressionResistancePriority(.required, for: .horizontal)
        choose.setContentHuggingPriority(.required, for: .horizontal)
        let destinationRow = NSStackView(views: [location, choose])
        destinationRow.spacing = 8; destinationRow.distribution = .fill; destinationRow.alignment = .centerY
        let names = sources.prefix(5).map(\.lastPathComponent).joined(separator: ", ") + (sources.count > 5 ? " … (\(sources.count) items)" : "")
        let selection = NSTextField(wrappingLabelWithString: names)
        selection.toolTip = sources.map(\.lastPathComponent).joined(separator: "\n")
        selection.preferredMaxLayoutWidth = Self.controlWidth
        selection.maximumNumberOfLines = 3; selection.cell?.truncatesLastVisibleLine = true
        selection.setAccessibilityLabel("Items to compress")

        let empty = NSGridCell.emptyContentView
        let rows: [[NSView]] = [
            [Self.formLabel("Items:"), selection],
            [Self.formLabel("Name:"), name],
            [Self.formLabel("Destination:"), destinationRow],
            [Self.formLabel("Format:"), format],
            [Self.formLabel("Compression:"), compression],
            [Self.formLabel("Encryption:"), encryption],
            [empty, passwords],
            [empty, filenames],
            [empty, encryptionNote],
            [empty, disclosure],
            [Self.formLabel("Dictionary:"), dictionary],
            [Self.formLabel("Threads:"), threads],
            [Self.formLabel("Solid:"), solid],
            [Self.formLabel("Solid block:"), solidBlock],
            [Self.formLabel("Split into volumes:"), split],
            [Self.formLabel("Custom bytes:"), customSplit],
            [empty, splitHint],
            [empty, memory],
            [empty, hint]
        ]
        let grid = NSGridView(views: rows)
        self.grid = grid
        grid.rowSpacing = 10; grid.columnSpacing = 8; grid.rowAlignment = .firstBaseline
        // Measure every label once (hidden Advanced labels included) so expanding
        // Advanced never shifts the controls sideways.
        let labelWidth = rows.compactMap { $0[0] as? NSTextField }.map { ceil($0.fittingSize.width) }.max() ?? 0
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = labelWidth
        grid.column(at: 1).xPlacement = .leading; grid.column(at: 1).width = Self.controlWidth
        for view in [selection, name, destinationRow, passwords, encryptionNote, splitHint, memory, hint] as [NSView] {
            grid.cell(for: view)?.xPlacement = .fill
        }
        for view in [destinationRow, passwords, disclosure] as [NSView] {
            grid.cell(for: view)?.row?.rowAlignment = .none
            grid.cell(for: view)?.row?.yPlacement = view === passwords ? .top : .center
        }
        grid.cell(for: disclosure)?.row?.topPadding = 4
        grid.cell(for: hint)?.row?.topPadding = 4

        grid.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: document.topAnchor, constant: Self.margin),
            grid.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Self.margin)
        ])
        scroll.documentView = document
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelCreate)); cancel.keyEquivalent = "\u{1b}"
        createButton.target = self; createButton.action = #selector(createArchive); createButton.keyEquivalent = "\r"
        for button in [cancel, createButton] {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            buttons.addArrangedSubview(button)
        }
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scroll); root.addSubview(buttons)
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: Self.minimumFormHeight)
        let bottom = buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.margin)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollHeight,
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: Self.footerSpacing),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.margin),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: Self.margin),
            bottom
        ])
        panel.contentView = root
        format.selectItem(at: encrypted ? 1 : 0)
        encryption.state = encrypted ? .on : .off
        changeFormat()
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func present(parent: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if let parent { parent.beginSheet(window) }
        else { showWindow(nil); window.makeKeyAndOrderFront(nil) }
        relayout()
        window.makeFirstResponder(name)
    }
    /// Hides a form row together with its content so it takes no space.
    private func setVisible(_ view: NSView, _ visible: Bool) {
        view.isHidden = !visible
        grid.cell(for: view)?.row?.isHidden = !visible
    }
    /// Sizes the window to the form, capped to the display; the form scrolls beyond that.
    func relayout() {
        guard let window, let grid else { return }
        let form = grid.fittingSize
        let formSize = NSSize(width: ceil(form.width) + 2 * Self.margin, height: ceil(form.height) + Self.margin + Self.formBottom)
        let footer = ceil(buttons.fittingSize.height) + Self.footerSpacing + Self.margin
        let chrome = window.frameRect(forContentRect: .zero).height
        let available = availableHeightOverride ?? (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let visibleForm = min(formSize.height, max(Self.minimumFormHeight, floor(available - chrome - footer)))
        let scrolls = visibleForm < formSize.height
        let scroller = scrolls && NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        document.frame = NSRect(origin: .zero, size: formSize)
        scrollHeight.constant = visibleForm
        let content = NSSize(width: formSize.width + scroller, height: visibleForm + footer)
        if window.isVisible && window.sheetParent == nil {
            // Keep the title bar in place while sections expand or collapse, moving up
            // only when the taller window would otherwise leave the visible screen.
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            if let screen = (window.screen ?? NSScreen.main)?.visibleFrame, frame.minY < screen.minY {
                frame.origin.y = min(screen.minY, screen.maxY - frame.height)
            }
            window.setFrame(frame, display: true)
        } else {
            window.setContentSize(content)
        }
        window.contentView?.layoutSubtreeIfNeeded()
    }
    @objc private func changeFormat() {
        let nextName = selectedFormat.isStandalone && sources.count == 1 ? sources[0].lastPathComponent : CreationHandoff.baseName(for: sources)
        if name.stringValue == suggestedName { name.stringValue = nextName }
        suggestedName = nextName
        compression.removeAllItems()
        let presets = CompressionPreset.available(for: selectedFormat)
        let fixedSettings = selectedFormat != .zip && selectedFormat != .sevenZip
        compression.addItems(withTitles: fixedSettings ? [selectedFormat.compressionDescription] : presets.map(\.title))
        compression.isEnabled = !fixedSettings
        compression.selectItem(at: presets.firstIndex(of: .normal)!)
        compression.toolTip = fixedSettings ? "Fixed, bounded compression settings. This format has no encryption." : selectedFormat == .sevenZip ? "LZMA2 compression. Higher presets may need substantially more memory and time." : "Store uses no compression; other presets use Deflate."
        encryption.isEnabled = !fixedSettings
        setVisible(encryptionNote, selectedFormat != .sevenZip)
        setVisible(encryption, !fixedSettings)
        encryptionNote.stringValue = fixedSettings ? "This format does not support encryption." : "ZIP uses WinZip AES-256. Filenames remain visible."
        if fixedSettings { encryption.state = .off; passwords.clear() }
        changeEncryption()
        updateAdvanced()
    }
    @objc private func changeEncryption() {
        let enabled = (selectedFormat == .sevenZip || selectedFormat == .zip) && encryption.state == .on
        setVisible(passwords, enabled); setVisible(filenames, enabled && selectedFormat == .sevenZip)
        if !enabled { passwords.clear() }
        relayout()
    }
    @objc private func updateAdvanced() {
        solidBlock.isEnabled = solid.indexOfSelectedItem == 1
        let seven = selectedFormat == .sevenZip, expanded = seven && advancedToggle.state == .on
        setVisible(disclosure, seven); setVisible(memory, seven)
        for view in [dictionary, threads, solid, solidBlock, split, splitHint] as [NSView] { setVisible(view, expanded) }
        setVisible(customSplit, expanded && split.indexOfSelectedItem == Self.customSplitIndex)
        createButton.isEnabled = true
        if selectedFormat.isStandalone {
            let regular = sources.count == 1 && (try? FileManager.default.attributesOfItem(atPath: sources[0].path)[.type] as? FileAttributeType) == .typeRegular
            createButton.isEnabled = regular
            encryptionNote.stringValue = regular ? "One regular file. No encryption. Use TAR for folders or multiple files." : "Choose exactly one regular file, or use a TAR-based format for this selection."
        }
        if seven {
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
        splitHint.stringValue = Self.splitExplanation
        hint.stringValue = seven && split.indexOfSelectedItem > 0 ? Self.splitCollisionHint : Self.singleCollisionHint
        do { _ = try selectedSplit() } catch {createButton.isEnabled=false;splitHint.stringValue=error.localizedDescription}
        relayout()
    }
    @objc private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { destination = url; location.stringValue = url.path; location.toolTip = url.path }
    }
    @objc private func createArchive() {
        guard createButton.isEnabled else { return }
        var value = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if (!selectedFormat.isStandalone || value != sources.first?.lastPathComponent), let suffix = ArchiveFormat.allCases.map(\.fileExtension).sorted(by: { $0.count > $1.count }).first(where: { value.lowercased().hasSuffix($0) }) {
            value = String(value.dropLast(suffix.count))
        }
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
        guard !finished else { return }
        let splitOptions: SevenZipSplitOptions?
        do {splitOptions = destination == nil ? nil : try selectedSplit()}
        catch {NSAlert(error:error).runModal();return}
        finished = true
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        sizeCancellation.cancel()
        passwords.clear()
        close(); complete?(destination, name, preset, selectedFormat, password, selectedFormat == .sevenZip && filenames.state == .on, selectedFormat == .sevenZip ? selectedOptions : nil, splitOptions)
    }
    deinit { sizeCancellation.cancel() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelCreate(); return false }
}
