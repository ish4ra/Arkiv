# README media

Everything the repository homepage shows. None of it is part of the app
bundle, and nothing here is fetched from a third-party host.

## Inventory

| File | Bytes | What it is | Source |
| --- | ---: | --- | --- |
| `arkiv-hero.gif` | 749,600 | Animated hero, 1280 × 440, 120 frames at 20 fps (6 s loop), 255-colour global palette | Rendered from [`design/readme/hero.html`](../../design/readme/hero.html) |
| `arkiv-hero.jpg` | 122,897 | Static fallback, 2560 × 880 (2×), shown when the viewer asks for reduced motion | The same scene at phase 0.62 |
| `artwork/seal-dark/*-128.png` (11) | 123,251 | Seal Dark, the bundled default: production 128 px tier | `Resources/DocumentIcons/Arkiv-*.iconset/icon_128x128.png` |
| `artwork/seal-dark/*-32@2x.png` (6) | 16,618 | Seal Dark 32 pt @2x tier, for the format table | `Resources/DocumentIcons/Arkiv-*.iconset/icon_32x32@2x.png` |
| `artwork/<theme>/*-256.png` (7 × 3) | 680,783 | ZIP, 7z and TAR of Folio, Folio Dark, Strata, Seal Original, Original Aubergine, Seal Wine and Seal Noir | `archive/document-icon-concepts-v1` at `7e9b736`, `previews/<family>/<format>-256.png` |
| `artwork/seal-dark-restored/*-256.png` (3) | 111,997 | ZIP, 7z and TAR of Restored Readability | `archive/document-icon-concepts-v2` at `8a1b92a`, its preserved `iconsets/…/icon_256x256.png` |
| **Total** (43 files) | **1,805,146** | | |

**Artwork is copied byte for byte**: never resized, recompressed, recoloured or
redrawn. [`collect-artwork.py`](../../design/readme/collect-artwork.py) reads it
from the bundled resources and the pinned archive commits, and `--check`
verifies every copy. The README shows the optional themes from their archived
256 px renders, which are the references their downloadable packs are verified
against. The rejected Classic Extended candidate is not shown, and the partial
Classic theme is described rather than pictured.

The hero places, scales and moves the unmodified Tension Seal app icon
(`branding/Arkiv-AppIcon-512.png`) and five Seal Dark document icons
(`icon_256x256.png`). Its colours are the production values:

| Token | Value | Source |
| --- | --- | --- |
| Plum (clasp highlight) | `#703A47` | `scripts/render-icon.swift`, sRGB 0.44 / 0.23 / 0.28 |
| Plum (clasp shade) | `#301A2B` | `scripts/render-icon.swift`, sRGB 0.19 / 0.10 / 0.17 |
| Jade | `#CFF0D4` → `#4A9C82` | `scripts/render-icon.swift` seal; `BRAND.jade*` in `design/document-icons/lib/formats.mjs` |
| Aubergine page | `#4C2C3F` → `#1E111A` | Seal Dark surface, `design/document-icons/seal-dark.mjs` |
| Midnight plum (spine) | `#0C060A` | Seal Dark surface |
| Brass | `#F4E2B8` · `#CDA66C` · `#8C6538` | `BRASS` in `seal-dark.mjs` |
| Ivory | `#F5E9DE` | `IVORY` in `seal-dark.mjs` |

Lettering is Inter Display 4.0 SemiBold and Bold, the fonts already vendored in
`design/document-icons/fonts` (SIL OFL 1.1).

## Rebuilding

See [`design/readme`](../../design/readme/README.md). After any change, run:

```sh
python3 design/readme/check-readme.py
```

## Screenshots to capture on a real Mac

The README has **no application screenshots yet**, because none have been
captured on a real Mac. Screenshots made by CI on headless runners are not used: they are not
verified real-Mac renderings. Please do not substitute mock-ups.

**Setup:** the newest development build; macOS appearance **Dark** (Arkiv's
default), and a second set in **Light** if you want light-mode variants; a
Retina display; desktop wallpaper hidden or plain; no personal file names. Use
a small sample folder, for example a `Project Archive.zip` holding `Design/`,
`Documents/`, `Photos/`, a nested `Backups/old-site.tar.xz` and a few files.

Capture each window alone with **⇧⌘4, then Space, then click the window**
(keeps the native shadow). Name the files as below and put them in
`docs/media/screenshots/`.

| # | File | What to show |
| --- | --- | --- |
| 1 | `browser.png` | The archive browser on `Project Archive.zip`: a folder opened, several rows, Packed Size, Ratio and Modified columns visible, one row selected |
| 2 | `create-archive.png` | **File → Create Archive…** with 7z selected, password protection on (password field empty or dots), Advanced options visible |
| 3 | `search.png` | **⌘F** search across the archive with a few matches from different folders, Back and Forward available |
| 4 | `extraction.png` | **Extract All…** progress, or the extracted folder in Finder next to the archive |
| 5 | `archive-info.png` | **File → Archive Info** (⌘I) for the same archive |
| 6 | `finder-menu.png` | Finder's right-click **Arkiv** submenu on a ZIP (crop to the menu and the file) |
| 7 | `appearance.png` | **Settings → Appearance → Document Icon Theme** with Seal Dark selected. After theme activation, a second capture with a downloaded theme applied |

**Optional short demonstrations** (screen recordings with ⇧⌘5, 5–8 seconds
each, at most 1280 px wide): opening an archive and previewing a file with
Space; extracting a selection by dragging it to Finder; creating a 7z with a
password. Convert each to an optimized GIF of 1–2 MB or less, or share the
recordings in the pull request and they can be converted to match the hero.

**Compression before committing:** losslessly optimize PNGs (for example
`oxipng -o 4 --strip safe`), and keep each screenshot under about 400 KB; a
window at 1600 px wide is plenty for the README.
