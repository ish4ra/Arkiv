# Add Finder items by dragging into a ZIP

Open a writable ZIP and drag local Finder files/folders into its table. Drop on
empty space to add to the currently browsed archive folder (root when at root),
or directly on a folder/package row to add inside it. A drop between rows adds
to the current folder, not to the adjacent row. Search does not change the current
folder; a folder-row target uses that row's complete archive path.

The native table accepts file URLs and advertises Copy only when the existing
ArchiveZIPUpdater eligibility check allows additions. 7z, RAR, TAR, encrypted,
ZIP64 and unsupported ZIP layouts remain read-only. Busy archives and open sheets
reject drops. Source links/special files remain unsupported by the existing
creation engine; failures do not publish a partial rewrite.

The core updater validates the destination as an existing archive directory and
checks names within that directory, including case/Unicode-normalized conflicts.
An internal prefix on the existing ZIP writer produces additions under that
folder; there is no second archive writer. Original compressed entries and metadata
are preserved by the existing temporary replacement → verification → atomic
commit transaction. Existing entry names are never replaced or merged. Rename a
conflicting source before retrying. Failure/cancellation leaves the original ZIP
unchanged and removes staging.

The existing progress/cancel controls apply. Successful additions refresh the
browser at the target folder and play the completion sound once. Drops do not
explicitly activate Arkiv or Finder. Add Files/Add Folder pickers retain their
existing root-addition behavior. Native file-promise drag-out is unchanged.

## Real-Mac checks

- Drop a file at the root, then multiple files and nested/empty Unicode folders.
- Browse an archive folder and drop on empty space; verify additions are inside it.
- Drop directly onto a visible folder row; verify the target and refreshed path.
- Retry a conflicting name and cancel a large addition; verify original contents
  and ZIP bytes remain unchanged after the failed/cancelled transaction.
- Hover/drop over 7z, TAR, RAR or an unsupported ZIP: no Copy/add operation.
- Drag an archive entry back out to Finder, including an application package.
