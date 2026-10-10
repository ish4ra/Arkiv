# Development builds and release preparation

Arkiv is an early development/testing build, not a production release. macOS 13+ is required. No runtime Homebrew, external compressor, Python, or Xcode installation is needed to run the downloaded app.

## Download and install the development DMG

1. Sign in to GitHub and open [macOS foundation workflow runs](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml?query=branch%3Amain).
2. Select a **successful run on `main`** that includes the DMG packaging jobs. Check its commit and scroll to **Artifacts**.
3. Download `Arkiv-arm64-development-dmg` for an Apple Silicon Mac, or `Arkiv-universal-development-dmg` for Intel or Apple Silicon. GitHub downloads an artifact ZIP wrapper; unzip it first to obtain the `.dmg` and checksum file.
4. Optionally verify download integrity from that extracted folder: `shasum -a 256 -c Arkiv-arm64-development.dmg.sha256` (substitute `universal` for the Universal download). This checksum is not an Apple signature or notarization.
5. Open `Arkiv-arm64-development.dmg` or `Arkiv-universal-development.dmg`. Its Finder volume is named **Arkiv** and contains **Arkiv.app** and an **Applications** shortcut.
6. Drag **Arkiv.app** onto **Applications**. If a previous Arkiv is installed, quit it first and confirm replacement only if intended. Eject the Arkiv volume, then open Arkiv from Applications.

| Actions artifact name | File inside the downloaded artifact ZIP | Architectures |
| --- | --- | --- |
| `Arkiv-arm64-development-dmg` | `Arkiv-arm64-development.dmg` and `.dmg.sha256` | arm64 |
| `Arkiv-universal-development-dmg` | `Arkiv-universal-development.dmg` and `.dmg.sha256` | arm64 + x86_64 |
| `Arkiv-arm64-development` | `Arkiv-arm64.zip` | arm64 |
| `Arkiv-universal-development` | `Arkiv-universal.zip` | arm64 + x86_64 |

The ZIP alternatives contain the same app; unzip the outer Actions wrapper, then unzip the inner app ZIP and drag Arkiv.app to Applications. Artifacts expire according to the repository's GitHub Actions retention policy. No GitHub Release is published by this workflow.

## Signing, notarization, and Gatekeeper

The app has an **ad-hoc Hardened Runtime signature**, not a Developer ID signature. The DMG itself is **unsigned**. Neither the app nor the DMG is **notarized**, and there is no notarization ticket to staple. The scripts do not request or invent Apple credentials.

A browser download is normally quarantined. Gatekeeper may refuse the first launch with wording such as **“Apple could not verify Arkiv is free of malware”**, **“Arkiv Not Opened”**, or an unidentified-developer warning. This is expected for this development build and is not a claim that Apple has reviewed it.

Only if you trust the selected repository/run: attempt to open the installed app, then use **System Settings → Privacy & Security → Open Anyway** for Arkiv, authenticate if requested, and confirm **Open**. The exact wording varies by macOS version; managed Macs may disallow this override. Do not disable Gatekeeper globally. If macOS reports a damaged app, verify the download checksum and run `codesign --verify --strict --all-architectures /Applications/Arkiv.app`; report verification failures rather than treating every warning as quarantine. Ad-hoc signature verification alone does not establish Gatekeeper approval.

## Reproduce the packages on macOS

Development requires Xcode command-line tools with Swift 5.9+ and Python 3 for the fixture tests. `hdiutil`, `lipo`, `codesign`, `ditto`, `iconutil`, and `plutil` are macOS/Xcode tools; no extra packaging package is required.

```sh
python3 scripts/build-sevenzip.py
swift test -Xlinker -L"$PWD/.build/sevenzip" -Xlinker -rpath -Xlinker "$PWD/.build/sevenzip"
scripts/test-engine.sh
scripts/build-app.sh
scripts/build-dmg.sh
open build/Arkiv-arm64-development.dmg
```

`scripts/build-dmg.sh` consumes the already-built `build/Arkiv.app`; it does not silently rebuild it. Architecture mismatches fail validation. For Universal:

```sh
ARKIV_ARCH=universal scripts/build-app.sh
ARKIV_ARCH=universal scripts/build-dmg.sh
```

