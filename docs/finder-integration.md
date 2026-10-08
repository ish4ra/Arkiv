# Finder extraction through AppKit Services

Arkiv provides four native file Services, declared inside `Arkiv.app`. There is no
Finder Sync extension, background folder monitor, Automator installer, helper,
custom URL scheme, shared command file, or duplicated archive engine.

## API research and decision (2026-10-08)

| Approach | Fit for this milestone |
| --- | --- |
| Finder Sync | Supports dynamic contextual menus and selected URLs, but its documented selection/menu scope is the extension's managed `directoryURLs`. Making this a general archive menu would require monitoring broad directory trees and extension enablement. Rejected for this non-sync utility. |
| Action extensions / Finder Quick Actions | A supported host/extension model with activation rules and item-provider input, but host-controlled presentation and extension request lifetimes. A container-app handoff and extension signing/access handling would be needed for long extraction and destination UI. Does not provide a guaranteed arbitrary dynamic Finder submenu. Deferred. |
| AppKit Services | Native selected-file actions, type restrictions, menu names, and launch/delivery directly to the app's Services provider. The app owns the chooser, progress, cancellation, and existing engine. Chosen as the smallest supported architecture for the current macOS 13+ target. |
| Automator Quick Actions | User-installed workflows can appear as Finder Quick Actions, but require separate workflow installation and usually a script/app handoff. Not bundled as a pretend app extension. |
| App Intents / Shortcuts | Modern automation entry points; a user-configured shortcut can be exposed as a Quick Action. They do not by themselves install these four Finder Services. A future automation feature, not needed for this milestone. |

