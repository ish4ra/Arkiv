// Verify against the public key embedded in the payload, not merely the signing key.
import Foundation
import CryptoKit
let args = CommandLine.arguments
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[1])), format: nil) as! [String: Any]
guard let encoded = info["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: encoded),
      let signature = Data(base64Encoded: args[3]) else { fatalError("Missing update trust metadata") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: archive) else { fatalError("Update signature does not match the embedded public key") }
print("Verified update archive against embedded EdDSA public key")
