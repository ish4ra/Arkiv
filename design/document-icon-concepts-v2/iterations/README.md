# Superseded design variants

These are variants that existed during the exploration and refinement on
2026-11-22 but were replaced before the final versions archived in v1, or in
build 26501.

`render-iterations.mjs` rebuilds each one from the final code it was replaced
by, using the original code as exact text substitutions. Every substitution
must match exactly once, so a variant can only be produced from its true
predecessor:

```sh
node iterations/render-iterations.mjs --v1 <checkout>/design/document-icon-concepts-v1 [--out out/iterations]
```

| Variant | Family | Formats rebuilt | What it was, and why it was replaced |
| --- | --- | --- | --- |
| `folio-tar-three-windows` | A · Folio | TAR, TAR.GZ, TAR.BZ2 | Tape reel with three kidney windows; read as a radiation trefoil, so it became five round windows |
| `folio-xs-glyph-unit-60` | A · Folio | 16 pt ZIP, 7Z, TAR, XZ | First 16 pt layout (glyph unit 60, y 540); reduced to 54 / 548 for margin |
| `folio-dark-zip-pale-tape` | A · Folio Dark | ZIP, ZIP volume | Folio's pale tape wash on graphite read khaki; became a warm amber tape |
| `strata-tar-trefoil-windows` | B · Strata | TAR and TAR.\* | Three sector windows read as a trefoil; became five round windows |
| `strata-xz-octahedron-v0` | B · Strata | XZ, TAR.XZ | First crystal: axis-aligned, darker octahedron; became rotated and lighter with a gem facet |
| `strata-zst-floating-streaks` | B · Strata | ZSTD, TAR.ZST | Short streak blocks floating above-left; became longer streaks behind the Z |
| `seal-zip-pale-ladder` | C · Seal | ZIP, ZIP volume | First ZIP: pale tapes, wavy teeth; tapes darkened |
| `seal-rar-ring` | C · Seal | RAR, RAR volume | Ribbons threaded through a plum ring collar; read as a megaphone, so became pressed slanted layers |
| `seal-layout-v0` | C · Seal | 7Z, RAR, TAR, TAR.GZ, ZIP, 7Z volume | First glyph placement (scale 0.84 at y 430) |
| `seal-layout-v0.5-large-glyph` | C · Seal | 7Z, RAR, ZIP, RAR volume | Second placement (scale 0.94 at y 432); overlapped the fold |
| `production-zip-loose-teeth` | Seal Dark production | ZIP | First refinement pass: 11 looser teeth; tightened to the 13-tooth chain in build 26501 |

The variants carry the final versions' bug fixes, such as valid colour
values and point-based size tiers, so they show each design without the
rendering defects that some session sheets contain.

`session-sheets/` holds the actual review sheets rendered during the session
(WebP). They are a record of what was seen at the time:

| Sheet | Shows | Known defects visible |
| --- | --- | --- |
| `01-folio-first-render` | Folio at 256 / 32 / 16 px | three-window reel; VOLUME text overlapping the label on volumes |
| `02-strata-first-render` | Strata | black back sheets on volumes (invalid colour value); trefoil reel; first XZ and ZSTD |
| `03-seal-first-render` | Seal and Strata | ring RAR; pale ZIP; first layout |
| `04-seal-zip-rar-second-pass` | Seal | layout v0.5 overlapping the fold |
| `05`–`07` | 16 / 32 px pixel inspection of the three families | 16 pt tiers chosen by pixel size, not point size (fixed before review) |
| `08-folio-dark-seal-dark-first-render` | Folio Dark and Seal Dark | khaki Folio Dark ZIP tape |
| `09-small-sizes-dark-families-and-surfaces` | 16 / 32 px, dark families and Wine / Noir | (none) |
| `10-seal-dark-surface-study-on-dark` | Aubergine / Wine / Noir | (none) |
| `11-production-refinement-first-pass` | Concept vs first production pass, light and dark | (none) |
| `12-production-zip-rar-tgz-first-pass-512` | First-pass ZIP (loose teeth), RAR, TGZ at 512 px | (none) |
| `13-production-small-sizes-first-pass` | First-pass 16 / 32 px | (none) |
| `14-rebuilt-superseded-variants` | All variants above, rebuilt by `render-iterations.mjs` | (none) |
