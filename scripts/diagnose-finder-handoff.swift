// macOS CI: deliver all eight custom URLs through real NSWorkspace to the packaged
// Arkiv executable, then await AppKit receiver acknowledgements. No extraction.
import AppKit

func runProbe(firstCommand: String) throws -> Int32 {
let app = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let nonce = UUID().uuidString
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Arkiv-handoff-" + nonce)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let archive = root.appendingPathComponent("日本語 & # percent%.zip")
try Data([0x50, 0x4b, 0x05, 0x06] + Array(repeating: UInt8(0), count: 18)).write(to: archive)
let expected: Set<String> = ["zip", "sevenZip", "password", "addArchive", "open", "extractHere", "extractFolder", "extractTo"]
var received: Set<String> = []
var failure = false
var launched = false
var warmCompleted = false
var child: NSRunningApplication?
let center = DistributedNotificationCenter.default()
let observer = center.addObserver(forName: Notification.Name("xyz.isharalakshan.arkiv.finder-delivery-diagnostic"),
                                  object: nonce, queue: .main) { notification in
    guard let command = notification.userInfo?["command"] as? String, expected.contains(command) else {
        failure = true; return
    }
    if command == firstCommand, notification.userInfo?["browserWindows"] as? Int != 0 {
        failure = true; return
    }
    received.insert(command)
}
defer {
    center.removeObserver(observer)
    // Only the isolated application instance created by this probe is cleaned up.
    if let child, !child.isTerminated {
        child.forceTerminate()
        let cleanupDeadline = Date().addingTimeInterval(5)
        while !child.isTerminated && Date() < cleanupDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
let commands = [firstCommand] + ["zip", "sevenZip", "password", "addArchive", "open", "extractHere", "extractFolder", "extractTo"].filter { $0 != firstCommand }
let urls = commands.map { command -> URL in
    var components = URLComponents()
    components.scheme = "arkiv-finder"; components.host = ["zip", "sevenZip", "password", "addArchive"].contains(command) ? "create" : "action"; components.path = "/v1"
    components.queryItems = [URLQueryItem(name: "command", value: command), URLQueryItem(name: "file", value: archive.absoluteString)]
    return components.url!
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.arguments = ["--verify-finder-url-delivery", nonce, "--finder-action"]
configuration.addsToRecentItems = false
configuration.activates = false
NSWorkspace.shared.open([urls[0]], withApplicationAt: app, configuration: configuration) { application, error in
    DispatchQueue.main.async {
        child = application
        launched = application != nil && error == nil
        guard launched else { failure = true; return }
        // Also exercise delivery to the already-running app, without new arguments.
        let existing = NSWorkspace.OpenConfiguration()
        existing.addsToRecentItems = false
        NSWorkspace.shared.open(Array(urls.dropFirst()), withApplicationAt: app, configuration: existing) { running, error in
            DispatchQueue.main.async {
                warmCompleted = true
                if error != nil || running?.processIdentifier != child?.processIdentifier { failure = true }
            }
        }
    }
}
let deadline = Date().addingTimeInterval(30)
while !failure && (!launched || !warmCompleted || received != expected) && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
guard launched, warmCompleted, !failure, received == expected else {
    fputs("Packaged Finder URL delivery failed or did not reach all eight app routing callbacks\n", stderr)
    return 1
}
print("Verified real NSWorkspace → packaged AppKit URL receipt → all eight Finder action callbacks (read-only extraction dispatch intercepted)")

return 0
}
for command in ["zip", "sevenZip", "extractHere", "extractFolder"] {
    let result = try runProbe(firstCommand: command)
    if result != 0 { exit(result) }
}
exit(0)
