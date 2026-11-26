# Using Arkiv

The everyday guide. What each format supports is summarised in the
[README](../README.md#supported-formats), with per-format evidence in
[format evidence](archive-formats.md) and the [feature matrix](feature-matrix.md).

## Browse, open and extract

A new Arkiv window shows the **welcome** canvas: **Open Archive…** (⌘O),
**Create Archive…** (⇧⌘N), your recent archives (click one to open it) and an
**Appearance…** shortcut. Drop archives anywhere on it to open them.

Open an archive with **File → Open Archive…** (⌘O), from **File → Open Recent**
or the welcome window, by dropping it on the welcome window, by
double-clicking an archive once Arkiv handles its type, or through Finder.

The archive window's toolbar holds Back/Forward beside the title, then Open,
Extract, Extract All, **Add** (Add Files, Add Folder, New Folder), Test and
Info, and the search field. The subtitle shows the format, file count and
size. The bar at the bottom shows where you are (click any part of the path to
go there) and the item count, selection size or the progress of a running
operation with Cancel. **View → Customize Toolbar…** adds Enclosing Folder,
Create, Quick Look or Settings, or shows labels.
Folders open on double-click. App and framework bundles appear as packages; use
**Show Package Contents** to look inside.

- **Extract Selected…** (⌘E) and **Extract All…** (⇧⌘E) write to a new folder
  in the destination you choose, with progress and cancellation. Existing files
  are never overwritten.
- **Open** launches a single file in its default app from a private temporary
  copy. Changes to that copy are **not** written back to the archive, and the
  copy is removed when the archive window closes, so save anything you want to
  keep somewhere else.
- **Quick Look** (Space) previews one regular file using the same temporary copy.
- **Nested archives:** double-clicking an entry whose contents are a supported
  archive, or choosing **Open as Archive**, opens it in a new Arkiv window. Only
  that entry is extracted, to the same private temporary workspace. Encrypted
  inner archives use the normal password prompt. Changes made inside a nested
  archive affect only its temporary copy and are never written back to the outer
  archive. Arkiv does not open nested archives automatically or browse them in
  the current window.
- **Search** (⌘F) filters by name across the whole archive. **Back** (⌘[),
  **Forward** (⌘]) and **Parent Folder** (⌘↑) handle navigation.
- **Columns:** Packed Size, Ratio, Modified, Method, Encrypted, CRC32 and
  Attributes can be shown from the table header's menu. Unknown values stay blank.
- **Archive Info** (⌘I) shows the archive's path, sizes, ratio and entry counts
  without extracting anything. See [Archive Info](archive-info.md).

Encrypted 7z and AES ZIP archives ask for a password when needed, with retry on
a wrong password. Passwords are never saved. Extraction preserves symbolic links
and safe executable permission bits, including inside app and framework bundles.
See [extraction compatibility](extraction-compatibility.md),
[open files and Quick Look](open-files.md) and [nested archives](nested-archives.md).

Split 7z sets (`name.7z.001`, `.002`, …) open from the first or any later part
when every part is in the same folder. See [split 7z](multipart.md).

## Create archives

Use **File → Create Archive…** (⇧⌘N) or Finder's **Add to Archive…** to choose a
name, destination, format and compression level.

| Format | Options |
| --- | --- |
| **ZIP** (default) | Store, Fastest, Fast, Normal, Maximum; optional **AES-256 password** (filenames stay visible) |
| **7z** | LZMA2 Fastest to Ultra; optional AES-256 with encrypted filenames; Advanced: dictionary, threads, solid blocks and **split into volumes** (100 MB to 4 GB presets or a custom size) |
| **TAR**, TAR + gzip / bzip2 / XZ / Zstandard | PAX TAR with fixed, bounded compression settings; `.tgz`, `.tbz2`, `.txz` and `.tzst` aliases; no passwords |
| **GZIP**, **BZIP2**, **XZ**, **Zstandard** single file | Exactly one regular file (`database.sql` → `database.sql.gz`); for several items, choose a TAR container |

**Compress with Password…** defaults to 7z, with ZIP AES-256 selectable. Arkiv
never falls back silently to legacy ZipCrypto.

New archives are reopened and verified before they appear, and existing files
are never replaced: name clashes become `Name (2).zip` and so on (split 7z sets
are never renamed; an existing volume stops creation). See [creation](creation.md),
[compression presets](compression-presets.md), [7z advanced options](sevenzip-advanced.md),
[standalone compression](standalone-compression.md) and [Zstandard](zstandard.md).

## Edit archives

Every edit builds a complete replacement archive, verifies it, and then swaps it
in atomically. If anything fails, or you cancel before that point, the original
is left untouched.

**ZIP** (ordinary single-disk ZIP32 archives without encryption):

- **Add Files…** and **Add Folder…** to the archive root, or drag Finder items
  onto the current folder or a folder row
- **Delete…** (⌘⌫) files and folders, after confirmation
- **Rename…** one file or folder within its current folder
- **New Folder**
- **Replace File…**: swap one file's contents for a file on disk, keeping its
  name and path in the archive
- **Replace Folder…** and **Update Folder…** for one selected folder or package
- **Update Selected Files…** for two or more files in one folder, with Replace
  All or Replace Older

**7z** (plain or encrypted, single-volume and non-solid, with supported methods
and metadata): **Add Files / Add Folder** to the root, **Delete**, **Rename** and
**Replace File**. Encrypted edits ask for the password for each operation.
Archives that encrypt only their headers allow Delete and Rename. Unchanged data
is copied without recompression.

Read-only: encrypted, ZIP64 and multipart ZIPs; solid or split 7z; TAR,
compressed TAR, standalone streams and RAR. Drag-in works for writable ZIPs only.
See [ZIP additions](zip-additions.md), [ZIP edits](zip-edits.md),
[7z editing](sevenzip.md#encrypted-adddeleterename-and-policy-inspection) and
[drag-in](drag-in.md).

## Drag and drop

Drag files or folders from Arkiv into Finder. Nothing is extracted until you
drop, and Finder's chosen destination is never overwritten. Read-only archives
do not accept drops. See [drag-out](drag-out.md).

## Test Archive

**File → Test Archive** (⌘T) reads and checks the open archive without writing
any files. **Test Archive File…** (⇧⌘T) checks an archive that may be too
damaged to open. Results distinguish OK, Warning, Corrupt, CRC Error, Wrong
Password and Unsupported Method where the format allows. TAR has no per-entry
checksum, so a passing TAR test is reported as a warning. See
[integrity checks](integrity.md).

## Finder integration

Arkiv includes a Finder extension that adds an **Arkiv** submenu to Finder's
context menu:

| Selection | Actions |
| --- | --- |
| One ZIP, 7z or uncompressed TAR | Open in Arkiv · Extract Here · Extract to "Name/" · Extract To… · Test Archive |
| Files and folders (up to 128, in the same folder) | Add to Archive… · Compress to "Name.zip" · Compress to "Name.7z" · Compress with Password… |

**Enabling it:** macOS requires you to turn the extension on yourself. Arkiv
shows a setup window on first launch, also available from
**Arkiv → Finder Integration…**, with a button and manual instructions:

- **macOS 15 and later:** System Settings → General → Login Items & Extensions →
  Extensions → Finder → enable **Arkiv Finder**
- **macOS 13–14:** System Settings → Privacy & Security → Extensions → Finder
  Extensions → enable **Arkiv Finder**

**Scope:** the submenu appears only for items inside your home folder. For
archives elsewhere, such as external drives, use the fallback **Services** menu:
right-click → Services → *Open in Arkiv*, *Extract Here with Arkiv*,
*Extract to Folder with Arkiv* or *Extract To… with Arkiv*. These Services cover
one ZIP or uncompressed TAR at a time. Enable them under System Settings →
Keyboard → Keyboard Shortcuts → Services if needed.

Extract Here and Extract to Folder run immediately, play a short completion
sound and never overwrite or merge existing items. See [Finder Sync](finder-sync.md)
and [Services](finder-integration.md), including real-Mac test steps.

## Settings

**Arkiv → Settings…** (⌘,) has a sidebar with **General** (Finder
Integration status and setup, clearing recent archives), **Appearance**
(System/Light/Dark with Dark by default, accent colour, row density,
alternating rows, toolbar customization, with a live preview), **Document
Icons** (the theme gallery) and **Updates** (Sparkle). See
[Settings](settings.md) and [document icon themes](document-icon-themes.md).

## Updates

After installing once, use **Arkiv → Check for Updates…**. Sparkle installs an
update only after verifying its EdDSA signature, and always asks first. This
proves the update came from this project's signing key; it is not Apple
notarization. See [development updates](updates.md).
