# WinZip AES ZIP — Phase 1

ZIP remains the default. Create Archive (including Finder Add to Archive) offers
**Protect with AES-256 password**, confirmation and Show Password for ZIP.
Filenames remain visible; filename encryption is a 7z-only option. Finder's
existing direct ZIP command stays unencrypted; Compress with Password retains
its existing 7z default, with ZIP selectable explicitly.

## Verified scope and backend

Single-volume ordinary ZIP32, Store/Deflate, WinZip AES **AE-1 and AE-2**, method
99 with matching local/central `0x9901` records. Reading supports fixture-tested
AES-128/192/256; creation uses AES-256 only. ZIP presets remain unchanged.
Mixed encrypted/plain entries and independently encrypted empty files are tested.
The system writer leaves empty files and directories unencrypted (there are no
content bytes to protect); their metadata reports that honestly. An archive
containing only empty items therefore does not require a password to open.

The in-process system **libarchive** reader/writer uses platform cryptographic
implementations (CommonCrypto on macOS). No new runtime crypto binary, shell
command, Homebrew dependency, RAR code or homemade AES primitive is introduced.
The inspected reference is libarchive v3.7.4's `archive_read_support_format_zip.c`,
`archive_write_set_format_zip.c`, `archive_cryptor.c`, `archive_hmac.c` and
`archive_random.c`, under their BSD notices. Apple's system version is validated
by both native CI runners; registration alone is not treated as compatibility.
7-Zip's pinned WzAes implementation was also reviewed but was not newly integrated.
The WinZip AES reference is https://www.winzip.com/en/support/aes-encryption/ .

## Authentication and admission

WinZip's specified PBKDF2-HMAC-SHA1 (1,000 iterations) derives the AES key,
authentication key and two-byte verifier from the password and random per-entry
salt. AES-CTR encrypts compressed bytes; the stored authentication value is the
first 10 bytes of HMAC-SHA1 over the complete ciphertext. AES-256 uses a 16-byte
salt. The short verifier is only a password-screening value: it never authorizes
publication. The scheme's fixed KDF is relatively inexpensive for offline guessing;
use a strong password. It does not encrypt/authenticate ZIP filenames or all header
metadata, and this is not a general digital-signature scheme.

The inspected libarchive reference compares authentication tags with `memcmp`;
Arkiv does not claim constant-time password/tag verification across system backend
versions. The complete tag must still match before an unlock is accepted.

Arkiv validates matching names, methods, flags, AES vendor/version/strength,
framing lengths, CRC/size descriptors, contiguous nonoverlapping local records,
central bounds and supported extras before invoking the codec. Duplicate names,
unsafe paths, unsupported links/special types, unfamiliar extras and ambiguous
legacy non-ASCII names fail closed. AE-2 requires a zero CRC field and relies on
HMAC authentication; AE-1 also verifies its stored CRC. AE-2 CRC columns stay blank.

Encrypted directories are rejected, including trailing-slash, DOS-directory and
Unix-mode representations: libarchive can otherwise skip their payload/HMAC
initialization. Encrypted nonregular entries are also rejected after decoding the
header. Ordinary unencrypted directories and authenticated empty regular files
remain supported. The generic listing/extraction path refuses encrypted entries,
including unselected entries, so unsupported ZIP64/SFX encryption cannot bypass
the dedicated unlock path. `__MACOSX/._*` entries are authenticated as ordinary
files, not silently hidden or merged into resource metadata.

An unlock fully authenticates and decodes every entry into a private 0700-owned,
0600-file TAR spool before creating a usable snapshot. The existing bounded,
no-follow extractor/Open/Quick Look/drag workflows then materialize selections.
No failed or cancelled authentication exposes that spool to a browser or publishes
extracted output. Failure removes it; successful snapshots retain it only for their
existing session/child-window ownership lifetime. Passwords are not retained by the
snapshot, preferences, URLs or logs. Native strings and system-library allocations
cannot be promised secure erasure; crashes can leave private plaintext staging,
as with existing 7z unlock. This is not protection from another process running
with the same user privileges.

Budgets remain 100,000 entries and 20 GiB actual decoded output; ZIP32 admission
also limits physical ZIP size to below 4 GiB and count below 65,535. Header-name
storage is capped at 64 MiB. The spool, including TAR padding, must fit the output
budget. Cancellation is checked between entries/64-KiB reads. Source identity,
size, mtime and ctime are checked around backend work. Creation additionally
rechecks all source records, reads the completed encrypted ZIP, compares plaintext
with original source bytes, and publishes by the existing exclusive hard-link path.

Test Archive performs full authentication/decompression without a spool. A
verifier mismatch permits retry (wrong password **or damaged verifier**); a bad
HMAC is **Authentication Failed**. CRC, structural and unsupported errors retain
their distinct states where the backend provides reliable evidence. No tag failure
is downgraded to a warning/success, and no password attempt falls back to ZipCrypto.

## Intentionally unavailable

Encrypted ZIP **editing** (including drag-in), ZIP64 AES, multipart, ZIPX,
non-Store/Deflate methods, strong-PKWARE encryption, ZipCrypto creation/reading,
encrypted directories/links/special entries, filename encryption and unsupported extra fields.
Ordinary ZIP editing and existing formats keep their established policies.

## Independent evidence and real-Mac checks

`tests/fixtures/zip-aes/provenance.json` records hashes and origins: WinZip AES
fixtures from the BSD libarchive v3.7.4 corpus, plus pyzipper 0.3.6/PyCryptodome
3.23.0 generated AE-1/AE-2, all three strengths, Store/Deflate, Unicode, empty and
mixed entries. The generation recipe is recorded in `tests/test_zip_aes.py`.
Pinned/hash-verified Python tools are test-only and are not shipped in Arkiv.
They independently read Arkiv-created encrypted ZIPs. Mutations cover tags,
verifiers/headers, CRCs, truncated streams, duplicate/overlapping/unsafe entries,
authenticated invalid Deflate, cancellation and limits. Fixture notices are in
`licenses/zip-aes-fixtures.txt`.

1. Create ZIP Store and Deflate with AES-256 from Unicode/nested/empty items.
   Open in an independent AES ZIP reader and compare bytes; try an existing output
   name and confirm the earlier archive is preserved.
2. Open the independent fixtures in Arkiv. Cancel the password prompt, retry an
   incorrect password, then unlock correctly. Inspect encrypted/CRC columns and
   Archive Info. Filenames remain visible in other ZIP tools.
3. Extract one/multiple/all entries; Open and Space Quick Look a regular file;
   drag to Finder. Editing and drag-in must stay disabled.
4. Test good and tag-damaged archives. Authentication failures must publish no
   output. Cancel a larger creation/unlock and check private staging cleanup.
5. Repeat on Intel and Apple Silicon; verify ordinary ZIP editing, 7z encryption,
   RAR reading, Finder operations, icons and Sparkle remain unchanged.
