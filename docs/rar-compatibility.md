# RAR4 / RAR5 compatibility — Phase 1

RAR is read-only. Arkiv uses Apple's in-process **system libarchive** RAR/RAR5
readers; it neither bundles nor invokes UnRAR, `rar`, Homebrew, or a 7z command.
The actual libarchive version is available through `LibArchiveEngine.version`.
No RAR encoder or restricted RAR source is included. Existing RAR document
artwork and Viewer/Alternate registrations are unchanged. Direct Finder actions
remain restricted to their existing ZIP/7z/TAR policy; open RAR through Arkiv.

## Backend and licensing evidence

The inspected reference readers are upstream libarchive v3.7.4
`archive_read_support_format_rar.c` and `archive_read_support_format_rar5.c`.
They implement stored and compressed decoding and have BSD 2-clause notices
(Tim Kientzle/Andres Mejia; Grzegorz Antoniak respectively). Apple's system copy
can differ; native CI tests the installed implementation on Apple Silicon and
Intel rather than assuming parity with Linux. Neither RAR encryption nor broad
RAR compatibility follows from merely registering these readers.

7-Zip's optional RAR code and UnRAR carry additional restrictions concerning RAR
encoding. They are not integrated here and are not described as unrestricted
LGPL/public-domain components. RAR creation remains a non-goal.

## Evidence matrix

Fixtures come from the independent libarchive v3.7.4 test corpus, not an Arkiv
encoder. `tests/fixtures/rar/provenance.json` records source paths, tag and SHA256;
`licenses/rar-compatibility-fixtures.txt` preserves the associated test notices.
The prior `rar5-stored.rar` fixture and its license also remain intact.

| Variant | Status / evidence |
| --- | --- |
| RAR4 Store (`m0`) | Verified: text, hierarchy, empty directory, relative symlink |
| RAR4 Normal (`m3`), Best (`m5`) | Verified: LZSS fixture payloads, repeated nested files, 20,131,111-byte multi-block payload, complete CRC checks |
| RAR4 Unicode | Verified: Japanese paths, empty file/folder, text and symlink |
| RAR5 Store (`m0`) | Verified: original upstream `helloworld.txt` fixture |
| RAR5 Best compressed (`m5`) | Verified: independently generated polynomial bytes, four-file archive and selective extraction |
| RAR5 Unicode / links | Verified: Unicode regular file, internal hardlink and relative symlink; shared safe link extraction |
| Other ordinary methods `m1`–`m5` | Limited: admitted by header policy, decoder-dependent; not all levels/filter combinations have independent fixture coverage |
| Solid | Unsupported in this phase, including RAR5 although upstream has solid code; rejected before output |
| Encrypted data or headers | Unsupported; RAR4 independent encrypted fixtures reject, RAR5 crypt header/extra records reject. No password prompt or wrong-password claim |
| Multipart / split entries | Unsupported; explicit volume/split indicators yield Missing Volume in Test Archive, with no discovery or guessed filenames |
| SFX, legacy pre-RAR4, recovery/service/unknown headers, newer RAR5 codec versions | Unsupported by the narrow admission policy |

The corpus covers compressed files up to 20,131,111 bytes, not production-scale
multi-gigabyte compatibility. Large-file eligibility is bounded by existing
limits; larger real-world samples and additional filter coverage remain follow-up
work. No blanket claim about every WinRAR/RAR variant is made.

## Admission, integrity and metadata

A bounded header-only scan precedes libarchive decoding. It validates header
CRCs, block/data bounds and an exact end-of-archive marker, rejects unsupported
policy flags, and enforces entry/declared output budgets. Older archives without
an end marker are intentionally rejected: libarchive can otherwise accept a
truncated archive as EOF. At most 200,000 header blocks, 64 MiB cumulative header
bytes and 2 MiB per RAR5 header are inspected; the cancellation token is checked
between headers. RAR5 window declarations are limited to 16 MiB. RAR4's decoder
memory is controlled by libarchive's own LZSS/PPMd implementation, not a new
Arkiv allocator ceiling. The existing 20 GiB expanded-data and 100,000 entry
limits and 64 KiB copy buffers remain in force.

**Test Archive reads every payload, not just headers.** Arkiv independently
compares every regular-file payload CRC32 to the validated stored value, since
libarchive's stored RAR4 path can omit that comparison. Extraction performs the
same streaming comparison for selected regular files before publishing staging.
An absent CRC causes a Warning after a complete decode, never a fabricated
checksum success. Decoder CRC errors produce CRC Error; malformed/truncated
structures produce Corrupt; unavailable compression/encryption produces
Unsupported Method. There is no password attempt for unsupported encryption.

Browser metadata uses validated header evidence: packed size, method number,
stored CRC32, Unix mode when the recorded host is Unix, otherwise recorded file
attributes. Modification times come from libarchive's archive-entry API. No hash
is calculated for columns. Directories do not invent packed sizes or file CRCs;
synthetic folders invent nothing. The confirmed single-volume/non-solid/plain
policy populates Archive Info; unknown metadata remains absent.

Files, folders and links use the existing destination-relative, no-follow
extractor. Absolute/parent-relative symlink targets remain link objects; later
writes cannot traverse them. Hardlinks resolve only to safe selected regular
files. No-overwrite, cancellation, source revalidation, private staging and
failure cleanup remain shared with other formats. Open File, Quick Look,
nested-archive ownership and lazy drag-out use those same selective workflows.
RAR modification is never enabled.

## Real-Mac acceptance

On Intel and Apple Silicon:

1. Open the stored/normal/best RAR4 and compressed/multiple RAR5 fixtures. Inspect
   names, sizes, method, stored CRC and attributes; confirm editing is disabled.
2. Test each archive; extract one file, two selected files and all contents.
   Compare the extracted data with the documented upstream fixture expectations.
3. Open/Quick Look a regular file and drag files/folders to Finder. Check Unicode,
   empty directories and symlink/hardlink behavior. No extraction sound for previews.
4. Try damaged payload/header and truncated copies; no successful publication of
   partial output. Cancel a decode. Repeat extraction beside existing files and
   confirm existing data is untouched.
5. Test encrypted, solid and first-volume fixtures: clear unsupported/multipart
   results, no automatic sibling-volume access, and no password persistence.

System decoder updates may change supported methods; expand claims only after
independent fixtures and both native CI jobs pass.

## Multipart conventions (not enabled)

Common names include `name.part1.rar`/`part2.rar` and legacy `name.rar`/`name.r00`/`name.r01`. Names alone are not volume evidence. Existing RAR4/RAR5 envelope volume/split flags continue to produce Missing Volume/unsupported admission before decoder registration. Individual RAR volumes contain structured headers and split-file state; they cannot use split-7z byte concatenation. The new descriptor validation/discovery concepts may be reused later, but no RAR sibling discovery, encryption, solid or multipart extraction is enabled here. See [multipart policy](multipart.md).
