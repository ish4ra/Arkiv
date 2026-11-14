# Archive creation and Finder compression

ZIP is Arkiv’s primary/default creation format. Arkiv creates ZIP archives using system libarchive and offers 7z as a secondary format using a bundled, in-process 7-Zip library. RAR/RAR5 creation is not supported; read support never implies write support.
There is no shell compression command, bundled 7zz executable, or Homebrew/runtime
installation requirement. Editing existing archives is limited to eligible ZIPs;
see [ZIP additions](zip-additions.md) and [ZIP edits](zip-edits.md).

## Finder and native UI

Within the existing home-directory Finder scope, select one regular file, one
folder, or up to 128 files/folders in the same parent directory. Mixed selection,
Unicode, spaces, emoji, nested contents and empty directories are supported.
The menu for normal items offers:

- **Add to Archive…** — native setup sheet (or standalone native panel when no
  browser is open), with selected items, name, destination, ZIP/7z/TAR format and
  ZIP Store/Deflate presets or 7z LZMA2 presets, both defaulting to Normal. TAR options use fixed bounded settings described below. See [preset mappings and resource limits](compression-presets.md). Destination selection uses the native folder chooser.
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

## TAR and compressed TAR creation

The same Create Archive sheet (including Finder **Add to Archive…**) offers TAR
(`.tar`), TAR + gzip (`.tar.gz`, `.tgz`), TAR + bzip2 (`.tar.bz2`, `.tbz2`) and
TAR + XZ (`.tar.xz`, `.txz`). Aliases produce identical formats. ZIP remains the
default; direct Finder ZIP/7z actions are unchanged. No additional direct Finder
commands, TAR encryption or TAR editing. Standalone compression is a separate
choice for one regular file; see below.

System libarchive writes restricted PAX TAR, adding PAX headers when UTF-8/long
paths require them. The existing descriptor traversal accepts only regular files
and directories, including empty files/directories. It rejects links (including
ancestor symlinks), special files, unsafe paths, overlapping roots and output
inside a source. Permissions preserve only `0777` bits (no setuid/setgid/sticky);
mtime is stored at whole-second precision. Owners, ACLs, xattrs, resource forks,
Finder metadata and link identities are not copied.

Fixed compression settings are gzip level 6 (Deflate with CRC32/ISIZE trailer),
bzip2 block level 9 (block/stream CRCs), and XZ preset 6 (LZMA2, 8 MiB dictionary,
CRC64). There are no TAR level/dictionary/thread controls. Encoding uses 64 KiB
input/output buffers; XZ admission requires at most 128 MiB encoder memory and
64 MiB decoder memory. Sources are limited to 100,000 entries, depth 128 and
4096-byte archive paths. The TAR, including metadata/padding, is capped at 20 GiB;
source identity/path records have a 64 MiB budget. Compressed output allows at
most TAR's limit plus 1% + 1 MiB framing overhead. These are ceilings, not reserved
memory. Temporary disk may hold the original TAR, compressed output and decoded
verification TAR together (roughly three times uncompressed size).

Before publication, every TAR file is read back and compared with its safely
reopened source, with modes/mtime/entry sizes checked. Compressed output is decoded
by Arkiv's existing bounded, checksum-validating reader and compared byte-for-byte
with that TAR. The shared integrity reader then checks the verified TAR. Every
source identity/size/mtime/ctime is revalidated before an exclusive same-filesystem
hard link publishes the result. Numbered suffixes preserve complete extensions
(e.g. `Name (2).tar.gz`). Cancellation/failure cleans private staging and never
replaces an existing archive. Inputs must remain stable; this is not a filesystem
snapshot. Test Archive still reports TAR's honest no-per-file-checksum Warning.

Backend tests independently decode all wrappers with Python's gzip/bz2/lzma and
read the PAX TAR with tarfile, checking bytes, long Unicode paths, empty entries,
permissions, mtime, checksums, collision handling, bounds and unsafe-source cleanup.
Core round trips use Arkiv inspection, extraction, Test, Open/Quick Look materialization
and drag delivery. Native tests exercise the shared sheet's formats and disable
unsupported options. SDK probes link encoder and decoder APIs for both CPUs;
macOS CI is required to confirm the system-library implementation.

Real-Mac check: create every variant from a folder containing nested/empty folders,
a long Unicode filename and an executable file. Reopen, Test and extract; compare
contents and permissions. Repeat to check numbered names, cancel a large creation,
and try an unsafe symlink input. Check Finder Add to Archive exposes the formats,
direct ZIP/7z remains unchanged, and TAR shows no password or advanced controls.

## Standalone single-file compression

GZIP (.gz), BZIP2 (.bz2) and XZ (.xz) are available in the same setup sheet for one
regular file only. They retain its full basename/extension and use fixed levels
6/9/6 respectively, without password/advanced controls. Multiple files or folders
require a container such as TAR. Core enforces this independently of UI. The same
bounded codecs, source pinning, decoded byte comparison and exclusive publication
protect creation; [policy, metadata and compatibility details](standalone-compression.md).
