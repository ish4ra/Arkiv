# Standalone GZIP, BZIP2 and XZ

Arkiv reads and creates one-file `.gz`, `.bz2` and `.xz` streams in process.
`database.sql.gz` represents one regular file, `database.sql`, rather than a
folder hierarchy. ZIP remains the default creation format. These streams cannot
be edited in place and offer no encryption, solid, dictionary or thread controls.
Standalone LZMA, ZSTD and other codecs are not implemented by this milestone.

## Recognition and integrity

The codec comes from magic bytes and complete decoder validation, never the
extension. A decoded TAR is routed to the existing TAR browser/extractor even
under a misleading suffix. Recognizable TAR with damaged headers or invalid
termination fails closed; it does not become an opaque single-file entry.
Otherwise decoded bytes are represented directly as one regular entry. No TAR
headers, permissions, timestamps or hierarchy are synthesized. Compressing an
existing TAR file therefore produces compressed TAR, which opens as TAR.

All three codecs share the bounded loops used for compressed TAR. Every input
must finish exactly one complete stream with no unused/trailing bytes. Multiple
gzip members, concatenated bzip2/XZ streams, XZ stream padding, truncated input
and checksum damage are rejected. XZ without a supported integrity check is
rejected. Existing compressed TAR policies remain in force, including its
512-byte alignment and two termination blocks.

Decoded output is capped at 20 GiB; XZ decoder memory is capped at 64 MiB. Codec
I/O uses 64 KiB buffers and checks cancellation on each iteration. Initial open
validates/decompresses the entire stream into a private owned spool (0700 folder,
0600 file), so opening requires temporary disk space and is not random access.
Snapshots retain that data; failures and cancelled opens remove partial output.
Closing the last owner removes the spool. Open/Quick Look and drag promises use
the existing session/owned-copy lifecycle. Source identities are checked while
decoding and sources are revalidated before extraction. Test Archive checks the
original stream again and reports OK only after complete checksum validation.
Compressed TAR retains its Warning about absent per-file TAR content checksums.

## Names and metadata

Gzip embedded FNAME/mtime are deliberately not used: FNAME has ambiguous encoding
and is generally unauthenticated by the payload checksum. Embedded absolute or
`../` names never become paths. Strip one `.gz`, `.bz2` or `.xz` suffix from the
source basename, case-insensitively; for misleading/unrecognized suffixes append
`.decompressed`. Empty/dot/dot-dot names, separators, colons, controls and names
over 255 UTF-8 bytes are rejected. Rename an unsafe source and reopen it.

The browser reports one file with the measured decoded length and actual codec.
Archive Info shows original path/physical size, decoded size, counts and ratio
when nonempty. Per-entry dates, POSIX permissions, stored CRC and packed payload
size remain unavailable: temporary-file attributes are not archive evidence, and
framing overhead is not claimed as per-file packed data. Extraction creates a
safe regular file with private permissions, not an invented stored mode.

## Creation and native integration

Use File → Create Archive or Finder → Arkiv → Add to Archive, select **exactly one
regular file**, and choose GZIP/BZIP2/XZ. The default name retains the full source
basename/extension (`server.log` → `server.log.bz2`). Folders and multiple files
cannot use these formats; the sheet disables Create and directs the user to TAR.
Core independently enforces the same restriction. ZIP/7z/TAR choices and direct
Finder ZIP/7z commands remain unchanged. No extra Finder context actions are added.

Settings are fixed: gzip level 6, bzip2 level 9, XZ preset 6 (LZMA2/8 MiB dictionary,
CRC64). XZ creation admits at most 128 MiB encoder and 64 MiB decoder memory.
Private staging holds compressed output plus a decoded verification copy. The
original regular file is pinned with no-follow descriptor access, the result is
fully decoded and byte-compared, and source identity/size/mtime/ctime is checked
again before exclusive same-filesystem publication. Numbered names resolve
collisions; existing files are never replaced. Cancellation/error cleans staging.
Streams and source input retain the 20 GiB limit; compressed framing overhead is
bounded by 1% + 1 MiB above that limit. No CLI, Homebrew or external tools are used.

File → Open Archive, Extract Selected/All, default-app Open, Space Quick Look,
drag-out, Test Archive and Archive Info reuse existing workflows. The app registers
GZIP/BZIP2/XZ as Viewer/Alternate for Finder Open With; it does not change chosen
default handlers. Additional document artwork is deferred; existing icons are
unchanged. Finder Sync and Services extraction eligibility is unchanged.

## Evidence and real-Mac checks

Python standard-library fixtures and independent gzip/bz2/lzma decoding validate
round trips, empty files, Unicode names, corruption, truncation, trailing and
concatenated streams, XZ check/memory restrictions, cancellation, no-overwrite,
source changes and cleanup. Native tests exercise Open/Space, shared setup through
Finder routing, full-basename naming and single-input restrictions. SDK probes
continue to link encoder/decoder APIs for arm64 and x86_64 against explicit Apple
SDK stubs; packaged dependency checks reject Homebrew paths.

1. Open each independently compressed file through File → Open and Finder Open
   With. Confirm one correctly named row and honest blank metadata fields.
2. Extract Selected/All; compare bytes. Open and Space-preview it, drag it to
   Finder, and Test Archive. No Open/preview/drag completion sound is expected.
3. Create each format from one Unicode-named file, including an empty file. Repeat
   to verify numbered names. Select folders/multiple files and verify the TAR hint.
4. Try truncated/corrupt/trailing data and cancel a large operation; verify no
   partial visible output. Reopen compressed TAR and recheck existing workflows.
