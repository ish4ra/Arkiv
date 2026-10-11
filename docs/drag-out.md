# Drag archive entries to Finder

Select a file, folder, or multiple rows in an open archive and drag them to Finder.
Arkiv uses AppKit `NSFilePromiseProvider` objects and the table's native drag UI.
Only copy operations are advertised. Ordinary selection and double-click behavior
are unchanged. Dragging into Arkiv is not implemented.

A folder promises its complete hierarchy. A selected child beneath a selected
folder is omitted from the promise list. Items are placed separately at Finder's
supplied URLs, without an extra extraction folder. Finder may choose a different
name; Arkiv always honors the supplied destination and never silently replaces
an existing item. A conflict or unavailable destination produces a delivery error.

Promises retain the opened archive snapshot, including an already-unlocked 7z
session. They do not store passwords or place archive paths/passwords on the
pasteboard as a custom command. No extraction starts while merely advertising or
dragging the promise. Materialization starts when the receiver requests delivery,
on a serial background operation queue using ArkivCore's selective extractor.

This supports the existing tested ZIP, TAR, 7z and RAR/RAR5 decoding capabilities;
it does not add codecs or multipart support. Symlinks, safe hardlinks and executable
permissions use the existing extraction rules. Hardlink dependencies may be
materialized privately so a selected link can be delivered without publishing its
unselected target. Traversal/link-write confinement, limits, source validation,
cancellation and exclusive publication remain enforced.

Temporary extraction uses a private hidden destination-volume staging area.
Completed promises have no UUID wrapper. Cancellation before delivery creates no
output; failed delivery cleans staging. Items already delivered successfully are
not removed if a later item fails. If a receiver requests only part of a selection, remaining private output expires
after five idle minutes; a later request fails clearly and requires a new drag.
Finishing, cancelling, or releasing the session cleans its private output. Process termination can still leave private staging, as with
other extraction operations; no secure-erasure or crash-recovery guarantee is made.

Delivery does not reveal files, activate Finder, or play extraction sounds.
Errors go to the receiver's completion handler and the available Arkiv window;
unsupported-special-entry warnings use the existing extraction warning UI.

## Validation

Core tests cover lazy materialization, single/multiple items, folder hierarchy,
Unicode, overlapping selection, cancellation, conflicts/failure cleanup and links.
Native tests exercise the file-promise delegate and its completion behavior.
After packaging each macOS CI app, a native delegate test promises the real
`Arkiv.app` from the distribution ZIP. CI compares every app path, file hash,
symlink target and executable bit, then runs the existing signature, architecture,
Finder extension and Sparkle runtime verification on the promised app without
re-signing it. This is automated delivery coverage; an interactive Finder drag
still needs a real-Mac check.

## Real-Mac checks

1. Open a ZIP, select a file, and drag it to a fresh Finder folder. Confirm its
   original name/content and no wrapper folder, extra Finder window or sound.
2. Drag a nested folder with empty folders and Unicode/emoji names. Verify its
   complete hierarchy. Repeat with multiple selected files/folders.
3. Search the archive so both a parent folder and child are visible; select both
   and drag. Only the parent hierarchy should be delivered.
4. Start a drag and press Escape before dropping. Confirm no output appears.
   Repeat a drop into a folder with an existing same-named item: no silent overwrite.
5. Unlock an encrypted 7z, then drag an entry. It should reuse the open session.
6. Open the official Universal ZIP and drag `Arkiv.app` to a fresh folder. Quit
   the running app and launch the promised app; check Finder integration and
   Check for Updates. Sparkle framework links and executables must remain intact.

API references: Apple's [file-promise provider](https://developer.apple.com/documentation/appkit/nsfilepromiseprovider)
and [delegate](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate)
contracts. The public SDK header specifies a weak delegate, a receiver-supplied
exact URL, and an optional background operation queue; Arkiv explicitly retains
its delegate/session for asynchronous delivery.

## macOS packages in the browser

Directory entries ending in `.app`, `.framework`, `.bundle`, `.plugin`, `.appex`
or `.xpc` use package type labels and native type icons. Double-click does not
enter or launch them. Select one and choose **Show Package Contents** from the
context menu to browse inside; Back, Forward, Up and search keep their normal
behavior. Recognition is by directory/name, not execution or bundle validation.
Packages remain directories in the archive model: extraction and drag-out include
the complete hierarchy. No archive data is changed by this presentation policy.
