# Split 7z reading — Phase 1

Arkiv reads conventional byte-split 7z streams named `name.7z.001`, `.002`, …,
using the bundled official 7-Zip 26.04 handler after private reconstruction.
Open the first or any existing later part with File → Open Archive, Open Recent,
or Finder → Open With → Arkiv. All parts must be in the same accessible directory.
The generic `.001` extension is deliberately not registered as exclusively an
archive type. Existing direct Finder extraction menus are unchanged.

## Discovery and safety

Only the selected file's containing directory is enumerated, with a 100,000-name
scan bound. Exact three-digit consecutive names beginning at 001 are required;
this phase admits at most **128 parts**, at least two parts, and **4 GiB total
physical input**. All nonfinal parts have equal length; the final part is no
larger. Numeric aliases such as `.01`, `.0001`, `.000`, case aliases and numbers
beyond 128 are rejected. Other unrelated files are ignored. There is no recursive
search or network volume fetching.

Directories are opened component-by-component with `O_NOFOLLOW`; sibling files
are opened relative to the pinned directory descriptor. Parts must be readable
regular files with link count one. Symlinks, hardlinked parts, duplicate identities,
path replacement and changes to device/inode, size, mode, link count, mtime or
ctime are rejected. The complete sequence and directory identity are rechecked
around copying, decoding, extraction and Open/Quick Look/drag delivery. Originals
are never overwritten. Multipart editing is disabled, even for decrypted input.

The current development app is not sandboxed; the Finder extension is sandboxed
and does not discover volumes. Discovery uses only access already available to
the main app. Unreadable/TCC-restricted directories fail with an access diagnostic;
no permission bypass or background broad search exists. A future sandboxed
build will need explicit containing-directory authorization/bookmarks. It must
not infer sibling access from an individual file security scope.

## Reconstruction and resources

This is **disk-backed reconstruction**, not native segmented random access.
A 64 KiB copy buffer writes a mode-0600 reconstructed `.7z` in the existing owned
mode-0700 temporary-session directory. Valid 7z magic and start-header CRC are
required; the start header's next-header offset/size must exactly match the
assembled input length. The existing backend then opens, decodes and verifies
all streams under its unchanged dictionary, header, entry and **20 GiB decoded
payload** limits before any browser snapshot or output becomes usable.

Temporary space can include 4 GiB reconstructed input plus 20 GiB decoded data
and TAR header/padding overhead (budget roughly 25 GiB at the upper limits),
plus any user-requested extracted copies. Limits are per open archive, not a global
process quota. Disk-full failures clean owned staging normally. Cancellation is
cooperative between copies/codec callbacks. Successful snapshots retain their
spools and descriptor set; last-owner release removes them. Open copies, previews,
child windows and file promises retain the ownership they need. Crash cleanup and
secure-erasure limitations are the same as existing 7z unlock spools; a forced
termination can leave private temporary data. No password is retained in snapshots.

## Diagnostics and operations

A missing `.001` or an observed interior numbering gap reports the exact expected
filename. A shorter reconstructed stream reports **incomplete/corrupt input**;
Arkiv does not invent a final missing part number. Bad header CRC, payload damage,
unsupported numbering, unreadable files and changed sources produce distinct
messages. Test Archive maps proven gaps to Missing Volume and incomplete/corrupt
input to Corrupt. No incomplete set produces a successful test.

Browse/search, Archive Info, extraction, Test, Open File, Quick Look and native
drag-out share existing implementations. Info reports total physical volume size
and multipart=true, with other metadata from the actual handler. An ordinary
nested archive inside a split set can open in a child window normally. A split
part embedded alone in another archive cannot discover its siblings inside that
archive and fails safely; automatic nested-set materialization is not supported.

Independent fixtures verify Copy and LZMA2, Unicode, empty files/directories,
AES-256 data encryption with header encryption on/off, password retry, CRC checks
and extraction byte comparison. 7z AES is not an authenticated-encryption scheme:
this retains upstream password/decryption/CRC verification and must not be confused
with WinZip AES's HMAC authentication. Passwords are operation-local and never
logged or saved. See `tests/fixtures/split-sevenzip/provenance.json` for official
upstream 7-Zip 26.01 fixture commands and hashes. The fixture producer is test-only;
users need no installed CLI, Homebrew or subprocess.

RAR multipart, split ZIP, noncanonical numbering, non-7z multipart creation and generic
split/combine remain unavailable. RAR volumes are structured containers and must
not be concatenated through this byte-stream reader.

