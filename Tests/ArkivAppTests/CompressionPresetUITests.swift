import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class CompressionPresetUITests: XCTestCase {
    private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    @MainActor
    func testSolidControlsDefaultDependencyAndSubmission() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("input".utf8).write(to:file)
        defer { try? FileManager.default.removeItem(at:file) }
        let sheet = CreateArchiveSheet(sources:[file],encrypted:false)
        defer { sheet.close() }
        let root = try XCTUnwrap(sheet.window?.contentView)
        let popups = views(root).compactMap { $0 as? NSPopUpButton }
        let format = try XCTUnwrap(popups.first { $0.itemTitles.contains("ZIP (.zip)") })
        let solid = try XCTUnwrap(popups.first { $0.itemTitles == ["Off","On"] })
        let block = try XCTUnwrap(popups.first { $0.itemTitles.contains("16 MiB block") })
        XCTAssertTrue(solid.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(solid.titleOfSelectedItem,"Off"); XCTAssertFalse(block.isEnabled)
        format.selectItem(at:1); XCTAssertTrue(format.sendAction(format.action,to:format.target))
        let create = try XCTUnwrap(views(root).compactMap { $0 as? NSButton }.first { $0.title == "Create" })
        for _ in 0..<400 where !create.isEnabled { try await Task.sleep(nanoseconds:25_000_000) }
        try XCTUnwrap(views(root).compactMap { $0 as? NSButton }.first { $0.bezelStyle == .disclosure }).performClick(nil)
        XCTAssertFalse(solid.isHiddenOrHasHiddenAncestor)
        solid.selectItem(withTitle:"On"); XCTAssertTrue(solid.sendAction(solid.action,to:solid.target))
        XCTAssertTrue(block.isEnabled); XCTAssertEqual(block.titleOfSelectedItem,"Auto")
        block.selectItem(withTitle:"64 MiB block"); XCTAssertTrue(block.sendAction(block.action,to:block.target))
        solid.selectItem(withTitle:"Off"); XCTAssertTrue(solid.sendAction(solid.action,to:solid.target))
        XCTAssertFalse(block.isEnabled); XCTAssertTrue(create.isEnabled)
        solid.selectItem(withTitle:"On"); XCTAssertTrue(solid.sendAction(solid.action,to:solid.target))
        var submitted = false
        sheet.complete = { _, _, _, format, _, _, options in
            submitted = true; XCTAssertEqual(format,.sevenZip)
            XCTAssertEqual(options?.solid,.on(blockBytes:64<<20))
        }
        create.performClick(nil); XCTAssertTrue(submitted)
    }
    @MainActor
    func testAdvancedDisclosureUnsafeCombinationAndSubmission() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("source".utf8).write(to:file)
        defer { try? FileManager.default.removeItem(at:file) }
        let sheet = CreateArchiveSheet(sources:[file],encrypted:false)
        defer { sheet.close() }
        let root = try XCTUnwrap(sheet.window?.contentView)
        let format = try XCTUnwrap(views(root).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("ZIP (.zip)") })
        let create = try XCTUnwrap(views(root).compactMap { $0 as? NSButton }.first { $0.title == "Create" })
        XCTAssertTrue(create.isEnabled,"ZIP has no advanced preflight")
        format.selectItem(at:1); XCTAssertTrue(format.sendAction(format.action,to:format.target))
        for _ in 0..<400 where !create.isEnabled { try await Task.sleep(nanoseconds:25_000_000) }
        XCTAssertTrue(create.isEnabled)
        let disclosure = try XCTUnwrap(views(root).compactMap { $0 as? NSButton }.first { $0.bezelStyle == .disclosure })
        XCTAssertEqual(disclosure.state,.off)
        disclosure.performClick(nil)
        let dictionary = try XCTUnwrap(views(root).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("64 MiB") })
        let threads = try XCTUnwrap(views(root).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("1") })
        XCTAssertEqual(dictionary.titleOfSelectedItem,"Auto"); XCTAssertEqual(threads.titleOfSelectedItem,"Auto")
        XCTAssertFalse(dictionary.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(views(root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Approximate compression memory:") })
        dictionary.selectItem(withTitle:"64 MiB"); XCTAssertTrue(dictionary.sendAction(dictionary.action,to:dictionary.target))
        XCTAssertFalse(create.isEnabled)
        XCTAssertTrue(views(root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("exceeds Arkiv’s 2 GiB") })
        threads.selectItem(withTitle:"1"); XCTAssertTrue(threads.sendAction(threads.action,to:threads.target))
        XCTAssertTrue(create.isEnabled)
        format.selectItem(at:0); XCTAssertTrue(format.sendAction(format.action,to:format.target))
        XCTAssertTrue(disclosure.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(create.isEnabled)
        format.selectItem(at:1); XCTAssertTrue(format.sendAction(format.action,to:format.target))
        var submitted = false
        sheet.complete = { destination, _, preset, format, _, _, options in
            submitted = true; XCTAssertNotNil(destination); XCTAssertEqual(preset,.normal); XCTAssertEqual(format,.sevenZip)
            XCTAssertEqual(options,SevenZipCreationOptions(dictionaryBytes:64*1024*1024,threads:1))
        }
        create.performClick(nil)
        XCTAssertTrue(submitted)
    }
    @MainActor
    func testAvailablePresetsDefaultsFormatSwitchAndSubmission() async throws {
        _ = NSApplication.shared
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("input".utf8).write(to:source)
        defer { try? FileManager.default.removeItem(at:source) }
        for wanted: ArchiveFormat in [.zip,.sevenZip] {
            for preset in CompressionPreset.available(for:wanted) {
                let sheet = CreateArchiveSheet(sources:[source],encrypted:false)
                defer { sheet.close() }
                let all = views(try XCTUnwrap(sheet.window?.contentView))
                let format = try XCTUnwrap(all.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("ZIP (.zip)") })
                let compression = try XCTUnwrap(all.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("Fastest") })
                XCTAssertEqual(compression.itemTitles,["Store","Fastest","Fast","Normal","Maximum"])
                XCTAssertEqual(compression.titleOfSelectedItem,"Normal")
                format.selectItem(at:wanted == .zip ? 0 : 1)
                XCTAssertTrue(format.sendAction(format.action,to:format.target))
                XCTAssertEqual(compression.itemTitles,CompressionPreset.available(for:wanted).map(\.title))
                XCTAssertEqual(compression.titleOfSelectedItem,"Normal")
                compression.selectItem(withTitle:preset.title)
                let create = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.title == "Create" })
                for _ in 0..<400 where !create.isEnabled { try await Task.sleep(nanoseconds:25_000_000) }
                XCTAssertTrue(create.isEnabled)
                var submitted = false
                sheet.complete = { destination, _, selected, format, password, _, options in
                    submitted = true
                    XCTAssertNotNil(destination)
                    XCTAssertEqual(selected,preset)
                    XCTAssertEqual(format,wanted)
                    XCTAssertNil(password)
                    XCTAssertEqual(options,wanted == .sevenZip ? SevenZipCreationOptions() : nil)
                }
                try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.title == "Create" }).performClick(nil)
                XCTAssertTrue(submitted)
            }
        }
        let encrypted = CreateArchiveSheet(sources:[source],encrypted:true)
        defer { encrypted.close() }
        let controls = views(try XCTUnwrap(encrypted.window?.contentView))
        let format = try XCTUnwrap(controls.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("ZIP (.zip)") })
        XCTAssertEqual(format.indexOfSelectedItem,1)
        XCTAssertEqual(controls.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("Ultra") }?.titleOfSelectedItem,"Normal")
        XCTAssertEqual(controls.compactMap { $0 as? NSButton }.first { $0.title == "Protect with AES-256 password" }?.state,.on)
        XCTAssertEqual(controls.compactMap { $0 as? NSButton }.first { $0.title == "Encrypt filenames" }?.state,.on)
    }
}
