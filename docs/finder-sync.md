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
The menu action is carried by a scalar tag. At invocation, the extension reads
Finder’s documented action-time selection, validates it, and snapshots the URL
before asynchronous delivery. It does not depend on a custom represented object
surviving Finder’s cross-process menu transport. Unsupported types,
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

**The URL itself cannot authenticate Finder.** Arkiv now checks the current
`kAEGetURL` Apple event's exact URL and its OS-supplied, read-only sender audit
token. Security.framework resolves that token to running code and validates it
against the exact code-directory hash of the bundled Finder extension. A bundle
identifier, same user/PID, URL parameter or self-declared entitlement is never
sufficient. This works with ad-hoc code signatures without inventing a Team ID.
The extension remains sandboxed with unchanged entitlements.

Only successful authentication bypasses the additional confirmation for Extract
Here and Extract to Folder. Extract To always presents its destination chooser.
Missing identity, a Launch Services broker/delegate with different identity,
invalid signature, or an old/mismatched extension binary falls back to the existing
confirmation. Arbitrary applications/websites cannot opt into trust through URL
fields. Requests still undergo normal validation and revalidation before writes.
The macOS URL delivery route may expose a broker rather than the original Finder
extension on some versions or launch paths: such requests **still prompt**. CI
cannot promise that every real Finder cold/warm launch preserves sender identity.

Successful Extract Here and Extract to Folder do not reveal/select output in
Finder; nearby files/folders appear naturally without changing its directory.
Extract To retains the reveal of the explicitly chosen destination's result.
Error recovery reveals files only if the user clicks **Show Extracted Files**.

Both entry points share the existing `FinderServiceProvider` operation owner and
`FinderExtractor` in ArkivCore. No parsing/extraction is duplicated. Existing
no-overwrite publication, collision suffixes, traversal/link/special-file
protection, size limits, cancellation, progress and recovery behavior remain.
Only one Finder extraction can run at a time. Services retain their existing
AppKit delivery and behavior.

## Enablement (requires user approval)

On first launch with the extension disabled, Arkiv shows a compact native
**Enable Finder Integration** setup window. It explains the four actions and
always displays the manual Settings path below, even if Apple's settings button
opens an unrelated Services pane on that macOS release.

**Open Extension Settings…** calls Apple's supported
`FIFinderSyncController.showExtensionManagementInterface()`. It does not grant
permission. Each time Arkiv becomes active again, the window re-reads
`FIFinderSyncController.isExtensionEnabled`. If enabled, it shows **Arkiv Finder
Enabled** and an Enabled success state; if still disabled, it says so.

**Not Now** (or closing the window) is remembered across launches. Once Arkiv has
observed the extension enabled, it also stops automatic setup prompts, including
if you later deliberately disable it. **Arkiv → Finder Integration…** always
reopens the same management window with current status, manual instructions,
settings button, and Services fallback information. Services visibility is a
separate macOS setting; Arkiv does not claim to detect or enable Services here.

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

## Registration correction after build 12401

Build 12401 did not appear in Finder extension settings on a real M1 Mac. Treat
that as a registration defect, not a user configuration error. The extension now
includes the complete Finder Sync `NSExtension` dictionary:

```xml
<key>NSExtensionAttributes</key><dict/>
<key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
<key>NSExtensionPrincipalClass</key><string>ArkivFinderSync.ArkivFinderSync</string>
```

The Swift class no longer overrides its Objective-C runtime name with the old
unqualified `@objc(ArkivFinderSync)` alias. It uses the actual module-qualified
Swift class name. The identifier remains `xyz.isharalakshan.arkiv.finder-sync`,
versions are copied from the containing app, and placement remains
`Contents/PlugIns/ArkivFinderSync.appex`.

CI now runs `--verify-principal-class` in the **actual signed extension executable**
on each native runner. A small Objective-C startup probe resolves the packaged
plist's name using `NSClassFromString`, checks its exact `NSStringFromClass` name,
and verifies it subclasses `FIFinderSync`. Normal extension startup still uses
Apple's `NSExtensionMain`; the probe does not instantiate the Finder extension.
This test also runs against the mounted DMG and copied installation. Metadata
regressions explicitly reject absent/wrong-type attributes and unqualified names.

A CI-only PlugInKit diagnostic registers the built appex with `pluginkit -a`, then
checks discovery with `pluginkit -m -A -D -v -v -i xyz.isharalakshan.arkiv.finder-sync`.
The check requires both the identifier and this build’s resolved appex path, so
an older installed copy cannot satisfy it. It never enables the extension or resets caches. Raw diagnostic output remains
in local CI logs. Users do not need terminal commands. These checks establish
bundle/class discovery, not interactive Settings visibility or user approval.

Retest the new Sparkle development build on your M1 Mac: confirm the first-run
setup appears, follow its manual path if the settings button opens Services,
verify Arkiv Finder is listed and enable it, then return to Arkiv and confirm
**Arkiv Finder Enabled**. Quit/relaunch to confirm no repeated onboarding. Test
**Not Now** on a fresh user profile with the extension disabled; relaunch should
stay quiet and the menu must still reopen management. Re-run the direct menu,
extraction/conflict/cancellation and Services checks above. If the new build is
still absent from Settings, report it as an unresolved registration bug with the
macOS version; do not reset caches as a normal setup step.

