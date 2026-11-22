# Document icon themes

**Status:** downloadable theme packs and **Settings → Appearance → Document
Icon Theme** are implemented (roadmap milestone 2, in review). Selected themes
apply **inside Arkiv's own windows**. Finder and Quick Look keep the bundled
Seal Dark icons; changing them safely is unproven and remains milestone 4.
No production theme packs or signed catalogue are published yet; that needs
the maintainer steps under [provisioning](#provisioning-maintainer).

## What users get

* **Seal Dark** (the refined C · Seal Dark family from build 26501) is bundled,
  always available, and cannot be removed. It is the default.
* **20 optional themes**, each downloaded only when the user asks:
  * the explored families and surface studies: A · Folio, Folio Dark, B · Strata, C · Seal Original
  * the Seal Dark studies: Original Aubergine, Wine, Noir, and Restored Readability
  * Classic, the pre-redesign icons
  * all 11 superseded intermediate variations, each listed under its family

  The [inventory](document-icon-theme-inventory.md) gives each theme's source,
  coverage, download size and installed size.
* All artwork is the preserved artwork, rendered by the archived generators
  and verified against the archived pixel manifests. Nothing is redrawn,
  mocked up or simplified, and previews are the themes' own files.

## Settings → Appearance → Document Icon Theme

A native AppKit pane (`Sources/ArkivApp/DocumentIconThemePane.swift`):

* **Theme list:** "Included with Arkiv" first, then each family. Variations
  follow their family and are labelled as variations.
* **Row status, in text and never by colour alone:** In use, Bundled,
  Available with its download size, Downloading %, Installing, Installed,
  Update available.
* **Detail view:**
  * name, family, kind and parent
  * which formats a variation changes
  * coverage notes (Classic)
  * 11 previews of the theme's own 128 px artwork
  * download and installed sizes
* **Actions:**
  * **Download**, with a progress bar and **Cancel**
  * **Apply**
  * **Remove**: removing the theme in use asks first, then switches to Seal Dark
  * **Restore Default**
  * **Refresh Catalogue**
* **States:**
  * verified catalogue
  * offline, showing the last verified catalogue
  * rejected or failed catalogue
  * not configured (a build without a theme key; installed themes keep working)
* **Boundary note, shown in the pane:** downloaded themes apply inside Arkiv;
  Finder and Quick Look keep the bundled Seal Dark document icons until a
  safe, supported way exists. Arkiv never modifies its app bundle, archives
  or default apps.

## Where a theme applies

| Surface | State |
| --- | --- |
| Archive rows inside Arkiv (nested archives such as `inner.zip`) | **Implemented.** 16 pt artwork of the selected theme; other files keep their system icons |
| Window title-bar proxy icon of an open archive | **Implemented** |
| Archive Info | **Implemented** (64 pt) |
| Finder document icons (icon, list, column views, Get Info) | **Not changed.** Finder reads `CFBundleTypeIconFile` from the signed bundle; there is no supported way to point it elsewhere |
| Quick Look thumbnails | **Not implemented.** An opt-in, bundled `QLThumbnailProvider` remains the candidate (milestone 4); packs already carry the TAR.\* and volume artwork it would need |
| Per-file custom icons | **Rejected.** They would write into users' files |

Formats map to icons exactly as in `Resources/Info.plist`, using the last
extension: `name.tar.gz` gets GZIP, `.tgz` gets TGZ and `.tzst` gets ZSTD.
Generic numeric suffixes such as `.7z.001` are never claimed. Theme changes
apply immediately to every open window, through the
`ArkivDocumentIconThemeDidChange` notification; no restart is needed. A
partial theme (Classic) falls back to the system icon for the formats it never
had.

## Architecture

```
Sources/ArkivThemes/                  macOS-only module; CryptoKit, ImageIO, AppKit (system frameworks)
  ThemeModels.swift                   limits, icon names, catalogue and manifest types
  CatalogVerifier.swift               envelope, Ed25519 verification, validation, rollback
  ThemeDownloader.swift               bounded URLSession download, streamed SHA-256
  ThemePackValidator.swift            entry allowlist, hardened extraction, manifest and PNG checks
  ThemeStore.swift                    storage layout, atomic publication, selection, recovery
  DocumentIconThemeManager.swift      catalogue, downloads, install, apply, remove, previews
  DocumentIconProvider.swift          icons for Arkiv's UI, lazy and cost-bounded
Sources/ArkivApp/DocumentIconThemePane.swift   the Settings pane
```

**Storage, outside the signed bundle:**

```
~/Library/Application Support/Arkiv/DocumentIconThemes/
    catalog.json        last verified catalogue envelope
    <id>/<version>/     installed, verified files (read-only)
    .staging/<uuid>/    downloads being verified; never read as a theme
    .trash/<uuid>/      replaced or removed themes being deleted
~/Library/Caches/Arkiv/DocumentIconThemePreviews/<id>-<version>/   verified preview packs (purgeable)
```

The selection is `Arkiv.DocumentIconTheme` (`{id, version}`) in Arkiv's
UserDefaults; when absent, the bundled theme is used. The App Group container
needed by a future sandboxed Quick Look extension would hold the same layout.

### Catalogue

Hosted on the single-file `document-icon-themes` branch:
`https://raw.githubusercontent.com/ish4ra/Arkiv/document-icon-themes/catalog.json`.
This is not Sparkle's `updates` branch.

```json
{"schema": 1, "keyID": "<first 8 bytes of SHA-256(public key), hex>",
 "payload": "<base64 of the catalogue JSON>", "signature": "<base64 Ed25519>"}
```

* The signature covers `"Arkiv document icon theme catalogue v1\n"` followed
  by the exact payload bytes. It is made with a **dedicated Ed25519 theme key**
  and verified by **CryptoKit** (`Curve25519.Signing`). Several public keys can
  be configured, for rotation.
* Only the public key is in the app (`ArkivDocumentIconThemePublicEDKey` in
  Info.plist, from the `ARKIV_THEME_PUBLIC_ED_KEY` build variable). The build
  refuses a theme key equal to Sparkle's.
* The payload lists, per theme:
  * id, version, name, family, kind, parent, summary, coverage and extras
  * minimum app build, licence and provenance (archive branch, commit, source file)
  * the pack URL, size, SHA-256, installed size and file count
  * the preview pack URL, size, SHA-256 and every preview file's size, SHA-256 and dimensions
* **Accepted only if:**
  * the envelope has exactly its four keys and a 64-byte signature, from a configured key
  * the schema is known and the default theme is `seal-dark`
  * ids are unique, lowercase and hyphenated
  * text is bounded and free of control characters
  * every URL is HTTPS under `https://github.com/ish4ra/Arkiv/releases/download/`, with no query
  * sizes are within the limits below
  * coverage names only the 11 known icons and 8 known extras
  * every preview matches the coverage
* **Rollback:** a catalogue older than the highest version ever verified is
  rejected. That version is also kept in UserDefaults, so deleting the cache
  file does not reopen rollback. A different payload with the same version is
  rejected as equivocation.
* **Last-known-good:** the verified envelope is cached and re-verified on
  every read. If the network fails, the cached catalogue is shown as offline.
  A rejected catalogue is never shown as offline.

### Packs

`<id>-<version>.arkivtheme` is a ZIP using the Store method, with fixed
timestamps, mode 0444 and a fixed entry order. It contains:

* `theme.json`: id, version, name, licence, and for every covered icon and
  extra all ten representations, each mapped to a stored file with its size,
  SHA-256, dimensions and decoded-pixel hash
* `Arkiv-<NAME>.iconset/icon_<pt>x<pt>[@2x].png` for the 11 icons
* `extras/Arkiv-<NAME>.iconset/…` for TAR.GZ, TAR.BZ2, TAR.XZ, TAR.ZST,
  TZST, `7z-volume`, `RAR-volume-future` and `ZIP-volume-future`

Byte-identical representations (128 pt @2x = 256 pt, 256 pt @2x = 512 pt)
are stored once. The manifest still lists all ten representations of every
icon. The preview pack holds each covered icon's 128 px file, byte-identical
to the one in the pack.

### Download and installation

1. Download only after the user clicks Download, with an ephemeral
   `URLSession` (no cookies or cache).
   * The response must be HTTP 200.
   * Redirects are followed only to HTTPS `github.com`,
     `objects.githubusercontent.com` or `release-assets.githubusercontent.com`.
   * The transfer stops as soon as it would exceed the signed size.
   * The data is hashed while it streams into `.staging/<uuid>/`.
   * Progress is reported, and Cancel stops it.
2. Size and SHA-256 must equal the signed catalogue. The staged file is hashed
   again before it is parsed.
3. Entry list check (`LibArchiveEngine.inspect`): ZIP signature; at most 256
   entries; regular files only, so no links, folders, devices or encrypted
   entries; no executable, setuid or setgid bits; an exact path allowlist
   derived from the theme's coverage; no duplicate or case-folded duplicate
   paths; at most 2 MiB per file and 16 MiB in total.
4. Extraction with Arkiv's hardened extraction engine into the staging folder.
   The extracted tree must equal the checked list, with no links.
5. Manifest check: same id, version and coverage as the catalogue; every
   representation present; the exact file list; dimensions matching each
   representation; each file's size and SHA-256; installed size equal to the
   catalogue's.
6. Image check for every PNG:
   * signature, IHDR first, 8-bit RGBA, non-interlaced
   * only IHDR, IDAT and IEND chunks, each with a valid CRC, and nothing after IEND
   * exact dimensions
   * a single ImageIO image, fully decoded
7. Files are made read-only. The folder is published with one `rename(2)`; an
   existing copy of the same version is first moved to `.trash`.
8. A newer version replaces the older one. If the older version was in use,
   the selection moves to the new one.

Any failure discards the staging folder; the theme in use never changes.
Downloaded content is never executed: packs hold only PNG data and one JSON
manifest.

### Using installed themes

* Nothing is read at launch.
* The provider resolves the selection the first time an icon is drawn, and
  loads only the representations for the requested size.
* Every read re-checks the file's size and SHA-256 against the manifest. A
  missing or damaged theme falls back to Seal Dark, and Settings reports it.
* Images are held in a cost-bounded `NSCache` (96 images, 12 MiB), emptied when
  the selection changes.
* Previews are loaded only for the theme being shown, cached in a separate
  bounded cache (24 MiB), and released when the pane closes.

**Recovery.** When the pane opens, and no download is running, stale
`.staging` and `.trash` folders are removed. Theme folders without a valid
manifest, with a file list that differs from the manifest, or that are links
are ignored. Nothing is cleaned up at launch.

### Limits (enforced in the app and the pipeline)

| | Limit |
| --- | --- |
| Catalogue envelope | 1 MiB, at most 128 themes |
| Pack download | 16 MiB (largest pack today: 8.86 MB) |
| Installed theme | 16 MiB |
| Preview pack | 2 MiB |
| Files per pack | 256 (today: 137) |
| Single file | 2 MiB (largest: a 1024 px representation, under 0.5 MB) |
| Manifest | 256 KiB |

## Theme-pack pipeline (design-time and CI only)

`design/document-icon-themes/` (see its README) builds every pack from the
archive commits pinned in `themes.json`. It never uses a branch tip, and
nothing in it is built into the app.

1. `render.mjs` extracts both archives with `git archive` and runs the
   archived generators **unmodified**:
   * v1 `render.mjs`
   * v2 `iterations/render-iterations.mjs`
   * v2 `reproduce.mjs seal-dark-restored-readability` (0 of 175 files may differ)

   It then renders what the archives define but never rendered at every size:
   * each variation's formats, through its parent family's own pipeline, from
     the exact archived source substitutions (read from the archived script,
     not retyped)
   * the unregistered artwork of the two v2 Seal Dark themes

   Self-checks:
   * every variation, re-rendered at the archived script's sizes, must be
     byte-identical to its output
   * the extras' 512 px renders must be byte-identical to the preserved previews
2. `build.py`:
   * decodes every representation with the repository's standard-library
     decoder and requires its pixels to equal the archived manifest
     (`reference/v1-pixels.sha256`, the restored theme's `PIXELS.sha256`, or
     `Resources/DocumentIcons/PIXELS.sha256`)
   * renders an unaffected control icon from the unpatched parent source,
     which must equal the parent's archived pixels
   * requires every variation to change at least one icon
   * recompresses with the pinned lossless optimizer used for the bundled
     icons, then re-checks every pixel
   * deduplicates, then writes the packs, preview packs and the unsigned
     catalogue payload
   * compares everything with the committed lock, `inventory.json`
3. `scripts/document-icon-theme-catalog.swift` signs and verifies the payload
   with CryptoKit.

**Variations:**
* A variation is its parent family plus the archived variant artwork for the
  formats the archive records for it; nothing else changes.
* Three variations (`folio-xs-glyph-unit-60`, `seal-layout-v0`,
  `seal-layout-v0.5-large-glyph`) change layout code that every format shares.
  The archive records their artwork only for specific formats, so only those
  formats use it.
* Two Strata variations leave their TAR.\* format identical to Strata. The
  inventory lists, for each variation, the formats whose pixels actually differ.

**Determinism:**
* The CI job "Document icon themes" rebuilds every pack from scratch on Linux,
  with Playwright 1.63.0 / Chromium 157.0.8103.78 (the archives' toolchain),
  and requires byte-identical packs and catalogue payload.
* Verified locally: this toolchain also reproduces the bundled Seal Dark PNGs
  byte-for-byte (`node design/document-icons/generate.mjs --check`), and all
  1,824 archive-v1 renders pixel-identically.

## Distribution

* **Packs:** GitHub release `document-icon-themes-v<catalogue version>`. It is
  created as a prerelease, with `--latest=false`, so it can never become the
  repository's Latest release. Assets are immutable: an existing release is
  never overwritten, and unchanged packs keep their earlier URLs.
* **Catalogue:** the `document-icon-themes` branch, holding exactly one file,
  `catalog.json`. It advances with plumbing commits and a normal push; it is
  never force-pushed. Its version must increase.
* **Independence from app updates:**
  * Sparkle reads only `updates/appcast.xml`, whose single item must reference
    `releases/download/dev-<build>/Arkiv-universal.zip`
    (`scripts/update_channel.py`).
  * The theme tag namespace never overlaps `dev-*` or `development-updates`,
    and the publisher refuses those names.
  * Theme releases therefore cannot change Sparkle's build selection, the
    development feed, existing tags or signed app updates. Arkiv updates
    continue only through the signed Sparkle in-app updater.
* **Publishing** is the manual `publish` job of
  `.github/workflows/document-icon-themes.yml`: `workflow_dispatch` with
  `publish: true`, on `main` only, in the protected `document-icon-themes`
  environment. In order, it:
  1. signs with the theme key
  2. verifies the signature, and the published catalogue it replaces
  3. checks that the version increases and every asset matches the signed
     size and SHA-256
  4. uploads the assets, and requires each to download back byte-identical
  5. only then advances the catalogue branch

## Provisioning (maintainer)

None of this has been done; there is no production theme key yet. CI signs
only with throwaway keys generated per job.

1. On a trusted Mac, outside any repository, create the dedicated key:

   ```bash
   swift scripts/document-icon-theme-catalog.swift test-key ~/arkiv-theme-key
   ```

   Despite the subcommand's name, this is an ordinary Ed25519 key pair:
   `theme-test-signing.key` (private, base64 seed) and `theme-test-signing.pub`.
   Store the private key in your password manager, never in the repository,
   and never reuse Sparkle's key (the tools refuse it).
2. In GitHub, Settings → Environments → **New environment**
   `document-icon-themes`: add **required reviewers**, restrict it to `main`,
   and add the secret `ARKIV_THEME_PRIVATE_ED_KEY` (the private key file's
   contents).
3. In Settings → Secrets and variables → Actions → **Variables**, add the
   repository variable `ARKIV_THEME_PUBLIC_ED_KEY` (the public key). Builds made
   after this embed it, which enables downloads in Settings.
4. Delete the local key file once it is stored.
5. To publish: Actions → **Document icon themes** → Run workflow on `main` with
   **publish** checked, then approve the deployment after reviewing the
   inventory and screenshots of that run.
6. Rotation: add the new public key alongside the old one (the verifier
   accepts any configured key), ship a build, then sign with the new key.

## Remaining real-Mac acceptance

Automated CI covers verification, installation, removal, failure handling and
rendering of the pane. These need a person at a Mac:

1. Open Settings, then the Appearance tab. The window grows, the catalogue
   loads, and previews appear only for the selected theme. Other tabs stay compact.
2. Download a theme, watch the progress and Cancel it; download it again, then
   Apply. Open archives update immediately: the rows of nested archives, the
   title-bar proxy icon, and Archive Info.
3. Quit and relaunch: the theme persists; Finder still shows Seal Dark.
4. Turn Wi-Fi off and reopen the pane: an offline notice, installed themes
   still apply, and previews of themes not downloaded are unavailable.
5. Remove the theme in use: the confirmation appears and Arkiv returns to Seal Dark.
6. Check VoiceOver labels and keyboard navigation in the list and buttons, in
   light and dark appearance, and at 1× and 2×.
7. Visually compare each theme's 16, 32 and 128 pt rendering in Arkiv with the
   archived review boards.
8. Measure installed size (`du -sh ~/Library/Application\ Support/Arkiv/DocumentIconThemes`)
   and confirm that `/Applications/Arkiv.app` and its signature are unchanged
   (`codesign --verify --deep --strict`) after installing themes.

## Runtime cost

* **At launch: none.** No theme code runs, nothing is read and nothing is
  requested. `DocumentIconProvider` is created lazily on first use.
* **No background agents, timers, login items or services.**
* **Network:** only while the Appearance tab is shown (one catalogue request
  of about 78 KB), plus user-started downloads and the preview pack (80–133 kB)
  of a theme the user selects.
* **Disk:** only what the user downloads.
* **Bundle:** no artwork was added. The new Swift code is the only bundle
  increase; see [size](#size-impact).

## Size impact

* Optional artwork is never bundled. The bundle keeps exactly the 11 Seal Dark
  ICNS files, and packaged-app verification enforces that.
* The only increase is compiled Swift: the ArkivThemes module and the Settings
  pane. CI's informational size report step measures the app bundle, the
  update archive and the DMG.

## Size baseline (measured 2026-11-22)

**App download size (CI artifacts):**

| Build | arm64 DMG | Universal DMG | arm64 app ZIP | Universal app ZIP |
| --- | --- | --- | --- | --- |
| `4d80a94` (before Seal Dark icons) | 4.22 MB | 5.57 MB | 4.04 MB | 5.27 MB |
| `84320df` (build 26501, Seal Dark) | 13.33 MB | 14.71 MB | 13.02 MB | 14.25 MB |

The 11 bundled icon files held 7.81 MB of PNG data, which is most of the
increase. The 1024 px representations are 4.15 MB of that (53%).

**After lossless optimization (roadmap milestone 1, measured in CI):**
* PNG data: 6.33 MB (−18.9%), pixel-identical; the 1024 px representations are 3.19 MB.
* Packaged ICNS: 10.37 → 6.36 MB, because iconutil had re-encoded the PNGs larger.
* Universal update archive: 14.30 → 10.15 MB.
* DMGs: arm64 9.06 MB, Universal 10.42 MB.

See [document icons](document-icons.md#lossless-optimization).

**Ways to make the default lighter without changing a pixel.** Each needs
approval, because it changes shipped bytes:
1. **Lossless recompression (done, in review):** oxipng level 6 with
   libdeflate 12 takes 7.81 → 6.33 MB (−18.9%), verified pixel-identical.
   Level 4 gave 6.43 MB.
2. **Fewer duplicate representations:** 128 pt @2x equals 256 pt @1x, and
   256 pt @2x equals 512 pt @1x, accounting for 1.73 MB. Omitting the
   duplicates needs real-Mac confirmation that Finder still renders identically.
3. **Smaller updates:** Sparkle binary delta updates, so unchanged icons are
   not downloaded again with every update.

**Not yet measured** (needs a Mac):
* installed size (`du -sh /Applications/Arkiv.app`)
* launch time and resident memory (`/usr/bin/time -l`, Instruments)

The document icons are read by Finder and Icon Services, not by Arkiv at
launch, so no launch or memory cost is expected. That expectation is
unverified.

**Optional theme-pack sizes:** measured per pack in the [inventory](document-icon-theme-inventory.md) (0.54–8.86 MB per pack, with extras and every representation).

## Optimisation tasks

These are separate tasks, independent of the theme feature. The default
artwork stays build 26501's refined Seal Dark: none of these may change a
visible pixel.

1. **Pixel-identical lossless icon recompression: implemented (in review).**
   The 110 bundled PNGs go from 7,808,654 to 6,334,859 bytes, with every
   decoded pixel verified identical against `PIXELS.sha256`. `SHA256SUMS`, the
   generator and the tests are updated; see
   [document icons](document-icons.md#lossless-optimization).
2. **Duplicate-representation investigation: deferred** (below).
3. **Signed Sparkle delta updates.** Publish Sparkle binary deltas, signed and
   verified like full updates, so unchanged resources such as icons are not
   downloaded again. A full signed update must remain the fallback whenever a
   delta is missing or fails to apply.
4. **Real-Mac measurements.** Record installed size
   (`du -sh /Applications/Arkiv.app`), cold and warm launch time, and resident
   memory at launch and while browsing a large archive. Measure before and
   after any resource change.

## Duplicate-representation investigation (deferred)

**Findings (2026-11-22, automated):**
* In all 11 families, `icon_128x128@2x.png` is byte- and pixel-identical to
  `icon_256x256.png`, and `icon_256x256@2x.png` to `icon_512x512.png`: 22
  pairs, 1,726,055 bytes before and 1,477,371 bytes after optimization.
* `icon_16x16@2x.png` is *not* the same as `icon_32x32.png`: the 16 and 32 pt
  tiers have dedicated artwork, so they are not duplicates.
* ICNS stores each representation under its own element type (`ic13` for
  128 pt @2x, `ic08` for 256 pt, `ic14` for 256 pt @2x, `ic09` for 512 pt).
  The format has no way to share one payload between two types, so the only
  saving is to omit `ic13` and `ic14`.
* Omitting them changes what Icon Services selects from when drawing at
  128 pt and 256 pt on Retina displays. Whether every consumer (Finder icon,
  list, column and gallery views, Get Info, Quick Look, Dock, open/save
  panels) then picks the 256 / 512 px image unscaled cannot be shown on the
  headless CI runners, and Apple documents the full ten-image iconset.

**Decision:** not implemented. All ten representations stay in every ICNS,
and verification still requires them. Revisit only with a real-Mac
comparison across the supported macOS versions (13 and later), at 1× and 2×,
in light and dark appearance, showing identical rendering. The likely saving
is about 1.5 MB of ICNS data.

## Lightweight principle (applies to all future features)

Arkiv stays a small, fast, native Swift/AppKit app:
* Bundle only what the default experience needs; download optional content on demand.
* Keep optional content outside the signed bundle.
* Add no new runtime frameworks or background services.
* Do no work at launch that a feature does not need.
* Load lazily, with bounded caches.
* Measure the download size, installed size, launch time and memory of any
  change that adds resources.
