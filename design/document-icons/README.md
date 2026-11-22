# Document icons: C · Seal Dark (production source)

This folder generates Arkiv's archive document icons. It is **design-time
only**: the app build packages the committed PNGs in
`Resources/DocumentIcons` with `iconutil` and never runs anything here.
Format coverage, registrations and Finder limitations are in
[docs/document-icons.md](../../docs/document-icons.md).

## Selected family

**C · Seal Dark (Aubergine)** was approved in November 2026 from five explored
families: A Folio, A Folio Dark, B Strata, C Seal and C Seal Dark, plus Wine and
Noir surface studies. Everything explored is preserved, with exact regeneration
instructions, on the branch
[`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1).
`previews/approved-concept-*.webp` are the boards it was approved from.

Production refinements over the approved concept:

| Area | Change |
| --- | --- |
| ZIP | Ribbon "ladder" replaced by meshing ribbon teeth, a brass slider and parting tapes |
| RAR | Flat slanted bars replaced by a pressed three-layer block with depth, distinct from BZIP2's bands |
| TAR.\* | Larger compressor medallion (brass bezel, compressor-hue ring); the page fold takes the compressor hue |
| 16 / 32 pt | Brighter sheet, firmer rose rim on dark backgrounds, narrower spine, larger glyph; compressor cues on TAR.\* |
| Typography | Labels are outlined from vendored Inter Display (OFL-1.1, `fonts/OFL.txt`), so there is no font dependency |
| Unchanged | Lacquered aubergine sheet, near-black spine, champagne-brass seam, jade stud and its restrained halo, ivory labels, per-format ribbon glyphs, transparency |

`previews/production-board.webp` shows every production icon beside the
approved concept, in light and dark, at large and actual small sizes.

## Files

| Path | Purpose |
| --- | --- |
| `seal-dark.mjs` | The icon family: sheet, spine, seam, stud, ribbon glyphs, size tiers |
| `lib/core.mjs`, `lib/mini.mjs`, `lib/formats.mjs` | SVG helpers, 16/32 pt pixel-grid glyphs, verified format registry and palette |
| `outline.mjs` | Converts label text to outlined paths (opentype.js) |
| `generate-config.mjs` | Production icon table (must match `scripts/verify-document-icons.py`) |
| `generate.mjs` | Renders `Resources/DocumentIcons/*.iconset`, then runs `optimize.py`; also writes editable SVGs and unregistered previews |
| `optimize.py`, `requirements-optimize.txt` | Lossless, deterministic PNG recompression (pinned, hash-locked pyoxipng 9.1.1 / oxipng); writes `SHA256SUMS` and checks `PIXELS.sha256` |
| `board.mjs` | Review board, optionally against the archived concept |
| `svg/` | Outlined, editable SVG sources (`-xs` 16 pt, `-s` 32 pt, `-l` large) for shipped and unregistered artwork |
| `previews/unregistered/` | TAR.\* double-suffix labels, TZST, the 7z volume (for a future Quick Look extension) and future RAR/ZIP volume concepts |

## Regenerate

Toolchain: Node 22, Playwright **1.63.0** (Chromium 157.0.8103.78) and
opentype.js **1.3.4**, all pinned in `package-lock.json`, plus Python 3.13 with
the hash-locked optimizer in `requirements-optimize.txt`.

```sh
cd design/document-icons
npm ci
npx playwright install chromium
python3.13 -m pip install --require-hashes -r requirements-optimize.txt
node generate.mjs --check     # expect: Regenerated 11 iconsets match PIXELS.sha256 and SHA256SUMS byte-for-byte
node generate.mjs             # only after an approved design change; commit the result
node board.mjs previews/production-board.png \
  --concept <archive checkout>/design/document-icon-concepts-v1/directions/seal-dark.mjs
```

## Lossless optimization

The committed PNGs are Playwright's renders recompressed by `optimize.py`:
oxipng level 6 with libdeflate level 12, every colour-type, bit-depth,
palette and alpha reduction disabled, no metadata added and no timeout. The
pixels, the 8-bit RGBA non-interlaced format and the IHDR/IDAT/IEND layout
are unchanged; only the row filters and the Deflate stream differ. For build
26501 this takes the 110 PNGs from 7,808,654 to 6,334,859 bytes (−18.9%).

* `Resources/DocumentIcons/PIXELS.sha256` holds the SHA-256 of each image's
  decoded `WIDTHxHEIGHT\n` + RGBA bytes. It is byte-identical to the manifest
  preserved for this theme on `archive/document-icon-concepts-v2`, and its own
  hash is pinned in `tests/test_document_icons.py`. CI decodes every committed
  PNG and every PNG element of the packaged ICNS files against it.
* `optimize.py --reproduce <renders>` optimizes a copy of unoptimized renders
  and requires the result to match `SHA256SUMS` byte-for-byte. CI runs it on
  both macOS architectures against build 26501's renders (`84320df`).
  Output is independent of thread count and machine speed.
* `optimize.py --check` confirms the committed files are already at the
  optimizer's fixed point.
* Only `node generate.mjs` (an approved artwork change) rewrites
  `PIXELS.sha256`, through `optimize.py --record-pixels`. Update the pinned
  hash in the test, and the render pin in the CI reproducibility job, in the
  same change.

After changing artwork, run `node generate.mjs`, then
`python3 scripts/verify-document-icons.py` and `python3 tests/test_document_icons.py`
from the repository root, and review the board. Adding a document type also
needs `generate-config.mjs`, `Resources/Info.plist` and `ICONS` in
`scripts/verify-document-icons.py` to agree. The tests enforce this.
