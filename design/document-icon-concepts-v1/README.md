# Arkiv document-icon exploration

> **Archived.** These are the original design notes. See [ARCHIVE.md](ARCHIVE.md) for
> what is preserved, how to regenerate every render exactly, and where boards and
> previews live (`boards/`, `previews/`, `svg/`). Paths below that start with `out/`
> refer to a fresh render. C · Seal Dark (Aubergine) was approved for production.

Status: **design exploration only, awaiting approval.** Nothing here is wired
into the app. The shipping app icon (Tension Seal), `branding/`,
`scripts/render-icon.swift`, `scripts/render-document-icons.swift`,
`Resources/Info.plist`, file associations, signing and publication are
unchanged.

## What was inspected

| Source | Finding |
| --- | --- |
| `branding/`, `scripts/render-icon.swift` | Tension Seal: aubergine clasp `#703A47 → #301A2B`, amber ribbons `#FDCF73 → #C46E38`, jade stud `#CFF0D4 → #4A9C82`. Preserved untouched (pinned by `app-icon-preservation.json`). |
| `scripts/render-document-icons.swift` | Today ZIP, 7z, TAR and RAR all use the same paper, the same full-colour mark and a plum label, so only the text differs. |
| `Resources/Info.plist` | Viewer/Alternate document types for ZIP, TAR, 7z, RAR, GZIP, BZIP2, XZ and Zstandard. Only the first four have icons. `tzst` is declared under `org.zstandard.zstd` together with `zst`. |
| `Sources/ArkivCore/ArchiveCreator.swift`, `docs/*.md` | Supported suffixes: `.zip .7z .rar .tar .gz .bz2 .xz .zst .tar.gz .tgz .tar.bz2 .tbz2 .tar.xz .txz .tar.zst .tzst`, plus split 7z `.7z.001…` (2–128 parts). RAR is read-only. Multipart RAR and split ZIP are **not** supported. |

## The three directions

All three share one format registry (`lib/formats.mjs`), one hue family per
format and one dedicated 16/32 pt glyph set (`lib/mini.mjs`). Each format's
motif means something:

| Format | Motif | Hue |
| --- | --- | --- |
| ZIP | interlocking zipper teeth | Amber (brand ribbon colour, primary creation format) |
| 7Z | heptagon (7) rosette or prism | Jade (brand stud colour) |
| RAR | dense pressed slabs | Claret |
| TAR | tape reel (tape archive) | Slate |
| GZIP | bellows press (deflate) | Coral |
| BZIP2 | sorted block staircase (block sorting) | Moss |
| XZ | dense crystal (high-ratio LZMA2) | Iris |
| ZSTD | speed Z | Cerulean |
| TAR.\* | TAR reel combined with the compressor's hue and emblem | compressor hue |
| Split volume | stacked sheets plus a segment strip (first segment filled) | format hue |

* **A · Folio:** Apple-native white paper with a folded corner and a refined
  illustration per format. The quietest and most system-like option.
* **B · Strata:** a tinted glass card holding a dimensional porcelain object.
  The objects are real polyhedra with facet lighting from `directions/strata.mjs`,
  so depth and light are consistent across the whole family.
* **C · Seal:** warm ivory paper bound by a plum spine with the jade stud,
  using the Tension Seal palette and material without ever reproducing the
  mark, plus format glyphs drawn as folded ribbons.

## Round 2: dark families

Arkiv is dark-first, so two dark reinterpretations were added. The originals are
untouched: their sources are byte-identical and all 684 original PNGs re-render
identically.

* **A · Folio Dark** (`directions/folio-dark.mjs`) uses the same Folio
  illustrations on a satin graphite sheet. It has a cool top sheen, a
  light-catching rim for dark backgrounds and a dark hairline for light ones.
  The format hue rises from the bottom edge and a soft halo lifts the
  illustration. The only artwork change is the ZIP tape, whose pale paper wash
  turned khaki on graphite and is now a warm translucent amber.
