# Open or preview a file inside an archive

Double-click a regular non-archive file, or select any regular file and choose
**File → Open** or **Open** from the table context menu. Supported nested archives
open in a new Arkiv window on double-click; explicit Open always uses the default
macOS application. Arkiv selectively extracts the selected entry into
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
changes back into the archive. [Nested archives](nested-archives.md) open in a separate Arkiv window; changes are not written back into the outer archive.

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

## Quick Look

Select exactly one regular file and press **Space**, or choose **Quick Look**
from the File or context menu. Arkiv prepares only that file through the same
owned temporary session used by Open and displays the native macOS Quick Look
panel. Press Space again or Escape to close the preview. Folders, packages,
links, special entries and multiple selections are not previewed.

The original filename and extension remain intact. ZIP, TAR, 7z and currently
supported RAR entries use the existing selective extractor; encrypted 7z reuses
the unlocked session. No external application is launched, Finder is not
revealed, and the extraction sound is not played. Preparation can be cancelled
with the existing progress controls. Failure, cancellation or a changed archive
prevents preview and cleans partial output.

The preview copy remains available throughout the preview. Closing the archive
session or quitting Arkiv closes its preview before cleaning the workspace.
The existing owned-session and abandoned-workspace cleanup rules apply.

### Real-Mac preview checks

1. Select a text file or image in a ZIP and press Space. Check its filename and
   contents; press Space again, then repeat and close with Escape.
2. Try File → Quick Look and contextual Quick Look on a nested Unicode filename.
3. Check a folder still navigates on double-click and a package still requires
   Show Package Contents. Space must not extract either or a multiple selection.
4. Repeat using TAR, 7z, supported RAR and an unlocked encrypted 7z.
5. Cancel a large preview preparation and confirm no preview appears.
6. With a preview open, close its archive window or switch archives; the preview
   should close cleanly. Try two archive windows to check preview ownership.
7. Double-click a regular file to confirm default-application Open still works.
