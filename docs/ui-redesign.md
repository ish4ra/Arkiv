# UI redesign: “Ledger”

The redesign replaces the build 30701 interface with a coherent, native
design language across the welcome window, the archive window, Settings, the
document icon theme gallery and Arkiv's dialogs. It is presentation only: the
archive engine, extraction policy, editing transactions, signing, Sparkle and
theme verification are unchanged. The earlier design remains in Git history
(`5044993` and before; [native browser refinement](ui-refinement.md)).

## Directions explored

Three directions were sketched before implementation
([`design/ui-redesign/directions.html`](../design/ui-redesign/directions.html),
rendered as [`directions.png`](../design/ui-redesign/directions.png); concept
mockups, **not** application screenshots, and outside the app bundle):

| Direction | Structure | Verdict |
| --- | --- | --- |
| **A · Ledger** | Unified toolbar with navigation beside the title and grouped actions plus native search on the right; title and subtitle carry the archive's identity; one bottom bar holds the path and status; two-column welcome; sidebar Settings | **Chosen** |
| B · Atelier | Folder-tree sidebar, table and permanent inspector | Rejected: the tree duplicates the path bar, costs width at the 640 pt minimum, needs extra work for 100,000-entry archives; the inspector duplicates Archive Info |
| C · Utility | Icon-only toolbar with an in-toolbar path control, classic toolbar-tab Settings | Good fallback, but least distinctive, and tab Settings cannot fit the theme gallery without resizing |

Criteria: usability (every operation one click or one shortcut away),
platform conventions, visual quality, implementation cost and performance.
A uses only stock AppKit (NSToolbar unified style, NSToolbarItemGroup,
NSMenuToolbarItem, NSSearchToolbarItem, NSPathControl, view-based
NSTableView, NSVisualEffectView) and adds no per-row cost.

## Root causes of the reported problems

Inspected in the build 30701 source, not assumed:

| Reported | Cause in 30701 | Now |
| --- | --- | --- |
| Right-heavy toolbar | Default items were `open, flexibleSpace, extract, all, test, info`: one item on the left, four pushed right | Navigation sits beside the title (`isNavigational`); actions are grouped (Open · Extract, Extract All · Add, Test, Info) and end with search |
| Unbalanced title bar, items poorly placed vertically | `.iconAndLabel` labels in the unified style made a tall bar whose title, icons and labels did not share a baseline; navigation buttons and search lived in a second strip under the toolbar | Icon-only by default (labels remain available through the native palette); one row: navigation, title + subtitle, actions, search |
| Inconsistent control spacing | Hand-sized 28 pt textured buttons, a 180 pt fixed search field and a stack view with mixed insets | Native toolbar items only; NSSearchToolbarItem sizes and collapses itself |
| Excessively empty initial window | A 64 pt icon, a title, one sentence and one button centred in a 920 × 580 window | Welcome canvas with actions, recent archives or a drop zone, drop-to-open and shortcuts |
| Outdated Settings | NSTabView inside a window that resized and animated between 520 × 330 and 820 × 680 | Fixed 880 × 640 sidebar window with grouped cards |
| Overlapping theme section headings | The theme list was a source list with `floatsGroupRows` left on (the default) and bare text fields as group rows, so floating headings were drawn over the rows below while scrolling | `floatsGroupRows = false`, proper header cells |
| Gaps between compound archive previews | An NSGridView with 18 pt column spacing whose columns took the width of captions such as `.tar.bz2 · family` | Fixed 58 pt preview cells, short captions, dimming plus tooltips for artwork a theme lacks |
| Basic theme list | Name and status text only | Thumbnails, banner, family headings, folding variations, filter, artwork card |

### Dark-mode Settings tab labels (headless CI)

