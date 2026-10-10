import AppKit
import ArkivCore

/// Passwords exist only in these controls and the active engine request, never preferences/IPC.
final class PasswordEntryView: NSStackView {
    private let secret = NSSecureTextField(string: "")
    private let visible = NSTextField(string: "")
    private let confirmation = NSSecureTextField(string: "")
    private let visibleConfirmation = NSTextField(string: "")
    private let show = NSButton(checkboxWithTitle: "Show Password", target: nil, action: nil)
    private let confirms: Bool
    var value: String { show.state == .on ? visible.stringValue : secret.stringValue }
    var confirmedValue: String { show.state == .on ? visibleConfirmation.stringValue : confirmation.stringValue }

    init(confirm: Bool) {
        confirms = confirm
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 6
        secret.placeholderString = "Password"; visible.placeholderString = "Password"
        confirmation.placeholderString = "Confirm Password"; visibleConfirmation.placeholderString = "Confirm Password"
        secret.setAccessibilityLabel("Password"); visible.setAccessibilityLabel("Password")
        confirmation.setAccessibilityLabel("Confirm Password"); visibleConfirmation.setAccessibilityLabel("Confirm Password")
        for field in [secret, visible] as [NSTextField] { addArrangedSubview(field); field.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
        if confirm {
            for field in [confirmation, visibleConfirmation] as [NSTextField] { addArrangedSubview(field); field.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
        }
        visible.isHidden = true; visibleConfirmation.isHidden = true
        show.target = self; show.action = #selector(toggleVisibility)
        addArrangedSubview(show)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func toggleVisibility() {
        if show.state == .on {
            visible.stringValue = secret.stringValue; visibleConfirmation.stringValue = confirmation.stringValue
            secret.stringValue = ""; confirmation.stringValue = ""
        } else {
            secret.stringValue = visible.stringValue; confirmation.stringValue = visibleConfirmation.stringValue
            visible.stringValue = ""; visibleConfirmation.stringValue = ""
        }
        secret.isHidden = show.state == .on; visible.isHidden = show.state != .on
        confirmation.isHidden = show.state == .on || !confirms
        visibleConfirmation.isHidden = show.state != .on || !confirms
    }
    func clear() {
        secret.stringValue = ""; visible.stringValue = ""
        confirmation.stringValue = ""; visibleConfirmation.stringValue = ""
    }
}

enum CreationPasswordPolicy {
    static func validate(_ password: String, confirmation: String) throws -> String {
        guard !password.isEmpty, password.utf8.count <= 1024, !password.contains("\0") else {
            throw ArchiveFailure.message("Enter a password of up to 1,024 UTF-8 bytes, without a null character.")
        }
        guard password == confirmation else { throw ArchiveFailure.message("Passwords do not match.") }
        return password // Deliberately preserve spaces and Unicode exactly.
    }
}

enum ArchivePasswordPrompt {
    static func isPasswordFailure(_ error: Error) -> Bool {
        if case ArchiveFailure.passwordRequired = error { return true }
        if case ArchiveFailure.wrongPassword = error { return true }
        return false
    }
    static func ask(archive: URL, retry: Bool, parent: NSWindow? = nil, completion: @escaping (String?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = retry ? "Couldn’t unlock archive" : "Unlock archive"
        alert.informativeText = (retry ? "The password was incorrect or the encrypted archive is damaged. Try again.\n\n" : "") + archive.lastPathComponent + "\nYour password is not saved."
        let fields = PasswordEntryView(confirm: false)
        fields.setFrameSize(NSSize(width: 320, height: 64))
        alert.accessoryView = fields
        alert.addButton(withTitle: "Unlock"); alert.addButton(withTitle: "Cancel")
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let password = response == .alertFirstButtonReturn ? fields.value : nil
            fields.clear(); completion(password)
        }
        if let parent { alert.beginSheetModal(for: parent, completionHandler: finish) }
        else { finish(alert.runModal()) }
    }
}
