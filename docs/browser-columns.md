# Browser metadata columns

Name, Size and Kind are joined by Packed Size, Ratio, Modified, Method and Encrypted.
All are resizable/sortable. Unknown values are blank. Sizes/ratios sort numerically,
dates chronologically; optional nil values sort before known values ascending and
after them descending. The new columns keep folders first and use paths as tie
breakers. Existing selection, search, navigation and original-column sorting remain.
Synthetic parent directories do not inherit child metadata.

Evidence is cached during inspection without payload extraction for columns or
new password prompts. ZIP/TAR timestamps come from libarchive's entry headers.
Ordinary validated ZIP32 Store/Deflate layouts additionally supply packed size,
method and false encryption from the existing ZIP envelope validator. Unsupported,
encrypted, ZIP64, legacy-name or ambiguous layouts leave these fields unknown.
TAR has no per-entry packed/method/encryption values in this phase.

7z uses official per-item PackSize, MTime, Method and Encrypted properties from the
original archive with the already available inspection password. Solid packed sizes
are deliberately omitted: a shared block cannot be assigned to a single file.
Missing mtimes stay blank (Arkiv's current 7z creator does not write item mtimes).
Directories, links and special entries receive only evidenced timestamps; duplicate
paths receive no metadata. Original content/security validation is unchanged.
Ratio means packed/unpacked bytes, not percentage saved; it is undefined for zero
or unknown unpacked sizes and for non-regular entries. No checksums are computed.

Real-Mac check: open ZIP Store/Deflate, TAR and plain/encrypted/solid 7z; inspect all
five columns, resize them, sort both directions, search, navigate, and verify the
same items remain selected. Blank unknown fields and solid packed sizes are expected.

CRC and Attributes columns use stored evidence only. CRC32 is eight uppercase hex
 digits; no hash calculation is performed. Validated ordinary ZIP32 records supply
CRC32 and external attributes; POSIX mode is used only for Unix-origin records.
7z exposes CRC only for an actual UI4 item CRC property (including solid/encrypted
items), and POSIX/Windows attributes only when provided by its handler. TAR exposes
stored mode, never its header checksum as content CRC. Directories/links/special
entries retain evidenced attributes but omit CRC. Synthetic folders remain blank.
POSIX modes render rwxr-xr-x including special s/S/t/T bits; otherwise raw stored
attribute bits render as explicitly hexadecimal values. Sorting uses numeric evidence.
