# Finder, Desktop and Quick Look theme switching: feasibility

Roadmap milestone 4. **Status: prototype and report; nothing ships.** Finder
and Get Info keep the bundled Seal Dark document icons. The current
architecture (downloadable themes apply inside Arkiv only) is unchanged.

## The question

The maintainer applied Folio Dark on build 30701. Inside Arkiv it applied;
Finder and Get Info still showed Seal Dark. Can Arkiv extend optional themes
to Finder safely, with supported mechanisms, ad-hoc signing and no paid Apple
Developer membership?

Hard limits for any answer (from the brief and the existing architecture):
never modify the installed app bundle or break its signature; never write
into users' archives or add custom-icon metadata without consent; never claim
generic numeric extensions such as `.001`; never change default applications;
never reset global Finder, Quick Look or LaunchServices caches; never require
disabling Gatekeeper or SIP; no persistent background daemon.

## What macOS uses where

| Finder surface | Source of the picture | Can a theme reach it? |
| --- | --- | --- |
| Icon view, Desktop (with “Show icon preview”, the default) | Quick Look **thumbnail** if a thumbnail provider answers for the file's type; otherwise the document **icon** | **Yes, via a thumbnail extension** (supported API), subject to thumbnail caching |
| List and column view small icons | Thumbnails when “Show icon preview” is on in View Options (off by default in list view); otherwise the icon | Only where the user enabled previews |
| Column view preview pane, Quick Look panel (Space) | Quick Look preview / thumbnail | Thumbnail: yes. A full preview would need a separate preview extension (not proposed) |
| Get Info header icon | The document icon (`CFBundleTypeIconFile` of the default app); Get Info's Preview section may show a thumbnail | **No** for the header icon |
| Dock, Open/Save panels, Spotlight list icons | Mostly the document icon | **No** |
| Document icon itself | `CFBundleTypeIconFile` in the signed Info.plist of the default app | **No**: changing it means changing the signed bundle (forbidden) |

The only supported, per-type, app-provided hook that can draw different
pictures without changing files or bundles is a **Quick Look Thumbnail
Extension** (`QLThumbnailProvider`, `com.apple.quicklook.thumbnail`, macOS 10.15+).

## Prototype

[`prototypes/quicklook-thumbnail/`](../prototypes/quicklook-thumbnail/) —
outside the Swift package; never built into Arkiv.app, the DMG, the ZIP or the
Sparkle update.

