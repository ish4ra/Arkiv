# Document icon themes

**Status:** downloadable theme packs and the **Settings → Document Icons**
gallery are implemented and integrated (roadmap milestone 2, `d70c14c`, first
shipped in development build 30201). Selected themes apply **inside Arkiv's
own windows** and switch immediately, without reopening archives. Finder and
Get Info keep the bundled Seal Dark icons; a Quick Look thumbnail prototype is
evaluated separately ([feasibility report](quicklook-thumbnail-feasibility.md)).

**Production activation (verified by the maintainer):** the signed production
catalogue and all 20 theme packs are published (`document-icon-themes-v1`),
and build 30701 embeds the production theme public key. On a real Apple
Silicon Mac the catalogue loads (20 themes available) and Folio Dark was
downloaded and applied. Persistence across relaunch, offline use, removal,
every in-app icon consumer and the redesigned gallery still need complete
real-Mac acceptance ([checklist](#remaining-real-mac-acceptance)).

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

## Settings → Document Icons

A native AppKit pane (`Sources/ArkivApp/DocumentIconThemePane.swift`),
redesigned after build 30701:

* **Banner:** the theme in use with its ZIP artwork, its family, whether it is
  included or downloaded, and **Restore Default**.
* **Theme list:** "Included with Arkiv" first, then each family under a fixed
  heading. Headings no longer float: in build 30701 the list used
  `floatsGroupRows` (the NSTableView default) with bare text-field group rows,
  so the floating heading was drawn over the rows beneath it while scrolling.
  Each theme shows a thumbnail, its name and a text status (never colour
  alone): In use, Included, its download size, Downloading %, Installing,
  Downloaded, Update available. A family's variations fold under their parent
  theme behind **Show N variations**; showing a variation unfolds it. A
  **filter** field matches names and families and lists matching variations
  directly.
* **Thumbnails without network:** list thumbnails come only from artwork
  already on the Mac (the bundled icons, installed themes, or a preview pack
  verified earlier). A theme never previewed shows a neutral placeholder;
  nothing is downloaded to fill the list.
* **Detail view:** name, family, kind and parent; Download (with its size),
  Apply and Remove next to the title, with a progress bar and Cancel while
  downloading; which formats a variation changes; coverage notes (Classic);
  then one preview card of the theme's own 128 px artwork: the 11 Finder
  formats in a 6-column grid and, under **Inside Arkiv only**, the six
  compound-suffix and split-volume icons. Every cell has the same fixed width.
  In build 30701 the in-app extras sat in an `NSGridView` whose columns took
  the width of their captions (`.tar.bz2 · family`) plus 18 pt spacing, which
  pushed those icons far apart; captions are now short labels, and artwork a
  theme lacks is dimmed with an explanatory tooltip.
* **Actions:** Download, Cancel, Apply, Remove (removing the theme in use
  asks first, with a destructive button, then switches to Seal Dark),
  Restore Default, Refresh Catalogue.
* **States:** verified catalogue; offline, showing the last verified
  catalogue; rejected or failed catalogue; not configured (a build without a
  theme key; installed themes keep working).
* **Boundary note, shown in the pane:** downloaded themes apply inside Arkiv;
  Finder keeps the bundled Seal Dark document icons. Arkiv never modifies its
  app bundle, archives or default apps.

## Where a theme applies

| Surface | State |
| --- | --- |
| Archive rows inside Arkiv (nested archives such as `inner.zip`, `inner.tar.xz`, `set.7z.001`) | **Implemented.** 16 pt (24 pt in Comfortable density) artwork of the selected theme, including compound-suffix and split-volume artwork; other files keep their system icons. Redrawn in place when the theme changes |
| Window title-bar proxy icon of an open archive | **Implemented**, redrawn in place |
| Path bar (archive item) | **Implemented**, redrawn in place |
| Archive Info | **Implemented** (64 pt), redrawn while the sheet is open |
| Welcome window recent archives | **Implemented** |
| Password prompt and Finder operation progress panel | **Implemented** (artwork of the archive being unlocked or processed) |
| Settings → Appearance preview and Document Icons banner | **Implemented** |
| Finder document icons (icon, list, column views, Get Info) | **Not changed.** Finder reads `CFBundleTypeIconFile` from the signed bundle; there is no supported way to point it elsewhere |
| Quick Look thumbnails | **Prototype only, not shipped.** A sandboxed `QLThumbnailProvider` is built into a copy of the app on CI runners; see the [feasibility report](quicklook-thumbnail-feasibility.md) |
| Per-file custom icons | **Rejected.** They would write into users' files |

**Which artwork a name gets** (full table:
[format and icon coverage](format-icon-coverage.md)):
* **Inside Arkiv**, the longest suffix wins, case-insensitively.
  * `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst` and `.tzst` use their
    preserved compressed-TAR artwork; `.tgz`, `.tbz2`/`.tbz` and `.txz` use
    TGZ, TBZ2 and TXZ.
  * Split 7z volumes use the volume artwork, by exactly the engine's own rule
    (`.7z.` followed only by digits). A bare `.001` is never assumed to be 7z.
  * Names only choose artwork; archive detection stays content-based.
* **Bundled Seal Dark** ships this in-app artwork as PNGs in
  `Contents/Resources/DocumentIconsInApp`, at 16 pt and the 128 pt tier, 1×
  and 2×: 24 files, 307,048 bytes.
  * They come from the archived 26501 generator through the verified pipeline.
  * Their pixels are pinned in `Resources/DocumentIconsInApp/PIXELS.sha256`.
* **Downloaded themes** use the extras in their packs. A theme without one
  falls back to its family icon (TAR.XZ → TXZ, TZST → ZSTD, 7z volume → 7z),
  and a theme without that either (Classic) keeps the system icon.
* **Finder** follows `Resources/Info.plist` and the type macOS assigns to the
  **last** extension. So `name.tar.gz` shows GZIP, `name.tar.xz` shows XZ and
  `.tzst` shows ZSTD, and only while Arkiv is the default app for that type.
  Generic numeric suffixes are never claimed.

Theme changes apply immediately to every open window, through the
`ArkivDocumentIconThemeDidChange` notification; no restart is needed.

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

**Determinism and the rendering toolchain:**
* The CI job "Document icon themes" rebuilds every pack from scratch on a
  stock Ubuntu runner and requires byte-identical packs and catalogue payload.
* **The rendering toolchain the archives needed** was Chrome for Testing
  **157.0.8103.78**'s headless shell, launched with `--font-render-hinting=none
  --disable-lcd-text --force-color-profile=srgb`. The archives did not record
  those switches; they came from the original environment's launch wrapper.
  The first CI run found the gap and failed closed.
* What changes without each part, found by bisection:
  * **Without the switches:** archive v1's font-drawn labels rasterize
    differently.
  * **With stock Playwright 1.63.0's own 153.0.8010.12 build:** 1,806 of the
    1,824 v1 references match, but 18 Strata 512 px renders differ.
* `design/document-icon-themes/fetch-headless-shell.sh` installs the official
  157.0.8103.78 build, pinned by SHA-256. `render.mjs` checks the version and
  launches every browser, including the unmodified archived scripts, with the
  switches.
* Verified locally with that build: the bundled Seal Dark PNGs regenerate
  byte-for-byte (`node design/document-icons/generate.mjs --check`), all
  1,824 archive-v1 renders are pixel-identical, and every pack is
  byte-identical to `inventory.json`.

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
  environment, after a maintainer approves the deployment. See
  [publication safety](#publication-safety) for the order of steps and how
  interrupted runs resume.

## Provisioning (maintainer)

For the complete, step-by-step first launch (encrypted key storage, environment
protection, publication, the trusting app build and verification), follow the
[launch guide](document-icon-theme-launch.md). This section is the reference.

There is no production theme key yet, and none should ever be generated in a
cloud session or CI. CI signs only with throwaway keys from `test-key`, which
must never be configured in GitHub.

**Commands** (`scripts/document-icon-theme-catalog.swift`):

| Command | Purpose |
| --- | --- |
| `production-key <folder>` | The real key pair. The folder must be outside any Git checkout. Refuses to overwrite anything. Writes the private key with mode 0600 in a 0700 folder and never prints it; prints the public key and its key ID |
| `verify-keypair` | Checks that `ARKIV_THEME_PRIVATE_ED_KEY` belongs to `ARKIV_THEME_PUBLIC_ED_KEY`, and refuses either if it equals a Sparkle key. Prints key IDs only. The publish job runs it before signing |
| `test-key <folder>` | Throwaway keys for CI and local tests only |

**On your Apple Silicon Mac** (Xcode Command Line Tools and the GitHub CLI,
`brew install gh`, signed in with `gh auth login`):

1. Generate the key **outside the repository**. Run this from your Arkiv
   checkout (the folder must not exist inside it):

   ```bash
   swift scripts/document-icon-theme-catalog.swift production-key ~/ArkivThemeSigning
   ```

   It prints the public key and a key ID, and writes
   `~/ArkivThemeSigning/arkiv-theme-signing.key` (private, mode 0600) and
   `arkiv-theme-signing.pub`.
2. Optionally check the pair, without printing the private key:

   ```bash
   ARKIV_THEME_PRIVATE_ED_KEY="$(cat ~/ArkivThemeSigning/arkiv-theme-signing.key)" ARKIV_THEME_PUBLIC_ED_KEY="$(cat ~/ArkivThemeSigning/arkiv-theme-signing.pub)" swift scripts/document-icon-theme-catalog.swift verify-keypair
   ```

3. In GitHub, **Settings → Environments → New environment**
   `document-icon-themes`:
   * add yourself under **Required reviewers**
   * under **Deployment branches and tags**, choose *Selected branches* and allow only `main`
4. Store the private key as an environment secret, reading it from the file so
   it never appears in your shell history:

   ```bash
   gh secret set ARKIV_THEME_PRIVATE_ED_KEY --repo ish4ra/Arkiv --env document-icon-themes < ~/ArkivThemeSigning/arkiv-theme-signing.key
   ```

5. Store the public key as a repository variable. Builds made after this embed
   it, which turns on downloads in Settings:

   ```bash
   gh variable set ARKIV_THEME_PUBLIC_ED_KEY --repo ish4ra/Arkiv < ~/ArkivThemeSigning/arkiv-theme-signing.pub
   ```

6. Move the private key into your password manager (or another offline
   backup). Then delete the local copy:

   ```bash
   rm -P ~/ArkivThemeSigning/arkiv-theme-signing.key
   ```

   If the key is lost, publish with a new key after shipping a build that
   trusts it (rotation, below).
7. Never reuse Sparkle's key: `production-key`, `sign`, `verify-keypair` and
   the build all refuse it.

**Publishing:** Actions → **Document icon themes** → *Run workflow* on `main`
with **publish** checked. Review the run's inventory, then approve the
`document-icon-themes` deployment. The publish job:
1. checks that the key pair matches
2. signs the catalogue, then publishes as described under [publication safety](#publication-safety)

**Rotation:**
1. Add the new public key next to the old one. The verifier accepts any
   configured key; the build embeds one today, so extend
   `ArkivDocumentIconThemePublicEDKey` handling before a rotation.
2. Ship a build that trusts both keys.
3. Then switch the secret to the new key.

## Publication safety

`scripts/publish-document-icon-themes.py` never exposes an incomplete
catalogue, and every step can be retried safely:

1. **Checks before anything is uploaded:**
   * the signature verifies, as does the signature of the catalogue it replaces
   * the catalogue version increases
   * a theme version that was already published keeps exactly the same pack and preview
   * every asset of this release matches the signed size and SHA-256
   * every asset refers to a `document-icon-themes-v*` release, never `dev-*`, `updates` or `development-updates`
2. **Draft release:** the release `document-icon-themes-v<N>` is created as a
   **draft**, which is invisible to the public and never "Latest". Assets are
   uploaded, then compared with GitHub's own SHA-256 digests.
   * A rerun completes or repairs its own draft: it deletes partial or wrong
     uploads and uploads what is missing.
   * Nothing is overwritten.
3. **Publishing the release:** only a complete, verified draft is published,
   as a prerelease with `--latest=false`. A release that is already published
   is accepted only if it is complete and identical; published assets are
   never changed.
4. **Before the catalogue:** every asset the catalogue references, including
   those in older theme releases, must download back byte-identical from its
   public URL.
5. **The catalogue, last:** it is committed to the single-file
   `document-icon-themes` branch with a normal push. A concurrent publication
   is rejected, and history is never rewritten.
   * The workflow's `concurrency` group also serialises runs.
   * A failed push is retried by rerunning, which finds the published release
     complete.

6. **Finding the draft again:** GitHub can take a moment to list a draft it
   has just created. In run [45578558002](https://github.com/ish4ra/Arkiv/actions/runs/45578558002)
   attempt 1, the lookup right after creation returned nothing and
   `complete_release` crashed with `TypeError: 'NoneType' object is not
   subscriptable`; attempt 2 resumed the draft and published it. The draft is
   now looked up again with a doubling wait (2, 4, 8, 16 and 32 s, about a
   minute) after it is created and before each later step. It is created at
   most once per run. If GitHub never lists it, publication stops with a
   message to rerun, and nothing is uploaded, published or pushed. Two
   releases with the same theme tag (possible for drafts, which have no tag
   yet) stop publication instead of acting on whichever is listed first.
   The published `document-icon-themes-v1` release and catalogue version 1
   were not touched by this fix.

These paths are covered by `PublicationRecoveryTests`:
* delayed draft visibility (listed after several lookups; never listed, then
  resumed by a rerun without a second draft; lost during uploads)
* ambiguous drafts with the same tag, across result pages
* interrupted and corrupted uploads
* a tampered public download
* a rejected catalogue push
* an immutable published release
* repeated publication

## Remaining real-Mac acceptance

The maintainer has verified on a real Apple Silicon Mac (build 30701) that the
production catalogue loads with 20 themes and that Folio Dark downloads and
applies. Automated CI covers verification, installation, removal, failure
handling, immediate in-app switching across windows, offline use after a
simulated relaunch, damaged-theme fallback and rendering of the pane. These
still need a person at a Mac:

1. Open Settings → Document Icons. The catalogue loads, the banner names the
   theme in use, the list headings stay put while scrolling, variations fold
   and unfold, the filter works, and full previews appear only for the theme
   being shown.
2. Download a theme, watch the progress and Cancel it; download it again, then
   Apply. With two archive windows and Archive Info open, every visible icon
   updates at once without reopening anything: nested archive rows, the
   title-bar proxy icon, the path bar, Archive Info, the welcome window's
   recent archives.
3. Quit and relaunch: the theme persists; Finder and Get Info still show Seal Dark.
4. Turn Wi-Fi off and reopen the pane: an offline notice, installed themes
   still apply, list thumbnails of previewed themes remain, and previews of
   themes never shown are unavailable.
5. Remove the theme in use: the confirmation appears and Arkiv returns to Seal Dark.
6. Damage an installed theme (edit one PNG in its folder): Arkiv falls back to
   Seal Dark everywhere and the pane says the theme is damaged.
7. Check VoiceOver labels and keyboard navigation in the list, filter and
   buttons, in light and dark appearance, and at 1× and 2×.
8. Visually compare each theme's 16, 32 and 128 pt rendering in Arkiv with the
   archived review boards.
9. Measure installed size (`du -sh ~/Library/Application\ Support/Arkiv/DocumentIconThemes`)
   and confirm that `/Applications/Arkiv.app` and its signature are unchanged
   (`codesign --verify --deep --strict`) after installing themes.

## Runtime cost

* **At launch: none.** No theme code runs, nothing is read and nothing is
  requested. `DocumentIconProvider` is created lazily on first use.
* **No background agents, timers, login items or services.**
* **Network:** only while Settings → Document Icons is shown (one catalogue
  request of about 78 KB), plus user-started downloads and the preview pack
  (80–210 kB) of a theme the user selects. List thumbnails never download.
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
