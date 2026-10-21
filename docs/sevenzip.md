# In-process 7z and AES-256

Arkiv builds the official 7-Zip 26.04 7z handler, LZMA/LZMA2 and AES code into the separate `libArkivSeven.dylib`. The application embeds that library; users need no command-line tools or package manager. The source pin, compilation list, licenses, and small resource/privacy patches are in [Vendor/7zip](../Vendor/7zip/README.md). AppKit remains independent of C++.

Creation first reads sources with the existing no-follow, bounded C traversal into a private ZIP. Each file is checked for changes during reading. The 7-Zip update callbacks read a private anonymous spool and emit LZMA2 7z, optionally AES-256 with independently selectable filename/header encryption. The output is decoded and CRC-checked before an atomic no-overwrite hard-link publication. Collision suffixes preserve existing files. Cancellation is checked during source reads, spool transfers, codec callbacks, verification, and publication. Codec progress reports bytes; counters may restart between phases. Sources changed after their validated staging read do not change the staged snapshot.

Inspection detects the 7z magic regardless of the filename extension. Official decoding callbacks validate paths, types, counts and sizes before emitting a private TAR in a new 0700 session directory (0600 file). No archive-chosen filesystem path is opened by the 7-Zip bridge. Existing libarchive listing/extraction then applies the same strict path validation, no-follow descriptor traversal, link-aware extraction, bounds, private extraction staging and publication rules. POSIX symbolic-link targets and safe permission bits are preserved in the spool. Special entries remain marked unsupported for extraction warnings; sockets use a private generic special-entry marker because TAR cannot encode sockets. No socket or FIFO is created from that marker. Unsupported Windows reparse encodings remain rejected. Selective extraction uses this backing archive and does not prompt again.

Unlocking currently decodes the entire archive to the private disk spool. It therefore requires time and free disk space proportional to uncompressed size, even for browsing one file. Every retained snapshot owns the session; dropping the last snapshot removes its plaintext spool. A crash or forced termination can leave that private temporary directory behind. There is no secure-erasure guarantee and no password/key persistence or Keychain feature. Swift/String and allocator memory cannot promise complete erasure. The upstream global password/key cache is disabled; codec caches and handler/password callbacks exist only during the synchronous operation. Passwords never enter arguments, URLs, filenames, preferences, or logs.

Limits: 100,000 entries; 20 GiB uncompressed payload; paths at most 4096 bytes and 256 components; 64 MiB packed/decoded header buffers; metadata counts at most 1,000,000; LZMA/LZMA2 dictionaries at most 128 MiB; decoder memory hint 256 MiB; KDF exponent at most 20 (normal encoder uses 19). KDF and individual codec calls are not interruptible instruction-by-instruction; cancellation is cooperative between callbacks. These are conservative format restrictions, not a strict whole-process memory or CPU sandbox. Highly unusual archives can be rejected. Source size/time/inode is revalidated before and after inspection and before/after extraction; changed source archives require reopening.

Wrong passwords and encrypted corruption can be indistinguishable and share a typed error. Missing passwords have a separate typed result. The official 7-Zip ZIP handler implements WinZip AES (`ZipUpdate.cpp` / `WzAes`), but it is outside the bundled 7z-only module and has not passed an Arkiv cross-tool interoperability suite. ZIP password requests are rejected, never silently converted to ZipCrypto. Existing plain ZIP/TAR behavior is unchanged. Add Files and Add Folder support the root of writable, plain, non-solid single 7z archives. Encrypted Add/Rename/Replace remain disabled. Eligible encrypted Delete is described below; multipart archives, solid archives, links, ambiguous Unicode/case paths, trailing/prefixed data and unsupported methods or metadata remain read-only. Delete and same-folder Rename use the same eligibility and transaction. Delete includes all descendants of selected folders/packages; Rename changes exactly one basename and its descendant paths, rejecting conflicts and invalid names while allowing case-only changes. Replace File supports exactly one regular archive file and one local regular source, retaining the archive path and supported original metadata. The changed entry is encoded with LZMA2 (including originally Copy entries); unrelated packed streams are copied unchanged. Finder drag-in remains ZIP-only. Multipart creation and arbitrary codecs are not added.

7z Add pins the original source and parent through the existing ZIP transaction infrastructure. Only new input files are staged through the validated private ZIP creator. The same official 7z handler opens the original and calls `UpdateItems`, marking every old item as retained (`newData = false`, `newProperties = false`): upstream copies its packed streams without recompression. New entries use LZMA2, with solid mode and encryption disabled. Complete staged paths and root conflicts are checked before append. A private same-filesystem replacement is fully decoded and CRC-checked under the existing limits before metadata copying, fsync, and coordinated atomic replacement. Delete and Rename map snapshot paths to actual handler indices before updating; retained data stays compressed. Rename forwards every original property except the changed path, preserving supported timestamps and attributes. Entries carrying StartPos metadata remain read-only because the upstream property-update path cannot preserve it. Cancellation, failed verification and stale-source checks leave the original untouched. The small upstream `7zIn.cpp` patch marks ignored opaque archive properties as an unsupported-feature warning, so the append gate rejects them without changing browsing behavior.

