import AppKit
import ArkivCore

/// Shared by browser and Finder completion handlers, each called once per result.
enum ExtractionFeedback {
    static func showWarnings(_ report: ArchiveExtractionReport, parent: NSWindow? = nil) {
        guard !report.warnings.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Extraction completed with warnings"
        alert.informativeText = "Some entries could not be safely created. Extracted files are in \(report.url.path)."
        alert.alertStyle = .warning
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.string = report.warnings.map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        alert.accessoryView = scroll
        if let parent { alert.beginSheetModal(for: parent) }
        else { NSApp.activate(ignoringOtherApps: true); alert.runModal() }
    }
    static func completed<T>(_ result: Result<T, Error>, play: () -> Void = { CompletionSoundPlayer.shared.play() }) {
        if case .success = result { play() }
    }
}

private final class CompletionSoundPlayer: NSObject, NSSoundDelegate {
    static let shared = CompletionSoundPlayer()
    private var active: [NSSound] = []

    func play() {
        // NSSound uses the normal system output; playback is asynchronous.
        // Keep separate instances so simultaneous completions are not dropped.
        guard let url = Bundle.main.url(forResource: "Arkiv-Extraction-Complete", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        sound.delegate = self
        active.append(sound)
        if !sound.play() { active.removeAll { $0 === sound } }
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        DispatchQueue.main.async { self.active.removeAll { $0 === sound } }
    }
}
