# Roadmap

**Revised 2026-11-22 by the project owner.** Downloadable document icon themes
and native UI customization are no longer held back until every archive-engine
feature is finished. Nothing below is in current builds unless the
[feature matrix](feature-matrix.md) says it is implemented.

## Near-term order

| # | Milestone | State |
| --- | --- | --- |
| 1 | **Lossless icon optimization and CI reliability** | Integrated (`022631e`): pixel-identical recompression of the bundled Seal Dark icons, pipefail-safe dependency checks, bounded PlugInKit retries. See [document icons](document-icons.md#lossless-optimization) |
| 2 | **Downloadable document icon theme packs** | **Integrated and published.** `d70c14c` (build 30201); production catalogue v1 and all 20 packs published as `document-icon-themes-v1`; build 30701 embeds the production key. Verified by the maintainer on a real Apple Silicon Mac: catalogue loads (20 themes), Folio Dark downloads and applies. Complete real-Mac acceptance (persistence, offline, removal, every in-app consumer) outstanding. Publication now retries delayed draft discovery; [details](document-icon-themes.md), [inventory](document-icon-theme-inventory.md) |
| 3 | **Native Appearance Settings and UI customization** | **In review** (complete UI redesign): welcome window, archive window, sidebar Settings, theme gallery, accent/density/alternating rows, immediate in-app theme switching; [design](ui-redesign.md), [Settings](settings.md). Real-Mac visual acceptance outstanding |
| 4 | **Safe Finder and Quick Look customization feasibility** | **Prototype and report in review.** A sandboxed, ad-hoc-signed `QLThumbnailProvider` is built into a copy of the app on CI runners only; nothing ships. Finder icons and Get Info cannot follow a theme through supported mechanisms; thumbnails are the only supported route: the extension builds, signs ad hoc and registers on CI, but drawing and refresh timing need a real Mac; [feasibility report](quicklook-thumbnail-feasibility.md). Real-Mac Finder evaluation is next |
| 5 | **RAR multipart reading** | Read-only, evidence-gated like RAR Phase 1; [RAR matrix](rar-compatibility.md) |
| 6 | **Split ZIP support** | `.z01`/`.zip.001` sets; [multipart](multipart.md) |
| 7 | **Remaining archive-engine features** | The rest of the queue below, in its existing relative order |

**Permanent rule for every format milestone (5, 6 and 7 included):** a new
archive format, alias or volume scheme ships only with its document-icon
coverage: bundled default artwork, coverage in every theme family, extension
and alias mapping, safe registration where macOS can type it, in-app icons,
updated theme and preview packs, and a row in
[`format-icon-coverage.json`](format-icon-coverage.md) with passing coverage
tests. See "Document icon coverage for every archive format" in
[ARKIV_SPEC.md](../ARKIV_SPEC.md).
For example, multipart RAR (milestone 5) must decide how its first and later
volumes are identified before the preserved RAR-volume artwork is used.

Rules for milestones 2–4:
* The refined **C · Seal Dark** family from build 26501 stays the default and
  the only bundled document-icon family.
* Every other preserved design ([`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1),
  [`archive/document-icon-concepts-v2`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v2/design/document-icon-concepts-v2))
  is an optional download built from its real artwork (milestone 2). No
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
* Editing more formats: solid and split 7z, TAR and others (eligible single-volume, non-solid 7z editing is already implemented)
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
