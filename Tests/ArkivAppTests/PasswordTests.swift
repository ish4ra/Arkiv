import XCTest
import ArkivCore
@testable import ArkivApp

final class PasswordTests: XCTestCase {
    func testCreationRequiresMatchingNonemptyPasswordsAndPreservesUnicodeSpaces() throws {
        XCTAssertThrowsError(try CreationPasswordPolicy.validate("", confirmation: ""))
        XCTAssertThrowsError(try CreationPasswordPolicy.validate("first", confirmation: "second"))
        XCTAssertThrowsError(try CreationPasswordPolicy.validate("a\0b", confirmation: "a\0b"))
        let long = String(repeating: "x", count: 1025)
        XCTAssertThrowsError(try CreationPasswordPolicy.validate(long, confirmation: long))
        let exact = " 日本語 🐘 spaces "
        XCTAssertEqual(try CreationPasswordPolicy.validate(exact, confirmation: exact), exact)
    }
    func testOnlyPasswordFailuresPromptForRetry() {
        XCTAssertTrue(ArchivePasswordPrompt.isPasswordFailure(ArchiveFailure.passwordRequired))
        XCTAssertTrue(ArchivePasswordPrompt.isPasswordFailure(ArchiveFailure.wrongPassword))
        XCTAssertFalse(ArchivePasswordPrompt.isPasswordFailure(ArchiveFailure.cancelled))
        XCTAssertFalse(ArchivePasswordPrompt.isPasswordFailure(ArchiveFailure.message("Damaged archive")))
    }
}
