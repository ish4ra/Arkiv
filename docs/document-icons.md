# Archive document icons

Arkiv's document icons use the **C · Seal Dark (Aubergine)** family. Each
document is a lacquered aubergine sheet bound by a near-black spine with a
champagne-brass seam. A jade pressure stud carries a restrained halo, labels
are ivory, and each format has its own folded-ribbon artwork. Small sizes
(16 and 32 pt) use dedicated simplified artwork, not downscaled copies. The
Tension Seal app icon is unchanged; its renderer and the six branding exports
are pinned by `branding/app-icon-preservation.json`.

## Format-to-icon matrix

| Icon resource | Artwork | Content type (Info.plist) | Finder shows it for |
| --- | --- | --- | --- |
| `Arkiv-ZIP.icns` | ribbon zip: interlocking teeth, brass slider | `public.zip-archive` | `.zip` |
| `Arkiv-7z.icns` | seven-petal rosette around a jade stud | `org.7-zip.7-zip-archive` (imported) | `.7z` |
| `Arkiv-RAR.icns` | pressed three-layer block | `com.rarlab.rar-archive` (imported) | `.rar` (read-only support) |
| `Arkiv-TAR.icns` | wound tape spiral | `public.tar-archive` | `.tar` |
| `Arkiv-GZIP.icns` | pleated ribbon between brass plates | `org.gnu.gnu-zip-archive` (imported) | `.gz`, including `.tar.gz` |
| `Arkiv-BZIP2.icns` | sorted ribbon bands | `public.bzip2-archive` (imported) | `.bz2`, including `.tar.bz2` |
| `Arkiv-XZ.icns` | crystal (diamond) ribbon | `org.tukaani.xz-archive` (imported) | `.xz`, including `.tar.xz` |
| `Arkiv-ZSTD.icns` | speed Z-fold | `org.zstandard.zstd` (imported) | `.zst`, `.tzst`, including `.tar.zst` |
| `Arkiv-TGZ.icns` | tape spiral + GZIP medallion, coral fold | `org.gnu.gnu-zip-tar-archive` (declared by macOS) | `.tgz` |
| `Arkiv-TBZ2.icns` | tape spiral + BZIP2 medallion, moss fold | `public.tar-bzip2-archive` (declared by macOS) | `.tbz2`, `.tbz` |
| `Arkiv-TXZ.icns` | tape spiral + XZ medallion, iris fold | `org.tukaani.tar-xz-archive` (declared by macOS) | `.txz` |

