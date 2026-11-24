// Signs and verifies Arkiv's document-icon theme catalogue with CryptoKit.
//
//   swift scripts/document-icon-theme-catalog.swift sign <payload.json> <catalog.json>
//       private key: ARKIV_THEME_PRIVATE_ED_KEY (base64 of the 32-byte Ed25519 seed)
//   swift scripts/document-icon-theme-catalog.swift verify <catalog.json> [<payload.json>]
//       public key: ARKIV_THEME_PUBLIC_ED_KEY (base64 of the 32-byte public key)
//   swift scripts/document-icon-theme-catalog.swift verify-keypair
//       checks ARKIV_THEME_PRIVATE_ED_KEY against ARKIV_THEME_PUBLIC_ED_KEY (prints key IDs only)
//   swift scripts/document-icon-theme-catalog.swift production-key <directory outside any Git checkout>
//       the production key pair, generated on the maintainer's own Mac; never overwrites
//   swift scripts/document-icon-theme-catalog.swift test-key <directory outside any Git checkout>
//       a throwaway key pair for CI and local tests; never configure it in GitHub
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

/// Writes a new key pair to `path`, which must be outside any Git checkout,
/// without overwriting anything. The private key file is 0600 in a 0700 folder
/// and is never printed.
func writeKeyPair(_ path: String, prefix: String, label: String) {
    let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    var probe = directory
    while probe.path != "/" {
        if FileManager.default.fileExists(atPath: probe.appendingPathComponent(".git").path) {
            fail("Refusing to write a signing key inside a Git checkout (\(probe.path))")
        }
        probe.deleteLastPathComponent()
    }
    let manager = FileManager.default
    let privateFile = directory.appendingPathComponent(prefix + ".key"), publicFile = directory.appendingPathComponent(prefix + ".pub")
    for file in [privateFile, publicFile] where manager.fileExists(atPath: file.path) {
        fail("Refusing to overwrite \(file.path); move it away first if you really mean to replace this key")
    }
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else { fail("\(directory.path) is not a folder") }
    } else {
        do { try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { fail("Cannot create \(directory.path)") }
    }
    let privateKey = Curve25519.Signing.PrivateKey()
    let publicKey = privateKey.publicKey.rawRepresentation
    refuseSparkle(privateKey: privateKey.rawRepresentation, publicKey: publicKey)
    // O_EXCL: never replace a file that appeared in the meantime.
    let fd = open(privateFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { fail("Cannot create \(privateFile.path)") }
    let secret = Data(privateKey.rawRepresentation.base64EncodedString().utf8)
    let written = secret.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    close(fd)
    guard written == secret.count else { fail("Cannot write \(privateFile.path)") }
    guard manager.createFile(atPath: publicFile.path, contents: Data(publicKey.base64EncodedString().utf8), attributes: [.posixPermissions: 0o644]) else {
        fail("Cannot write \(publicFile.path)")
    }
    print("Wrote a new \(label) key pair, key \(keyID(publicKey)):")
    print("  private key (keep secret, mode 0600): \(privateFile.path)")
    print("  public key: \(publicFile.path)")
    print("  public key value: \(publicKey.base64EncodedString())")
    if label == "TEST" { print("  TEST key: never configure it in GitHub or use it for published catalogues") }
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
case ("production-key", 2):
    // The real signing key: generate it on the maintainer's own Mac only.
    writeKeyPair(args[args.startIndex + 1], prefix: "arkiv-theme-signing", label: "PRODUCTION")
case ("test-key", 2):
    // Throwaway keys for CI and local tests. Never configure them in GitHub.
    writeKeyPair(args[args.startIndex + 1], prefix: "theme-test-signing", label: "TEST")
case ("verify-keypair", 1):
    // Before publishing: the private key in the environment must belong to the
    // public key the app embeds. Prints key IDs only.
    let seed = key("ARKIV_THEME_PRIVATE_ED_KEY"), configured = key("ARKIV_THEME_PUBLIC_ED_KEY")
    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { fail("Invalid private key") }
    refuseSparkle(privateKey: seed, publicKey: privateKey.publicKey.rawRepresentation)
    refuseSparkle(privateKey: nil, publicKey: configured)
    guard privateKey.publicKey.rawRepresentation == configured else {
        fail("ARKIV_THEME_PRIVATE_ED_KEY (key \(keyID(privateKey.publicKey.rawRepresentation))) does not match ARKIV_THEME_PUBLIC_ED_KEY (key \(keyID(configured)))")
    }
    print("Theme signing key pair matches (key \(keyID(configured)))")
default:
    fail("Usage: sign <payload> <catalog> | verify <catalog> [<payload>] | verify-keypair | production-key <directory> | test-key <directory>")
}