## Build and replacement

Run `python3 scripts/build-sevenzip.py --output .build/sevenzip`, then link Swift builds with `-Xlinker -L$PWD/.build/sevenzip`. For development tests, set `DYLD_LIBRARY_PATH=$PWD/.build/sevenzip` on macOS or `LD_LIBRARY_PATH` on Linux. Release packaging builds both architectures, embeds the universal library in `Contents/Frameworks`, and uses `@rpath/libArkivSeven.dylib`. The bundle verifier checks the actual loaded library location. No developer absolute rpath is required.

For LGPL replacement/relinking, rebuild the checked-in bridge and source subset with your changes, preserve the C ABI in `ArkivSeven.h`, and replace the bundled library with compatible architecture slices. A modified signed app must be re-signed (an ad-hoc signature is sufficient for local development, subject to macOS execution policy); Arkiv development builds are not notarized. Full source and build instructions accompany this repository; distributors must provide corresponding source and notices with their binaries. Do not impose restrictions on reverse engineering for debugging modifications to this LGPL library. No project-wide license is inferred from the library's license.

## Verification

`tests/test_sevenzip.py` covers a separately constructed Copy-format 7z, hostile names and link/device attributes, real plain/AES fixtures, header encryption on/off, missing/wrong password and successful retry, corruption and cancellation. `SevenZipTests.swift` exercises creation → inspection → full/selective extraction → byte comparison, Unicode/empty files/directories, collisions, magic detection, private-session cleanup, changed archives and ZIP-password rejection. Runtime-generated passwords remain in memory. Fixture password `fixture password` is public test data. Tests run through `scripts/test-engine.sh` and `swift test`; macOS bundle/Universal verification is performed by CI.

## Encrypted Delete and policy inspection

`SevenZipPolicyInspector` inspects the original 7z and reports data encryption,
header encryption, mixed encrypted/plain data, supported layout, full-data
verification, and narrow encrypted-Delete eligibility. Header encryption
is detected from the upstream header-open password callback, independently of
per-item `kpidEncrypted`. A missing or wrong password returns a typed failure,
not a usable policy result. Header-encrypted archives require a password before
the complete policy can be known.

`prepareEncryptedEdit` is a read-only preparation API with an operation-local
password-request closure. It does not enable a menu or write anything. The caller
supplies its normal password sheet when a future edit flow uses this API. An
already-unlocked snapshot still needs a fresh credential: its plaintext TAR is
not evidence of password availability. The result contains no credential or
reusable authorization. Validation opens the original with the existing no-follow
path walker, pins the descriptor, tests every stream, and checks descriptor/path
identity and timestamps afterward; Swift also checks the snapshot before and
after, including after the password callback. No new plaintext spool is created.

Future eligibility requires the existing ordinary non-solid, single-file,
no-prefix/trailer, safe metadata/path rules; Copy/LZMA2 data with AES KDF exponent
19 where encrypted; CRC metadata for encrypted entries; no mixed encrypted/plain
nonempty data; and successful verification of all streams with one password.
Different passwords that prevent full verification cannot qualify. Empty files
and directories do not count as unencrypted payload streams. Header-only encryption
can qualify, with only Delete enabled after operation-local password validation. Unsupported layouts
remain read-only even when their payload can be decoded. Encrypted header metadata must carry a CRC and use AES KDF exponent 19. Other KDF settings are decoded for browsing but flagged read-only. Headers are rebuilt with the upstream encoder; retained encrypted file-data streams, including their coder properties, are copied unchanged.

Password strings are borrowed only for the synchronous operation, never persisted
or logged. Existing Swift allocator/secure-erasure limitations still apply.


Delete caches only a non-secret eligibility result on the opened snapshot. The
native destructive confirmation is followed by one password request per edit;
cancelling either does nothing. The borrowed credential is validated against the
pinned original, used for header rewriting and full output verification, and
reused only to refresh this operation's browser snapshot. It is never retained
for the next edit. Wrong passwords fail without writing or automatic retry.

Encrypted Delete uses the existing ZIP/7z transaction staging, source-change
checks, coordinated atomic commit, cleanup and single success sound. It preserves
header encryption on/off, including an encrypted empty header after deleting the
last item (a narrow documented upstream patch). If headers were unencrypted and
all encrypted data is deleted, an empty archive naturally has no encrypted data
streams; no password is then needed to read that empty archive. No other encrypted
editing capability is enabled. Tests compare the complete retained ciphertext
range, exercise header on/off and final-item deletion, and cover password errors,
cancellation, external source changes, recursive packages and unrelated ZIP/7z edits.
