# Editing writable ZIPs

Open an eligible ZIP and select entries in the browser. **File → Delete…** is also available in the table context menu. This document describes ZIP-only editing; see [7z editing](sevenzip.md) for its separate eligibility rules. Arbitrary multi-selection mapping and update-by-date remain deferred.

Delete requires a native destructive confirmation. Files, folders and packages
can be selected together. Folder/package deletion includes all descendants;
selecting both a parent and its child does not process the child twice.

## Rename

Select exactly one item and choose **File → Rename…** or **Rename…** in the
table context menu. The native sheet starts with its current basename. Rename
stays inside the same parent; it does not move entries. Renaming a folder or
package updates its descendants together. Empty names, dot components, path
separators, controls and normalized/case-insensitive sibling conflicts are
rejected. A case-only rename of the same item is allowed.

Rename updates both local-header and central-directory filenames and rebuilds
their offsets. Compressed payloads are copied without recompression. CRCs,
timestamps, supported extra fields, attributes, entry comments and the archive
comment are preserved. Unsafe filename encodings or metadata fail closed rather
than risking an ambiguous or inconsistent ZIP. Affected legacy non-ASCII
filenames are not renamed. Converting an ASCII name to Unicode also requires
an ASCII entry comment when the original ZIP UTF-8 flag is unset; otherwise
the operation is refused to avoid reinterpreting that comment.

## Replace File

Select exactly one regular file and choose **File → Replace File…** or the
matching context-menu command. Choose one local regular disk file in the native
file panel. Its bytes replace the selected entry's contents; the archive path
and filename stay unchanged, even when the chosen disk file has a different
name. For one selected directory/package, use the separate Replace Folder or Update Folder commands below. For two or more regular files in one archive folder, use Update Selected Files below.

Replacement uses the same transaction and full verification as other ZIP edits.
Unrelated entries are not recompressed, and the archive comment is preserved.
The selected entry keeps its Store or Deflate method, raw filename, accepted
extra fields, timestamps, attributes and comment. The disk file supplies content,
not replacement permissions or timestamps. CRC and compressed/uncompressed sizes
are rebuilt. On macOS, the backend may emit Store for empty input despite a
Deflate request; replacement encodes the standard empty Deflate block to retain
the original method, then verifies the complete ZIP as usual. Compression flags and minimum-reader version are adjusted when
needed; a data descriptor, if present, is regenerated. Ambiguous filenames or
unsupported metadata fail closed. Encrypted, ZIP64 and multipart archives remain
read-only.
The refreshed browser keeps the replaced entry selected in its original parent.

## Transaction and preservation

Delete, Rename, Replace File, New Folder, Replace Folder, Update Folder, Update Selected Files and Add share `ArchiveZIPUpdater` and the same pinned-source,
private sibling replacement, full verification and coordinated atomic commit
architecture. The original ZIP is never edited in place. Stale snapshots and
changed source/replacement files are rejected before commit. Cancellation or
failure before commit leaves the original untouched and removes private staging;
cancellation after a successful commit cannot undo it.

For Delete, retained local records, compressed payloads, extra fields and comments are copied
without recompression or filename rewriting. Central-directory offsets and end
record counts/locations are updated to match the retained entries; the archive
comment is preserved. Existing encrypted/ZIP64/multipart/opaque layout restrictions
remain in effect. The deletion plan validates entry count against the pinned ZIP
and does not depend on re-encoding legacy filenames. If the existing integrity
backend cannot verify a legacy filename encoding, deletion fails without replacing
the original; raw preservation does not bypass verification.

The replacement is fully tested before publication. Progress and Cancel use the
existing browser controls. A successful edit refreshes the logical parent folder
and plays the completion sound once. Failure/cancellation does not play it.

As with additions, an uncoordinated external writer cannot be completely locked
out; avoid simultaneously editing the archive with another application. Abrupt
process/system termination can leave private staging. This is not secure erasure
or a crash-recovery mechanism.

## Real-Mac checks

1. Work on a disposable ZIP. Delete one file, then multiple files and a nested
   folder/package. Cancel the confirmation once and verify no edit occurs.
2. Search to select both a folder and a descendant; confirm one recursive deletion.
3. Delete the last item; verify the empty ZIP opens and passes Test Archive.
4. Delete a Unicode-named folder/package. Extract remaining entries and compare
   their contents, including nested and empty folders.
5. Cancel a large deletion before commit. Verify the original still opens/tests
   and no staging remains. Try an externally changed archive without reopening.
6. Add another item using Add Files and Finder drag-in, then drag it back out.
7. Open 7z/RAR/TAR or an unsupported ZIP: Delete must be disabled.