* **C · Seal Dark** (`directions/seal-dark.mjs`) is a lacquered aubergine sheet
  bound by a near-black spine. A champagne-brass seam marks the binding. The
  jade stud sits in a brass bezel with a faint jade halo (the only glow, kept
  low). It uses its own copy of the ribbon glyphs re-tuned for a dark ground:
  ribbon bodies never end in the hue's darkest tone, top edges are lit, and a
  format-hue halo sits behind the glyph. GZIP's press plates become brass, and
  the TAR tail now runs straight out, so the spiral no longer reads as a
  magnifier. Labels are ivory.
* **Seal Dark surface study:** Aubergine (selected), Wine and Noir, rendered
  as `seal-dark`, `seal-dark-wine` and `seal-dark-noir`. Wine loses claret
  (RAR) separation. Noir keeps the plum spine but is the least distinctive.

Both dark families were checked on light Finder backgrounds. They don't depend
on Dark Mode: a macOS document icon (`.icns`) has a single appearance, so
whichever family ships is seen on both.

## Updated recommendation (round 2): C · Seal Dark

1. **It is unmistakably Arkiv.** The spine, brass seam and jade stud carry the
   Tension Seal identity, so a folder of archives reads as Arkiv's before any
   label. Most documents in Finder are white, which makes it the most
   distinctive family.
2. **It suits a dark-first app and still works on light.** On white Finder
   windows the lacquered sheet reads as a crisp, bound volume. On dark ones the
   rose rim and brass seam keep the silhouette.
3. **Format identity survives.** Each format keeps its own folded-ribbon symbol
   and hue, and the dark ground makes those hues cleaner, not muddier.

Its honest weakness: at 16 pt on a dark background the sheet itself goes
dark-on-dark, and recognition relies on the glyph colour and brass seam. Strata
still separates formats best at that size. Before production I would:
* lift the 16/32 pt sheet slightly, with a brighter rim and a 1 px larger glyph
* replace the ZIP ribbon "ladder" with tighter interlocking teeth
* give RAR's pressed layers a clearer stacked-block read
* apply the shared items from round 1: compressor emblem on TAR.\*, and outlined labels

If you prefer a quieter, more Apple-native look, **Folio Dark** is the runner-up.
**Strata** remains the most legible at tiny sizes.

## Round 1 recommendation (kept for reference): B · Strata

1. **It is the most readable in Finder.** Hue fills the whole document, so the
   formats separate at 16 pt in list view, in light and dark mode, before any
   label can be read (see `03-actual-size-*` and `04-finder-*`).
2. **It looks premium without decoration.** One porcelain material, one light
   direction, a restrained inner glow and a glass rim tie every format together.
   Nothing is neon, and identity comes from the objects themselves.
3. **It is not a template.** Each format's artwork has a different silhouette.
   Changing the label alone would never produce another format's icon.
4. **It stays honest to the brand.** The palette comes from Tension Seal (amber
   ZIP, jade 7Z, claret RAR), and the app icon is untouched.

Refinements I would make before production:

* GZIP's bellows and RAR's slab stack are too similar at 64 pt. GZIP should
  become a side-view clamp, or a squeezed cube with visible pleats.
* Compressed TAR icons currently differ only by card hue and label. Put the
  compressor's emblem on the reel hub.
* Give the 16 pt glyphs one more pixel of margin. 7Z and TAR touch the card edge.
* Calm the amber and coral card saturation by about 5–8 % for large grids.
* Optionally add a small jade stud on the fold as a quiet Arkiv signature.

Runner-up: **A · Folio**, if a quieter Apple-native look is preferred. Seal is
the most brand-forward, but the spine repeats on every format and costs about a
quarter of the glyph area at 16 pt.

## Finder mechanisms and limitations (investigated, not implemented)

* **Icons appear only where Arkiv is the default handler.** Arkiv declares
  Viewer/Alternate document types and imports (does not export) the UTIs, so
  Finder shows `CFBundleTypeIconFile` artwork only after the user picks Arkiv in
  Get Info → Open with → Change All. Arkiv must never call
  `LSSetDefaultRoleHandlerForContentType` or otherwise change defaults.
* **Finder types a file by its last extension.** `website.tar.gz` is typed as
  `.gz` and `snapshot.tar.zst` as `.zst`, so a document-type icon **cannot**
  show the TAR.GZ or TAR.ZST artwork for double-extension names. Only the single
  aliases can:
  * `.tgz` (`org.gnu.gnu-zip-tar-archive` is believed to be system-declared;
    verify with `mdls -name kMDItemContentTypeTree sample.tgz`)
  * `.tbz2` and `.txz` (would need imported UTIs)
  * `.tzst` (would need splitting out of `org.zstandard.zstd`)
