# Arko foundation implementation plan

**Goal:** A native archive browser backed by a streaming, testable extraction engine.
**Spec:** `ARKO_SPEC.md` is authoritative. This is the first stable subset of Priority A, not completion of Priority A.
**Architecture:** AppKit app → Swift engine protocol/models → narrow C libarchive adapter. The app never invokes external archive commands. macOS 13+, Apple Silicon first; system libarchive initially, with capabilities constrained by fixtures.
**Execution:** Inline, as requested; existing isolated cloud checkout. No worktree needed.

## Constraints and review focus
No overwrite, no traversal, no links/devices; bounded entry count and expanded bytes; cancellation during streaming; no plaintext passwords; no unverified format claims. Review duplicate paths, case-insensitive collisions, changed archives between browsing and extraction, malformed UTF-8, and UI updates after cancellation.

## Tasks
- [ ] Engine: `Sources/CArko` provides synchronous list/extract with callbacks, bounded streaming, cancellation; test real ZIP/TAR plus hostile names/links/duplicates/limits/corruption in `tests/test_engine.py`. Write tests before implementation, observe failure, then implement and run full suite.
- [ ] Swift integration: `Sources/ArkoCore` owns engine protocol, immutable entries, cancellation and owned output workspaces. Tests cover hierarchy and selection. C/Swift boundary does not expose libarchive pointers.
- [ ] Native shell: `Sources/ArkoApp` provides windows, Open, table, folder navigation, search, selected/all extraction, cancellation and errors. Unsupported commands are absent. AppKit works off main thread for archive work.
- [ ] Packaging: SwiftPM, Info.plist, original icon renderer, macOS build script, macOS Actions build/tests/artifact. No public release.
- [ ] Validation/documentation: run C fixtures, Swift tests where compiler available, inspect diff, independent review, commit and push. Record macOS CI access limitations accurately.

## Deferred
Archive creation, preview/open, richer navigation, RAR/7z compatibility expansion, encryption, Finder integration, mutation, advanced tools, final icon refinement. Continue these in subsequent tested milestones.
