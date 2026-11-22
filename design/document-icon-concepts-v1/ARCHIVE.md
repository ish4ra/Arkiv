# Arkiv document-icon concepts v1 (archive)

This branch (`archive/document-icon-concepts-v1`) permanently preserves the
complete document-icon exploration that preceded Arkiv's production document
icons. Branch it from `main` at `4d80a94`; it adds only this folder. Nothing
here is built into, linked by, or shipped with the app.

The production family is **C · Seal Dark (Aubergine)**, refined and integrated
on `claude/document-icon-design`. This archive keeps every concept exactly as
reviewed so that any of them can be revisited or re-rendered later.

## Contents

| Path | What it is |
| --- | --- |
| `README.md` | Design notes from both review rounds: inspection, rationale, palettes, Finder limitations, recommendations |
| `directions/folio.mjs` | **A · Folio**: native paper + format illustrations |
| `directions/folio-dark.mjs` | **A · Folio Dark**: graphite sheet (reuses Folio glyphs) |
| `directions/strata.mjs` | **B · Strata**: tinted glass card + porcelain polyhedra (includes the tiny iso 3-D renderer) |
| `directions/seal.mjs` | **C · Seal**: ivory paper, plum spine, folded-ribbon glyphs |
| `directions/seal-dark.mjs` | **C · Seal Dark** with three surfaces: `aubergine` (approved), `wine`, `noir` |
| `directions/current.mjs` | Reproduction of the pre-redesign shipping icons, for comparison only |
| `lib/core.mjs` | SVG helpers, page silhouettes, gradients, shadows, iso projection |
| `lib/formats.mjs` | Verified format registry (extensions, UTIs, support status), hue families, brand palette |
| `lib/mini.mjs` | Dedicated 16/32 pt pixel-grid glyphs shared by all families |
| `render.mjs` | Renders every family × format × size to PNG plus editable SVG |
| `boards.mjs` | Rebuilds the review boards from a render |
| `verify-renders.mjs` | Re-renders and checks every file against `reference/renders.sha256` |
| `tools/zoom.py` | Nearest-neighbour 16/32 px inspection sheet (Pillow) |
| `fonts/` | Inter Display SemiBold, Bold and ExtraBold 4.0 (OFL-1.1, `fonts/OFL.txt`), bound by the renderer |
| `reference/renders.sha256` | SHA-256 of all 2,432 reference outputs (PNG + SVG) |
| `svg/<family>/<id>-{xs,s,m,l}.svg` | Editable vector sources per size tier for the seven family renders |
| `previews/<family>/<id>-256.png` | Transparent 256 px preview of every format, alias and volume concept |
| `previews/hero-512/` | Transparent 512 px heroes (ZIP, 7Z, RAR, TAR, GZIP, ZSTD, TAR.GZ, 7Z volume) per family |
| `boards/round-1/*.webp` | Original round-1 boards (three directions, comparison, actual size, Finder, current vs proposed, multipart) |
| `boards/round-2/*.webp` | Round-2 boards: five families, original vs dark, Seal Dark surface study, Finder light/dark per family |

Families and render keys: `folio`, `folio-dark`, `strata`, `seal`,
`seal-dark` (Aubergine), `seal-dark-wine`, `seal-dark-noir`, `current`.

Formats covered: ZIP, 7Z, RAR, TAR, GZIP, BZIP2, XZ, ZSTD, TAR.GZ/TGZ,
TAR.BZ2/TBZ2, TAR.XZ/TXZ, TAR.ZST/TZST, and 7Z volumes (supported). It also
covers RAR multipart and split ZIP volumes, which are **future concepts only**
and are not supported formats.

Boards are stored as WebP (quality 86, 2× density) and previews as optimised
PNG, to keep the branch small. The full 283 MB render set is not committed;
regenerate it as below.

## Reproduce exactly

Pinned toolchain (the reference was produced with these):

* Node.js 22.23 (any 22.x should do)
* Playwright **1.63.0** (`package.json`/`package-lock.json`), Chromium **157.0.8103.78**
* Inter Display 4.0 (`fonts/`, vendored; no system fonts are used for icons)
* Pillow 12 (only for `tools/zoom.py`)

```sh
cd design/document-icon-concepts-v1
npm ci
npx playwright install chromium
node render.mjs --out out          # ~2 min: 2,432 PNG/SVG files in out/png, out/svg
node verify-renders.mjs            # expect: 2432 reference files checked, 0 differ
node boards.mjs                    # optional: review boards in out/boards
```

Useful variants:

```sh
node render.mjs --dirs seal-dark --only zip,7z --sizes 512 --out out
node verify-renders.mjs seal-dark-wine seal-dark-noir
python3 tools/zoom.py out/png/seal-dark zoom.png zip 7z rar tar
```

The SVG font stack names SF Pro first. `render.mjs` binds the vendored Inter
Display files to every family in that stack, so renders do not change on a Mac
with SF Pro installed. `verify-renders.mjs` passed byte-for-byte for all 2,432
files from this folder before the branch was pushed. Boards use the host's Inter
for their captions only, so regenerated boards can differ slightly in caption
text, but never in icon pixels.

Output naming: `out/png/<family>/<id>/<id>-<px>.png` are 1× previews
(16…1024). `<id>-<pt>pt@2x.png` are Retina pairs that keep the point-size
artwork tier. Tiers: 16 pt → `xs`, 32 pt → `s`, ≤ 80 pt → `m`, larger → `l`.

## Not in this archive

The production icon sets, refinements and packaging live on
`claude/document-icon-design` (and, once merged, `main`). The app icon
(Tension Seal) was never modified by this work.
