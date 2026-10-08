import XCTest
@testable import ArkivCore

final class BrowserTests: XCTestCase {
    let entries = [
        ArchiveEntry(id: 0, path: "a/hello.txt", size: 5, kind: .file),
        ArchiveEntry(id: 1, path: "a/deep/🦊.txt", size: 9, kind: .file),
        ArchiveEntry(id: 2, path: "top.txt", size: 3, kind: .file)
    ]
    func testImplicitFoldersAndImmediateChildren() {
        let index = ArchiveIndex(entries: entries)
        XCTAssertEqual(index.children(of: "").map(\.path), ["a", "top.txt"])
        XCTAssertEqual(index.children(of: "a").map(\.path), ["a/deep", "a/hello.txt"])
        XCTAssertTrue(index.children(of: "missing").isEmpty)
    }
    func testFolderSelectionExpandsAndDeduplicates() {
        let index = ArchiveIndex(entries: entries)
        XCTAssertEqual(index.entryIDs(for: ["a", "a/hello.txt"]), [0, 1])
        XCTAssertEqual(index.entryIDs(for: ["top.txt"]), [2])
        XCTAssertEqual(index.entryIDs(for: ["unknown"]), [])
    }
    func testSearchDoesNotExtractAndMatchesFullPath() {
        let index = ArchiveIndex(entries: entries)
        XCTAssertEqual(index.search("DEEP").map(\.path), ["a/deep", "a/deep/🦊.txt"])
    }
    func testExplicitDirectoryDoesNotDuplicateImplicit() {
        let index = ArchiveIndex(entries: entries + [ArchiveEntry(id: 3, path: "a/", size: 0, kind: .directory)])
        XCTAssertEqual(index.children(of: "").count, 2)
        XCTAssertEqual(index.entryIDs(for: ["a"]), [0, 1, 3])
    }
    func testPrefixIsNotSibling() {
        let index = ArchiveIndex(entries: entries + [ArchiveEntry(id: 3, path: "abc/file", size: 0, kind: .file)])
        XCTAssertEqual(index.entryIDs(for: ["a"]), [0, 1])
    }
}
