import AppKit
import XCTest
import ArkivCore
import ArkivFinderIntegration
@testable import ArkivApp

/// Measures the real Create Archive geometry rather than control presence: four-sided
/// padding, containment, shared label/control edges, baselines, clipping, wrapping,
/// scrolling and resizing across formats, sections, split modes and appearances.
final class CreateArchiveLayoutTests: XCTestCase {
    private let tolerance: CGFloat = 0.5

    private struct Form {
        let window: NSWindow, root: NSView, scroll: NSScrollView, document: NSView, grid: NSGridView
        let cancel: NSButton, create: NSButton
    }
    private struct Controls {
        let format: NSPopUpButton, encryption: NSButton, advanced: NSButton, split: NSPopUpButton
        let custom: NSTextField, dictionary: NSPopUpButton, create: NSButton, cancel: NSButton
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func spread(_ values: [CGFloat]) -> CGFloat { (values.max() ?? 0) - (values.min() ?? 0) }

    @MainActor private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arkiv-layout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    @MainActor private func source(in root: URL, _ name: String = "input.txt") throws -> URL {
        let file = root.appendingPathComponent(name)
        try Data("input".utf8).write(to: file)
        return file
    }
    @MainActor private func form(_ sheet: CreateArchiveSheet) throws -> Form {
        let window = try XCTUnwrap(sheet.window)
        let root = try XCTUnwrap(window.contentView)
        root.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        document.layoutSubtreeIfNeeded()
        let grid = try XCTUnwrap(descendants(document).compactMap { $0 as? NSGridView }.first)
        let buttons = descendants(root).compactMap { $0 as? NSButton }
        return Form(window: window, root: root, scroll: scroll, document: document, grid: grid,
                    cancel: try XCTUnwrap(buttons.first { $0.title == "Cancel" }),
                    create: try XCTUnwrap(buttons.first { $0.title == "Create" }))
    }
    @MainActor private func controls(_ sheet: CreateArchiveSheet) throws -> Controls {
        let all = descendants(try XCTUnwrap(sheet.window?.contentView))
        let popups = all.compactMap { $0 as? NSPopUpButton }, buttons = all.compactMap { $0 as? NSButton }
        return Controls(format: try XCTUnwrap(popups.first { $0.itemTitles.contains("ZIP (.zip)") }),
                        encryption: try XCTUnwrap(buttons.first { $0.title == "Protect with AES-256 password" }),
                        advanced: try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "Advanced compression" }),
                        split: try XCTUnwrap(popups.first { $0.itemTitles.contains("No splitting") }),
                        custom: try XCTUnwrap(all.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Custom split size in bytes" }),
                        dictionary: try XCTUnwrap(popups.first { $0.itemTitles.contains("64 MiB") }),
                        create: try XCTUnwrap(buttons.first { $0.title == "Create" }),
                        cancel: try XCTUnwrap(buttons.first { $0.title == "Cancel" }))
    }
    @MainActor private func labels(_ sheet: CreateArchiveSheet) -> [NSTextField] {
        sheet.window?.contentView.map { descendants($0).compactMap { $0 as? NSTextField } } ?? []
    }
    @MainActor private func hint(_ sheet: CreateArchiveSheet) throws -> NSTextField {
        try XCTUnwrap(labels(sheet).first { $0.stringValue.hasPrefix("Existing files are never replaced") })
    }
    @MainActor private func select(_ popup: NSPopUpButton, _ title: String) {
        popup.selectItem(withTitle: title)
        XCTAssertEqual(popup.titleOfSelectedItem, title)
        XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
    }
    @MainActor private func setEncryption(_ c: Controls, _ on: Bool) {
        if (c.encryption.state == .on) != on { c.encryption.performClick(nil) }
        XCTAssertEqual(c.encryption.state == .on, on)
    }
    @MainActor private func setAdvanced(_ c: Controls, _ expanded: Bool) {
        if (c.advanced.state == .on) != expanded { c.advanced.performClick(nil) }
        XCTAssertEqual(c.advanced.state == .on, expanded)
    }
    @MainActor private func enterCustomSize(_ sheet: CreateArchiveSheet, _ c: Controls, _ value: String) {
        c.custom.stringValue = value
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: c.custom))
    }
    @MainActor private func waitForEstimate(_ sheet: CreateArchiveSheet) async throws {
        for _ in 0..<400 {
            if labels(sheet).contains(where: { $0.stringValue.hasPrefix("Approximate compression memory:") }) { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Memory estimate did not arrive")
    }
    @MainActor private func content(_ cell: NSGridCell) -> NSView? {
        guard let view = cell.contentView, view !== NSGridCell.emptyContentView else { return nil }
        return view
    }
    @MainActor private func visibleRows(_ grid: NSGridView) -> [(label: NSTextField?, control: NSView)] {
        (0..<grid.numberOfRows).compactMap { index -> (label: NSTextField?, control: NSView)? in
            let row = grid.row(at: index)
            guard !row.isHidden, let control = content(row.cell(at: 1)), !control.isHiddenOrHasHiddenAncestor else { return nil }
            return (content(row.cell(at: 0)) as? NSTextField, control)
        }
    }
    @MainActor private func leaves(_ view: NSView) -> [NSView] {
        if view.isHidden { return [] }
        if view is NSControl { return [view] }
        return view.subviews.flatMap { leaves($0) }
    }
    /// Alignment rectangle (what Auto Layout and NSGridView align) in `target` coordinates.
    @MainActor private func aligned(_ view: NSView, in target: NSView) -> NSRect {
        guard let parent = view.superview else { return .zero }
        return parent.convert(view.alignmentRect(forFrame: view.frame), to: target)
    }
    @MainActor private func describe(_ view: NSView) -> String {
        (view as? NSTextField).map { "“\($0.stringValue.prefix(40))”" } ?? (view as? NSButton).map { "“\($0.title)”" } ?? "\(type(of: view))"
    }

    @MainActor private func assertLayout(_ sheet: CreateArchiveSheet, _ context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let f = try form(sheet)
        let margin = CreateArchiveSheet.margin, note = " [\(context)]"
        let doc = f.document.bounds, clip = f.scroll.contentView.bounds, rootBounds = f.root.bounds

        // Padding on all four sides of the form; never any horizontal clipping.
        let grid = aligned(f.grid, in: f.document)
        XCTAssertEqual(grid.minX, margin, accuracy: tolerance, "leading padding" + note, file: file, line: line)
        XCTAssertEqual(grid.minY, margin, accuracy: tolerance, "top padding" + note, file: file, line: line)
        XCTAssertEqual(doc.width - grid.maxX, margin, accuracy: 1, "trailing padding" + note, file: file, line: line)
        XCTAssertGreaterThanOrEqual(doc.height - grid.maxY, 4, "bottom padding" + note, file: file, line: line)
        XCTAssertLessThanOrEqual(doc.width, clip.width + tolerance, "form wider than its viewport" + note, file: file, line: line)
        XCTAssertFalse(f.scroll.hasHorizontalScroller, note, file: file, line: line)
        if doc.height > clip.height + tolerance {
            XCTAssertTrue(f.scroll.hasVerticalScroller, "tall form must scroll" + note, file: file, line: line)
        } else {
            XCTAssertEqual(clip.height, doc.height, accuracy: 1, "viewport fits the form exactly" + note, file: file, line: line)
        }

        // One shared label edge and one shared control edge, Advanced rows included.
        var labelEdges: [CGFloat] = [], controlEdges: [CGFloat] = [], rects: [(NSView, NSRect)] = []
        let rows = visibleRows(f.grid)
        XCTAssertGreaterThanOrEqual(rows.count, 6, note, file: file, line: line)
        for (label, control) in rows {
            let c = aligned(control, in: f.document)
            controlEdges.append(c.minX)
            XCTAssertLessThanOrEqual(c.width, CreateArchiveSheet.controlWidth + tolerance, describe(control) + note, file: file, line: line)
            if let label {
                let l = aligned(label, in: f.document)
                labelEdges.append(l.maxX)
                XCTAssertGreaterThanOrEqual(l.width, label.intrinsicContentSize.width - tolerance, "clipped label " + describe(label) + note, file: file, line: line)
                XCTAssertLessThan(l.maxX, c.minX, "label overlaps control " + describe(label) + note, file: file, line: line)
                if control is NSControl {
                    XCTAssertEqual(l.minY + label.firstBaselineOffsetFromTop, c.minY + control.firstBaselineOffsetFromTop, accuracy: 1,
                                   "baseline " + describe(label) + note, file: file, line: line)
                } else {
                    XCTAssertEqual(l.midY, c.midY, accuracy: 2, "vertical centring " + describe(label) + note, file: file, line: line)
                }
                rects.append((label, l))
            }
            rects += leaves(control).map { ($0, aligned($0, in: f.document)) }
        }
        XCTAssertLessThanOrEqual(spread(labelEdges), tolerance, "labels share one trailing edge" + note, file: file, line: line)
        XCTAssertLessThanOrEqual(spread(controlEdges), tolerance, "controls share one leading edge" + note, file: file, line: line)

        // Every visible control is inside the padded form, unclipped and non-overlapping.
        for (view, r) in rects {
            let name = describe(view) + note
            XCTAssertGreaterThanOrEqual(r.minX, margin - tolerance, "leading margin " + name, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxX, doc.width - margin + tolerance, "trailing margin " + name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.minY, margin - tolerance, "top margin " + name, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxY, doc.height + tolerance, "outside form " + name, file: file, line: line)
            let intrinsic = view.intrinsicContentSize
            if let field = view as? NSTextField {
                if field.isEditable {
                    XCTAssertGreaterThanOrEqual(r.width, 150, "field too narrow " + name, file: file, line: line)
                    XCTAssertGreaterThanOrEqual(r.height, intrinsic.height - tolerance, "field clipped " + name, file: file, line: line)
                } else if field.cell?.wraps == true, let cell = field.cell {
                    let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10_000)).height
                    if field.maximumNumberOfLines == 0 {
                        XCTAssertGreaterThanOrEqual(field.bounds.height, needed - 1, "wrapped text clipped " + name, file: file, line: line)
                    } else {
                        let lineHeight = NSLayoutManager().defaultLineHeight(for: field.font ?? .systemFont(ofSize: NSFont.systemFontSize))
                        XCTAssertLessThanOrEqual(field.bounds.height, CGFloat(field.maximumNumberOfLines) * lineHeight + 4, "line limit " + name, file: file, line: line)
                    }
                    XCTAssertGreaterThan(field.bounds.height, 0, "collapsed text " + name, file: file, line: line)
                } else if field.lineBreakMode != .byTruncatingMiddle {
                    XCTAssertGreaterThanOrEqual(r.width, intrinsic.width - tolerance, "clipped " + name, file: file, line: line)
                }
            } else {
                XCTAssertGreaterThanOrEqual(r.width, intrinsic.width - tolerance, "clipped " + name, file: file, line: line)
                XCTAssertGreaterThanOrEqual(r.height, intrinsic.height - tolerance, "clipped " + name, file: file, line: line)
            }
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                XCTAssertFalse(rects[i].1.insetBy(dx: 1, dy: 1).intersects(rects[j].1.insetBy(dx: 1, dy: 1)),
                               "overlap " + describe(rects[i].0) + " / " + describe(rects[j].0) + note, file: file, line: line)
            }
        }

        // Footer: Cancel then Create, aligned, unclipped, inside the margins, below the form.
        let cancel = aligned(f.cancel, in: f.root), create = aligned(f.create, in: f.root)
        for (button, r) in [(f.cancel, cancel), (f.create, create)] {
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, note, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.width, button.intrinsicContentSize.width - tolerance, "clipped " + describe(button) + note, file: file, line: line)
            XCTAssertEqual(r.minY, margin, accuracy: 1, "bottom margin " + describe(button) + note, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.minX, margin - tolerance, note, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxY, f.scroll.frame.minY - 8, "button overlaps form" + note, file: file, line: line)
        }
        XCTAssertEqual(rootBounds.width - create.maxX, margin, accuracy: 1, "Create trailing margin" + note, file: file, line: line)
        XCTAssertLessThan(cancel.maxX, create.minX, "Cancel precedes Create" + note, file: file, line: line)
        XCTAssertEqual(cancel.minY, create.minY, accuracy: tolerance, note, file: file, line: line)
        XCTAssertEqual(cancel.height, create.height, accuracy: tolerance, note, file: file, line: line)
        XCTAssertEqual(f.scroll.frame.width, rootBounds.width, accuracy: tolerance, note, file: file, line: line)
        XCTAssertEqual(f.scroll.frame.maxY, rootBounds.height, accuracy: tolerance, note, file: file, line: line)

        // The window never exceeds the usable display height.
        let available = sheet.availableHeightOverride ?? (f.window.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
        XCTAssertLessThanOrEqual(f.window.frame.height, available + tolerance, "taller than the display" + note, file: file, line: line)
    }

    @MainActor private func assertAppearance(_ sheet: CreateArchiveSheet, _ name: NSAppearance.Name) throws {
        let f = try form(sheet)
        XCTAssertEqual(f.window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
        XCTAssertFalse(f.scroll.drawsBackground, "form uses the native window background")
        for (label, control) in visibleRows(f.grid) {
            if let label { XCTAssertEqual(label.textColor, .labelColor, describe(label)) }
            if let text = control as? NSTextField, !text.isEditable, text.font?.pointSize == NSFont.smallSystemFontSize {
                XCTAssertEqual(text.textColor, .secondaryLabelColor, describe(text))
            }
        }
    }

    @MainActor
    func testGeometryAcrossFormatsSectionsSplitModesValidationAndAppearances() async throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let input = try source(in: root)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let sheet = CreateArchiveSheet(sources: [input], encrypted: false)
            defer { sheet.close() }
            sheet.window?.appearance = NSAppearance(named: appearance)
            let c = try controls(sheet), label = appearance.rawValue
            try assertAppearance(sheet, appearance)
            XCTAssertEqual(c.format.titleOfSelectedItem, "ZIP (.zip)")
            for encrypted in [false, true] {
                setEncryption(c, encrypted)
                XCTAssertTrue(c.advanced.isHiddenOrHasHiddenAncestor)
                XCTAssertTrue(c.split.isHiddenOrHasHiddenAncestor)
                XCTAssertEqual(try hint(sheet).stringValue, CreateArchiveSheet.singleCollisionHint)
                try assertLayout(sheet, "\(label) ZIP encrypted=\(encrypted)")
            }
            select(c.format, ArchiveFormat.sevenZip.title)
            try await waitForEstimate(sheet)
            for encrypted in [false, true] {
                setEncryption(c, encrypted)
                setAdvanced(c, false)
                XCTAssertTrue(c.split.isHiddenOrHasHiddenAncestor)
                try assertLayout(sheet, "\(label) 7z collapsed encrypted=\(encrypted)")
                let collapsed = try form(sheet).window.frame.height
                setAdvanced(c, true)
                XCTAssertGreaterThan(try form(sheet).window.frame.height, collapsed, "expanding Advanced grows the dialog")
                for title in ["No splitting", "100 MB", "Custom size"] {
                    select(c.split, title)
                    XCTAssertFalse(c.split.isHiddenOrHasHiddenAncestor)
                    XCTAssertEqual(c.custom.isHiddenOrHasHiddenAncestor, title != "Custom size", "custom bytes only for Custom size")
                    let text = try hint(sheet).stringValue
                    if title == "No splitting" {
                        XCTAssertEqual(text, CreateArchiveSheet.singleCollisionHint)
                    } else {
                        XCTAssertEqual(text, CreateArchiveSheet.splitCollisionHint)
                        XCTAssertFalse(text.contains("numbered name"), "split sets are never renamed")
                    }
                    try assertLayout(sheet, "\(label) 7z expanded encrypted=\(encrypted) split=\(title)")
                }
                enterCustomSize(sheet, c, "31")
                XCTAssertFalse(c.create.isEnabled)
                XCTAssertTrue(labels(sheet).contains { $0.stringValue.hasPrefix("Split size must be at least 32 bytes") })
                try assertLayout(sheet, "\(label) custom split validation")
                enterCustomSize(sheet, c, "100000000")
                select(c.dictionary, "64 MiB")
                XCTAssertFalse(c.create.isEnabled)
                XCTAssertTrue(labels(sheet).contains { $0.stringValue.contains("exceeds Arkiv’s 2 GiB") })
                try assertLayout(sheet, "\(label) memory validation")
                select(c.dictionary, "Auto")
                select(c.split, "No splitting")
                XCTAssertTrue(c.custom.isHiddenOrHasHiddenAncestor)
                setAdvanced(c, false)
                XCTAssertEqual(try form(sheet).window.frame.height, collapsed, accuracy: tolerance, "collapsing restores the size")
            }
        }
    }

    @MainActor
    func testLongFilenamesAndDestinationPathsStayInsideTheForm() throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        var folder = root
        for level in 0..<3 {
            folder = folder.appendingPathComponent("Destination folder with a deliberately long descriptive name \(level) " + String(repeating: "x", count: 120))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try (0..<7).map { try source(in: folder, "Quarterly-report-\($0)-" + String(repeating: "a", count: 180) + ".txt") }
        let reference = CreateArchiveSheet(sources: [try source(in: root)], encrypted: false)
        defer { reference.close() }
        let referenceWidth = try form(reference).root.bounds.width
        for sources in [[files[0]], files] {
            let sheet = CreateArchiveSheet(sources: sources, encrypted: false)
            defer { sheet.close() }
            try assertLayout(sheet, "long names (\(sources.count) items)")
            let f = try form(sheet)
            XCTAssertEqual(f.root.bounds.width, referenceWidth, accuracy: tolerance, "long text must not widen the dialog")
            let location = try XCTUnwrap(labels(sheet).first { $0.stringValue == folder.path })
            XCTAssertLessThan(aligned(location, in: f.document).width, location.intrinsicContentSize.width, "long path truncates")
            XCTAssertEqual(location.toolTip, folder.path)
            let choose = try XCTUnwrap(descendants(f.root).compactMap { $0 as? NSButton }.first { $0.title == "Choose…" })
            XCTAssertGreaterThanOrEqual(aligned(choose, in: f.document).width, choose.intrinsicContentSize.width - tolerance)
            let name = try XCTUnwrap(labels(sheet).first { $0.accessibilityLabel() == "Archive name" })
            XCTAssertGreaterThan(name.stringValue.count, 150)
            XCTAssertEqual(aligned(name, in: f.document).width, CreateArchiveSheet.controlWidth, accuracy: tolerance)
            let items = try XCTUnwrap(labels(sheet).first { $0.accessibilityLabel() == "Items to compress" })
            XCTAssertEqual(items.maximumNumberOfLines, 3)
        }
    }

    @MainActor
    func testSmallDisplayScrollsTheFormAndKeepsButtonsVisible() async throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let sheet = CreateArchiveSheet(sources: [try source(in: root)], encrypted: true)
        defer { sheet.close() }
        sheet.availableHeightOverride = 420
        let c = try controls(sheet)
        try await waitForEstimate(sheet)
        setAdvanced(c, true)
        select(c.split, "Custom size")
        try assertLayout(sheet, "small display")
        let f = try form(sheet)
        XCTAssertLessThanOrEqual(f.window.frame.height, 420 + tolerance)
        XCTAssertGreaterThan(f.document.bounds.height, f.scroll.contentView.bounds.height + 1, "form scrolls on a small display")
        let last = aligned(try hint(sheet), in: f.document)
        f.document.scrollToVisible(last)
        XCTAssertTrue(f.document.visibleRect.insetBy(dx: -1, dy: -1).contains(last), "final row reachable by scrolling")
        sheet.availableHeightOverride = 5_000
        sheet.relayout()
        let restored = try form(sheet)
        XCTAssertEqual(restored.document.bounds.height, restored.scroll.contentView.bounds.height, accuracy: 1, "no scrolling when it fits")
    }

    @MainActor
    func testFinderAndFileMenuPresentationsKeepLayoutWhileResizing() async throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let input = try source(in: root)
        // Finder: a routed handoff opens a standalone panel.
        for command in [CreationCommand.addArchive, .password] {
            let routed = try CreationHandoff(url: try CreationHandoff(command: command, sources: [input]).url)
            let sheet = CreateArchiveSheet(sources: routed.sources, encrypted: routed.command == .password)
            defer { sheet.close() }
            var cancelled = false
            sheet.complete = { destination, _, _, _, _, _, _, _ in XCTAssertNil(destination); cancelled = true }
            sheet.present(parent: nil)
            let window = try XCTUnwrap(sheet.window)
            XCTAssertTrue(window.isVisible); XCTAssertNil(window.sheetParent)
            let c = try controls(sheet)
            XCTAssertEqual(c.format.indexOfSelectedItem, command == .password ? 1 : 0)
            XCTAssertEqual(c.encryption.state, command == .password ? .on : .off)
            try assertLayout(sheet, "Finder \(command.rawValue)")
            select(c.format, ArchiveFormat.sevenZip.title)
            try await waitForEstimate(sheet)
            let top = window.frame.maxY
            setAdvanced(c, true)
            if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
                XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(window.frame), "expanded window stays on screen")
                if top - window.frame.height >= screen.minY {
                    XCTAssertEqual(window.frame.maxY, top, accuracy: tolerance, "expanding keeps the title bar in place")
                }
            }
            try assertLayout(sheet, "Finder \(command.rawValue) expanded")
            setAdvanced(c, false)
            try assertLayout(sheet, "Finder \(command.rawValue) collapsed again")
            c.cancel.performClick(nil)
            XCTAssertTrue(cancelled); XCTAssertFalse(window.isVisible)
        }
        // File menu: attached as a sheet to the key browser window.
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false; parent.center(); parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let sheet = CreateArchiveSheet(sources: [input], encrypted: false)
        defer { sheet.close() }
        var cancelled = false
        sheet.complete = { destination, _, _, _, _, _, _, _ in XCTAssertNil(destination); cancelled = true }
        sheet.present(parent: parent)
        let window = try XCTUnwrap(sheet.window)
        XCTAssertTrue(parent.attachedSheet === window)
        try assertLayout(sheet, "File menu sheet")
        let c = try controls(sheet)
        select(c.format, ArchiveFormat.sevenZip.title)
        try await waitForEstimate(sheet)
        setAdvanced(c, true); select(c.split, "Custom size")
        try assertLayout(sheet, "File menu sheet expanded")
        setAdvanced(c, false)
        try assertLayout(sheet, "File menu sheet collapsed")
        c.cancel.performClick(nil)
        XCTAssertTrue(cancelled)
        for _ in 0..<200 where parent.attachedSheet != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(parent.attachedSheet)
    }
}