## Rename checks on a real Mac

1. In a disposable ZIP, rename a file at root, then a file inside a folder.
   Verify the parent stays open and the renamed item is selected.
2. Rename a nested folder, an empty folder and a package directory. Check their
   descendants using Show Package Contents, Test Archive and extraction.
3. Try spaces, Unicode/emoji and a case-only rename. Try a sibling collision,
   an empty name and path separators; none may overwrite or move an entry.
4. Cancel the sheet and a large rewrite; verify no edit or completion sound.
5. Add/Delete items and drag files into/out of the edited ZIP.
6. Open a read-only format or select multiple items: Rename must be disabled.

## Replace File checks on a real Mac

1. Open a disposable Store or Deflate ZIP. Select one file and choose
   **Replace File…**, then choose a differently named disk file. The archive
   filename must stay unchanged while its contents and size change.
2. Repeat with a smaller, larger and empty replacement and a Unicode path.
3. Run Test Archive and extract the ZIP; compare the replaced file's bytes with
   the chosen source and verify unrelated files are unchanged.
4. Cancel the chooser and a large rewrite before commit: no edit or sound.
5. Verify multiple selections, folders and read-only archive formats disable
   Replace File. Check Add/Delete/Rename and Finder drag-in/out still work.

## Replace Folder

For an eligible writable ZIP, select exactly one directory/package and choose
**Replace Folder…**. Choose a local directory, then explicitly confirm the
destructive replacement. The selected archive path stays fixed; its old descendants
are removed, and the chosen directory's contents become its new descendants.
The disk directory's basename is not added as a wrapper. An empty source leaves
an empty archive directory. This is not a merge or an update-by-date operation.

The existing transaction combines a retained-record mask with a private, verified
ZIP of the incoming subtree. All retained local records (including an explicit
selected directory record) are copied verbatim. Retained central records preserve
CRC, compression, extras, comments, attributes and timestamps; only local-record
offsets change where necessary. The archive comment is preserved. An implicit
selected directory gets an explicit record so empty replacement remains visible.
Incoming descendants are encoded through the existing ZIP creator using Deflate
(Store where the writer requires it for empty data/directories), with source
modification times and ordinary permission bits, including executable bits.
Old descendant metadata is replaced, not merged; filesystem ACLs/xattrs are not
imported. Source links and special files fail closed under the existing creator
policy. Unsupported/encrypted/ZIP64/multipart ZIPs and all other formats stay
read-only for this action.

Full output integrity verification, source revalidation and coordinated atomic
commit precede success feedback. Cancellation/failure before commit leaves the
original unchanged and cleans staging. After success the parent folder refreshes,
the replaced folder is selected, and completion feedback plays once.

On Mac, test a disposable folder/package with added, removed and changed files,
nested empty directories and Unicode names. Cancel the destructive sheet first;
then replace, run Test Archive and extract to compare with the chosen source.
Repeat with an empty source and verify unrelated entries remain unchanged.


## Update Folder

Select exactly one folder/package in an eligible writable ZIP and choose
**File → Update Folder…** or the table context-menu command. Choose one local
folder in the native picker and confirm the merge. Progress, cancellation and
errors use the existing edit flow. On success the parent refreshes, the selected
archive folder remains selected, and normal completion feedback plays once.

The selected archive path/name stays fixed; the disk folder's basename is never
added as a wrapper. Matching regular files receive new contents, new paths are
added, and archive-only descendants remain untouched. Existing directories are
retained, including their metadata. Empty source folders do not remove anything.
Unlike Replace Folder, this operation never deletes archive-only descendants.
It does not compare timestamps or mean “Replace Older.”

Unchanged local records, including compressed bytes and accepted extras, remain
raw; retained central records change only offsets where necessary. The archive
comment is preserved. Matching file records retain their original filename,
timestamps, attributes, comments and supported extra fields; CRC, sizes,
compression method/flags and required reader version are updated for the staged
payload. Payloads use the existing creator's Deflate/Store behavior. New entries
use the existing folder-creation metadata policy. No recompression is performed
for entries absent from the chosen source.

Case-only aliases, ambiguous Unicode paths and file/directory collisions fail
atomically instead of replacing a directory with a file or merging ambiguous
names. Existing encrypted, ZIP64, multipart and unusual ZIP restrictions apply.
Other archive formats and multiple selections do not enable this command.
The existing source-link/special-file restrictions remain unchanged.

