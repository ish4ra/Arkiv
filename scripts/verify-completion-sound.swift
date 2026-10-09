import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let sound = NSSound(contentsOf: url, byReference: false),
      abs(sound.duration - 0.55) < 0.001 else {
    fatalError("Packaged Arkiv completion sound cannot be decoded or has incorrect duration")
}
print("Verified packaged completion sound decodes in AppKit (without playback)")
