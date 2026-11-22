# Roadmap

**Revised 2026-11-22 by the project owner.** Downloadable document icon themes
and native UI customization are no longer held back until every archive-engine
feature is finished. Nothing below is in current builds unless the
[feature matrix](feature-matrix.md) says it is implemented.

## Near-term order

| # | Milestone | State |
| --- | --- | --- |
| 1 | **Lossless icon optimization and CI reliability** | In review: pixel-identical recompression of the bundled Seal Dark icons, pipefail-safe dependency checks, bounded PlugInKit retries. See [document icons](document-icons.md#lossless-optimization) |
| 2 | **Downloadable document icon theme packs** | Next. Signed, verified packs stored outside the app bundle; [plan](document-icon-themes.md) |
| 3 | **Native Appearance Settings and UI customization** | Settings → Appearance, including Document Icon Theme; [plan](document-icon-themes.md#planned-user-experience) |
| 4 | **Safe Finder and Quick Look customization feasibility** | Real-Mac prototype of an opt-in Quick Look thumbnail extension; no per-file icons or bundle changes; [constraints](document-icon-themes.md#where-a-theme-can-apply) |
| 5 | **RAR multipart reading** | Read-only, evidence-gated like RAR Phase 1; [RAR matrix](rar-compatibility.md) |
| 6 | **Split ZIP support** | `.z01`/`.zip.001` sets; [multipart](multipart.md) |
| 7 | **Remaining archive-engine features** | The rest of the queue below, in its existing relative order |

Rules for milestones 2–4:
* The refined **C · Seal Dark** family from build 26501 stays the default and
  the only bundled document-icon family.
* Every other preserved design ([`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1),
  [`archive/document-icon-concepts-v2`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v2/design/document-icon-concepts-v2))
  remains available for future optional download, with its real artwork. No
  design is redrawn.
* Optional themes are never bundled. The signed app bundle is never modified
  at runtime, and Sparkle update signing and verification are unchanged.
* No new runtime dependencies, background processes, launch-time work or
  network access outside the theme pane.

## Complete feature queue (preserved)

Nothing has been removed from the earlier queue. Items keep their existing
grouping; the near-term milestones above only move ahead of them.

**Formats**
* RAR multipart reading → milestone 5
* Split ZIP → milestone 6
* Additional RAR methods and filters; RAR encryption and solid archives; RAR comments
* Other multipart formats beyond split 7z (reading and creation)
* ZIPX, disk images and the other formats in the [specification](../ARKIV_SPEC.md)
* TAR creation: already implemented (see the feature matrix); listed earlier
  as planned and kept here for the record

**Archive work**
* Encrypted ZIP editing; ZIP64 AES; legacy ZipCrypto only after interoperability testing
* Arbitrary multi-selection mapping and folder update-by-date operations
* Editing more formats (7z, TAR and others)
* Archive comments

**Tools**
* Checksums
* Split / combine
* Benchmark
* Command-line companion

**App and Finder**
* Quick Look extension for archives in Finder (also the planned home for split-volume and TAR.\* artwork; feasibility is milestone 4)
* Finder Desktop vs Get Info icon investigation (open; [details](document-icons.md#finder-and-desktop-display-investigation-open))
* Advanced metadata

**Distribution and branding**
* Developer ID signing and notarization
* Final app icon and branding polish (the Tension Seal app icon stays unchanged until then)

**Lightweight tasks** (separate, independent of the themes; none may change a visible pixel)
* Duplicate ICNS representation elimination: investigated, **deferred** until
  real-Mac compatibility is shown; [findings](document-icon-themes.md#duplicate-representation-investigation-deferred)
* Signed Sparkle binary delta updates, with the full signed update as fallback
* Real-Mac measurements: installed size, cold/warm launch time, resident memory

The specification's priority lists (A, B, C) are unchanged in
[`ARKIV_SPEC.md`](../ARKIV_SPEC.md); this page records the owner's current
execution order.
