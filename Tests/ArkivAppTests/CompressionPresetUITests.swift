import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp

final class CompressionPresetUITests: XCTestCase {
    private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    @MainActor
    func testAvailablePresetsDefaultsFormatSwitchAndSubmission() throws {
        _ = NSApplication.shared
        let source = URL(fileURLWithPath:"/tmp/preset-source.txt")
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
                var submitted = false
                sheet.complete = { destination, _, selected, format, password, _ in
                    submitted = true
                    XCTAssertNotNil(destination)
                    XCTAssertEqual(selected,preset)
                    XCTAssertEqual(format,wanted)
                    XCTAssertNil(password)
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
