# Compressed TAR reading

TAR wrapped in a single gzip, bzip2 or XZ stream is read-only. Names such as
`.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz2`, `.tar.xz`/`.txz` are conventions: magic,
validated compression and the actual inner TAR determine acceptance. A valid
archive with a misleading suffix is still recognized; compressed non-TAR data
is rejected. No standalone GZIP/BZIP2/XZ-file support or TAR creation is claimed.

## Backend and limits

The existing libarchive TAR parser/extractor is retained. Compression is decoded
in-process using macOS system zlib, libbz2 and liblzma. Merely enabling libarchive
filters was insufficient: upstream gzip leaves trailer CRC/ISIZE unchecked and
upstream XZ uses an unlimited decoder-memory budget. Arkiv instead validates
checksums through the dedicated decoders and limits XZ decoder memory to 64 MiB.
XZ streams with no integrity check or unsupported checks are rejected.

Inspection sequentially decompresses into the existing owned private spool
(0700 directory, 0600 file), bounded to 20 GiB including TAR metadata and padding.
TAR entry/output limits and all existing extraction safeguards still apply.
Spool writes use exclusive creation, cancellation is checked each bounded decode
iteration, and failures remove partial output. Original source stamps are checked
before/after inspection and before extraction. Snapshots retain the spool and
release it when no longer needed. Existing open-file/nested/drag lifetime rules
continue to apply; no password is stored.
On macOS the private spool uses the physical `/private/var` or `/private/tmp`
location for system temporary aliases: Foundation's symlink-resolution API alone
can retain the alias. This preserves the metadata reader's strict no-symlink
ancestor checks; stored TAR permissions still come only from archive headers.

This is **not random access**. Initial open reads the entire compressed stream and
uses temporary disk space; later operations scan its TAR representation. TAR must
have a complete 512-byte alignment and two final zero blocks. Concatenated streams,
trailing bytes (including XZ stream padding), overly large XZ dictionaries and
nonstandard TAR termination are conservatively rejected in this phase.

Browse/search, full/selective extraction, internal-file Open/Quick Look, nested
archives and drag-out reuse existing workflows. Finder context-action eligibility
and document associations are unchanged; use File → Open Archive or Finder’s
explicit Open With → Arkiv. No new icons are introduced.

## Integrity and metadata

Test Archive decodes/verifies the original compressed stream and reads TAR payloads.
It reports Warning on success because TAR has no per-file content CRC. Compression
checksums cover the stream, not independent TAR entries. CRC columns remain blank;
TAR sizes, timestamps and stored permissions come from the inner TAR. Corrupt,
unsupported/resource-limited streams fail closed; unsupported decoder checks/memory or expansion budgets report Unsupported Method;
malformed input reports Corrupt with the failure detail, never a false OK.

## Verification and real-Mac checks

Independent Python stdlib compressors generate the committed fixtures using
`tests/make_compressed_tar_fixtures.py`. Core tests exercise all aliases and
misleading extensions, Unicode, empty containers, invalid inner TAR, metadata,
full/selective extraction, links, Open-file materialization, nested ZIPs and lazy
drag delivery. C tests cover damaged/truncated/trailing streams, expansion and
XZ memory limits, cancellation and cleanup. macOS CI tests the system libraries.

On a real Mac, open each variant; browse/search; test; extract selected/all; press
Space and open a regular entry; open nested.zip; drag entries to Finder; cancel a
large open. Confirm the archive is read-only, CRC remains blank, and temporary
space is released after closing archive windows. Visual/UI acceptance is manual.
