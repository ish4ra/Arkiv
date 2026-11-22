# Arkiv document-icon designs: archive v2

Branch: `archive/document-icon-concepts-v2`, created from `main` at
`84320dfa4ba81522dd71c63beb046b0b656819ad` (build 26501) with only this folder added. It extends, and never replaces,
[`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1)
(commit `7e9b736b123274e28a64727d0e6fde22ca11daf7`). Nothing here is built
into or required by the app.

Together v1 and v2 preserve every Arkiv document-icon design and variation
created so far, each as editable source that regenerates its artwork exactly.

## Complete inventory

| # | Design | Where | Artwork preserved as |
| --- | --- | --- | --- |
| 1 | **A · Folio** (original paper) | v1 `directions/folio.mjs` | source + `svg/folio/` + previews + 2,432-file render manifest |
| 2 | **A · Folio Dark** | v1 `directions/folio-dark.mjs` | same |
| 3 | **B · Strata** | v1 `directions/strata.mjs` | same |
| 4 | **C · Seal** (original ivory) | v1 `directions/seal.mjs` | same |
| 5 | **C · Seal Dark: original Aubergine** (approved concept) | v1 `directions/seal-dark.mjs` (`seal-dark`) | same |
| 6 | **C · Seal Dark: Wine** surface study | v1 `directions/seal-dark.mjs` (`seal-dark-wine`) | same |
| 7 | **C · Seal Dark: Noir** surface study | v1 `directions/seal-dark.mjs` (`seal-dark-noir`) | same |
| 8 | Pre-redesign shipping icons (comparison reproduction) | v1 `directions/current.mjs` | source + renders |
| 9 | **C · Seal Dark: refined production, build 26501** (current default) | v2 `themes/seal-dark-refined-26501/` | source + `SHA256SUMS`; PNGs live in `main` at `84320df`, `Resources/DocumentIcons/` |
| 10 | **C · Seal Dark: restored with small-size readability** (candidate) | v2 `themes/seal-dark-restored-readability/` | source + all 110 PNGs + `SHA256SUMS` + SVGs + unregistered previews + boards |
| 11–21 | Superseded intermediate variants (11) | v2 `iterations/` | exact source substitutions + rebuilt previews + original session sheets |

Every family in rows 1–7 covers 19 artwork variants (each in four size tiers):
* ZIP, 7Z, RAR, TAR, GZIP, BZIP2, XZ, ZSTD
* TAR.GZ, TAR.BZ2, TAR.XZ, TAR.ZST, plus their TGZ, TBZ2, TXZ and TZST labels
* the supported 7Z volume
* the future RAR and ZIP volume concepts

Rows 9 and 10 cover the 11 shipped icons. Each also keeps its unregistered
artwork: the 7z volume, the TAR.\* double-suffix labels, TZST, and the
future RAR and ZIP volumes.

Superseded variants (rows 11–21; details in `iterations/README.md`):
`folio-tar-three-windows`, `folio-xs-glyph-unit-60`, `folio-dark-zip-pale-tape`,
`strata-tar-trefoil-windows`, `strata-xz-octahedron-v0`, `strata-zst-floating-streaks`,
`seal-zip-pale-ladder`, `seal-rar-ring`, `seal-layout-v0`, `seal-layout-v0.5-large-glyph`,
`production-zip-loose-teeth`.

**Palettes and colour variations:**
* Per-format hue families (amber, jade, claret, slate, coral, moss, iris, cerulean) and the brand palette are in `lib/formats.mjs`. The file is byte-identical in v1, v2 `tooling/` and `main`.
* Surface colours (Aubergine, Wine, Noir; graphite for Folio Dark) are in the direction and theme sources.

**Deliberately not preserved as designs:** rendering defects that were fixed
before anything was shown for review. These are:
* black back sheets from an invalid colour value
* 16 pt artwork chosen by pixel instead of point size
* Folio's "VOLUME" label overlapping the format label
* a preview sheet whose colours broke because SVG gradient IDs collided

They appear in some session sheets and are marked as defects there.

## Layout

```
ARCHIVE.md                  this file
MANIFEST.sha256             SHA-256 of every file in this folder
reproduce.mjs               regenerate a theme and compare byte-for-byte
compare-board.source.mjs    script that produced the approved/26501/restored boards
tooling/                    shared generator (identical to main 84320df design/document-icons):
                            lib/, outline.mjs, generate-config.mjs, fonts/ (Inter Display, OFL),
                            package.json + package-lock.json (Playwright 1.63.0, opentype.js 1.3.4),
                            verify-pixels.py (encoder-independent check, Pillow)
reference/v1-pixels.sha256  decoded-pixel hashes of all 1,824 archive-v1 reference PNGs
themes/seal-dark-refined-26501/        seal-dark.mjs, SHA256SUMS, PIXELS.sha256, README.md
themes/seal-dark-restored-readability/ seal-dark.mjs, iconsets/ (110 PNG), SHA256SUMS, PIXELS.sha256, svg/ (57),
                                       previews/unregistered/ (8), boards/ (3), README.md,
                                       documentation-changes.patch
iterations/                 render-iterations.mjs, README.md, session-sheets/ (14 WebP)
```

## Reproduce

```sh
cd design/document-icon-concepts-v2/tooling && npm ci && npx playwright install chromium && cd ..
node reproduce.mjs seal-dark-refined-26501         # 110 files, 0 differ
node reproduce.mjs seal-dark-restored-readability  # 175 files, 0 differ
git -C ../.. archive origin/archive/document-icon-concepts-v1 design/document-icon-concepts-v1 | tar -x -C /tmp
node iterations/render-iterations.mjs --v1 /tmp/design/document-icon-concepts-v1
```

The results above were verified on 2026-11-22 with Node 22.23 and
Chromium 157.0.8103.78, using the stock Playwright 1.63.0 from
`tooling/package-lock.json`.

**PNG encoder caveat for archive v1**
* v1's `reference/renders.sha256` byte hashes were produced by a Playwright
  1.63.0 build patched to request `optimizeForSpeed` PNG encoding. That build
  was preinstalled in the original environment.
* Rendering v1 with stock Playwright gives byte-identical SVGs (608) and
  **pixel-identical** PNGs (1,824). Only the PNG compression bytes differ.
* To verify v1 with any Playwright 1.63.0 / Chromium 157:

```sh
cd <checkout>/design/document-icon-concepts-v1 && node render.mjs --out /tmp/v1
python3 ../document-icon-concepts-v2/tooling/verify-pixels.py \
  ../document-icon-concepts-v2/reference/v1-pixels.sha256 /tmp/v1   # 1824 images, 0 differ
```

Both themes also ship `PIXELS.sha256`, for the same encoder-independent check
of their iconsets.

## Deduplication

* **Not copied:** the build 26501 PNGs. They are permanent in `main`'s history
  (`git show 84320df:Resources/DocumentIcons/...`) and regenerate exactly.
* **Stored in full:** the restored candidate's 110 PNGs, because that design
  exists nowhere else. 68 of them are byte-identical to build 26501 files, so
  Git stores those blobs once across both branches.
* **Shared tooling:** `fonts/` and `lib/` are byte-identical to `main`'s copies,
  so they add no repository storage either.
* **Superseded variants:** stored as source substitutions plus small preview
  sheets, not as full render sets.

## Theme-pack sizes (11 icons × 10 representations)

| Theme | Raw PNG | Unique reps | Lossless-optimised estimate |
| --- | --- | --- | --- |
| Seal Dark refined 26501 (default) | 7.81 MB | 6.08 MB | 6.43 MB oxipng (5.78 MB with dedup + Pillow) |
| Seal Dark restored readability | 7.76 MB | 6.04 MB | 5.75 MB |
| Seal Dark Aubergine (concept) | 11.89 MB | 9.37 MB | 5.74 MB |
| Seal Dark Wine / Noir | 11.93 / 12.03 MB | 9.41 / 9.49 MB | 5.77 / 5.85 MB |
| C · Seal (ivory) | 8.66 MB | 6.67 MB | 3.76 MB |
| A · Folio / Folio Dark | 5.88 / 12.24 MB | 4.56 / 9.71 MB | 2.70 / 5.72 MB |
| B · Strata | 13.35 MB | 10.56 MB | 6.47 MB |

"Unique reps" removes the exact duplicates (128 pt @2x = 256 pt @1x, and
256 pt @2x = 512 pt @1x). Zip compression saves under 1%, because PNG is
already compressed. See `docs/document-icon-themes.md` for how these figures
shape the download design.

## Integrity

`MANIFEST.sha256` lists every file in this folder (excluding `node_modules/`
and `out/`). Check it with `shasum -a 256 -c MANIFEST.sha256` from this folder.
