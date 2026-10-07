# Arko

A native macOS archive manager in early development. `ARKO_SPEC.md` is the authoritative implementation specification.

The first foundation contains an AppKit archive table, folder navigation, search, multi-selection, selected/all extraction into a new directory, progress/cancellation, and a reusable Swift engine backed by system libarchive. It does not require users to install an external compressor.

**Validation:** Linux C and Swift core tests pass. macOS CI is configured, but its result has not yet been observed. The native UI, generated icon and bundle still require macOS compilation/interactive validation before this can be called a usable Mac release.

Fixture-verified locally: stored/Deflate ZIP, TAR, one basic 7z and one stored RAR5. This is not blanket codec/encryption/multipart support. Creation, modification, passwords, preview/open, Quick Look, Finder contextual actions, drag/drop and advanced tools are not implemented yet.

## Develop on macOS

```sh
swift test
scripts/test-engine.sh
scripts/build-app.sh
open build/Arko.app
```

Xcode command-line tools with Swift 5.9+; macOS 13+. App bundle defaults to arm64. Python 3 is needed only for developer fixture tests. No runtime Homebrew dependencies. See [release/build details](docs/release.md).

The repository is already isolated in Codex cloud tasks; reuse its checkout and do not create a worktree unless requested. Linux can test ArkoCore/CArko with Swift plus the system libarchive library, but cannot validate AppKit or produce Arko.app.

- [Architecture](docs/architecture.md)
- [Format evidence and backend research](docs/archive-formats.md)
- [Feature matrix](docs/feature-matrix.md)
- [Security and known limits](docs/security.md)
- [Finder integration](docs/finder-integration.md)
- [Original icon direction](docs/branding.md)
- [Third-party notices](docs/third-party-licenses.md)

Next: confirm/fix macOS CI and real-Mac browser behavior, then implement owned preview workspaces, single-entry Open/Quick Look and basic ZIP/TAR creation with round-trip tests. Complete those Priority A slices before encryption or modification.