## Real-Mac acceptance

1. Put each complete fixture set in Downloads. Open `.001`, then a later part;
   browse Unicode paths and empty folders, inspect total size and multipart state.
2. Test and extract all/selected files; compare bytes with the fixture recipe.
   Open/Space-preview a regular file and drag a file/folder to Finder.
3. Repeat with encrypted sets: cancel, retry a wrong password, then use the public
   test password `fixture password`. Editing must remain disabled.
4. Remove first/intermediate/final parts separately. Verify exact gaps versus
   incomplete-input wording, and no successful Test or published partial output.
5. Replace a part while an archive is open; subsequent extraction/Open/drag must
   fail safely. Cancel reconstruction and check cleanup. Test on Intel and arm64.

## Split creation — Phase 2 development branch

Create Archive (also Finder → Add to Archive) → 7z → Advanced → Split into volumes.
No splitting remains the default; ZIP remains the default creation format. Direct
Finder ZIP/7z commands remain unsplit. Custom bytes appears only for Custom size. The
sheet's collision note changes for split sets: an existing numbered volume stops
creation; split sets are never auto-renamed (unsplit archives still use “Name (2)”). Presets use **decimal** 100 MB, 650 MB,
700 MB, 1 GB, 2 GB, 4 GB; Custom size is an exact integer number of bytes.
A part must be at least 32 bytes; the encoded archive must be larger than that
part size and no larger than 4 GiB, with 2–128 parts. Encoded size is unknown
until compression completes, so final admission may reject a large preset or a
small custom size. 4 GB is 4,000,000,000 bytes, below 4 GiB, but usable only for
encoded archives above 4 GB. No silent single-part output or setting reduction.

The existing official bundled encoder creates an ordinary LZMA2 7z. Arkiv fully
decodes it, verifies members by name/type/size and source bytes, streams exact
encoded bytes into private parts, reconstructs them through Phase 1 and compares
the byte stream exactly. Presets, dictionary/thread controls, solid options and
AES-256/header encryption are retained. Creation does not expose Copy; Phase 1
Copy reading remains supported. Existing 7z creation does not preserve original
POSIX modes/timestamps; this phase does not invent those metadata guarantees.
Passwords remain operation-local. 7z CRC checks are not cryptographic authentication.

Source manifests are revalidated before each publication and after it. Destination
and staging directories are pinned with no-follow descriptors. Numeric set-name
collisions fail rather than replace or auto-rename a set. Exclusive hardlink
publication on the same filesystem cannot overwrite an existing file. After all
links, private links are removed and the final set is reconstructed, byte-compared
and revalidated again to catch concurrent replacement, truncation or extra parts.
Rollback removes only matching owned identities, never a substituted foreign file.
Stage cleanup uses pinned descriptors, including after destination moves.

This is **not crash-atomic publication**. Other processes may briefly observe an
incomplete set; a crash can leave numbered parts which Phase 1 rejects as incomplete.
No overwrite is allowed when retrying. Ordinary failure/cancellation rolls back
owned published parts and staging. Concurrent same-user tampering after the final
validation boundary cannot be prevented by filesystem APIs.

Splitting uses 64 KiB buffers. Once encoded size is known, available filesystem
space is checked for two extra encoded copies (parts and reconstruction), but this
is advisory and cannot reserve space. Initial creation also needs its existing
intermediate ZIP, verified decoded TAR and final 7z; peak temporary usage can
therefore substantially exceed input size. Disk/write errors fail safely. The
4 GiB admission applies to the encoded result; source decoding remains limited to
20 GiB. Part publication does not duplicate payload disk blocks (hardlinks).

Tests compare private encoded bytes with the exact concatenated parts, exercise
ciphertext/header on/off and solid creation, simulate write exhaustion, and race
collisions/cancellation/source/destination changes. Independent upstream 7-Zip
26.01 tests generated plain and encrypted sets (test-only downloaded tool; archive
SHA-256 8ea0fc8a135e7b848e80a4116fe22dff56c8c4518dde1f43cce67f4e340b437a).

Real-Mac creation checks: choose a small custom byte size for a small fixture;
create ordinary/encrypted/header-encrypted/solid sets; open first and later parts;
Test, extract and byte-compare; Open/Space-preview/drag a generated member; cancel
and retry; collide with an existing part and confirm it stays intact. Verify the
7z-only controls and no-splitting default through both File and Finder setup.
Phase 1 publication remains a prerequisite to merging/releasing this branch.