* `ArkivThumbnailProvider.swift`: chooses artwork from the **file name only**
  (the same longest-suffix rules as the app, so `.tar.gz` gets TAR.GZ artwork,
  which Finder's icons cannot express), loads the selected installed theme and
  verifies every file's size and SHA-256 against its manifest, else uses the
  bundled Seal Dark icons in the containing app, and draws it. It never opens
  the archive.
* `Info.plist`: `QLSupportedContentTypes` lists only the archive types Arkiv
  already declares (ZIP, 7z, TAR, RAR, GZIP, BZIP2, XZ, ZSTD and the compressed
  TAR types). No `.001` or other numeric type is claimed, so `name.7z.001` is
  never routed to it.
* `ArkivThumbnail.entitlements`: App Sandbox plus two **read-only temporary
  exceptions**: the theme folder
  (`~/Library/Application Support/Arkiv/DocumentIconThemes/`) and Arkiv's
  preference domain (to read the selected theme). Temporary exceptions are
  allowed outside the Mac App Store and need no paid membership or
  provisioning profile; they never grant writes. An App Group would be the
  App-Store-style alternative, but on macOS it needs a Team ID prefix, which
  ad-hoc signing does not have.
* Ad-hoc signed, exactly like the existing Arkiv Finder extension.
* `diagnose.sh` (CI step “Quick Look thumbnail prototype feasibility”): builds
  the extension into a **copy** of `build/Arkiv.app` on the ephemeral runner,
  registers that copy there only, and asks Quick Look for thumbnails with
  `qlmanage -t`. Then it writes a throwaway, manifest-verified test theme and
  selects it through the preference domain, asks again, and restores the
  runner. Report artefact: `Arkiv-<arch>-quicklook-prototype-report`.

## Results

### Proven on macOS CI runners

*Pending: the CI diagnostic for this branch has not completed yet. This section is filled from its report, with the run linked.*

### Reasoned, not proven here

* **Finder caching.** Finder and the Dock read thumbnails through the shared
  Quick Look thumbnail cache. Entries are keyed by the file (and its
  modification date), not by an app's preferences, and there is no public API
  for an app to invalidate entries for files it does not own. Supported ways a
  thumbnail is regenerated are: the file changes (Arkiv must not touch users'
  archives), the cache evicts it, or the extension itself is updated or
  re-registered (an app update). `qlmanage -r cache` resets the cache for
  **every** file on the Mac and is excluded by the brief. Consequence: after a
  theme switch, archives already thumbnailed keep the old artwork until the
  cache refreshes them; new or changed archives get the new theme at once.
  **This cannot be made immediate with supported mechanisms**, and the exact
  refresh timing must be measured on a real Mac.
* **Desktop** uses the same icon-view thumbnails as Finder windows.
* **Get Info** and the document icon cannot change: the header icon is the
  default app's bundled document icon.
* **Small sizes.** Finder requests 16–32 px thumbnails in list views only
  when previews are on; the prototype honours `QLThumbnailMinimumDimension`
  and uses the hand-tuned 16/32 pt tiers.
* **Registration.** Thumbnail extensions do not need user enablement (unlike
  Finder Sync); PlugInKit registers them when the containing app is installed
  and launched. Gatekeeper treats them as part of the app: an ad-hoc signed,
  non-notarized app still needs the user's one-time “Open Anyway”, as today.
* **Which app wins.** Several apps can provide thumbnails for `public.zip-archive`;
  macOS picks one. Arkiv cannot guarantee its extension is used, and must not
  try to change system preferences to force it.

## Verdict

| Goal | Verdict |
| --- | --- |
| Finder icon view and Desktop show the selected theme | **Feasible** with an opt-in thumbnail extension, using supported APIs, ad-hoc signing and no paid membership; switching is **not immediate** for already-cached files |
| Compound suffixes (`.tar.gz`) and split 7z volumes in Finder | Compound suffixes: feasible through thumbnails (name-based). `.7z.001`: **not feasible** without claiming `.001`, which is forbidden |
| List/column views | Only with “Show icon preview” on |
| Get Info header, Dock, Open/Save panels | **Not feasible** safely |
| Immediate Finder refresh after switching | **Not feasible** with supported mechanisms |

Recommendation: ship the extension only as an **opt-in** setting (default off,
because it changes how every archive looks in Finder, including archives
other apps own) after a real-Mac evaluation of: which provider macOS selects
when Archive Utility or another archiver is installed; cache refresh timing
after a theme change; Desktop and list-view behaviour; memory and CPU of the
extension process; and Gatekeeper behaviour of the ad-hoc signed extension in
a downloaded build. Until then the current system stays as it is.

## Real-Mac evaluation steps

1. Build the prototype into a copy of a development build
   (`prototypes/quicklook-thumbnail/diagnose.sh build/Arkiv.app` on a Mac
   whose state you are willing to change, or the manual steps in that
   script), launch the copy once, and check
   `pluginkit -m -p com.apple.quicklook.thumbnail -v | grep arkiv`.
2. In Finder icon view, look at ZIP, 7z, `.tar.gz` and `.gz` files: Seal Dark
   artwork, and different artwork for `.tar.gz` and `.gz`.
3. Apply a different theme in Arkiv. Note when each already-visible archive
   changes (immediately, after reopening the folder, after logout), without
   running `qlmanage -r`.
4. Check the Desktop, list view with and without icon previews, Get Info and
   Quick Look (Space).
5. Install another archiver with a thumbnail extension and see which one macOS uses.
6. Remove the copy and confirm the registration disappears.
