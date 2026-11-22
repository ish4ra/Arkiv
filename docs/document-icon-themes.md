# Document icon themes (planned, not implemented)

**Status:** roadmap only. This belongs to the final UI-customization
milestone, after the major archive-engine features. Nothing described here is
in current builds: no theme downloading, switching or settings UI exists yet.

## Decisions already made

* **Default:** the refined C · Seal Dark family shipped in build 26501 (`main`
  at `84320df`, `Resources/DocumentIcons`) is the permanent default. It is the
  only document-icon family bundled in Arkiv.app.
* **Optional themes:** every other preserved design is downloaded only when a
  user asks for it. The preserved designs are:
  * A · Folio, A · Folio Dark, B · Strata, C · Seal
  * C · Seal Dark: Aubergine concept, Wine, Noir
  * C · Seal Dark: restored readability candidate
  * superseded variants, if wanted as variants
* **Source of truth for all artwork:** the archive branches
  [`archive/document-icon-concepts-v1`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v1/design/document-icon-concepts-v1) and
  [`archive/document-icon-concepts-v2`](https://github.com/ish4ra/Arkiv/tree/archive/document-icon-concepts-v2/design/document-icon-concepts-v2) (see their `ARCHIVE.md`).
* **Previews:** use the actual preserved artwork, rendered by the archived
  generators. No simplified previews, invented icons or mock-ups.
* **App icon:** the Tension Seal app icon is not themed and is not changed.

## Planned user experience

**Settings → Appearance → Document Icon Theme**, as a native AppKit pane:

* Browse available themes, with previews of their real artwork (the 11
  shipped formats at 128 pt, plus 32 / 16 pt samples).
* Show download size and installed size per theme, and which are installed.
* Download individual themes with progress and **Cancel**.
* Select any installed theme. **Restore Default** returns to the bundled
  family, which can never be removed.
* Remove unused themes to reclaim disk space.
* Installed themes work fully offline. The catalogue is fetched only while the
  pane is open.
* An interrupted or failed download never changes the active theme, and leaves
  nothing half-installed.

## Architecture

**Storage, outside the signed bundle.** Arkiv.app is never modified at
runtime, so code signatures and Sparkle's update verification are unaffected.

```
~/Library/Application Support/Arkiv/DocumentIconThemes/
    catalog.json              last verified catalogue (optional cache)
    <theme-id>/<version>/     installed, verified, read-only to the app's logic
    .staging/<uuid>/          in-progress downloads; never read as a theme
```

If the Quick Look route below is adopted, installed themes live in an App
Group container that the sandboxed extension can read. The layout is the same.

**Catalogue and integrity**
* A versioned JSON catalogue, signed with a dedicated Ed25519 theme key (not
  Sparkle's update key) and verified with CryptoKit. CryptoKit is a system
  framework, so this adds no new dependency.
* Each entry lists:
  * theme id, version, minimum app version and licence/provenance note
  * pack URL, pack size and pack SHA-256
  * every file with its path, byte size, SHA-256 and expected pixel size
  * preview images, with their own checksums
* The catalogue is accepted only if the signature verifies and the version is
  not older than the cached one, which blocks rollback.

**Pack format**
* A ZIP using the Store method. PNG data is already compressed, and Deflate
  saves under 1%.
* Contents: `Arkiv-<NAME>.iconset/icon_<pt>x<pt>[@2x].png` for the 11 shipped
  types, deduplicated (see sizes below), plus preview PNGs.
* Extraction uses Arkiv's own hardened extraction engine with a strict
  allowlist: exact expected file names only, no directories beyond the
  iconsets, no links, at most 128 files, at most 2 MiB per file, and a total
  limit below 16 MiB. The download is aborted beyond the size declared in the
  catalogue.
* Every file's SHA-256 is checked, and each PNG is decoded with ImageIO to
  confirm the expected dimensions, RGBA format and transparent corners, before
  the staged folder is atomically renamed into place.

**Never execute downloaded content.** Packs contain only PNG data and
metadata. Anything else rejects the pack.

**Interruption and recovery**
* Downloads use a background-free `URLSession` task tied to the pane, with
  resume data where the server supports it.
* Stale `.staging` folders are removed the next time the pane opens or a
  download starts. This is never done at launch.
* The active selection is a theme id and version in `UserDefaults`. If that
  folder is missing or fails verification, Arkiv silently uses the bundled
  default.

**Runtime cost, with a target of none for users who never open the pane**
* No launch-time work, background agent, login item, timer or network access.
* Previews load lazily in the pane only, through an `NSCache` bounded by cost,
  and are released when the pane closes.
* Unselected themes are never read.
* Theme updates are independent of app updates: a new catalogue version can
  ship a new pack without a new Arkiv build.

## Where a theme can apply

| Surface | Feasibility | Notes |
| --- | --- | --- |
| Inside Arkiv's own windows (archive rows, Archive Info) | **Feasible** | Arkiv draws these itself and can use the selected theme's PNGs. |
| Finder document icons (Get Info, icon / list / column views) | **Not possible through supported means** | Finder takes document-type icons from `CFBundleTypeIconFile` inside the signed app bundle. No supported API points them at files outside the bundle. Changing the bundle would break its signature and Sparkle's verification. |
| Finder via a Quick Look thumbnail extension | **Possible, unproven** | A bundled, signed `QLThumbnailProvider` could draw the selected theme's artwork as a file thumbnail. See the caveats below. |
| Per-file custom icons | **Rejected** | Writes metadata into users' files and changes their ctime. Never used. |

Caveats for the Quick Look route:
* It needs an App Group shared with the sandboxed extension.
* Thumbnails replace icons for every file of a covered type, even when Arkiv
  is not the default app, so this must be opt-in.
* Finder caches thumbnails, and Arkiv must not reset that cache, so a theme
  change may not appear on existing files until macOS refreshes them.
* Finder shows thumbnails only where icon previews are enabled.
* The same extension is the planned home for the preserved split-volume
  artwork (`.7z.001` …) and for TAR.\* artwork on double suffixes.

It needs a real-Mac prototype before any promise is made. Until then, theme
switching is promised for Arkiv's own UI only.

## Size baseline (measured 2026-11-22)

**App download size (CI artifacts):**

| Build | arm64 DMG | Universal DMG | arm64 app ZIP | Universal app ZIP |
| --- | --- | --- | --- | --- |
| `4d80a94` (before Seal Dark icons) | 4.22 MB | 5.57 MB | 4.04 MB | 5.27 MB |
| `84320df` (build 26501, Seal Dark) | 13.33 MB | 14.71 MB | 13.02 MB | 14.25 MB |

The 11 bundled icon files hold 7.81 MB of PNG data, which is most of the
increase. The 1024 px representations are 4.15 MB of that (53%).

**Ways to make the default lighter without changing a pixel.** Each needs
approval, because it changes shipped bytes:
1. **Lossless recompression:** oxipng level 4 takes 7.81 → 6.43 MB (−17.6%),
   verified pixel-identical.
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

**Optional theme-pack sizes** (11 icons × 10 representations; full table in
the [v2 `ARCHIVE.md`](https://github.com/ish4ra/Arkiv/blob/archive/document-icon-concepts-v2/design/document-icon-concepts-v2/ARCHIVE.md)): about 2.7–6.5 MB per theme after deduplication and
lossless optimisation, for example:
* Folio 2.70 MB
* Seal 3.76 MB
* Seal Dark Aubergine, Wine and Noir about 5.7–5.9 MB
* Strata 6.47 MB

## Planned optimisation tasks (not implemented)

These are separate tasks, independent of the theme feature. The default
artwork stays build 26501's refined Seal Dark: none of these may change a
visible pixel.

1. **Pixel-identical lossless icon recompression.** Recompress the 110 bundled
   PNGs (for example with oxipng). Measured on 2026-11-22: 7.81 MB → about
   6.43 MB, with decoded pixels verified identical. Update `SHA256SUMS`, keep
   a pixel-level manifest, and regenerate the generator outputs to match.
2. **Duplicate-representation investigation.** 128 pt @2x is identical to
   256 pt @1x, and 256 pt @2x to 512 pt @1x (1.73 MB in total). Find out on
   real Macs whether omitting duplicates from the `.icns` keeps rendering
   identical in Finder, Get Info, Quick Look and Dock across supported macOS
   versions. Adopt it only if it is fully compatible.
3. **Signed Sparkle delta updates.** Publish Sparkle binary deltas, signed and
   verified like full updates, so unchanged resources such as icons are not
   downloaded again. A full signed update must remain the fallback whenever a
   delta is missing or fails to apply.
4. **Real-Mac measurements.** Record installed size
   (`du -sh /Applications/Arkiv.app`), cold and warm launch time, and resident
   memory at launch and while browsing a large archive. Measure before and
   after any resource change.

## Lightweight principle (applies to all future features)

Arkiv stays a small, fast, native Swift/AppKit app:
* Bundle only what the default experience needs; download optional content on demand.
* Keep optional content outside the signed bundle.
* Add no new runtime frameworks or background services.
* Do no work at launch that a feature does not need.
* Load lazily, with bounded caches.
* Measure the download size, installed size, launch time and memory of any
  change that adds resources.
