# Zstandard streams and compressed TAR

Arkiv reads and creates `.zst`, `.tar.zst` and `.tzst` in process. ZIP remains the
creation default. This is not ZSTD-in-ZIP, a new 7z method, or standalone LZMA.

## Backend and reproducibility

The bundled backend is official **Zstandard 1.5.7**, the stable release selected
from [upstream releases](https://github.com/facebook/zstd/releases/tag/v1.5.7).
Arkiv selects its **BSD 3-clause** license, reproduced in
`licenses/zstd-LICENSE.txt` and in the packaged application. Upstream offers BSD
or GPLv2; Arkiv does not select GPL. The library includes its upstream xxHash
implementation with its retained BSD notice.

`Sources/CZstd` contains the unmodified output of the official
[amalgamation tool](https://github.com/facebook/zstd/tree/v1.5.7/build/single_file_libs)
with its internal header fully inlined, plus public headers for Arkiv callers, not the CLI or an unrelated compression suite. SwiftPM
compiles this C target into each app slice. It is statically linked; no external
`libzstd`, Homebrew installation, subprocess, or download is needed at runtime.
The explicit Clang module map keeps the macro-gated static API headers textual;
SwiftPM and direct C builds therefore see the same pinned allocator/frame APIs.
`scripts/vendor-zstd.py` reproduces the source from the pinned archive with SHA256
`37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3`.
`Sources/CZstd/checksums.json` records generated source/header/license hashes.

Apple's public Compression framework on Arkiv's macOS 13 deployment baseline
provides LZ4/LZFSE/zlib/LZMA, not a documented ZSTD implementation. A private or
runner-local `libzstd` is not a deployment contract. Bundling portable upstream C
provides the same decoder/encoder on Intel and Apple Silicon. Existing SDK-pinned
zlib/bzip2/XZ linkage is unchanged. Native CI compiles and probes the static ZSTD
library for both architectures and rejects dynamic libzstd dependencies.

## Accepted frame policy and integrity

- Exactly one standard ZSTD frame, consumed completely, including its footer.
- Known or unknown decompressed size, including empty content.
- Optional content checksum present: decoder validates it. Creation always writes
  it. This is the format's low 32 bits of XXH64, **not CRC32**, and is not shown in
  the per-entry CRC column.
- Optional checksum absent: full framing/decode validation still occurs, but
  standalone Test Archive reports **Warning**, explicitly saying content integrity
  cannot be confirmed. TAR also retains its per-file no-checksum warning.
- Corrupt/truncated frames and checksum mismatches fail with no retained output.
- Concatenation, skippable frames, trailing bytes/padding and dictionary-dependent
  frames are not supported. Nonzero dictionary IDs are rejected before decoding;
  frames requiring an unadvertised external dictionary cannot decode without it.
- Legacy pre-standard frame formats are not supported.

The policy is narrower than upstream's general streaming API (which can accept
multiple/skippable frames). Arkiv stops at the first frame boundary and requires
EOF, preserving the existing single-stream policy of the other codecs.

## Resource limits and creation

The shared stream loop uses 64 KiB input and output buffers, checks cancellation
on each iteration and caps total decoded output at **20 GiB**. Known frame sizes
are checked before decoding; unknown sizes are checked as output is produced.
The maximum decoder window is **64 MiB** (`ZSTD_d_windowLogMax=26`), with an
**80 MiB hard codec heap budget**, including context and stream buffers. The
fixed encoder has a **128 MiB hard codec heap budget**. Custom allocators enforce
these budgets rather than relying only on an estimate. These are codec allocation
limits, not claims about the entire app's process memory.

Creation maps explicitly to level **3** (upstream's default), windowLog **23**
(8 MiB), nbWorkers **0** (synchronous single-thread codec), checksumFlag **1**.
There is no dictionary, encryption, threading or advanced-level UI. Stream sizes
may be unknown in the frame header; full verification does not depend on a size
hint. All buffers and codec allocations are bounded even for large input files.

Standalone creation accepts exactly one regular file. TAR variants reuse the
existing PAX writer, source manifest validation and TAR byte/metadata verifier;
folders, nested/empty directories, Unicode and multiple inputs work as before.
Private staging is decoded and compared byte-for-byte before no-overwrite,
collision-safe publication. Cancellation, source changes and failures remove
staging. Originals and existing destination files remain untouched.

## Browser, names and lifetime

Detection uses magic and actual decoded content. Valid TAR opens as a hierarchy
regardless of suffix; recognizable malformed TAR fails rather than becoming an
opaque file. Other content is one regular entry. Strip one `.zst` suffix from the
source basename (`database.sql.zst` → `database.sql`); misleading suffixes gain
`.decompressed`. Existing safe component validation rejects controls, separators,
colons, dot names and excessive UTF-8 length. No embedded pathname is trusted.

No timestamps, permissions, per-file packed sizes or stored CRC are invented for
standalone streams. The private owned spool and selective extraction backend are
shared with GZIP/BZIP2/XZ. Initial inspection fully decodes to disk; it is not
random access and needs space for up to the output limit. Open File, Quick Look,
nested archives and lazy file-promise drag reuse their existing lifetime/security
paths. Streams and compressed TAR remain read-only for editing.

The shared Create Archive/Finder Add to Archive picker exposes all three formats.
Standalone keeps the source's full basename and forbids folders/multiple inputs.
Viewer/Alternate registrations cover `zst`/`tzst`; they do not change the default
handler. Existing original app and document artwork remains unchanged; new ZSTD
artwork is deferred. No new direct Finder compression action is added.

## Evidence and real-Mac acceptance

Independent libzstd-produced fixtures cover size/checksum variants and TAR content.
Engine tests cover corruption, boundaries, limits, cancellation, source changes,
cleanup, no-overwrite and TAR metadata; Swift tests exercise inspection, extraction,
Open/Quick Look materialization, drag and nested ZIPs inside compressed TAR. Native
UI tests cover the shared picker restrictions and actual Quick Look/Open routing.

On Intel and Apple Silicon, install the development build and:

1. Create `.zst` from a Unicode-named file; reopen, Test, extract and compare bytes.
   Try an empty file. Verify two inputs/a folder are rejected for standalone.
2. Create `.tar.zst` and `.tzst` from a nested folder with empty directories; browse,
   extract, preview a text file, open a nested archive and drag a folder to Finder.
3. Open a checksum-less fixture: Test must show Warning, not checksum-verified OK.
   Truncated, oversized-window and concatenated fixtures must fail safely.
4. Cancel during creation/open; verify no published partial file or staging remains.
   Repeat creation beside an existing output and verify collision-safe naming.
5. Confirm ZIP default, 7z encryption, existing stream formats, Finder workflows,
   branding and Sparkle update behavior still work normally.
