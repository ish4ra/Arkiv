import Foundation
import CArkiv

/// Read-only assessment, not an editing permission or reusable password token.
public struct SevenZipEncryptionPolicy: Equatable, Sendable {
    public let dataEncrypted: Bool
    public let headersEncrypted: Bool
    public let mixedEncryption: Bool
    public let supportedLayout: Bool
    public let allDataVerified: Bool
    public var eligibleForFutureEncryptedModification: Bool {
        (dataEncrypted || headersEncrypted) && !mixedEncryption && supportedLayout && allDataVerified
    }
    /// Eligibility is only a hint: Each edit revalidates the original with a fresh password.
    public var eligibleForEncryptedDeletion: Bool { eligibleForFutureEncryptedModification }
    public var eligibleForEncryptedRenaming: Bool { eligibleForFutureEncryptedModification }
    /// No general encrypted-edit permission: Replace remains disabled.
    public var modificationEnabled: Bool { false }
    public var readOnlyReason: String {
        if mixedEncryption { return "Mixed encrypted and plain data remains read-only." }
        if !supportedLayout { return "Unsupported 7z layout or metadata remains read-only." }
        return "Only Add, Delete and Rename are available for eligible encrypted 7z archives."
    }
}

public struct SevenZipPolicyInspector: Sendable {
    public init() {}
    /// Requests a credential for THIS operation; never reads credentials from the
    /// unlocked spool or stores them in a snapshot/result. No editing is performed.
    public func prepareEncryptedEdit(in snapshot: ArchiveSnapshot, cancellation: ArchiveCancellation,
                                     requestPassword: () throws -> String?) throws -> SevenZipEncryptionPolicy {
        do { return try inspect(snapshot, password: nil, cancellation: cancellation) }
        catch ArchiveFailure.passwordRequired {
            guard let password = try requestPassword() else { throw ArchiveFailure.cancelled }
            return try inspect(snapshot, password: password, cancellation: cancellation)
        }
    }
    public func inspect(_ snapshot: ArchiveSnapshot, password: String?, cancellation: ArchiveCancellation) throws -> SevenZipEncryptionPolicy {
        try validateArchivePassword(password)
        if cancellation.isCancelled { throw ArchiveFailure.cancelled }
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed. Reopen it before inspecting encryption policy.")
        }
        var url = snapshot.url.standardizedFileURL
        #if os(macOS)
        if url.path.hasPrefix("/var/") || url.path.hasPrefix("/tmp/") {
            url = URL(fileURLWithPath: "/private" + url.path)
        }
        #endif
        var flags: UInt32 = 0
        let result = arkiv_inspect_seven_policy(url.path, password, &flags, cancellation.pointer)
        guard try SourceStamp(snapshot.url) == snapshot.stamp else {
            throw ArchiveFailure.message("Archive changed during encryption policy validation.")
        }
        switch result {
        case 0: break
        case 2: throw ArchiveFailure.cancelled
        case 4: throw ArchiveFailure.passwordRequired
        case 5: throw ArchiveFailure.wrongPassword
        default: throw ArchiveFailure.message("Cannot safely verify the original 7z encryption policy.")
        }
        let pathsSupported = (try? ArchiveAdditionUpdater.validateSevenPaths(snapshot)) != nil
        return SevenZipEncryptionPolicy(dataEncrypted: flags & 1 != 0, headersEncrypted: flags & 2 != 0,
                                        mixedEncryption: flags & 4 != 0,
                                        supportedLayout: flags & 8 != 0 && pathsSupported,
                                        allDataVerified: flags & 16 != 0)
    }
}
