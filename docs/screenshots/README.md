# Screenshots

> [!NOTE]
> **Headless CI renderings, not real-Mac captures.** Every image here is a
> genuine capture of Arkiv's real windows, drawn by AppKit on a GitHub macOS 15
> Apple Silicon runner by `UIScreenshotTests` (see the
> [UI redesign](../ui-redesign.md#screenshots)), using the packaged app's own
> icon and Seal Dark document icons. They are not mockups. Because the runner
> has no logged-in desktop:
>
> * the windows are never key, so selections show the **inactive** (grey)
>   colour instead of the accent, and default (Return) buttons such as Open
>   Archive draw neutral; the Settings preview draws its selection as active
>   on purpose, which is where the accent is visible;
> * translucent materials (title bar, Settings sidebar) have no wallpaper
>   behind them, and there are no window shadows;
> * the runner reports the accessibility display settings recorded in
>   `accessibility-display-flags.txt` of the CI artefact; with Increase
>   Contrast or Reduce Transparency on, the welcome canvas deliberately draws
>   a plain surface instead of its ivory or plum-black glow.
>
> Real-Mac screenshots remain on the [acceptance list](../ui-redesign.md#real-mac-acceptance).

Source: [run 45737861346](https://github.com/ish4ra/Arkiv/actions/runs/45737861346) (commit `c02d74b`, macOS 15 Apple Silicon runner; Reduce Transparency and Reduce Motion reported on). The application code is unchanged after that commit.

## Welcome window

| Recent archives, Dark | Recent archives, Light |
| --- | --- |
| ![Welcome window with recent archives in Dark appearance](01-welcome-recents-dark.png) | ![Welcome window with recent archives in Light appearance](04-welcome-recents-light.png) |

| First launch (drop zone) | Minimum window size (640 × 400) |
| --- | --- |
| ![Welcome window on first launch with the drop zone](02-welcome-first-launch-dark.png) | ![Welcome window at its minimum size](03-welcome-minimum-size-dark.png) |

## Archive window

![Archive window, wide, Dark](05-browser-wide-dark.png)

![Archive window, wide, Light](07-browser-wide-light.png)

| Narrow (660 × 420): search collapses, Info moves to the overflow menu | Inside a folder: path bar |
| --- | --- |
| ![Archive window at a narrow width](06-browser-narrow-dark.png) | ![Archive window inside a folder](10-browser-folder-path-bar-dark.png) |

| Search across the archive | Comfortable density, alternating rows, Jade accent |
| --- | --- |
| ![Search results](08-browser-search-dark.png) | ![Comfortable density with alternating rows](09-browser-comfortable-alternating-jade-dark.png) |

## Dialogs

| Archive Info | Create Archive (layout unchanged; accent on Create) |
| --- | --- |
| ![Archive Info](11-archive-info-dark.png) | ![Create Archive](12-create-archive-dark.png) |

## Settings

| General | Updates |
| --- | --- |
| ![Settings, General](13-settings-general-dark.png) | ![Settings, Updates](15-settings-updates-dark.png) |

| Appearance, Dark | Appearance, Light |
| --- | --- |
| ![Settings, Appearance, Dark](14-settings-appearance-dark.png) | ![Settings, Appearance, Light](17-settings-appearance-light.png) |

| Appearance: Brass accent, Compact density | Document Icons (build without a theme key: Seal Dark only) |
| --- | --- |
| ![Settings, Appearance with Brass and Compact](18-settings-appearance-brass-compact-light.png) | ![Settings, Document Icons](16-settings-document-icons-unconfigured-dark.png) |

## Document icon theme gallery (real theme packs)

From the theme workflow's end-to-end test, [run 45739339528](https://github.com/ish4ra/Arkiv/actions/runs/45739339528)
(Apple Silicon runner): the 20 real packs, built from the preserved design
archives, served from an in-process fixture server with a catalogue signed by
a throwaway CI key (never the production key), then downloaded, verified,
installed and applied through the real pane. Same headless rendering notes
as above.

| Seal Wine installed and in use | Strata downloading, Seal Original variations unfolded |
| --- | --- |
| ![Seal Wine installed and in use](theme-03-installed-in-use-seal-wine-dark.png) | ![Strata downloading](theme-06-download-progress-strata-dark.png) |

| Classic: partial coverage (system icons dimmed) | Folio in use, Light |
| --- | --- |
| ![Classic partial coverage](theme-04-classic-partial-coverage-dark.png) | ![Folio in use, Light](theme-08-installed-in-use-folio-light.png) |

All captures of that test (including variations, offline and Restore Default)
are in its `document-icon-theme-settings-screenshots-<runner>` artefacts.
