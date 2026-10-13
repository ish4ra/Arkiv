# Editing writable ZIPs

Open an eligible ZIP and select entries in the browser. **File → Delete…** is also available in the table context menu. Other archive formats
remain read-only for modification. Folder replacement and multi-file update
remain deferred.

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
name. Folder/package replacement and multi-file updates are unavailable.

Replacement uses the same transaction and full verification as other ZIP edits.
Unrelated entries are not recompressed, and the archive comment is preserved.
The selected entry keeps its Store or Deflate method, raw filename, accepted
extra fields, timestamps, attributes and comment. The disk file supplies content,
not replacement permissions or timestamps. CRC and compressed/uncompressed sizes
are rebuilt. Compression flags and minimum-reader version are adjusted when
needed; a data descriptor, if present, is regenerated. Ambiguous filenames or
unsupported metadata fail closed. Encrypted, ZIP64 and multipart archives remain
read-only.
The refreshed browser keeps the replaced entry selected in its original parent.

## Transaction and preservation

Delete, Rename, Replace File and Add share `ArchiveZIPUpdater` and the same pinned-source,
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
