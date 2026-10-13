# Open a file inside an archive

Double-click one regular file, or select it and choose **File → Open** or
**Open** from the table context menu. Arkiv selectively extracts that entry into
an owned private temporary workspace and asks macOS to open the copy in its
default application. Its filename and extension stay intact. Arkiv does not
reveal it in Finder or play the extraction completion sound.

Folders retain normal navigation. Packages retain explicit **Show Package
Contents**. Directories, links and special entries cannot be opened as files.
The existing ZIP, TAR, 7z and supported RAR/RAR5 extraction backends are reused;
encrypted 7z uses the already-unlocked archive session without saving passwords.
Open accepts paths up to 64 components so every accepted hierarchy can be
cleaned within the temporary-workspace descriptor budget; deeper paths can
still use normal extraction. Large-file preparation uses the normal progress and cancellation controls.
Failed, cancelled or stale-source operations do not launch an application.

## Lifetime and editing

The temporary copy is kept after the external application launches. It belongs
to the archive browser session and is removed when that session ends or Arkiv
quits. Save a separate copy in the external application before closing the
archive window if you want to keep it. Editing this copy does **not** write
changes back into the archive. Quick Look and special nested-archive navigation
are not part of this feature.

The private workspace uses owner-only directory permissions. Active sessions
hold a filesystem lock. At startup and when creating a session, Arkiv removes
abandoned, unlocked session directories using descriptor-relative traversal
that does not follow symlinks. Same-archive refreshes retain existing copies.

Cleanup is limited to Arkiv-owned open-file workspaces. It never scans arbitrary
extraction destinations for matching names. Abandoned workspace cleanup is best
effort; deletion is not secure erasure.

## Real-Mac checks

1. Open a ZIP containing a text file and an unrelated file. Double-click the text
   file; its default application should show the correct name and bytes.
2. Try File → Open and contextual Open on a nested Unicode filename. Multiple
   selections, folders and links must not launch external applications.
3. Check normal folder navigation and Show Package Contents still work.
4. Repeat with TAR, 7z and a supported RAR fixture; unlock encrypted 7z first.
5. Cancel preparation of a large file; no external application should launch.
6. Keep an opened copy in its external app while opening another file from the
   same archive. Save anything you need before closing the Arkiv archive window.
7. Confirm extraction, drag-in/out and ZIP edits still work normally.
