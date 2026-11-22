# Theme candidate: C · Seal Dark, restored with small-size readability

Prepared on 2026-11-22 as a correction candidate, then set aside when build
26501's refined artwork was kept as the default. Preserved here as a distinct
theme. It differs from the approved concept (archive v1 `seal-dark`) and
from the refined production family (`../seal-dark-refined-26501`).

What it is:

* **128 pt and larger:** the approved concept's artwork, unchanged. The
  generated SVG markup was verified identical to archive v1
  `svg/seal-dark/*-l.svg` and `*-m.svg` for all 19 variants, so its glyphs are:
  * **ZIP:** the folded-ribbon ladder between two ribbon tapes
  * **RAR:** three offset, slanted pressed ribbon layers
  * **TAR.\*:** the concept's medallion (radius 122, scale 0.40), with no tinted fold
* **16 / 32 pt:** the concept's symbols and colours, with production's
  readability treatment:
  * a slightly brighter sheet and fold
  * a firmer rose rim (opacity 0.78 at 16 pt, 0.60 at 32 pt)
  * a narrower spine and seam
  * a slightly larger glyph
  
  There is no compressor badge and no compressor-tinted fold.

Against build 26501, the differences are:
* **7z, TAR, GZIP, BZIP2, XZ, ZSTD:** byte-identical.
* **ZIP and RAR:** differ at 128 pt and up only.
* **TGZ, TBZ2, TXZ:** differ at every size.

| Path | Content |
| --- | --- |
| `seal-dark.mjs` | Generator source (imports `./lib/...`; `reproduce.mjs` stages it beside `../../tooling/lib`) |
| `iconsets/Arkiv-*.iconset/` | All 11 iconsets, 10 representations each (110 PNGs) |
| `SHA256SUMS` | Checksums of those 110 PNGs |
| `svg/` | 57 outlined, editable SVGs (`-xs` 16 pt, `-s` 32 pt, `-l` large) for shipped and unregistered artwork |
| `previews/unregistered/` | 7z volume, TAR.GZ / TAR.BZ2 / TAR.XZ / TAR.ZST labels, TZST, future RAR and ZIP volumes (512 px) |
| `boards/approved-vs-26501-vs-restored-{light,dark}.webp` | Three-way review boards, all 11 icons plus preserved artwork |
| `boards/restored-vs-approved-concept.webp` | Production-style board against the approved concept |
| `documentation-changes.patch` | The documentation edits written for this candidate (README and `docs/document-icons.md`) |

Verified on 2026-11-22: `node reproduce.mjs seal-dark-restored-readability`
regenerated 175 files (110 PNGs, 57 SVGs, 8 previews) with 0 differences.

`PIXELS.sha256` holds decoded-pixel hashes of the 110 PNGs
(`python3 ../../tooling/verify-pixels.py PIXELS.sha256 <iconsets dir>`). It verifies
the artwork even when a different PNG encoder changes the file bytes.