Every type is registered as **Viewer** with **LSHandlerRank Alternate**.
Imported declarations conform to `public.data` and `public.archive` (see
[the TAR.XZ investigation](#tarxz-and-imported-type-investigation)). Arkiv
exports no types and never changes a default application.

## Alias decisions

* **`.tgz`, `.tbz2`/`.tbz`, `.txz`:** macOS declares `org.gnu.gnu-zip-tar-archive`,
  `public.tar-bzip2-archive` and `org.tukaani.tar-xz-archive`. This was confirmed
  on the macOS 15 CI runners, which have no Arkiv type registered. Arkiv only
  attaches Viewer/Alternate document types and icons to these, with no new
  declarations. `scripts/diagnose-document-types.swift` prints each declaring
  bundle and fails packaged-app verification if a suffix stops resolving to its
  declared type.
* **`.tzst`:** macOS has no type for it, so it stays on `org.zstandard.zstd` (where
  Arkiv already declared it), and an association the user made for it does not move. It therefore shows the
  ZSTD icon. The TZST/TAR.ZST artwork is kept in `design/document-icons`.

## Finder limitations

* Finder uses a document-type icon only when Arkiv is the default app for that
  type (Get Info → Open with → Change All), because Arkiv only imports these
  types and does not own them. Another app's icon, a custom icon on the file, or
  a Quick Look thumbnail can take precedence.
* Finder types a file by its last extension, so `name.tar.gz` gets the GZIP icon
  and `name.tar.zst` the ZSTD icon. Compressed-TAR artwork can appear only for
  single-suffix aliases with their own type (`.tgz`, `.tbz2`/`.tbz`, `.txz`).
* **Split 7z volumes** (`name.7z.001`, `.002`, …) are typed by the generic
  numeric suffix, which unrelated software also uses. Arkiv does not register
  `.001`-style suffixes and never writes icons into user files. The approved
  volume artwork is kept for a dedicated Quick Look thumbnail-extension task,
  which could check the name pattern and 7z signature before drawing.
* Multipart RAR (`.part1.rar`, `.r00`) and split ZIP (`.z01`, `.zip.001`) volume
  artwork are **future concepts only**. Those formats are not supported.
* LaunchServices re-reads document icons when the updated app is registered.
  Finder may keep showing cached icons for a while; do not reset LaunchServices
  or Finder caches as part of installation.

## Finder and Desktop display investigation (open)

**Observed on a real Mac (build 26501):** Get Info for `~/Desktop/Arkiv-Test.zip`
shows the Seal Dark ZIP icon, with Arkiv as the default app, but the Desktop
showed a generic icon for the file.

**What this establishes:**
* Get Info asks Icon Services for the file's icon at the time you open it.
* Because Get Info shows the Seal Dark icon, Arkiv's document-type
  registration, the packaged `Arkiv-ZIP.icns` and the default-handler binding
  are all working.
* The difference is therefore in how the Desktop draws that item, not in
  Arkiv's resources.

**Candidate explanations** (not yet confirmed; no claim of resolution):
1. **Stale Desktop icon.** The Desktop is still drawing the icon it cached for
   the item before build 26501 was registered. Finder refreshes items
   individually.
2. **Stale preview thumbnail.** The Desktop has **Show icon preview** enabled
   and is drawing a Quick Look thumbnail cached before the update. A thumbnail
   is shown instead of the document icon.
3. **Another icon source.** A per-file custom icon, or another registered copy
   of Arkiv, takes precedence. This is less likely, because Get Info would
   usually reflect a custom icon too.

**Read-only diagnostic:** run `scripts/diagnose-finder-document-icons.sh
~/Desktop/Arkiv-Test.zip` on the affected Mac. It prints:
* the file's content type, dates and extended attributes
* the default handler and its build
* the icon Icon Services returns, saved as a PNG
* every Arkiv copy Spotlight knows about
* the Desktop view options
* a freshly rendered Quick Look thumbnail

It resets no caches, registers nothing, changes no defaults and does not touch
the file.

**Remaining real-Mac tests**
* Create a new archive on the Desktop after the update. If it shows Seal Dark
  while the old one does not, explanation 1 or 2 applies to the old item only.
* Compare the result with **Show icon preview** on and off (Desktop → View
  Options), which separates explanation 2 from 1.
* Repeat in a Finder window (icon, list, column views) to see whether the
  difference is Desktop-only.
* Whether a Finder relaunch changes the result. This is optional and only by
  the user's choice; Arkiv never does it.

Arkiv will not reset caches, change default applications, modify users'
archives or register generic numeric extensions to work around this.

## TAR.XZ and imported-type investigation

**Observed on a real Mac:** ZIP files show Arkiv's Seal Dark icon, but
`Sparkle-2.10.0.tar.xz` shows the generic macOS XZ icon.

**Confirmed on macOS 15 CI runners** with
`scripts/diagnose-document-icon-coverage.swift`:
* `.tar.xz` files, in any letter case and including `Sparkle-2.10.0.tar.xz`,
  are typed `org.tukaani.xz-archive` from their last extension. The compound
  tag `tar.xz` resolves to no type at all, so no app can give `.tar.xz` its own
  Finder icon.
* Arkiv's XZ document type uses that same identifier, with `Arkiv-XZ.icns`, and
  Arkiv is registered as a handler for it. The registration is correct.
* On a stock Mac, **Archive Utility** is the default app for ZIP, TAR, GZIP,
  BZIP2, XZ, TGZ, TBZ2 and TXZ. Arkiv registers as `Alternate` and never takes
  the default, so Finder draws the default app's icon.

**Root cause:** Arkiv is the default app for ZIP on that Mac, but not for XZ.
Finder therefore draws Archive Utility's XZ icon. It is not a missing resource
or a UTI mismatch. **To check it on your Mac:**
`swift scripts/diagnose-document-icon-coverage.swift --file ~/Downloads/Sparkle-2.10.0.tar.xz`
prints the default app for the file. **To change it:** Get Info → Open with →
Arkiv → Change All. Finder then shows the Seal Dark XZ icon for every `.xz` and
`.tar.xz`. A Sparkle update keeps the same bundle identifier and document types,
so it does not change which app is the default.

**A real registration bug found during the audit, and fixed:** `.rar`, `.zst`
and `.tzst` stayed *dynamic* types even in a fresh process, although
LaunchServices listed Arkiv's imported declarations as active and trusted. Those
declarations conformed only to `public.archive`, while lookup by filename
extension matches types conforming to `public.data`. Keka's declarations conform
to both. Arkiv's imported declarations now conform to `public.data` and
`public.archive`. `scripts/verify-document-icons.py` and
`tests/test_document_icons.py` enforce this, and the CI experiment re-checks the
lookups in a fresh process.

**Not resolved by CI:** after the throwaway runner made Arkiv the default for
XZ, the icon returned in the same process did not change within 30 s. The
experiment now repeats the check in a fresh process to separate in-process
caching from Finder behaviour. The real-Mac test after **Change All** is the
deciding check.

## Themes and archives

Build 26501's refined Seal Dark family is the permanent default and the only
bundled document-icon family. Every other design is preserved on
[`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1) and
[`archive/document-icon-concepts-v2`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v2/design/document-icon-concepts-v2).
Every other preserved design is an optional, signed, download-on-demand
theme (roadmap milestone 2, in review): Settings → Appearance → Document Icon
Theme. Downloaded themes apply inside Arkiv; Finder keeps these bundled icons.
See [document icon themes](document-icon-themes.md) and the
[inventory](document-icon-theme-inventory.md).

## Pipeline

* **Committed artwork.** `Resources/DocumentIcons/Arkiv-<name>.iconset/` holds
  all ten macOS representations per icon (16, 32, 128, 256, 512 pt at 1× and
  2×) as 8-bit RGBA, non-interlaced PNGs with real transparency and no
  metadata chunks. `SHA256SUMS` lists each file's bytes; `PIXELS.sha256` lists
  each file's decoded pixels (see below).
* **Build.** `scripts/build-app.sh` checks the checksums, then
  `scripts/package-document-icons.py` runs Apple's `iconutil` on each iconset
  and keeps the committed compression (below). Nothing is rendered at build
  time, so packaging is deterministic and needs no Node, fonts, browser or
  optimizer.
* **Design source.** `design/document-icons/` (see its README) holds the
  procedural generator and the lossless optimizer. Labels are converted to
  outlines from the vendored Inter Display (OFL), and `node generate.mjs
  --check` re-renders, optimizes and reproduces every committed PNG
  byte-for-byte. It is design-time only and adds nothing to the app.
* **Concept archive.** The five explored families, surface studies and original
  boards are preserved on the `archive/document-icon-concepts-v1` branch.

## Lossless optimization

The bundled PNGs are build 26501's renders, recompressed losslessly with a
pinned optimizer (oxipng 9.1.1 via hash-locked pyoxipng, level 6, libdeflate
level 12, with every colour-type, bit-depth, palette and alpha reduction
disabled). The artwork, colours, proportions, symbols, transparency, sizes,
representations and the original app icon are unchanged.

| | Build 26501 | Optimized | Change |
| --- | ---: | ---: | ---: |
| 110 PNGs | 7,808,654 bytes | 6,334,859 bytes | −1,473,795 (−18.9%) |
| 1024 px representations (11) | 4,148,952 bytes | 3,191,773 bytes | −23.1% |
| 11 packaged ICNS | 10,368,446 bytes | 6,359,786 bytes | −4,008,660 (−38.7%) |

Measured by CI on 2026-11-22, same run and runner as the baseline:

| Artifact | arm64 before → after | Universal before → after |
| --- | ---: | ---: |
| App bundle (apparent size) | 17.26 → 13.25 MB (−23.2%) | 20.64 → 16.63 MB (−19.4%) |
| App bundle (allocated, `du`) | 17.50 → 13.50 MB | 20.88 → 16.88 MB |
| Update archive ZIP (Sparkle payload is the Universal one) | 13.07 → 8.91 MB (−31.8%) | 14.30 → 10.15 MB (−29.1%) |
| DMG (UDZO) | 13.33 → 9.06 MB (−32.0%) | 14.70 → 10.42 MB (−29.2%) |

The ICNS saving is larger than the PNG saving because iconutil's own
re-encoding was larger than the source PNGs (below).

**Packaging keeps the compression.** `iconutil` re-encodes every PNG it
embeds. On `main`, the 11 ICNS files hold 10,368,446 bytes, more than the
7.81 MB of source PNGs. Recompressing the PNGs alone therefore changed
nothing in the app. `scripts/package-document-icons.py` lets `iconutil`
write each ICNS as usual: element types and order, the non-PNG 16/32 pt 1×
elements (`ic04`, `ic05`) and the `info` element. In each embedded PNG it
then replaces only the IDAT data with the committed PNG's. It does this only
when the IHDRs are identical, the committed PNG has no ancillary chunks, and
the result decodes to iconutil's pixels and to `PIXELS.sha256`. iconutil's
other chunks (on the macOS 15 runners, `sRGB` and `eXIf`) are kept exactly.
Packaged-app verification rebuilds this from the committed iconsets and
requires a byte-for-byte match.

Packaged ICNS, app bundle, update ZIP and DMG sizes are measured by the
informational **Document icon size report** step of both macOS CI jobs, which
compares this build with `main` in the same run.

**Pixel equivalence.** `PIXELS.sha256` holds, for every representation, the
SHA-256 of its decoded `WIDTHxHEIGHT\n` + 8-bit RGBA bytes. It is
byte-identical to the manifest recorded for this theme on
`archive/document-icon-concepts-v2`, and the test suite pins its hash. CI
decodes all 110 PNGs with a standard-library decoder and requires an exact
match, including the colour channels of fully transparent pixels. Packaged-app
verification parses each ICNS and checks every embedded PNG against the same
manifest.

**Reproducibility.** The optimizer uses no timeout and its result does not
depend on thread count or machine speed. A dedicated CI job re-optimizes
build 26501's renders on both macOS architectures and requires
byte-identical output.

**Not done: duplicate representations.** 128 pt @2x is identical to 256 pt
@1x, and 256 pt @2x to 512 pt @1x, in all 11 families (22 pairs, 1.48 MB
after optimization). ICNS has no way to reference one image from two slots,
and omitting a slot changes what Icon Services is asked to pick from. This is
deferred until it is shown on real Macs; see the
[investigation](document-icon-themes.md#duplicate-representation-investigation-deferred).

## Automated checks

`tests/test_document_icons.py` (CI, both architectures) and
`scripts/verify-document-icons.py` (packaged app, mounted DMG and extracted
update payload, via `verify-app.sh`) cover:
* registrations, roles and ranks, alias mappings and imported declarations
* no generic numeric or volume extension claims
* complete iconsets with exact pixel sizes, transparent corners, opaque centres and anti-aliased edges
* checksum integrity and exact decoded-pixel identity with `PIXELS.sha256`
* only IHDR/IDAT/IEND chunks in each PNG
* decoding of each packaged ICNS back into all ten representations, and pixel identity of its embedded PNGs
* exactly the expected icon set in the bundle, and preservation of the original app icon

## Delivery

The icons are ordinary resources inside `Arkiv.app`, so they ship in the same
signed Sparkle update archive as the rest of the app. No separate DMG download
is needed.

## Real-Mac visual acceptance (not automated)

1. Install the packaged app and confirm the original app icon is unchanged.
2. Associate representative `.zip .7z .rar .tar .gz .bz2 .xz .zst .tgz .tbz2 .txz` files
   with Arkiv via Get Info → Open with only if you want to. Existing defaults
   stay yours.
3. Inspect Finder icon, list, column and gallery views at 16–512 pt, on Retina
   and non-Retina displays, in light and dark appearance and on tinted desktops.
4. Confirm `.tar.gz`/`.tar.zst`/`.tzst` show their compressor icon, `.tgz`/`.tbz2`/`.txz`
   their TAR-family icon, and that `.7z.001` is unaffected.
5. After a Sparkle update from the previous build, confirm the new icons appear
   without manual cache resets (allow for Finder's own refresh delay).