Build 30701's theme workflow measured the share of distinctly inked pixels in
the dark Settings tab strip in three captures of the same window: plain
`cacheDisplay`, a Core Animation layer render, and `cacheDisplay` in the
window's own drawing appearance. In run
[45511900002](https://github.com/ish4ra/Arkiv/actions/runs/45511900002) all
three gave **12.5 %** on both Apple Silicon and Intel runners. CI therefore
never reproduced invisible labels: the captures drew the labels with the same
ink whichever way they were taken. Whatever was seen as unreadable could not
be shown to be an application defect from CI evidence, nor confirmed as a
capture artefact; it needed a real Mac. The question no longer applies to the
redesigned window, which has no NSTabView. The same measurement now runs on
the Settings sidebar labels (`sidebar-label-contrast.txt` in the theme
workflow artefacts) and asserts they are visible in the window's own
appearance. Real-Mac confirmation of the sidebar in Dark is in the acceptance
list.

## Design language

* **Native first.** System fonts, semantic colours (`labelColor`,
  `secondaryLabelColor`, `textBackgroundColor`, `separatorColor`), standard
  controls, NSAlert, NSOpenPanel and sheets wherever macOS already has the
  right pattern. No custom UI framework.
* **Brand where it identifies, not everywhere.** The Tension Seal palette
  (exact values from `scripts/render-icon.swift`: plum `#703A47`, aubergine
  `#301A2B`, midnight `#0C060A`, brass `#CDA66C`/`#8C6538`, jade `#4A9C82`,
  ivory `#F5E9DE`) appears in the welcome canvas (a warm ivory or plum-black
  surface with one soft static glow), the accent (selection and primary
  buttons), the Settings sidebar badges and small status marks (jade for
  installed/enabled, brass for “in use”). Tables, toolbars and sheets stay
  neutral.
* **Selection.** A rounded, inset highlight (5 pt radius) in the accent;
  inactive windows use the system's unemphasized colour; text switches to the
  emphasized style exactly as with the stock row view.
* **Cards.** Grouped content (Settings sections, the theme preview, Archive
  Info, the theme banner) sits on 10 pt rounded cards with a hairline border,
  drawn rather than layered.
* **Density, not decoration.** Standard keeps the existing 26 pt rows and 16 pt
  hand-tuned icon tier; metadata columns read as secondary text like Finder.
* **No motion.** Nothing animates (no window-resize animation in Settings any
  more); the canvas glow is one static gradient, replaced by a plain surface
  with Increase Contrast or Reduce Transparency.

## Surfaces

| Surface | What changed |
| --- | --- |
| Welcome window | Two columns: 96 pt app icon, name, one-line purpose, **Open Archive…** (default button, accent) and **Create Archive…**; **Recent Archives** (up to six, from NSDocumentController, missing files hidden, themed icons, folder path) or, with no history, a drop zone listing supported formats. Drop archives anywhere on the window to open them (regular files only). A quiet footer line with ⌘O, ⇧⌘N, ⌘, and an **Appearance…** shortcut. No toolbar items and a transparent title bar; an empty toolbar of the same height keeps the title bar from jumping when an archive opens |
| Archive window | Unified, customizable toolbar (saved by AppKit): Back/Forward beside the title; Open; Extract; Extract All; **Add** menu (Add Files, Add Folder, New Folder); Test; Info; native search. Palette extras: Enclosing Folder, Create, Quick Look, Settings. Title = archive name with the themed proxy icon; subtitle = format · files · size (and “Inside *outer*” for nested archives). Table scrolls under the toolbar. One bottom bar: clickable NSPathControl breadcrumb (archive, then folders; “Search results” while searching), status (items, archive entries, selection and its size) and operation progress with Cancel. Empty folder, empty archive and no-results states show a symbol and a sentence |
| Context menu | Grouped with separators and SF Symbols: open/preview, extract/copy, edit, then Delete last |
| Settings | Sidebar (General, Appearance, Document Icons, Updates); see [Settings](settings.md) |
| Document Icons | Gallery; see [document icon themes](document-icon-themes.md#settings--document-icons) |
| Archive Info | Header with the themed 64 pt icon (redrawn if the theme changes while open), name and summary (format · size · files · encrypted), then every property in one aligned grid on a card; Done |
| Password prompt | Native NSAlert, now showing the archive's own document icon |
| Test Archive result | Native NSAlert with a jade seal (passed) or an orange warning symbol |
| Finder operation progress | The archive's document icon beside name, status, spinner and Cancel |
| Create Archive | Layout unchanged (its geometry is covered by `CreateArchiveLayoutTests`); the Create button takes the accent |
| Remove theme confirmation | Native NSAlert, warning style, destructive Remove button |
| Menus | New **View** menu: Show Toolbar, Customize Toolbar…, Appearance Settings… |

Unchanged on purpose: NSOpenPanel/NSSavePanel for choosing files, NSAlert for
every confirmation (destructive buttons never take Return), the Finder setup
window, and the extraction-warnings list.

## Settings shortcut decision

A toolbar gear is **not** in the default toolbar. Arkiv's toolbar is a
document toolbar: every default item acts on the archive in that window.
Settings is an application-level destination that macOS already gives a
standard menu item and ⌘, in every window, and the welcome window (where new
users start) has an explicit **Appearance…** shortcut. A permanent gear would
add a ninth item for something used rarely, crowd the 640 pt minimum width and
duplicate a universal shortcut. Users who want one can add **Settings** from
the customization palette (View → Customize Toolbar…). The standard
**Arkiv → Settings…** menu item and ⌘, are unchanged.

## Appearance customization inventory

| Option | Kept | Why |
| --- | --- | --- |
| System / Light / Dark (default Dark) | Yes | Existing; moved to Appearance |
| Accent: Arkiv Wine (default), Jade, Brass, Graphite, System | Yes | Brand identity with a native escape hatch; all presets ≥ 4.5:1 with white text |
| Row density: Compact / Standard / Comfortable | Yes | Real need for both dense power use and readability |
| Icon size | Folded into density | A separate setting would allow mismatched rows and icons; Comfortable uses 24 pt icons |
| Alternating row backgrounds | Yes | Long listings; off by default |
| Toolbar items and labels | Yes, native palette | No custom UI; AppKit persists it |
| Sidebar visibility/sizing | No sidebar | No functional purpose (direction B rejected) |
| Persistent window size | Not added | AppKit window autosave would need per-window naming across reused and nested windows; left for a later, tested change |
| Live preview | Yes | Built from the real cells, not a picture |
| Restore Defaults | Yes | Resets only appearance keys |

## Immediate in-app theme refresh

Every consumer of document icons was audited:

| Consumer | Refresh on theme change |
| --- | --- |
| Archive rows, nested archives | Visible Name-column cells reloaded in place (`reloadData(forRowIndexes:columnIndexes:)`); archive not reread; selection, scroll and sort untouched |
| Title-bar proxy icon | Redrawn |
| Path bar archive item | Redrawn |
| Archive Info (open sheet) | Icon redrawn |
| Welcome recent archives | Reloaded |
| Settings preview and theme banner/list | Reloaded |
| Password prompt, operation progress | Read at the moment they appear |
| Multiple windows | Every window observes the notification |
| Damaged installed theme | Falls back to Seal Dark and now posts the change notification asynchronously so every view already showing it redraws |

Covered by `RedesignTests.testThemeSwitchUpdatesEveryIconConsumerInPlace`
(two windows, path bar, open Archive Info, no reload, relaunch with network
off, damaged files, removal of the active theme).

## Accessibility

* Every toolbar item has a label and palette label; tooltips name shortcuts.
* Accent swatches are radio buttons named by colour; the Settings sidebar,
  welcome list (a list of “Open *name*, in *folder*” buttons), drop zone,
  footer (“Path and status”) and preview have labels and roles.
* Status is never colour alone (text status everywhere; colour only adds).
* Increase Contrast / Reduce Transparency: plain surfaces. Reduce Motion:
  nothing animates.
* Keyboard: Return opens from the welcome window; ⌘O, ⇧⌘N, ⌘F, ⌘[ ⌘] ⌘↑,
  ⌘E, ⇧⌘E, ⌘T, ⌘I, ⌘⌫ unchanged; Settings sidebar responds to arrow keys.
* VoiceOver output itself needs a real Mac (see [real-Mac checks](#real-mac-acceptance)).

## Screenshots

Genuine screenshots are produced by `UIScreenshotTests` on the macOS CI
runners, drawing the real windows with the packaged app's own icon and Seal
Dark resources, and uploaded as the `Arkiv-<arch>-ui-screenshots` artefact.
They are **headless CI renderings**: the window server draws offscreen, so
translucent materials (the Settings sidebar, the toolbar) show no desktop
behind them, and there is no shadow or wallpaper. Theme-gallery screenshots
with every real pack come from the theme workflow
(`document-icon-theme-settings-screenshots-*`). See
[`docs/media/redesign`](media/redesign/README.md) for the selected images.

## Performance and size

See [measurements](#measurements). Design constraints held throughout:

* No new dependencies, frameworks, services, timers, launch-time work or
  network requests. The welcome window reads at most six recent URLs and
  checks they exist.
* Tables keep view reuse; the custom row view only overrides selection
  drawing. Theme and preference changes touch visible rows only.
* No images or fonts were added to the bundle; the canvas glow is one
  gradient.

## Real-Mac acceptance

Headless CI proves layout, state and drawing in code; it does not prove how
the app looks and feels on a real display. On a real Mac, in Light, Dark and
System, at 1× and 2×:

1. First launch: welcome window with drop zone; Open with Return; Create;
   drop an archive and a folder (folder refused).
2. With history: recent list, hover and keyboard focus, missing files hidden.
3. Open an archive: the title bar does not jump; toolbar alignment at 640 pt
   and full width; toolbar overflow; Icon and Text mode; customization palette
   and its persistence; Add menu enabled only for editable archives.
4. Path bar navigation, search (⌘F focuses the toolbar field), status and
   progress with Cancel during a long extraction.
5. Selection colours for each accent, active and inactive windows,
   alternating rows, all three densities on a 10,000-entry archive (scrolling
   and resizing stay smooth).
6. Settings: every pane, both appearances, sidebar vibrancy, no clipping.
7. VoiceOver pass over the welcome window, toolbar, table, footer and
   Settings; Full Keyboard Access.

## Measurements

**Measured (macOS CI).** Size of the packaged development artefacts, build
30701 (`main`, run [45597975229](https://github.com/ish4ra/Arkiv/actions/runs/45597975229))
against this branch (run [45732925626](https://github.com/ish4ra/Arkiv/actions/runs/45732925626)),
same packaging pipeline (Actions artefact sizes, bytes):

| Artefact | Build 30701 | Redesign | Change |
| --- | ---: | ---: | ---: |
| Apple Silicon update ZIP | 9,452,454 | 9,548,992 | +96,538 (+1.0%) |
| Apple Silicon DMG | 9,706,104 | 9,783,031 | +76,927 (+0.8%) |
| Universal update ZIP (the Sparkle archive) | 10,977,923 | 11,179,157 | +201,234 (+1.8%) |
| Universal DMG | 11,359,632 | 11,577,643 | +218,011 (+1.9%) |

The increase is compiled code only: no images, fonts, frameworks or theme
packs were added, and the Quick Look prototype is not in these artefacts.

**Not measured.** Launch time, resident memory and idle CPU were not measured:
headless CI runners give no reliable figures for an interactive AppKit app,
and no real-Mac measurement was possible here. By construction, launch does
no new work beyond building the welcome view and reading at most six recent
URLs; nothing animates, polls or uses timers, and the Settings window, theme
manager and theme previews are still created only on demand. These remain
items on the real-Mac acceptance list.
