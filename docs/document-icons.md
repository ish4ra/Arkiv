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
Imported declarations are unchanged from before this family, apart from the
icon references. Arkiv exports no types and never changes a default
application.

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

## Pipeline

* **Committed artwork.** `Resources/DocumentIcons/Arkiv-<name>.iconset/` holds
  all ten macOS representations per icon (16, 32, 128, 256, 512 pt at 1× and
  2×) as 8-bit RGBA PNGs with real transparency. `SHA256SUMS` lists each file.
* **Build.** `scripts/build-app.sh` checks the checksums and runs Apple's
  `iconutil` on each iconset. Nothing is rendered at build time, so packaging
  is deterministic and needs no Node, fonts or browser.
* **Design source.** `design/document-icons/` (see its README) holds the
  procedural generator. Labels are converted to outlines from the vendored
  Inter Display (OFL), and `node generate.mjs --check` reproduces every
  committed PNG byte-for-byte. It is design-time only.
* **Concept archive.** The five explored families, surface studies and original
  boards are preserved on the `archive/document-icon-concepts-v1` branch.

## Automated checks

`tests/test_document_icons.py` (CI, both architectures) and
`scripts/verify-document-icons.py` (packaged app, mounted DMG and extracted
update payload, via `verify-app.sh`) cover:
* registrations, roles and ranks, alias mappings and imported declarations
* no generic numeric or volume extension claims
* complete iconsets with exact pixel sizes, transparent corners, opaque centres and anti-aliased edges
* checksum integrity, decoding of each packaged ICNS back into all ten representations
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