## Action-handoff correction after build 12601

Registration and the direct menu were confirmed on a real M1 Mac, but all actions
were silent. The reproducible defect in the action callback was its dependency on
`NSMenuItem.representedObject`: a returned item without that custom URL payload
hit the first guard and returned without attempting to open Arkiv. The other
preflight guards also returned silently, and NSWorkspace failures only went to
Console. No real-Mac trace was available to distinguish those silent exits.

The four actions now have stable integer tags. The callback uses the public
`selectedItemURLs()` API, which Apple's Finder Sync header explicitly supports
inside menu actions. A shared, tested relay validates the single file and action,
resolves `Contents/PlugIns/*.appex` to its containing app, checks the app identifier,
and sends the existing encoded `arkiv-finder` URL through explicit-app NSWorkspace
opening. The extension location comes from `Bundle(for: ArkivFinderSync.self)`,
not an assumption that the host process's main bundle is the extension. There is
no default-scheme-owner fallback, shell, entitlement expansion, or new runtime IPC.

Any unrecognized action, unavailable selection, invalid containing app, missing
launch result or NSWorkspace error now presents a native **Couldn’t send the
Finder action to Arkiv** error with the underlying diagnostic domain/code and
instructions to use **Finder → Services** or open Arkiv manually. An OS launch
error is no longer swallowed. The menu structure, icons, registration, setup,
Services and updater remain unchanged.

CI tests all four actions with nil representedObject, verifies relay failures are
reported without launching, and retains URL parsing/consent/no-write tests. A
read-only packaged-app diagnostic launches the real Arkiv executable through
NSWorkspace for Open, then delivers the extraction URLs to the **same running
process**. It observes nonce-scoped test acknowledgements from AppKit routing and
refuses extraction consent. The diagnostic does not replace production IPC or
claim to test a live Finder extension's sandbox. The extension runtime probe also
checks that its principal class exports `performAction:`.

Retest after updating: with Arkiv quit, right-click a ZIP in Downloads and choose
Open in Arkiv. Repeat with Arkiv running. Test Extract Here and Extract to Folder,
accept their confirmations, verify collision protection, and cancel each once.
Test Extract To's destination chooser and cancellation, then repeat with TAR and
a Unicode filename. If any handoff fails, record the new visible error's domain
and code; do not reset caches or redo working registration. Live Finder menu
transport and sandboxed delivery still require that real-Mac test.

## Authenticated consent and completion behavior after build 12901

The former unconditional success reveal selected Extract Here's returned parent
directory in its own parent, moving Finder from `Downloads/Compressed` to
`Downloads`. Success now reveals only Extract To results. No engine or publication
semantics changed.

Public API research: macOS 13's
[AEDataModel.h](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX13.3.sdk/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/AE.framework/Versions/A/Headers/AEDataModel.h)
declares `keySenderAuditTokenAttr` as read-only;
[SecCode.h](https://github.com/alexey-lysiuk/macos-sdk/blob/master/MacOSX13.3.sdk/System/Library/Frameworks/Security.framework/Versions/A/Headers/SecCode.h)
provides public audit-token guest lookup and dynamic code validation. The exact
CDHash requirement avoids treating forgeable ad-hoc bundle identifiers as identity.
The original sender is not inferred from a PID or from the URL. This pins the
installed architecture's extension; a stale extension after an update or a
cross-architecture mismatch safely prompts instead of relaxing identity checks.

NSXPCConnection's public peer code-signing requirements are also available on
macOS 13, but introducing a separate sandbox-approved endpoint/helper rendezvous
is unnecessary for this conservative Apple-event check. No App Group, Mach lookup
exception, shell IPC, shared bearer token, or private API is introduced. Apple
web documentation was blocked in this environment; the public SDK declarations
above were inspected directly.

Regression coverage checks success reveal behavior, trusted/untrusted consent
policy, exact event-to-URL binding, missing/invalid/delegated identity, and forged
URL trust claims. On both macOS runners a separately ad-hoc-signed diagnostic
uses a genuine kernel task audit token to prove exact-code acceptance and rejection
of a sender that does not match the packaged extension. Existing cancellation,
no-overwrite, collision, and packaged URL delivery tests remain enabled.

Real-Mac retest: place a ZIP in `Downloads/Compressed`, open that Finder folder,
and run Extract Here. Verify Finder stays there and existing files are never
replaced. Run Extract to Folder twice and verify collision-safe names with no
navigation. Test Extract To cancellation and successful chosen-destination output.
Repeat all actions with Arkiv quit and running, and with uncompressed TAR. An
authenticated original extension event skips redundant confirmation; any path
that cannot be authenticated retains it. An externally opened custom URL must
still prompt (or show the destination chooser). Report macOS version and whether
a cold/warm Finder invocation still prompts; never disable consent to hide a
brokered-identity limitation.
