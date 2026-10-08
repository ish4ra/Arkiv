import XCTest
import ArkivCore
@testable import ArkivPresentation

final class BrowserPresentationTests: XCTestCase {
    private let archive = URL(fileURLWithPath: "/tmp/example.zip")
    private func state(_ url: URL? = nil, available: Bool = true) -> ArchiveWindowState {
        ArchiveWindowState(id: UUID(), archiveURL: url, isAvailable: available)
    }
    func testOpenReusesPreferredEmptyWindow() {
        let first = state(), preferred = state()
        XCTAssertEqual(BrowserPresentation.window(for: archive, preferred: preferred.id, among: [first, preferred]), preferred.id)
    }
    func testOpenReusesOtherEmptyWindowWhenPreferredIsOccupied() {
        let occupied = state(URL(fileURLWithPath: "/tmp/other.zip")), empty = state()
        XCTAssertEqual(BrowserPresentation.window(for: archive, preferred: occupied.id, among: [occupied, empty]), empty.id)
    }
    func testOpenCreatesWindowWhenOnlyBusyOrOccupiedWindowsExist() {
        let busy = state(available: false), occupied = state(URL(fileURLWithPath: "/tmp/other.zip"))
        XCTAssertNil(BrowserPresentation.window(for: archive, preferred: busy.id, among: [busy, occupied]))
        XCTAssertNil(BrowserPresentation.window(for: archive, preferred: nil, among: []))
    }
    func testRepeatedOpenFocusesLoadedOrPendingArchive() {
        let existing = state(archive, available: false), empty = state()
        XCTAssertEqual(BrowserPresentation.window(for: archive, preferred: empty.id, among: [empty, existing]), existing.id)
    }
    func testBatchOpenReservesFirstEmptyWindow() {
        let reserved = state(archive, available: false), empty = state()
        let next = URL(fileURLWithPath: "/tmp/next.zip")
        XCTAssertEqual(BrowserPresentation.window(for: next, preferred: reserved.id, among: [reserved, empty]), empty.id)
    }
    private var rows: [BrowserRow] {
        ArchiveIndex(entries: [
            ArchiveEntry(id: 0, path: "folder/a.txt", size: 9, kind: .file),
            ArchiveEntry(id: 1, path: "b.txt", size: 20, kind: .file),
            ArchiveEntry(id: 2, path: "a.txt", size: 10, kind: .file)
        ]).children(of: "")
    }
    func testSortingAndFilteringKeepSelectionOnSamePaths() {
        let sorted = BrowserPresentation.sorted(rows, by: "size", ascending: false)
        XCTAssertEqual(sorted.map(\.path), ["b.txt", "a.txt", "folder"])
        let selection = BrowserPresentation.selection(["a.txt", "b.txt"], in: sorted)
        XCTAssertEqual(selection, IndexSet([0, 1]))
        let filtered = sorted.filter { $0.path == "a.txt" }
        XCTAssertEqual(BrowserPresentation.selection(["a.txt", "b.txt"], in: filtered), IndexSet(integer: 0))
    }
    func testNameSortUsesNaturalOrderWithFoldersFirst() {
        let values = ArchiveIndex(entries: [
            ArchiveEntry(id: 0, path: "z/f", size: 0, kind: .file),
            ArchiveEntry(id: 1, path: "file10", size: 0, kind: .file),
            ArchiveEntry(id: 2, path: "file2", size: 0, kind: .file)
        ]).children(of: "")
        XCTAssertEqual(BrowserPresentation.sorted(values, by: "name", ascending: true).map(\.path), ["z", "file2", "file10"])
    }
    func testSelectedSizeOnlyUsesKnownSizes() {
        XCTAssertEqual(BrowserPresentation.selectedSize(rows.filter { !$0.isDirectory }), 30)
        XCTAssertNil(BrowserPresentation.selectedSize(rows))
        XCTAssertNil(BrowserPresentation.selectedSize([]))
        let overflowing = ArchiveIndex(entries: [
            ArchiveEntry(id: 0, path: "a", size: .max, kind: .file),
            ArchiveEntry(id: 1, path: "b", size: 1, kind: .file)
        ]).children(of: "")
        XCTAssertNil(BrowserPresentation.selectedSize(overflowing))
    }
}
