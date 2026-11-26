# Real-Mac acceptance: Ledger redesign

For the maintainer's Apple Silicon Mac. Every item below is **not yet
performed on a physical Mac** unless a result is written next to it. The
"Automated" column records what macOS CI has already proven, so effort goes
where only a real display, real input and a real Finder can decide.

CI basis: pull request [#8](https://github.com/ish4ra/Arkiv/pull/8); the PR head
and run links are in its description (all macOS and theme workflows green on
Apple Silicon and Intel). CI runners are headless: windows are never key,
there is no wallpaper behind materials, and they report Reduce Transparency on.

## 0. Setup (disposable, reversible)

Use only throw-away files in one folder; nothing here touches personal files.

```bash
mkdir -p ~/ArkivAcceptance && cd ~/ArkivAcceptance
mkdir -p src/Folder\ with\ spaces src/Unicode-日本語 many
printf 'hello\n' > src/hello.txt; head -c 2000000 /dev/urandom > src/random.bin
for i in $(seq 1 10000); do echo "$i" > many/f$i.txt; done
ditto -c -k --keepParent src sample.zip
tar -czf sample.tar.gz src; tar -cJf sample.tar.xz src; tar -cf sample.tar src
gzip -c src/hello.txt > hello.txt.gz
ditto -c -k --keepParent many many.zip
mkdir nest && cp sample.zip nest/inner.zip && ditto -c -k --keepParent nest nested.zip
head -c 30000000 /dev/urandom > split-source.bin
```

**Which build.** Before merge, test the pull request's build: in the PR's
*macOS foundation* run, download the `Arkiv-arm64-development-dmg` artefact
(GitHub sign-in required), verify it (`shasum -a 256 -c *.dmg.sha256`), and
run Arkiv from `~/ArkivAcceptance/Arkiv.app` rather than replacing
`/Applications/Arkiv.app`. Both share one preferences domain and theme folder;
the redesign only adds new preference keys, which build 30701 ignores.
Quit one before launching the other. Gatekeeper: open it once, then **System
Settings → Privacy & Security → Open Anyway** for this copy (never disable
Gatekeeper globally).

Record for each section: date, build number, pass / fail, and a screenshot of
anything that fails.

## 1. Updating through Arkiv → Check for Updates

Only possible after the redesign is merged and published as a `dev-<build>`.

| Check | Automated | Real Mac |
| --- | --- | --- |
| From installed **30701**: Arkiv → Check for Updates offers the new build; install; relaunch shows the new build in Settings → Updates | Appcast generation and EdDSA signature validated on CI | not yet performed |
| Preferences survive the update: 30701's appearance choice, column widths, Open Recent, selected theme | Migration tests (`AppPreferencesTests`) | not yet performed |
| Automatic-check checkbox in Settings → Updates matches the app menu item | `SettingsTests` | not yet performed |

## 2. Welcome window and recent archives

| Check | Automated | Real Mac |
| --- | --- | --- |
| First launch (after Clear Recent Archives): drop zone visible; Open Archive with Return; Create Archive | Geometry and actions (`RedesignTests`) | not yet performed |
| With history: up to six recents, folder shown, missing files hidden, click opens | Filtering test | not yet performed |
| Canvas shows the ivory (Light) / plum-black (Dark) glow with Reduce Transparency **off**, and a plain surface with it **on** | CI only saw the plain fallback | not yet performed |
| Open Archive button shows the accent in an **active** window | Not observable on CI | not yet performed |
| Minimum window size 640 × 400: nothing overlaps | Geometry test at 640 × 400 | not yet performed |

## 3. Drag and drop

| Check | Automated | Real Mac |
| --- | --- | --- |
| Drop `sample.zip` on the welcome window: it opens; drop a folder: refused; drop two archives: both open | Pasteboard filtering test | not yet performed |
| Drag rows from an archive to Finder (file promises) | Existing promise tests | not yet performed |
| Drag files from Finder into an editable ZIP (current folder and onto a folder row) | Existing drop tests | not yet performed |

## 4. Toolbar, Settings shortcut, navigation, search and path

| Check | Automated | Real Mac |
| --- | --- | --- |
| Toolbar alignment at full width and 640 pt; overflow chevron; search collapses to an icon | Item set, layout test | not yet performed |
| View → Customize Toolbar…: add **Settings**, Quick Look, Enclosing Folder, Create; Icon and Text; relaunch keeps the layout | Items available in palette | not yet performed |
| ⌘, and Arkiv → Settings… open one Settings window; Appearance… on the welcome window opens the Appearance pane | `SettingsTests` | not yet performed |
| Back/Forward/Enclosing Folder, ⌘[ ⌘] ⌘↑; clicking path-bar items; ⌘F focuses search; searching `many.zip` for `f99` | Path bar and navigation tests | not yet performed |
| Add menu enabled for `sample.zip` (writable), disabled for a read-only archive | Validation tests | not yet performed |

## 5. Appearance, accent, density

| Check | Automated | Real Mac |
| --- | --- | --- |
| Dark (default), Light, System (toggle macOS appearance) across two archive windows and Settings | Applied in tests; screenshots in both appearances | not yet performed |
| Each accent: selection in an **active** window, inactive selection grey, white text readable; System follows the macOS accent | Contrast ≥ 4.5:1 computed; propagation tested | not yet performed |
| Compact / Standard / Comfortable and alternating rows on `many.zip`: smooth scrolling and resizing | Row heights and icon sizes tested | not yet performed |
| Restore Defaults returns to Dark, Arkiv Wine, Standard, plain rows | Tested | not yet performed |

## 6. Document icon themes

| Check | Automated | Real Mac |
| --- | --- | --- |
| Settings → Document Icons: catalogue verified, 20 themes; headings fixed while scrolling; variations fold; filter | Real packs installed through the pane on CI (test-signed catalogue) | Catalogue load and Folio Dark verified on 30701 by the maintainer; redesigned pane not yet performed |
| Download (watch progress, Cancel, download again), Apply: with two archive windows and Archive Info open, every icon changes at once without reopening | Immediate refresh test across two windows | not yet performed |
| Relaunch: theme persists; Finder and Get Info still show Seal Dark | Relaunch simulated | not yet performed |
| Wi-Fi off: offline notice; installed theme still applies | Offline tests | not yet performed |
| Remove the theme in use: confirmation, return to Seal Dark | Tested | not yet performed |
| Damage one PNG in `~/Library/Application Support/Arkiv/DocumentIconThemes/<theme>/<n>/` (make a backup copy first): Arkiv falls back to Seal Dark and says the theme is damaged; then Remove and download again | Damaged-artwork test | not yet performed |

## 7. Multiple windows and Archive Info

| Check | Automated | Real Mac |
| --- | --- | --- |
| ⌘N twice; open different archives; reopening an open archive focuses its window | Routing tests | not yet performed |
| `nested.zip` → double-click `inner.zip`: new window, subtitle "Inside nested.zip" | Nested tests | not yet performed |
| Archive Info (⌘I): icon, summary and grid; path selectable; Done | Inspector tests | not yet performed |

## 8. Create, test, extract

| Check | Automated | Real Mac |
| --- | --- | --- |
| Create ZIP, 7z, TAR.GZ, TAR.XZ, ZSTD from `src` (File → Create Archive…, ⇧⌘N) | Engine and creation tests | not yet performed |
| Test Archive (⌘T) on each: jade seal on success; truncate a copy (`head -c 5000 sample.zip > broken.zip`) for the warning | Integrity tests | not yet performed |
| Extract All / Extract Selected into `~/ArkivAcceptance/out`: new folder, nothing overwritten, Finder reveals it | Safety suite | not yet performed |
| **Encrypted:** create a 7z with password and encrypted filenames, and an AES-256 ZIP; reopen; wrong password retries; correct password extracts | AES tests | not yet performed |
| **Split 7z:** create from `split-source.bin` with a custom split size of `10000000` bytes; open `.7z.001` and a later volume; extract and compare (`cmp`) | Split tests | not yet performed |
| **Cancellation:** extract `many.zip` and press Cancel in the footer: no partial output folder remains | Cancellation tests | not yet performed |
| Safe extraction: archives with `../` paths are refused (fixtures in `tests/fixtures`) | Hostile-path suite | not yet performed |

## 9. Accessibility

| Check | Automated | Real Mac |
| --- | --- | --- |
| VoiceOver: welcome (list of "Open *name*, in *folder*" buttons, drop zone), toolbar labels, table, footer ("Path and status"), Settings sidebar, accent swatches announced as radio buttons with colour names, preview | Labels and roles asserted | not yet performed |
| Full Keyboard Access: Tab through the welcome window, Settings and theme gallery | — | not yet performed |
| Increase Contrast, Reduce Transparency, Reduce Motion | Plain-surface fallback seen on CI | not yet performed |
| Larger text sizes in System Settings do not clip Settings rows | Clipping test at default size | not yet performed |

## 10. Size, launch time, memory and idle CPU

Measure 30701 first, then the redesign build, same Mac, same conditions.

```bash
du -sh /Applications/Arkiv.app ~/ArkivAcceptance/Arkiv.app
# Cold launch to process start (repeat 3 times after quitting Arkiv):
t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time'); open ~/ArkivAcceptance/Arkiv.app
until pgrep -x Arkiv >/dev/null; do sleep 0.02; done
perl -MTime::HiRes=time -e "printf \"%.0f ms\n\", (time - $t0) * 1000"
# Time to first window: stopwatch, or watch for the window by eye.
# Resident memory, idle, welcome window then with many.zip open:
ps -o rss=,command= -p "$(pgrep -x Arkiv)" | awk '{printf "%.1f MB\n", $1/1024}'
# Idle CPU over 30 s (should be ~0.0%):
top -l 31 -s 1 -pid "$(pgrep -x Arkiv)" -stats cpu | grep -E '^[0-9.]+$' | tail -30 | awk '{s+=$1} END {printf "%.2f%% average\n", s/NR}'
```

| Measure | CI result | 30701 (real Mac) | Redesign (real Mac) |
| --- | --- | --- | --- |
| App bundle / DMG | arm64 DMG 9,706,104 → 9,783,031 bytes (+0.8%) | not yet measured | not yet measured |
| Cold launch | not measurable on CI | not yet measured | not yet measured |
| Memory (welcome / many.zip) | not measurable on CI | not yet measured | not yet measured |
| Idle CPU | not measurable on CI | not yet measured | not yet measured |

## 11. Clean-up

```bash
rm -rf ~/ArkivAcceptance
```

Settings → General → Clear Recent Archives removes the test archives from
Open Recent; Settings → Appearance → Restore Defaults; Settings → Document
Icons → Restore Default and Remove any test themes.

The Quick Look prototype has its own, separate procedure:
[feasibility report](quicklook-thumbnail-feasibility.md#real-mac-evaluation).
