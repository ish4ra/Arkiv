# Arkiv

A native macOS archive manager in early development. `ARKIV_SPEC.md` is the authoritative implementation specification.

The first foundation contains an AppKit archive table, folder navigation, search, multi-selection, selected/all extraction into a new directory, progress/cancellation, and a reusable Swift engine backed by system libarchive. It does not require users to install an external compressor.

**Validation:** [macOS CI](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml) runs engine/security fixtures, Swift/AppKit tests, branding checks, arm64 and Universal app verification, and mounted DMG verification. Interactive Finder discovery, UI/accessibility, and Gatekeeper behavior still require a real Mac; this is not a production release.

Fixture-verified on Linux and macOS CI: stored/Deflate ZIP, TAR, one basic 7z and one stored RAR5. This is not blanket codec/encryption/multipart support. Creation, modification, passwords, preview/open, Quick Look, drag/drop and advanced tools are not implemented yet.

## Download for Mac testing

Open the [macOS foundation Actions page](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml?query=branch%3Amain), sign in, and choose a successful `main` run with DMG artifacts. Download **`Arkiv-arm64-development-dmg`** for Apple Silicon or **`Arkiv-universal-development-dmg`** for Intel/Apple Silicon. Unzip GitHub's artifact wrapper, open the enclosed **`Arkiv-…-development.dmg`**, and drag **Arkiv.app** to the **Applications** shortcut. Eject the **Arkiv** volume and launch the installed app from Applications.

These are **development builds**: the app is **ad-hoc signed**, the DMG is **unsigned**, and **neither is notarized**. Gatekeeper may block first launch with an Apple-could-not-verify/unidentified-developer warning. If you trust this build, attempt launch, then use **System Settings → Privacy & Security → Open Anyway** for Arkiv. See [exact artifact names, checksums, installation and Gatekeeper details](docs/release.md). No GitHub Release is published.

## Develop on macOS

```sh
swift test
scripts/test-engine.sh
scripts/build-app.sh
scripts/build-dmg.sh
open build/Arkiv-arm64-development.dmg
```

Xcode command-line tools with Swift 5.9+; macOS 13+. App bundle defaults to arm64. Python 3 is needed only for developer fixture tests. No runtime Homebrew dependencies. See [release/build details](docs/release.md).

The repository is already isolated in Codex cloud tasks; reuse its checkout and do not create a worktree unless requested. Linux can test ArkivCore/CArkiv with Swift plus the system libarchive library, but cannot validate AppKit or produce Arkiv.app.

- [Architecture](docs/architecture.md)
- [Format evidence and backend research](docs/archive-formats.md)
- [Feature matrix](docs/feature-matrix.md)
- [Security and known limits](docs/security.md)
- [Finder integration](docs/finder-integration.md)
- [Original icon direction](docs/branding.md)
- [Third-party notices](docs/third-party-licenses.md)

Next: confirm/fix macOS CI and real-Mac browser behavior, then implement owned preview workspaces, single-entry Open/Quick Look and basic ZIP/TAR creation with round-trip tests. Complete those Priority A slices before encryption or modification.

## Finder extraction

Right-click one ZIP or uncompressed TAR archive → **Services** for **Open in Arkiv**, **Extract Here with Arkiv**, **Extract to Folder with Arkiv**, or **Extract To… with Arkiv**. Enable these under **System Settings → Keyboard → Keyboard Shortcuts → Services** if needed. Extraction never overwrites or merges existing items. Single selection only; no archive creation. See [Finder setup, limitations, and test steps](docs/finder-integration.md).

### Development self-updates

Arkiv integrates Sparkle 2 with **Arkiv → Check for Updates…** and optional
background checks. One manual installation of a build containing your configured
public key is required. Subsequent development updates use a signed Universal ZIP
and signed GitHub prerelease feed. See [updater setup and testing](docs/updates.md)
for the one-time EdDSA key/Actions secret setup. Builds remain ad-hoc signed and
not notarized; keyless builds clearly report that updates are not configured.

### Direct Finder menu

Use the first-run Finder setup, or **Arkiv → Finder Integration…**, for a direct **Arkiv** submenu when
right-clicking one ZIP or uncompressed TAR in your home folder. Actions include
Open, Extract Here, Extract to an archive-named folder, and Extract To. Extraction
requests are confirmed in Arkiv; Services remain the fallback outside this scope.
See [Finder Sync setup and real-Mac tests](docs/finder-sync.md).

Finder setup shows the manual macOS Settings path and refreshes enabled status
when you return. **Not Now** is remembered; setup remains available from the menu.
