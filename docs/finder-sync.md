# Direct Finder contextual actions

Arkiv embeds `Contents/PlugIns/ArkivFinderSync.appex`, a native Finder Sync
extension with identifier `xyz.isharalakshan.arkiv.finder-sync`. The existing
[AppKit Services](finder-integration.md) remain a fallback. No app icon or browser
UI is redesigned. Archive creation and multiple-archive extraction are not added.

## Menu and scope

Right-click **one regular ZIP or uncompressed TAR** inside your home folder:

```
Arkiv >
    Open in Arkiv
    Extract Here
    Extract to “Example/”
    Extract To…
```

The folder title uses the actual filename with the same sanitization and byte
limit used by ArkivCore. For ordinary `Example.zip`, it is `Example/`; unsafe
characters are normalized, and an occupied name becomes `Example (2)/`, etc.
The extension snapshots the menu selection so a later Finder selection cannot
silently change which archive an action operates on. Unsupported types,
directories, symbolic links and multi-selection do not get an Arkiv menu.
Eligibility checks metadata only; parsing still happens in the main app.

`directoryURLs` contains **only the current user's actual home directory**.
Finder Sync includes descendants, covering normal Desktop, Downloads, Documents,
and other home folders. The extension obtains the real home through the public
POSIX account API because a sandboxed extension's `NSHomeDirectory()` points to
its container. It never registers `/`, `/Users`, `/Volumes`, or all mounted disks;
it does not scan/enumerate directories, request badges, or run a file watcher.
There is no requirement for Full Disk Access or broad filesystem entitlements.
macOS privacy protections still apply to access to protected/cloud files.

External/removable/network volumes, other users' homes, and symlinks leading
outside your home are deliberately outside the direct-menu scope. Use Arkiv
Services or Open Archive there. A home directory itself located on an external
volume is covered by its home path. Relocated Desktop/Documents outside the home
are not automatically added. iCloud/File Provider locations and Finder's virtual
views may have host-specific visibility; test the real containing directory.
User-selected extra directory scopes are follow-up work, not an implicit
whole-filesystem monitor.

## Safe handoff and extraction

The sandboxed extension links only Apple's frameworks and the small
`ArkivFinderIntegration` routing module. It has no archive engine, Sparkle,
network permission, write permission, app group, temporary sandbox exceptions,
helper daemon, shell command, or private API.

The extension opens a versioned `arkiv-finder://action/v1` URL using public
`NSWorkspace.open` targeted explicitly at its enclosing Arkiv.app. The request
contains one allowlisted action and one encoded local file URL. It carries no
output path, executable command, or overwrite option. The receiver rejects
unknown/duplicate fields, remote URLs, unsupported formats, malformed requests
and oversized payloads. It then runs the same `FinderRequest` regular-file and
symlink validation as Services, including revalidation after confirmation.

**A URL handler cannot authenticate Finder as the sender.** Other applications
or websites could invoke a registered scheme, so Extract Here and Extract to
Folder present a native confirmation showing the source and destination before
any filesystem writes. Extract To uses Arkiv's native destination chooser as the
explicit consent step. Cancelling performs no extraction. There is no setting
that silently trusts arbitrary URL requests. Open in Arkiv uses normal browsing.
This is a deliberate security tradeoff; the menu is direct, but extraction is
not an unauthenticated one-click remote command.

Both entry points share the existing `FinderServiceProvider` operation owner and
`FinderExtractor` in ArkivCore. No parsing/extraction is duplicated. Existing
no-overwrite publication, collision suffixes, traversal/link/special-file
protection, size limits, cancellation, progress and recovery behavior remain.
Only one Finder extraction can run at a time. Services retain their existing
AppKit delivery and behavior.

## Enablement (requires user approval)

Install/update Arkiv in **/Applications** and launch it once. In Arkiv choose
**Arkiv → Finder Integration…**. This reports the actual enabled state from
`FIFinderSyncController.isExtensionEnabled`; **Open Extension Settings** calls
Apple's supported `showExtensionManagementInterface()`.

Manual paths:

- **macOS 15 Sequoia / macOS 26 Tahoe:** System Settings → General → Login Items
  & Extensions → Extensions → Finder (information button) → enable **Arkiv Finder**.
