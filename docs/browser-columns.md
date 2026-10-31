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
