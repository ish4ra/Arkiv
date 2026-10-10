# ZIP / 7z creation and Finder compression

ZIP is Arkiv’s primary/default creation format. Arkiv creates ZIP archives using system libarchive and offers 7z as a secondary format using a bundled, in-process 7-Zip library. RAR/RAR5 creation is not supported; read support never implies write support.
There is no shell compression command, bundled 7zz executable, or Homebrew/runtime
installation requirement. Existing archive modification is not implemented.

## Finder and native UI

Within the existing home-directory Finder scope, select one regular file, one
folder, or up to 128 files/folders in the same parent directory. Mixed selection,
Unicode, spaces, emoji, nested contents and empty directories are supported.
The menu for normal items offers:

- **Add to Archive…** — native setup sheet (or standalone native panel when no
  browser is open), with selected items, name, destination, ZIP/7z format and
  Store/Deflate (ZIP) or LZMA2 Normal (7z) compression. Destination selection uses the native folder chooser.
- **Compress to “Name.zip”** — direct creation beside the selection.
- **Compress to “Name.7z”** — direct LZMA2 creation beside the selection.
- **Compress with Password…** — opens setup with 7z/AES-256 selected, Password,
  Confirm Password, Show Password and Encrypt filenames controls.

A single `file.txt` becomes `file.zip`; `Subs/` becomes `Subs.zip`; multiple items
use their common parent name. Names are sanitized and existing output is never
replaced: `Name.zip`, `Name (2).zip`, etc. Single ZIP/TAR/7z selections retain the
existing archive extraction menu. The File menu also offers **Create Archive…**
(Shift-Command-N), allowing files/folders to be selected before setup.

7z supports AES-256 content encryption and optional header/filename encryption.
Encrypted 7z archives prompt for a password when opened, allow retry, and use the
same browser/extractor after unlock. Passwords are not saved. ZIP AES remains
unavailable; Arkiv never substitutes ZipCrypto. See [backend details](sevenzip.md).

## Engine and safety

`ArchiveCreationRequest` and `ArchiveCreator` in ArkivCore are independent of
Finder/AppKit. The C bridge streams libarchive ZIP Store/Deflate entries. Inputs
are limited to regular files and directories: links, special files, overlapping
roots, duplicate unsafe names and output-inside-source directories are rejected.
The descriptor-based traversal uses no-follow opens, depth/entry/byte bounds,
source checks, progress and cancellation. The writer creates a private staged
archive, reopens it and reads every entry/data block for validation, then
publishes without replacing any existing item. Failures/cancellation clean the
private staging area. Existing extraction protections are unchanged.

Creation does not claim resource-fork/xattr/Finder-metadata preservation, archive
modification, arbitrary filesystem snapshots, or encrypted ZIP creation. Files being
edited during compression can cause creation to fail; retry with stable inputs.

Finder URLs carry only an allowlisted command and bounded local source URLs.
Direct creation is subject to the same explicitly accepted custom-URL trust
tradeoff as direct extraction: sender authentication is not claimed. Destination
and password options cannot be injected through the URL. App validation and the
engine revalidate sources; the extension never writes or parses archives.

## Quiet task launches

Finder launches include a task argument and use nonactivating NSWorkspace opening
for direct ZIP/7z, Extract Here and Extract to Folder. The app also tracks incoming
open requests, suppressing the otherwise unconditional initial empty browser.
Progress uses a nonactivating panel with Cancel. Success plays the existing
original completion sound once, without browser opening, Finder reveal, or app
activation. Open in Arkiv activates normally; Add to Archive and Extract To may
activate to present their UI. Errors may activate Arkiv to make failures visible.
Onboarding and normal Sparkle checks start during an interactive browser session,
not as an interruption to a background Finder task. Encrypted extraction activates
Arkiv when a password prompt is required.

## 7-Zip research and licensing

Researched official [ip7z/7zip](https://github.com/ip7z/7zip) main at commit
`9128b80e3a471108678e2b3ec3c985861c8d7b0f` (2026-10-09):

- `CPP/7zip/UI/Explorer/ContextMenu.cpp`: selection-based Compress/Add and direct
  ZIP/7z command dispatch, derived names, format-specific menu behavior.
- `CPP/7zip/UI/Common/ArchiveName.cpp`: single-item names, common-parent names
  for multiple selections, filesystem-safe output names and collision handling.
- `CPP/7zip/UI/Common/Update.cpp`: create/update preparation, temporary paths,
  writer callbacks and final output publication.
- `CPP/7zip/UI/GUI/CompressDialog.cpp`: format/method/level capability-driven
  controls and password confirmation; studied as behavior, not a visual template.
- `DOC/License.txt`: most source LGPL 2.1-or-later; RAR files additionally carry
  the unRAR restriction; identified BSD/public-domain exceptions are file-specific.

The 7z backend now bundles a pinned LGPL 2.1-or-later 7-Zip subset, with
source, patches and rebuild instructions. No UI/assets or RAR code are included.
ZIP continues to use libarchive; see [license and integration details](sevenzip.md).

## Validation and real-Mac test

Automated tests cover create → reopen → extract → byte comparison for Store and
Deflate, Unicode and mixed roots, empty folders, conflicts, invalid inputs,
cancellation and cleanup. C-level tests check ZIP methods, UTF-8 flags, CRC,
limits, symlink ancestors and special-file rejection. Routing tests cover bounded
multi-selection and malformed URLs; the packaged NSWorkspace diagnostic exercises
all four creation routes and checks that cold direct ZIP/7z requests have no browser window.

1. Update through Sparkle. Quit Arkiv, select two files in a home subfolder, choose
   Compress to ZIP. Verify no empty browser or focus jump, a valid parent-named ZIP,
   and one completion sound. Repeat for `(2)` without changing the first archive.
2. Repeat direct creation with ZIP and 7z and one folder containing nested, empty, Unicode/emoji/spaced names.
   Open the result in Arkiv, extract it and compare contents.
3. Use Add to Archive; verify preloaded names, destination, Store/Deflate, cancellation,
   and File → Create Archive too. Select 7z, enable AES-256, enter matching passwords,
   and test Encrypt filenames both on and off. Open each result: try a wrong password,
   retry correctly, browse, and extract/compare. Cancel an unlock without output.
4. Cancel a sufficiently large creation; verify no final ZIP is published and no
   hidden staging directory remains. Existing files must survive failures/conflicts.
5. With Arkiv quit, test Extract Here/Folder: no browser/focus jump or Finder
   navigation. Open activates; Extract To shows its chooser. Recheck Services,
   completion sound, onboarding on normal launch, and Sparkle on Intel/Apple Silicon.