- **macOS 13 Ventura / macOS 14 Sonoma:** System Settings → Privacy & Security →
  Extensions → Finder Extensions → enable **Arkiv Finder**.

Apple can adjust labels between minor releases; Arkiv's management button is the
supported entry point. Enabling is never automated with `pluginkit`, preferences
writes, or private settings URLs. No terminal command is part of normal setup.
The build remains ad-hoc signed and not notarized; initial Gatekeeper approval
is unchanged. Do not disable Gatekeeper or the extension sandbox.

After a Sparkle update, confirm the enabled state and reopen the Finder window
if it was displaying an old menu. macOS owns extension process lifetime and
registration, and may require re-enablement of an updated development signature.
Arkiv does not kill/restart Finder or claim it can bypass that approval.

## Research and implementation notes

The public [Finder Sync guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)
and [Finder Sync API](https://developer.apple.com/documentation/findersync) describe
scoped Finder customization. Apple's web documentation was blocked by this
execution environment's network policy; the actual public SDK headers were read
from [macOS 15.5](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX15.5.sdk/System/Library/Frameworks/FinderSync.framework/Versions/A/Headers/FinderSync.h)
and [macOS 26.5](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX26.5.sdk/System/Library/Frameworks/FinderSync.framework/Versions/A/Headers/FinderSync.h).
They retain `directoryURLs`, `menuForMenuKind:`, `selectedItemURLs`,
`isExtensionEnabled`, and `showExtensionManagementInterface` as supported APIs.
`directoryURLs` explicitly includes descendants. Menus are provided only for
`contextualMenuForItems`, never empty-background/sidebar/toolbar menus.

Unlike the earlier Services-only decision, this milestone intentionally accepts
the limited home-directory scope and user enablement required for direct menus.
Finder Sync provides a real NSMenu submenu; Services' obsolete slash-title
convention is not used. Apple's NSWorkspace SDK header supplies the explicit-app
URL-opening API. The extension entry point is the public Foundation
`NSExtensionMain`, with an Objective-C-visible `FIFinderSync` principal class.

## Validation and real-Mac acceptance

CI builds the extension for the same arm64 or Universal architectures as Arkiv,
signs it before its container, checks actual signed sandbox entitlements, checks
its plist/identifier/principal class and version alignment, and verifies it in
the built app, mounted DMG and copied installation. Dependency inspection ensures
no libarchive/Core/Sparkle code is linked into Finder. Existing updater framework,
EdDSA tests, Services metadata, engine/security and Swift tests remain enabled.
Routing tests cover Unicode/reserved filenames, malformed/ambiguous handoffs,
scope boundaries, links/directories/multiple selections, and cancellation before
writes. CI cannot establish interactive Finder menu visibility or enablement.

On your M1 Mac:

1. Use the verified Sparkle **Check for Updates…** flow to install the new build
   (or use its development DMG). Confirm About/Info.plist shows the newer build.
2. Choose **Finder Integration…**, open extension settings and enable Arkiv Finder.
   Confirm Arkiv reports it enabled. Test with one ordinary ZIP in Downloads;
   right-click should show **Arkiv** directly, alongside Finder's own actions.
3. Choose Open in Arkiv with Arkiv quit, with an empty window, and with an archive
   already open. Confirm the existing window-reuse/browsing behavior.
4. Test Extract Here, accept confirmation, and check files beside the ZIP. Repeat
   with an output-name collision: existing files must remain unchanged. Test
   cancelling confirmation and cancelling a large extraction.
5. Choose Extract to “Example/” twice; verify separate `Example` and `Example (2)`
   folders. Repeat with a Unicode filename. Test Extract To, cancel its chooser,
   then choose a different destination and verify output there only.
6. Repeat with uncompressed TAR on Desktop, in Documents, and in a nested home
   folder. Text files, `.tar.gz`, links, folders and multiple archives should not
   receive the direct menu. On removable media use the Services fallback.
7. Disable the extension: direct actions disappear, Services still work, and
   Finder Integration reports disabled. Re-enable it. Run another Sparkle update
   and confirm the updater, extension and Services still function together.
8. Repeat on Intel using the Universal app. Check both light/dark menus and
   keyboard/accessibility navigation. Report macOS version, build number and
   tested location if Finder does not expose the menu; do not assume CI proves it.
