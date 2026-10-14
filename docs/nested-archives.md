# Open an archive inside an archive

Double-click one regular entry whose contents are a supported archive to open it
in a **new Arkiv window**. **File → Open as Archive** and contextual **Open as
Archive** explicitly request archive browsing. Detection uses archive contents,
not the filename extension. The current ZIP, TAR, 7z and supported RAR/RAR5
backends are reused.

Arkiv materializes only that entry through `ArchiveOpenSession`, the same
selective extraction and private workspace used by Open and Quick Look. It
inspects the result before opening a child browser. A malformed archive does not
produce a broken child window. **Open** remains available to send a regular file
to its default macOS application. Normal files, folders, packages and Space
Quick Look retain their existing behavior.

An encrypted outer 7z uses its already-unlocked session. An encrypted inner
archive uses Arkiv's existing password prompt and retry behavior. Passwords are
not saved or logged. Cancellation and failed preparation do not open a child.

## Lifetime

The child holds a lease on the materialized entry inside the existing
`ArchiveOpenSession` workspace. The lease is also retained by its archive
snapshots, so outstanding extraction and file-promise operations keep their
source alive after the browser window closes.
Closing the parent does not invalidate an already-open child. Closing the child
releases its window ownership; the last snapshot/operation releases the copy. The existing private
workspace permissions, live-session locks and abandoned-session cleanup apply.
No extraction completion sound or Finder reveal is performed.

There is no automatic recursive opening, current-window nested navigation or
write-back into the outer archive. Changes made to a writable nested ZIP affect
only the temporary copy; extract/save a separate copy to keep it.

## Real-Mac checks

1. Put a ZIP containing a text file inside another ZIP. Double-click the inner
   ZIP; confirm a new Arkiv window browses it and the outer window stays open.
2. Close the outer window, then browse, extract, Open and Quick Look from the
   child. Its data should remain available.
3. Repeat with a nested 7z, TAR and supported RAR, including Unicode filenames
   and an archive with no filename extension.
4. Unlock an encrypted outer 7z, then open a nested archive. For an encrypted
   inner 7z, try a wrong password followed by the correct password.
5. Try Open as Archive on malformed/non-archive data; no child should appear.
   File → Open must remain available for normal external-app opening.
6. Cancel preparation of a large nested archive. Confirm no child appears.
7. Check ordinary-file double-click, Space Quick Look, folder navigation and
   Show Package Contents. Close all windows when finished.
