# Build and release

Requires macOS 13+ and Xcode command-line tools with Swift 5.9 or newer. No Homebrew/runtime compressor installation is needed.

```sh
swift test
scripts/test-engine.sh
scripts/build-app.sh
open build/Arko.app
```

The build script creates an arm64 release app, an original `.icns`, document registrations, notices, and an ad-hoc Hardened Runtime signature. Set `ARKO_ARCH=x86_64` for a local Intel build; Universal packaging is not yet automated. Developer tooling includes Python 3 for fixture tests, but the app runtime does not need Python. `swift run Arko` is useful during development; only the bundle carries document registrations and icon assets.

GitHub Actions builds/tests on macOS and uploads an arm64 development ZIP. It does not publish a release. A green Linux core test run does not establish that AppKit compiles or works. macOS CI must be green and its build warnings inspected before treating a milestone as Mac-validated.

Future direct-distribution release process: choose an owned bundle identifier, sign nested components and app with a Developer ID identity and Hardened Runtime, package with `ditto`, submit via `xcrun notarytool submit --keychain-profile ... --wait`, staple and validate, then create and notarize a DMG with `hdiutil` and validate Gatekeeper on a clean Mac. Credentials belong in secure CI secrets/Keychain; none are fabricated here. Do not replace the ad-hoc identity with a guessed certificate.

App Sandbox / Mac App Store distribution is a separate design decision requiring security-scoped bookmarks, selected destination access, extension constraints and codec license review. Current builds are development-only direct-distribution candidates. Public release is not authorized.

Interactive release gate: light/dark appearance, VoiceOver, tab/keyboard navigation, table selection, toolbar validation, resizing, menu shortcuts, cancel/close/quit during extraction, destination permission errors, app activation and Finder double-click routing, icon readability at every size, large catalogs, and end-to-end extraction on case-insensitive APFS.