Research inspected these published Apple SDK interfaces through accessible SDK
mirrors: [macOS 15.5 NSApplication Services APIs](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSApplication.h),
[macOS 26.5 NSApplication APIs](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSApplication.h),
[Finder Sync controller documentation](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/FinderSync.framework/Versions/A/Headers/FinderSync.h),
[NSExtensionContext](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSExtensionContext.h),
[Automator workflows](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/Automator.framework/Versions/A/Headers/AMWorkflow.h),
and [App Intents interfaces](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/AppIntents.framework/Versions/A/Modules/AppIntents.swiftmodule/arm64e-apple-macos.swiftinterface).
The Services property and provider APIs are present in both inspected SDKs;
`NSRegisterServicesProvider` specifically directs apps to `setServicesProvider`.
Arkiv uses that property and static `NSServices`, not dynamic service registration.
[iTerm2's maintained Services declarations](https://github.com/gnachman/iTerm2/blob/master/plists/release-iTerm2.plist)
were also inspected for real file-pasteboard registration.

Apple's [Services guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/introduction.html)
and [App Extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/)
are additional references. Direct requests to developer.apple.com were blocked by
the development environment's network policy; those web pages were not fetched.
SDK evidence is not a substitute for testing Finder's actual menu presentation.

## Registration correction

The first implementation passed source/plist checks but failed discovery on a real
M1 Mac: no Arkiv entries appeared in Services settings or Finder. That was a
registration defect, not a user configuration problem. Its validator incorrectly
required pasteboard `NSSendTypes`, a file-type context filter, and legacy slash
submenu titles. The corrected declarations use **`NSSendFileTypes`** with
`public.zip-archive` and `public.tar-archive`, an empty `NSRequiredContext`, direct
service titles, and no `NSSendTypes` or unused `NSReturnTypes`. The existing
selector, port, action data, and provider-side validation are preserved. Bundle
build version is incremented to 2 so the corrected app is identified as an update.

## Actions and scope

Right-click one `.zip` or **uncompressed** `.tar` file in Finder, then use
**Services** and choose a direct action:

- **Open in Arkiv**: existing browser/window-reuse workflow; no extraction.
- **Extract Here with Arkiv**: place the archive's top-level items beside the archive.
- **Extract to Folder with Arkiv**: create `<ArchiveName>/` beside it, or
  `<ArchiveName> (2)/`, `(3)/`, etc. if the name is occupied.
- **Extract To… with Arkiv**: Arkiv opens a native folder chooser, then creates an
  archive-named folder inside the chosen directory, using the same conflict rule.

There is no Arkiv submenu: slash-separated titles are not supported by modern
macOS Services. macOS controls Finder placement and eligibility. Titles are static;
the menu cannot display the selected archive's actual name. The destination folder
still uses that name, sanitized and bounded in UTF-8 length.

Only ZIP and uncompressed TAR types are advertised via `NSSendFileTypes`.
The provider revalidates one local regular file and its suffix; it rejects links,
directories, remote URLs, unknown actions, and multiple selections before any
extraction. Corrupt/encrypted/unsupported contents still fail engine validation.
Other browser formats and compressed TAR wrappers are not advertised by these
Finder actions. No multi-archive, Extract Each, Compress, or Create action is
implemented. If Finder offers the service for multiple matching files, invoking
it reports the one-archive limit and performs no work.

## Safety and cancellation

All parsing and extraction use the unchanged `LibArchiveEngine` through
`FinderExtractor` in ArkivCore, preserving path traversal, links/special-file,
CRC, source-change, 100,000-entry/20-GiB, and cancellation protections. No external
archiver or shell handles archive paths. Services accepts file pasteboards only,
not command text, and does not bypass filesystem permissions or add entitlements.

Verified extraction completes in a private output folder before publication.
Extract Here preflights all top-level names, including hidden names. **Any existing
file, folder, or symlink is a conflict. Existing trees are never merged.** A known
conflict leaves the destination untouched apart from the separate recovery folder.
Atomic, descriptor-relative no-replace renames (`renameatx_np(RENAME_EXCL)` on
macOS) also prevent overwrites if a conflicting name appears after preflight.
Unsupported exclusive-rename filesystems fail safely, never fall back to overwrite.

Publishing several top-level items is not one filesystem transaction. If a race,
I/O failure, or cancellation interrupts publication, already placed items remain;
remaining verified output stays in a uniquely named `Arkiv Extracted …` folder.
The error reports the placed count and recovery location and offers **Show
Extracted Files**. No destructive rollback runs. Cancellation before publication
cleans up the private output. Folder-mode publication is a single exclusive rename.
These safeguards do not promise protection from an adversarial same-user process
arbitrarily replacing/moving directories in the chosen parent.

Arkiv allows one Finder extraction at a time. A compact operation window provides
Cancel; closing it requests cancellation, and quitting is blocked until cleanup
finishes. Regular browser operations remain unchanged.

## Install and retest on a real Mac

1. Quit the previous Arkiv build. Download a successful current arm64 or Universal
   development DMG as described in [release.md](release.md). Replace
   **/Applications/Arkiv.app**, eject the DMG, and launch the installed app once.
   Complete the documented development Gatekeeper approval if needed.
2. Open **System Settings → Keyboard → Keyboard Shortcuts… → Services → Files
   and Folders**. Confirm all four direct titles appear: **Open in Arkiv**,
   **Extract Here with Arkiv**, **Extract to Folder with Arkiv**, and
   **Extract To… with Arkiv**. Enable them if unchecked. There is no Finder
   extension checkbox or expected Arkiv submenu.
3. Select one ZIP or uncompressed TAR in Finder. Right-click → **Services** and
   confirm the actions are available according to macOS Services policy. Test
   each action as listed below, including launching Arkiv while it is quit.
4. If the corrected build is still absent from Services settings, report that as
   a remaining registration bug with macOS version and app build information.
   Normal installation/use does not require terminal commands or cache resets.

## Optional developer registration diagnostics

These are diagnostics for investigating a registration failure, **not normal-user
setup instructions**. `pbs` is system tooling, not a supported app runtime API or
an Arkiv dependency. On a development Mac, inspect the installed bundle with:

```sh
/System/Library/CoreServices/pbs -read_bundle /Applications/Arkiv.app
/System/Library/CoreServices/pbs
/System/Library/CoreServices/pbs -dump
```

The first command asks the system Services tool to read the bundle, the second
refreshes its Services information, and the third dumps the registered Services.
Look for all four direct titles and their file UTIs. A dump may include unrelated
apps and local paths; review it before sharing. Tool options/output can vary with
macOS releases. Do not build application logic around them.

CI runs the strict metadata verifier against the built app, mounted DMG, and
copied installation. A separate macOS-only diagnostic runs `pbs -read_bundle`
on the built app, registers that build-directory bundle with Launch Services,
refreshes Services, and checks `pbs -dump` for all four titles. Explicit indexing
is a CI fixture step because the build directory is outside normal installation
locations; no registration tool is called by Arkiv itself. The check fails if commands
fail or titles are absent; raw system output stays in local build logs, while
only fixed status/count diagnostics are printed. This is stronger than checking
source XML, but it still does not establish Finder menu visibility on a user's Mac.

## Real-Mac acceptance checklist

- Test installed arm64 on Apple Silicon and Universal on Intel and Apple Silicon.
- With Arkiv quit, invoke Open in Arkiv; repeat with an empty and occupied browser
  window. Confirm existing window reuse and normal archive browsing.
- Extract Here from a ZIP containing a folder, file, hidden file, and Unicode name.
  Confirm direct placement, no extra wrapper, and an unchanged source archive.
- Repeat with an existing output file, folder, and dangling symlink. Confirm no
  overwrite/merge, a clear error, and usable recovery files.
- Run Extract to Folder with Arkiv twice; confirm `<name>` and `<name> (2)`. Occupy a
  candidate with a file or symlink and confirm it is preserved.
- Run Extract To… with Arkiv, cancel the chooser, then retry with a writable destination;
  confirm only the chosen destination receives a new archive-named folder.
- Test a permission-denied destination, corrupt ZIP, hostile traversal/link archive,
  and cancelling a large archive. Confirm errors/cleanup and that quitting waits.
- Select a text file, folder, compressed TAR, remote URL, or two archives. Confirm
  unsupported file types have no extraction service; multi-selection, if offered,
  must be rejected with no output. Do not count a visible menu alone as success.
- Check the progress window in light/dark mode, keyboard Cancel, and VoiceOver.

CI checks actual AppKit pasteboard routing and the exported selector, core path and
publication decisions, existing engine/security tests, and the service metadata in
the built app, mounted DMG, and copied installation. It builds/signs/verifies arm64
and Universal with no nested extension to sign. Finder discovery/enablement and
interactive invocation remain real-Mac acceptance checks, not claimed CI coverage.