For an Intel-only local package, use `ARKIV_ARCH=x86_64` for both commands. CI distributes arm64 and Universal, not a separate Intel-only artifact.

The default arm64 build remains independent. Universal builds compile the existing executable twice, combine the arm64/x86_64 slices using `lipo`, and **sign after combining**. The app's original icon, bundle metadata, document registrations and license notices are preserved. No application source changes or new runtime dependencies are needed.

## What CI verifies

Separate Apple Silicon (`macos-15`) and Intel (`macos-15-intel`) jobs run the complete engine fixture suite and Swift tests natively. The Apple Silicon job packages arm64; the Intel job builds both slices and packages Universal. `lipo` verifies the exact expected architecture set and `codesign` verifies every slice. Building both slices and running native tests on both platforms does not substitute for interactive GUI testing.

Before packaging, `verify-app.sh` checks the executable, original icon, metadata, notices, architecture(s), and signature. The DMG script stages the verified app with an `/Applications` symlink, creates a compressed read-only HFS+ image named **Arkiv**, verifies its checksum, mounts it read-only, verifies its volume name/link/app, verifies the app again, and tests copying it out into a temporary installation directory. It detaches the image before publishing the final `.dmg` and SHA-256 file to `build/`. Temporary staging and mount directories are cleaned up after successful detach. If attachment/detachment fails and cleanup cannot establish a safe detach, the temporary workspace is retained for diagnosis. The workflow also uploads the existing ZIP alternative; build jobs have read-only permissions; the separate signed development publisher updates the Sparkle channel after all checks pass.

Real-Mac release gates remain: first-launch/Gatekeeper behavior from an actual browser download, light/dark appearance, VoiceOver, keyboard navigation, table selection, resizing, cancel/close/quit during extraction, Finder routing, icon readability, large archives and case-insensitive APFS behavior. CI mounting/signature checks do not claim these interactive checks have happened.

## Future public distribution

The bundle identifier is `xyz.isharalakshan.arkiv`. Configure legitimate Developer ID signing securely, sign all nested components with Hardened Runtime, submit with `notarytool`, staple and validate the app and distribution image, and test Gatekeeper on a clean Mac. Apple credentials belong in secure CI secrets/Keychain and are not part of this development workflow. App Sandbox/Mac App Store distribution remains a separate decision involving bookmarks, selected-folder access, extensions and codec licensing. Public release is not authorized by this task.

## Finder Services

The four Finder Services are contained in the app executable and `Info.plist`; no separate extension/helper installation is needed. Launch the installed app once and enable the services in Keyboard Shortcuts settings if necessary. See [Finder integration](finder-integration.md) for exact actions, type restrictions, conflict/recovery behavior, setup, and interactive acceptance checks. App/DMG verification also checks the packaged Services declarations.

The corrected file-Service registration is in app build **2**. It uses `NSSendFileTypes` and direct action titles, not a submenu. Replace the previous installed app and confirm the four titles appear in Services → Files and Folders; terminal registration commands are optional developer diagnostics, not installation requirements.

## Sparkle development update channel

See [updates.md](updates.md) for one-time EdDSA key setup and in-app update testing.
The existing arm64 and Universal DMGs remain the bootstrap installation; after
installing a key-configured build, use **Arkiv → Check for Updates…**. CI assigns
monotonically increasing development build numbers and publishes signed Universal
updates only when both key settings are configured and all matrix jobs pass.
Only development prereleases are published, never stable production releases.

## Embedded Finder Sync extension

Development apps now include a sandboxed, ad-hoc-signed `ArkivFinderSync.appex`.
Both arm64 and Universal packaging verify its metadata, matching build version,
architectures and signed entitlements inside the app and mounted DMG. Sparkle
continues to distribute the complete Universal app, including this extension.
User enablement is required; see [Finder integration setup](finder-sync.md).

Finder registration validation now requires empty `NSExtensionAttributes` and the
runtime-resolved principal class `ArkivFinderSync.ArkivFinderSync`. CI checks
PlugInKit discovery as well as signed bundles. First-run setup guides approval;
no user terminal commands or cache resets are required.

Finder actions now use scalar menu tags and action-time selection instead of
custom represented objects. Handoff failures display a native error and Services
fallback. CI exercises real packaged-app URL delivery on launch and while running;
registration, onboarding and Sparkle remain intact.
