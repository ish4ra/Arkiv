# Settings

Open **Arkiv → Settings…** (Command-comma). Settings uses one reusable native
window with General, Updates, Finder Integration and Appearance tabs. Closing it does not
quit Arkiv; reopening focuses the same window.

## General

Appearance offers System, Light and Dark. **Dark is the default.** The choice is
stored in Arkiv’s UserDefaults and applies to Arkiv-owned windows immediately and
on subsequent launches. System follows macOS; neither Light nor Dark changes the
system appearance.

Clear Recent Archives uses the existing NSDocumentController-backed Open Recent
history. It does not delete archives. No separate history database is created.

## Updates

The version and build come from the installed app bundle. Check for Updates uses
the existing Sparkle controller and signed development channel. Automatically
check for updates changes Sparkle’s own preference; it does not enable automatic
installation or bypass signature verification. Sparkle retains ownership of
consent, scheduling and persistence. This control is unavailable in builds without
a configured update public key, where Check for Updates explains the limitation.

Opening Settings is interactive and starts the existing updater if necessary.
Quiet Finder operations alone still do not start it. There are no new network
requests for preference storage, no separate updater and no signing secrets or
archive passwords in Settings.

## Finder Integration

Finder Integration opens the existing setup window, including enabled status and
version-appropriate manual instructions. Enabling Arkiv Finder requires user
action in macOS Settings. Direct contextual actions cover the home folder;
Services remain the fallback for other locations. Settings does not silently
enable extensions or expand their directory scope.

## Appearance → Document Icon Theme

Choose the artwork Arkiv uses for archive documents inside its own windows.
Seal Dark is bundled and cannot be removed; other themes are optional signed
downloads, stored in `~/Library/Application Support/Arkiv/DocumentIconThemes`.
The tab and its theme manager are created only when the tab is first shown,
and the catalogue is requested only then or on Refresh Catalogue. The window
grows while this tab is shown. Finder and Quick Look keep the bundled icons;
the pane says so. Details: [document icon themes](document-icon-themes.md).

## Real-Mac checks

1. Press Command-comma; repeat and confirm only one Settings window exists.
2. Switch appearance through Light, Dark and System with a browser window open.
   Relaunch and confirm the chosen appearance persists.
3. Clear Recent Archives, then inspect File → Open Recent.
4. In Updates, check the installed version/build, toggle automatic checks and
   confirm the existing app-menu checkbox agrees. Check for Updates should use
   the usual Sparkle dialog.
5. Open Finder Integration and confirm the existing setup/status window appears.
6. Check keyboard tab navigation and all four sections in light and dark mode.
7. Appearance: see the document icon theme checks in
   [document icon themes](document-icon-themes.md#remaining-real-mac-acceptance).

Automated preference tests use isolated UserDefaults suites. Native tests inject
recent-history storage, an updater driver and the Finder presentation boundary;
they do not clear real user history, contact the update server or enable Finder.
