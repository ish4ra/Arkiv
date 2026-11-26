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

Run [45732925626](https://github.com/ish4ra/Arkiv/actions/runs/45732925626)
(macOS 15, Apple Silicon and Intel runners), step “Quick Look thumbnail
prototype feasibility”:

| Check | Apple Silicon | Intel |
| --- | --- | --- |
| Prototype compiles with `swiftc` and `QuickLookThumbnailing`; extension size | yes, 160 KiB | yes, 128 KiB |
| Ad-hoc signature of the app copy with the embedded, sandboxed extension verifies (`codesign --verify --strict`) | yes | yes |
| PlugInKit registers the ad-hoc signed extension (no Developer ID, no paid membership), found by identifier | yes | yes |
| `qlmanage -t` returns thumbnails | **no: did not finish within 60 s** (both requests) | **no: same** |
| `.zip` drawn with Arkiv artwork / `.tar.gz` differs from `.gz` / new theme drawn on the next request | **not observed** (no thumbnails were produced) | **not observed** |
| `.7z.001` routed to the extension | no; by construction it is not claimed | no |

In an earlier run without a time limit, `qlmanage -t` was still running after
19 minutes and the job was stopped at its 25-minute limit; the diagnostic now
bounds every request. On these headless runners, Quick Look thumbnail
generation does not complete, for Arkiv's extension or otherwise, so CI
**cannot** show whether the extension draws, whether it reads the theme
through its read-only exceptions, or how fast a theme change appears. Those
need a real Mac.

What CI does establish: an ad-hoc signed, sandboxed thumbnail extension with
read-only temporary exceptions builds, signs and registers alongside Arkiv's
existing signing model, at 128–160 KiB per architecture slice.

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
| Finder icon view and Desktop show the selected theme | **Plausible, not yet proven.** Supported API; the extension builds, signs ad hoc and registers without paid membership (CI). Drawing, theme reading under the sandbox exceptions and refresh timing are unverified (no thumbnails are generated on headless CI). Switching would **not** be immediate for already-cached files |
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

## Real-Mac evaluation

Uses an **isolated test host**, never the installed Arkiv:
`Arkiv Thumbnail Test.app` is a renamed copy of a CI-built Arkiv with its own
bundle identifier (`xyz.isharalakshan.arkiv-thumbnail-test`), and without
document types, type declarations, URL schemes, Services, Finder Sync and the
Sparkle feed. It cannot become a default app, open archives from Finder, or
update itself; it only hosts the prototype extension
(`xyz.isharalakshan.arkiv-thumbnail-test.thumbnails`). The extension only
**reads** the real Arkiv's theme selection and installed themes. Built by
[`make-isolated-test-app.sh`](../prototypes/quicklook-thumbnail/make-isolated-test-app.sh)
in the macOS workflow's Apple Silicon job, artefact
`Arkiv-Thumbnail-Test-arm64-PROTOTYPE-not-for-daily-use` (sign in to GitHub
to download; it is never part of the DMG, ZIP or Sparkle update).

Nothing below changes `/Applications/Arkiv.app`, your archives, default apps,
or system-wide caches.

**1. Install the test host (reversible).**

```bash
mkdir -p ~/ArkivQLTest && cd ~/ArkivQLTest
# Unzip GitHub's artefact wrapper here, then:
shasum -a 256 -c Arkiv-Thumbnail-Test-arm64.zip.sha256
ditto -x -k Arkiv-Thumbnail-Test-arm64.zip .
# Register only this copy's extension (do not launch the app):
pluginkit -a "$PWD/Arkiv Thumbnail Test.app/Contents/PlugIns/ArkivThumbnail.appex"
pluginkit -m -A -D -v -i xyz.isharalakshan.arkiv-thumbnail-test.thumbnails
```

Record whether it is listed and whether it is enabled (`+` at the start of
the line). If macOS blocks it because the download is quarantined, prefer
downloading with `gh run download`, which does not quarantine; otherwise
remove the quarantine attribute from **this test copy only**:
`xattr -dr com.apple.quarantine "Arkiv Thumbnail Test.app"`. Never disable
Gatekeeper globally.

**2. Disposable test files.**

```bash
mkdir -p ~/ArkivQLTest/files && cd ~/ArkivQLTest/files
for n in a.zip b.7z c.tar d.rar e.gz f.bz2 g.xz h.zst i.tgz j.tar.gz k.tar.xz l.tar.zst m.tzst n.7z.001 o.7z.002 p.001; do
  head -c 4096 /dev/urandom > "$n"
done
```

The contents are random: the prototype draws from the name only.

**3. Evaluate, recording what you see (with screenshots).**

| Check | How | Expected if it works |
| --- | --- | --- |
| Thumbnail generation | `qlmanage -t -s 256 -o ~/ArkivQLTest a.zip j.tar.gz e.gz` (Ctrl-C after 60 s if it hangs) | PNGs with Seal Dark artwork |
| Finder icon view | Open `files` in Finder, icon view, large icons | Seal Dark artwork for every archive name |
| Compound names | Compare `j.tar.gz` with `e.gz`, `k.tar.xz` with `g.xz` | Different artwork (TAR.GZ vs GZIP) |
| Split volumes | `n.7z.001`, `o.7z.002`, `p.001` | Not drawn by Arkiv: macOS does not route `.001` names to it (no claim on `.001`) |
| Desktop | Copy `a.zip` to the Desktop, then delete it after looking | Same artwork as Finder |
| List / column view | View Options → Show icon preview on and off | Artwork only with previews on |
| Get Info | ⌘I on `a.zip` | Header icon stays the document icon (expected); note the Preview section |
| Reading the selected theme | In the real Arkiv, apply a downloaded theme (e.g. Folio). Create a **new** file `q.zip` and look at it | `q.zip` shows Folio artwork |
| Theme-switch refresh | Look at `a.zip` (already thumbnailed) after the switch: immediately, after reopening the window, after logging out and in | Records the real refresh timing; no cache reset is done |
| Which provider wins | If another archiver with thumbnails is installed, note which artwork appears | Informational |
| Resource use | `ps -o rss=,command= -p $(pgrep -f ArkivThumbnail)` while thumbnails render | Small, short-lived process |

**4. Remove everything.**

```bash
pluginkit -r "$HOME/ArkivQLTest/Arkiv Thumbnail Test.app/Contents/PlugIns/ArkivThumbnail.appex"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$HOME/ArkivQLTest/Arkiv Thumbnail Test.app"
rm -rf ~/ArkivQLTest
pluginkit -m -A -D -i xyz.isharalakshan.arkiv-thumbnail-test.thumbnails   # expect no output
```

Thumbnails Finder already cached for the deleted test files expire with the
files; no global cache command is needed or recommended.

**Decision after the evaluation.** Ship nothing to Finder unless thumbnails
render with Seal Dark and a selected theme, compound names differ, `.001` is
untouched, and the refresh behaviour is acceptable to explain in Settings.
If adopted, it ships as an opt-in setting (off by default). The public beta
does not depend on it.
