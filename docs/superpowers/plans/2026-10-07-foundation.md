# Arkiv foundation implementation plan

**Goal:** A native archive browser backed by a streaming, testable extraction engine.
**Spec:** `ARKIV_SPEC.md` is authoritative. This is the first stable subset of Priority A, not completion of Priority A.
**Architecture:** AppKit app → Swift engine protocol/models → narrow C libarchive adapter. The app never invokes external archive commands. macOS 13+, Apple Silicon first; system libarchive initially, with capabilities constrained by fixtures.
**Execution:** Inline, as requested; existing isolated cloud checkout. No worktree needed.

## Constraints and review focus
No overwrite, no traversal, no links/devices; bounded entry count and expanded bytes; cancellation during streaming; no plaintext passwords; no unverified format claims. Review duplicate paths, case-insensitive collisions, changed archives between browsing and extraction, malformed UTF-8, and UI updates after cancellation.

## Tasks
- [x] Engine: `Sources/CArkiv` provides synchronous list/extract with callbacks, bounded streaming, cancellation; test real ZIP/TAR plus hostile names/links/duplicates/limits/corruption in `tests/test_engine.py`. Write tests before implementation, observe failure, then implement and run full suite.
- [x] Swift integration: `Sources/ArkivCore` owns engine protocol, immutable entries, cancellation and owned output workspaces. Tests cover hierarchy and selection. C/Swift boundary does not expose libarchive pointers.
- [x] Native shell: `Sources/ArkivApp` provides windows, Open, table, folder navigation, search, selected/all extraction, cancellation and errors. Unsupported commands are absent. AppKit works off main thread for archive work.
- [x] Packaging: SwiftPM, Info.plist, original icon renderer, macOS build script, macOS Actions build/tests/artifact. No public release.
- [x] Validation/documentation: run C fixtures, Swift tests where compiler available, inspect diff, independent review, commit and push. Record macOS CI access limitations accurately.

## Deferred
Archive creation, preview/open, richer navigation, RAR/7z compatibility expansion, encryption, Finder integration, mutation, advanced tools, final icon refinement. Continue these in subsequent tested milestones.

## Execution evidence and decisions

- Core behavior was developed against failing stub tests; final local suite is 19 Python/C fixture tests plus 10 XCTest cases, passing in debug/release for Swift.
- Independent review identified unretained Swift callback context risk; changed to balanced retained ownership. Added cancellation-during-extraction cleanup coverage. Final-listing cancellation regression was observed failing, fixed, and passed.
- Decision: ship the narrow safe read/extract slice first; creation and preview are deferred rather than exposing unfinished operations. Cost: Priority A remains incomplete.
- Decision: vendor BSD ABI headers because macOS SDK omits them; link OS libarchive, no runtime tool installation. Cost: OS-dependent decoder capabilities need per-release regression runs.
- macOS CI found missing archive headers and explicit-self capture errors; both were corrected. Run 37608385235 passed app compilation, tests, icon generation, arm64 packaging and ad-hoc signature verification.
- GitHub API was blocked and anonymous detailed logs unavailable. Used public run summaries and allowlisted test/compiler categories; no raw log excerpts published in annotations.
- Final boundary: no real-Mac interactive validation yet. Do not claim final icon readability, accessibility, Finder behavior or production readiness.
