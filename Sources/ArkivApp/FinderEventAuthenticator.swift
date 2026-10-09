import AppKit
import Security

/// Authenticates the OS-supplied Apple-event sender, never URL fields or a PID.
/// Brokered/missing identity and stale extension builds fall back to consent.
enum FinderEventAuthenticator {
    static func isTrusted(_ url: URL, event: NSAppleEventDescriptor?,
                          verifySender: (Data) -> Bool = matchesEmbeddedExtension) -> Bool {
        guard let event, event.eventClass == AEEventClass(kInternetEventClass),
              event.eventID == AEEventID(kAEGetURL),
              let sender = event.attributeDescriptor(forKeyword: keySenderAuditTokenAttr),
              sender.descriptorType == typeAuditToken else { return false }
        let actual = event.attributeDescriptor(forKeyword: keyActualSenderAuditToken)
        if let actual, actual.descriptorType != typeAuditToken { return false }
        return validateIdentity(url, eventURL: event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
                                sender: sender.data, actual: actual?.data, verifySender: verifySender)
    }

    static func validateIdentity(_ url: URL, eventURL: String?, sender: Data, actual: Data?,
                                 verifySender: (Data) -> Bool) -> Bool {
        guard eventURL == url.absoluteString, sender.count == 32 else { return false }
        // Do not elevate delegated/brokered events with differing actual identity.
        if let actual, actual != sender { return false }
        return verifySender(sender)
    }

    static func matchesEmbeddedExtension(_ auditToken: Data) -> Bool {
        matchesCode(auditToken, at: Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/ArkivFinderSync.appex"))
    }

    static func matchesCode(_ auditToken: Data, at expectedURL: URL) -> Bool {
        guard auditToken.count == 32 else { return false }
        var expected: SecStaticCode?
        guard SecStaticCodeCreateWithPath(expectedURL as CFURL, [], &expected) == errSecSuccess,
              let expected,
              SecStaticCodeCheckValidity(expected, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(expected, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data, !hash.isEmpty else { return false }
        // An identifier alone is forgeable with ad-hoc signing. Pin exact code.
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        var sender: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit as String: auditToken] as CFDictionary, [], &sender) == errSecSuccess,
              let sender else { return false }
        return SecCodeCheckValidity(sender, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}
