import CryptoKit
import Foundation

/// Signed catalogue envelope (`catalog.json`):
///
///     {"schema":1,"keyID":"<16 hex>","payload":"<base64 JSON>","signature":"<base64 Ed25519>"}
///
/// The signature covers `ThemeCatalogSignature.context + payload bytes`, made
/// with the dedicated document-icon theme key (never Sparkle's update key).
public enum ThemeCatalogSignature {
    public static let context = Data("Arkiv document icon theme catalogue v1\n".utf8)
    public static func message(_ payload: Data) -> Data { context + payload }
    /// First 8 bytes of SHA-256 of the raw public key, in hex.
    public static func keyID(_ publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    /// Test and tooling helper: build an envelope for `payload`.
    public static func envelope(payload: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        let signature = try privateKey.signature(for: message(payload))
        let object: [String: Any] = ["schema": 1, "keyID": keyID(privateKey.publicKey.rawRepresentation),
                                     "payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public struct VerifiedCatalog: Equatable, Sendable {
    public let catalog: ThemeCatalog
    /// Exact signed payload bytes; equal versions must have equal payloads.
    public let payload: Data
    public let envelope: Data
}

/// Where a pack or preview may be downloaded from. Integrity comes from the
/// signed SHA-256, so this is defence in depth against a mistaken catalogue.
public struct ThemeHostPolicy: Sendable {
    public let assetPrefix: String
    public let redirectHosts: Set<String>
    public static let github = ThemeHostPolicy(assetPrefix: "https://github.com/ish4ra/Arkiv/releases/download/",
        redirectHosts: ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"])
    public init(assetPrefix: String, redirectHosts: Set<String>) {
        self.assetPrefix = assetPrefix; self.redirectHosts = redirectHosts
    }
    public func allowsAsset(_ url: URL) -> Bool {
        url.scheme == "https" && url.absoluteString.hasPrefix(assetPrefix) && url.query == nil && url.fragment == nil
            && url.user == nil && url.password == nil && !url.path.contains("..")
    }
    public func allowsRedirect(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return redirectHosts.contains(host) && url.user == nil && url.password == nil
    }
}

public struct ThemeCatalogVerifier: Sendable {
    public let publicKeys: [Data]
    public let hosts: ThemeHostPolicy
    public let appBuild: Int
    public init(publicKeys: [Data], hosts: ThemeHostPolicy = .github, appBuild: Int) {
        self.publicKeys = publicKeys.filter { $0.count == 32 }; self.hosts = hosts; self.appBuild = appBuild
    }
    public var isConfigured: Bool { !publicKeys.isEmpty }

    /// Verifies the envelope signature, then the catalogue's structure, then
    /// rollback against the last verified catalogue (`previous`).
    public func verify(_ envelope: Data, previous: VerifiedCatalog?) throws -> VerifiedCatalog {
        guard isConfigured else { throw ThemeError.notConfigured }
        guard envelope.count <= ThemeLimits.catalogBytes else { throw ThemeError.catalogRejected("it is too large.") }
        guard let object = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
              Set(object.keys) == ["schema", "keyID", "payload", "signature"],
              object["schema"] as? Int == 1,
              let keyID = object["keyID"] as? String,
              let payloadText = object["payload"] as? String, let payload = Data(base64Encoded: payloadText),
              let signatureText = object["signature"] as? String, let signature = Data(base64Encoded: signatureText),
              signature.count == 64 else {
            throw ThemeError.catalogRejected("the envelope is malformed.")
        }
        guard let key = publicKeys.first(where: { ThemeCatalogSignature.keyID($0) == keyID }),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              publicKey.isValidSignature(signature, for: ThemeCatalogSignature.message(payload)) else {
            throw ThemeError.catalogRejected("its signature is not valid.")
        }
        let catalog: ThemeCatalog
        do { catalog = try JSONDecoder().decode(ThemeCatalog.self, from: payload) }
        catch { throw ThemeError.catalogRejected("its contents are malformed.") }
        try validate(catalog)
        if let previous {
            if catalog.catalogVersion < previous.catalog.catalogVersion {
                throw ThemeError.rollback(cached: previous.catalog.catalogVersion, received: catalog.catalogVersion)
            }
            if catalog.catalogVersion == previous.catalog.catalogVersion && payload != previous.payload {
                throw ThemeError.catalogRejected("it conflicts with the verified catalogue of the same version.")
            }
        }
        return VerifiedCatalog(catalog: catalog, payload: payload, envelope: envelope)
    }

    func validate(_ catalog: ThemeCatalog) throws {
        func reject(_ reason: String) -> ThemeError { .catalogRejected(reason) }
        guard catalog.schema == 1 else { throw ThemeError.requiresNewerArkiv }
        guard catalog.catalogVersion >= 1, catalog.catalogVersion <= 1_000_000_000 else { throw reject("its version is invalid.") }
        guard catalog.defaultTheme == DocumentIconThemeID.bundled else { throw reject("its default theme is not Arkiv's bundled theme.") }
        guard catalog.themes.count <= ThemeLimits.themes else { throw reject("it lists too many themes.") }
        var ids = Set<String>(), urls = Set<URL>()
        let known = Set(catalog.themes.map(\.id)).union([DocumentIconThemeID.bundled])
        let icons = Set(DocumentIconName.allCases.map(\.rawValue))
        for theme in catalog.themes {
            guard ThemeText.validID(theme.id), theme.id != DocumentIconThemeID.bundled, ids.insert(theme.id).inserted else {
                throw reject("a theme identifier is invalid or repeated.")
            }
            guard (1...1_000_000).contains(theme.version), theme.minimumAppBuild >= 0,
                  ThemeText.validID(theme.family), [theme.name, theme.familyName, theme.summary].allSatisfy({ ThemeText.validText($0) }),
                  ThemeText.validText(theme.licence) else { throw reject("theme \(theme.id) has invalid details.") }
            if let parent = theme.variantOf { guard parent != theme.id, known.contains(parent) else { throw reject("theme \(theme.id) names an unknown parent.") } }
            guard !theme.coverage.isEmpty, Set(theme.coverage).count == theme.coverage.count, Set(theme.coverage).isSubset(of: icons),
                  Set(theme.extras).count == theme.extras.count, Set(theme.extras).isSubset(of: documentIconExtraNames) else {
                throw reject("theme \(theme.id) has invalid format coverage.")
            }
            for asset in [(theme.pack.url, theme.pack.size, theme.pack.sha256, ThemeLimits.packBytes),
                          (theme.preview.url, theme.preview.size, theme.preview.sha256, ThemeLimits.previewBytes)] {
                guard hosts.allowsAsset(asset.0), (1...asset.3).contains(asset.1), ThemeText.validHex(asset.2), urls.insert(asset.0).inserted else {
                    throw reject("theme \(theme.id) has an invalid download.")
                }
            }
            guard let installed = theme.pack.installedSize, (1...ThemeLimits.installedBytes).contains(installed),
                  let files = theme.pack.files, (1...ThemeLimits.files).contains(files) else {
                throw reject("theme \(theme.id) has invalid sizes.")
            }
            let previewNames = theme.preview.files.map(\.name)
            guard Set(previewNames) == Set(theme.coverage.map { "Arkiv-\($0).png" }), previewNames.count == theme.coverage.count,
                  theme.preview.files.allSatisfy({ $0.width == 128 && $0.height == 128 && (1...ThemeLimits.fileBytes).contains($0.size) && ThemeText.validHex($0.sha256) }) else {
                throw reject("theme \(theme.id) has invalid previews.")
            }
        }
    }
}

public enum DocumentIconThemeID {
    /// The refined C · Seal Dark family bundled in Arkiv.app (build 26501).
    public static let bundled = "seal-dark"
}
