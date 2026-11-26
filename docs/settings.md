# Settings

Open **Arkiv → Settings…** (Command-comma), **View → Appearance Settings…**,
or **Appearance…** at the bottom of the welcome window. Settings is one
reusable native window with a sidebar: **General**, **Appearance**,
**Document Icons** and **Updates**. The window has a fixed size, so switching
sections never resizes or animates it. Closing it does not quit Arkiv;
reopening focuses the same window.

Build 30701 and earlier used a tab view (General, Updates, Finder Integration,
Appearance). Every preference and action from those tabs is still here:
Finder Integration moved into General, and the System/Light/Dark choice moved
from General to Appearance. Stored values are unchanged (see
[migration](#preferences-and-migration)).

## General

* **Finder** — whether Arkiv Finder is enabled, and **Finder Integration…**,
  which opens the existing setup window with version-appropriate manual
  instructions. Enabling Arkiv Finder requires user action in macOS Settings.
  Direct contextual actions cover the home folder; Services remain the
  fallback for other locations. Settings never enables extensions or widens
  their scope.
* **Recent Archives** — how many archives File → Open Recent lists, and
  **Clear Recent Archives**. This uses the existing NSDocumentController
  history (also shown in the welcome window). It never deletes archives and no
  separate history database exists.

## Appearance

A live **Preview** at the top is built from the real archive-table cells and
row view, so every change below looks exactly as it will in archive windows.
Changes apply immediately to every open window and persist.

| Setting | Choices | Default |
| --- | --- | --- |
| Appearance | System, Light, Dark | **Dark** |
| Accent colour | Arkiv Wine, Jade, Brass, Graphite, System | **Arkiv Wine** |
| Row density | Compact (20 pt rows), Standard (26 pt), Comfortable (34 pt, 24 pt icons) | **Standard** |
| Alternating row backgrounds | On, Off | **Off** |
| Toolbar | Customize Toolbar… (native palette: buttons, Icon Only / Icon and Text) | Icon only, default set |
| Document Icons | Choose Theme… (opens Document Icons) | Seal Dark |

The accent colours Arkiv's own selection highlights (archive rows, Settings
sidebar, theme list) and primary buttons. Checkboxes, switches and other
standard controls always follow the macOS accent colour, and **System** makes
Arkiv follow it too. Every preset carries white text at 4.5:1 or better.

**Restore Defaults** returns Appearance, accent, density and alternating rows
to their defaults. It does not change the document icon theme, column
layout, recent archives or update consent.

Customize Toolbar is enabled when an archive window is open (the welcome
window has no customizable toolbar). The same palette is in **View → Customize
Toolbar…**; toolbar layout is saved by AppKit.

## Document Icons

The theme gallery: choose the artwork Arkiv uses for archive documents inside
its own windows. Seal Dark is bundled and cannot be removed; other themes are
optional signed downloads stored in
`~/Library/Application Support/Arkiv/DocumentIconThemes`. The pane and its
theme manager are created only when this section is first shown, and the
catalogue is requested only then or on Refresh Catalogue. Details:
[document icon themes](document-icon-themes.md#settings--document-icons).

## Updates

Arkiv's version and build (from the installed bundle), **Check for Updates…**
and **Check for updates automatically**. Sparkle owns transport, consent,
scheduling, persistence and signature verification; the checkbox changes
Sparkle's own preference and does not enable automatic installation. It is
unavailable in builds without a configured update public key, where Check for
Updates explains the limitation.

Opening Settings is interactive and starts the existing updater if necessary.
Quiet Finder operations alone still do not start it. Settings makes no network
requests of its own.

## Preferences and migration

| Key | Meaning | Since |
| --- | --- | --- |
| `Arkiv.Appearance` | `system`, `light` or `dark` (absent: dark) | before 30701, unchanged |
| `Arkiv.Accent` | `arkiv`, `jade`, `brass`, `graphite`, `system` (absent: arkiv) | redesign |
| `Arkiv.Browser.Density` | `compact`, `standard`, `comfortable` (absent: standard) | redesign |
| `Arkiv.Browser.AlternatingRows` | Boolean (absent: false) | redesign |
| `Arkiv.Browser.Columns.v1.*` | Column visibility and widths | unchanged |
| `Arkiv.DocumentIconTheme` | Selected theme | unchanged |

No existing key is renamed, rewritten or removed. An install from build 30701
keeps its appearance choice and receives the defaults for the new keys.
Unknown or malformed values fall back to the default without being
overwritten. These rules are covered by `AppPreferencesTests` (isolated
UserDefaults suites).

## Real-Mac checks

1. Press Command-comma twice; confirm one Settings window. Use the sidebar
   with the mouse and with the arrow keys; the window never resizes.
2. Appearance: switch Light, Dark and System with two archive windows open;
   change accent, density and alternating rows and confirm both windows and
   the preview follow at once. Relaunch and confirm every choice persists.
   Restore Defaults.
3. With Increase Contrast and Reduce Transparency on, check the welcome
   canvas is plain and every label is readable.
4. General: Clear Recent Archives, then inspect File → Open Recent and the
   welcome window. Open Finder Integration.
5. Updates: check version/build, toggle automatic checks and confirm the app
   menu checkbox agrees; Check for Updates uses the usual Sparkle dialog.
6. Document Icons: see [document icon themes](document-icon-themes.md#remaining-real-mac-acceptance).
7. VoiceOver: sidebar sections, accent swatches (radio buttons with colour
   names), density control and preview are announced.

Automated tests (`SettingsTests`, `RedesignTests`, `DocumentIconThemeSettingsTests`)
use isolated UserDefaults suites and inject recent-history storage, an
updater driver and the Finder boundary; they never clear real history,
contact the update server or enable Finder.