Real-Mac checks: update a disposable ZIP folder with a matching file, a new file,
an empty nested directory and an archive-only file. Verify replaced bytes, added
paths and retained archive-only data with Test Archive and extraction. Repeat
with an empty source, cancel the picker/confirmation, and check that package
selection works without adding a disk-folder wrapper.

## Update Selected Files

Select two or more regular files in the current directory of an eligible writable
ZIP, then choose **File → Update Selected Files…** or the table context command.
Choose one local folder and confirm the displayed file count. Each selected basename
must have exactly one same-named regular file directly in that folder. Missing files,
links, directories, case aliases and ambiguous normalized names reject the entire
operation. Unselected source files are ignored; names and archive paths stay unchanged.
This does not compare timestamps. Folder/package selections and non-ZIP archives are
not eligible.

All sources are pinned with no-follow descriptors and revalidated through commit.
The existing ZIP transaction writes one private replacement, verifies its complete
contents, rechecks the original and sources, and atomically commits it. Cancel or
failure before commit leaves the original intact. Success refreshes the current
folder, reselects the updated files and plays one completion sound.

Each updated file retains its original Store/Deflate method, path, supported extras,
timestamps, attributes and entry comment. CRC and sizes are rebuilt in both headers;
compression-option flags follow the new payload. The archive comment is retained.
Unrelated local records, including compressed data, are copied byte-for-byte; central
offsets are adjusted. Regression tests compare raw record bytes and metadata and
independently read/test the resulting ZIP.

## Replace Older policy

`ZIPMetadataReader.modificationTime(for:in:dosTimeZone:)` exposes an optional
canonical time for a regular entry in an eligible writable ZIP. It reads the pinned
original headers, not an extracted file's timestamp, and rejects stale snapshots.
Update Selected Files offers **Replace All** (the default) and **Replace Older** in its confirmation sheet. Other edit commands do not consume this policy.

- Valid Info-ZIP `UT` (0x5455) modification seconds take priority, in UTC, with
  one-second precision. Either header may supply it; if both do, they must agree.
  Duplicate fields, malformed sizes/flags and conflicting times are ineligible.
  This phase accepts the unambiguous nonnegative signed-32-bit range (1970 through
  2038); it does not guess signed/pre-epoch versus unsigned post-2038 meanings.
- Without extended time, matching local/central DOS date/time can be decoded with
  two-second precision **only when the caller supplies a known origin time zone**.
  ZIP does not record that zone; the current computer's zone is not assumed.
  Invalid/zero dates, invalid clock fields, DST gaps and repeated hours are rejected.
- NTFS timestamp extras remain unsupported by this conservative policy, even when
  UT is also present. They are not silently ignored or reinterpreted. Other ZIP
  layouts/metadata outside the existing writable ZIP policy remain ineligible.

`ZIPReplaceOlderPolicy.decide` is pure: a canonical archive time represents
`[date, date + precision)`. Replace only when a matched regular local file's mtime
is at or beyond that interval's upper boundary. Equal/effectively equal and older
local times return Keep; missing/ambiguous archive time, missing/nonfinite local
time or a non-regular source return Ineligible. Replace Older treats any ineligible match as an error and aborts the entire operation.

`ZIPUpdateSource` retains a no-follow descriptor and operation-local mtime. Its
`revalidate()` checks path and descriptor identity, size, nanosecond mtime and ctime.
Replace Older retains these pins and revalidates all matched sources and the original archive before the existing coordinated atomic commit. A policy decision is not authorization to reuse stale source bytes.

References: [PKWARE ZIP APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
and [libarchive ZIP extra-field reader](https://github.com/libarchive/libarchive/blob/master/libarchive/archive_read_support_format_zip.c).


Replace Older validates every selected match before filtering, then updates all
qualifying files together through the existing Update Selected Files transaction.
Even one qualifying file is supported; the original selection still requires at
least two regular files. Skipped entries and unrelated records stay raw/unrecompressed.
Names, supported ZIP metadata, Store/Deflate methods and the archive comment remain
preserved, including the existing archive mtimes. No timestamps are rewritten by
this policy, and no unselected local files are added.

When nothing is newer, no replacement ZIP is created or committed. The selection
stays intact and the status bar says **No selected files were newer. Archive unchanged.**
No completion sound plays for this no-op. Successful replacements refresh the same
folder, retain the selection and play one completion sound.

The UI does not infer a DOS origin time zone or offer a zone override in this phase.
DOS-only entries therefore fail safely in Replace Older; use explicit Replace All.
The core accepts an explicit known zone for callers and tests, with two-second
boundary coverage. There is no folder, 7z, or extraction-conflict Replace Older mode.