* **Split volumes.** `Footage.7z.001` is typed as `.001`, a generic extension
  used by many unrelated tools. Arkiv must not declare it, so no document-type
  icon can target split volumes. Options:
  * **Quick Look thumbnail extension** (`QLThumbnailProvider`, macOS 10.15+), the
    only plausible safe route. It would return volume artwork only when the name
    matches `*.7z.NNN` and the 7z signature checks out (on the `.001` part).
    Unrelated `.001` files keep their normal icon. Open questions that need a
    real-Mac prototype:
    1. Whether registering for the dynamic UTI of `001` works without declaring it.
    2. Finder thumbnail caching.
    3. List-view behaviour when "Show icon preview" is off.
    4. Thumbnails apply even when Arkiv is not the default app, so this should
       be an opt-in setting.

    The same extension is the only route to TAR.\* artwork on `.tar.gz` names.
  * **Per-file custom icons** (`NSWorkspace.setIcon`). Not recommended: this
    writes `com.apple.FinderInfo`/resource-fork xattrs into the user's files,
    changes ctime (which trips the split-set identity checks in
    `docs/multipart.md`) and travels inconsistently.
  * `.part1.rar` is typed as `.rar`, and `.z01`/`.zip.001` have the same
    issues. Those concepts are marked **future** and imply no support.

## Files

```
lib/core.mjs           SVG helpers, page/card silhouettes, iso projection
lib/formats.mjs        verified format registry, hues, brand palette
lib/mini.mjs           dedicated 16/32 pt pixel-grid glyphs
directions/folio.mjs   A
directions/strata.mjs  B (includes the tiny polyhedron renderer)
directions/seal.mjs    C
directions/folio-dark.mjs  A · Folio Dark (reuses Folio glyphs)
directions/seal-dark.mjs   C · Seal Dark (+ surface study: wine, noir)
directions/current.mjs reproduction of today's shipping icons, for comparison only
render.mjs             all directions × formats → PNG + editable SVG
boards.mjs             review boards
tools/zoom.py          nearest-neighbour pixel inspection of 16/32 pt renders
out/svg/<dir>/<id>-{xs,s,m,l}.svg            editable vector sources per size tier
out/png/<dir>/<id>/<id>-<px>.png             1× previews 16…1024
out/png/<dir>/<id>/<id>-<pt>pt@2x.png        Retina pairs (tier chosen by point size)
out/boards/*.png                             review boards (round 2, five families)
out/boards/round-1/*.png                     round-1 boards, preserved
```

Regenerate (Node 22 and the preinstalled Playwright Chromium):

```sh
node design/document-icon-concepts-v1/render.mjs --out design/document-icon-concepts-v1/out
node design/document-icon-concepts-v1/boards.mjs
```

Size tiers: 16 pt → `xs` (pixel-grid glyph, no text), 32 pt → `s` (glyph plus
short label), ≤ 80 pt → `m` (full art, larger label), otherwise `l`. Retina
pairs reuse their point-size tier, as macOS iconsets expect.

Typography renders with Inter Display Bold here (SF Pro fallback order in the
SVG). For production I recommend converting labels to outlines from Inter
(OFL), so rasters stay identical across macOS versions and the SF Pro licence
question does not arise.

## Proposed production step (not started; needs approval)

1. Apply the Strata refinements above and finalise the selected family.
2. Commit the generated `.iconset` PNGs (or an outline-only SVG plus a
   deterministic AppKit port). Replace `render-document-icons.swift` output in
   `scripts/build-app.sh`, keeping `iconutil`.
3. Add icons for the existing GZIP/BZIP2/XZ/ZSTD document types. Consider
   imported UTIs for `.tgz/.tbz2/.txz/.tzst` aliases, all still Viewer/Alternate.
4. Update `scripts/verify-document-icons.py`, `tests/test_document_icons.py`
   and `docs/document-icons.md`.
5. Treat the Quick Look thumbnail extension for split volumes as a separate,
   prototype-first task.
