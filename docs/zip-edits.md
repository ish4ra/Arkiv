# Delete inside writable ZIPs

Open an eligible ZIP and select entries in the browser. **File → Delete…** is also available in the table context menu. Other archive formats
remain read-only for modification; Rename and Replace/Update remain deferred.

Delete requires a native destructive confirmation. Files, folders and packages
can be selected together. Folder/package deletion includes all descendants;
selecting both a parent and its child does not process the child twice.

## Transaction and preservation

Delete and Add share `ArchiveZIPUpdater` and the same pinned-source,
private sibling replacement, full verification and coordinated atomic commit
architecture. The original ZIP is never edited in place. Stale snapshots and
changed source/replacement files are rejected before commit. Cancellation or
failure before commit leaves the original untouched and removes private staging;
cancellation after a successful commit cannot undo it.

Retained local records, compressed payloads, extra fields and comments are copied
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
