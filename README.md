# Arkiv

A native macOS archive manager in early development. `ARKIV_SPEC.md` is the authoritative implementation specification.

The first foundation contains an AppKit archive table, folder navigation, search, multi-selection, selected/all extraction into a new directory, progress/cancellation, and a reusable Swift engine backed by system libarchive. It does not require users to install an external compressor.

**Validation:** [macOS CI passed](https://github.com/ish4ra/Arkiv/actions/runs/37608385235): engine fixtures, Swift tests, native app compilation, arm64 bundle/icon generation, ad-hoc signature verification and artifact upload. Locally, 19 C-backed fixture tests and 10 Swift tests pass (Swift debug and release). Interactive UI/accessibility, icon readability and Finder behavior still require a real Mac; this is not a production release.

Fixture-verified on Linux and macOS CI: stored/Deflate ZIP, TAR, one basic 7z and one stored RAR5. This is not blanket codec/encryption/multipart support. Creation, modification, passwords, preview/open, Quick Look, Finder contextual actions, drag/drop and advanced tools are not implemented yet.

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
