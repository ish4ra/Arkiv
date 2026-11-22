// Signs and verifies Arkiv's document-icon theme catalogue with CryptoKit.
//
//   swift scripts/document-icon-theme-catalog.swift sign <payload.json> <catalog.json>
//       private key: ARKIV_THEME_PRIVATE_ED_KEY (base64 of the 32-byte Ed25519 seed)
//   swift scripts/document-icon-theme-catalog.swift verify <catalog.json> [<payload.json>]
//       public key: ARKIV_THEME_PUBLIC_ED_KEY (base64 of the 32-byte public key)
//   swift scripts/document-icon-theme-catalog.swift test-key <directory outside the repository>
//       writes an isolated, throwaway key pair for CI and local tests
//
// The theme key is dedicated: this tool refuses Sparkle's update key. The
// signed message is the context below followed by the exact payload bytes;
// it must match ThemeCatalogSignature in Sources/ArkivThemes (a test checks).
import CryptoKit
import Foundation

let context = Data("Arkiv document icon theme catalogue v1\n".utf8)
let env = ProcessInfo.processInfo.environment
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
func key(_ name: String) -> Data {
    guard let text = env[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { fail("\(name) is not set") }
    guard let data = Data(base64Encoded: text), data.count == 32 else { fail("\(name) must be base64 of 32 bytes") }
    return data
}
func keyID(_ publicKey: Data) -> String { SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined() }
func read(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("Cannot read \(path)") }
    return data
}
/// The theme key must never be Sparkle's update key, in either direction.
func refuseSparkle(privateKey: Data?, publicKey: Data) {
    for name in ["SPARKLE_PRIVATE_ED_KEY", "SPARKLE_PUBLIC_ED_KEY"] {
        guard let text = env[name]?.trimmingCharacters(in: .whitespacesAndNewlines), let other = Data(base64Encoded: text) else { continue }
        if other == publicKey || (privateKey != nil && (other == privateKey || other.prefix(32) == privateKey)) {
            fail("Refusing: the document-icon theme key must not be Sparkle's update key")
        }
        if name == "SPARKLE_PRIVATE_ED_KEY", other.count >= 32,
           let derived = try? Curve25519.Signing.PrivateKey(rawRepresentation: other.prefix(32)), derived.publicKey.rawRepresentation == publicKey {
            fail("Refusing: the document-icon theme key must not be Sparkle's update key")
        }
    }
}

let args = CommandLine.arguments.dropFirst()
switch (args.first, args.count) {
case ("sign", 3):
    let seed = key("ARKIV_THEME_PRIVATE_ED_KEY")
    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { fail("Invalid private key") }
    let publicKey = privateKey.publicKey.rawRepresentation
    refuseSparkle(privateKey: seed, publicKey: publicKey)
    let payload = read(args[args.startIndex + 1])
    guard (try? JSONSerialization.jsonObject(with: payload)) is [String: Any] else { fail("Payload is not a JSON object") }
    guard let signature = try? privateKey.signature(for: context + payload) else { fail("Signing failed") }
    let envelope: [String: Any] = ["schema": 1, "keyID": keyID(publicKey), "payload": payload.base64EncodedString(),
                                   "signature": signature.base64EncodedString()]
    let data = try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    guard privateKey.publicKey.isValidSignature(signature, for: context + payload) else { fail("Self-verification failed") }
    try! data.write(to: URL(fileURLWithPath: args[args.startIndex + 2]))
    print("Signed catalogue with key \(keyID(publicKey)) (\(payload.count) payload bytes)")
case ("verify", 2), ("verify", 3):
    let publicKeyData = key("ARKIV_THEME_PUBLIC_ED_KEY")
    refuseSparkle(privateKey: nil, publicKey: publicKeyData)
    guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else { fail("Invalid public key") }
    guard let object = try? JSONSerialization.jsonObject(with: read(args[args.startIndex + 1])) as? [String: Any],
          Set(object.keys) == ["schema", "keyID", "payload", "signature"], object["schema"] as? Int == 1,
          object["keyID"] as? String == keyID(publicKeyData),
          let payload = (object["payload"] as? String).flatMap({ Data(base64Encoded: $0) }),
          let signature = (object["signature"] as? String).flatMap({ Data(base64Encoded: $0) }),
          publicKey.isValidSignature(signature, for: context + payload) else { fail("Catalogue signature is NOT valid") }
    if args.count == 3, payload != read(args[args.startIndex + 2]) { fail("Signed payload differs from the expected payload") }
    print("Catalogue signature valid (key \(keyID(publicKeyData)))")
case ("test-key", 2):
    let directory = URL(fileURLWithPath: args[args.startIndex + 1]).standardizedFileURL
    let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["-C", FileManager.default.currentDirectoryPath, "rev-parse", "--show-toplevel"]
    let pipe = Pipe(); git.standardOutput = pipe; git.standardError = Pipe()
    try? git.run(); git.waitUntilExit()
    let top = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if !top.isEmpty, directory.path == top || directory.path.hasPrefix(top + "/") { fail("Refusing to write a key inside the repository") }
    let privateKey = Curve25519.Signing.PrivateKey()
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let privateFile = directory.appendingPathComponent("theme-test-signing.key")
    try! Data(privateKey.rawRepresentation.base64EncodedString().utf8).write(to: privateFile)
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFile.path)
    try! Data(privateKey.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: directory.appendingPathComponent("theme-test-signing.pub"))
    print("Wrote an isolated TEST key pair \(keyID(privateKey.publicKey.rawRepresentation)) to \(directory.path); never use it for production")
default:
    fail("Usage: sign <payload> <catalog> | verify <catalog> [<payload>] | test-key <directory>")
}
