import AppKit

/// Shared by browser and Finder completion handlers, each called once per result.
enum ExtractionFeedback {
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
