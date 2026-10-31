# Archive Info

File → Archive Info (Command-I) presents a compact native sheet of metadata captured
when the archive was opened. Values and the original path are selectable/copyable.
Opening the sheet performs no extraction, password lookup, or checksum scan.

All inspected formats expose original filename/path, physical size, regular-file
count and explicit directory-entry count. Implicit browser folders are not counted
as stored directory entries. Unpacked size is the sum of regular-file sizes when
all non-directory entries have known regular-file sizes. Links/special entries or
overflow make that total unknown. Empty archives have zero totals and no ratio.
The ratio is physical size / unpacked size, including container overhead, not a
codec efficiency measurement; it can exceed 100%.

- ZIP/TAR (and other libarchive-readable formats): format is the backend's detected
  format name, not a filename extension. Compression methods, encryption and solid
  fields currently remain unknown. No missing fields are inferred from editability.
- 7z: original format is 7z even though the unlocked session uses a private spool.
  Header-only official handler inspection supplies actual method strings, solid
  state, data encryption and header encryption. Passwords are borrowed only during
  the existing open operation, never retained in metadata. Failed metadata inspection
  leaves these fields unknown. Existing integrity/extraction limits are unchanged.
- Multipart/volume state remains unknown for every format in this phase.

Unknown rows are omitted. Totals describe the full opened archive, not the current
folder/search. This is snapshot information; reopening refreshes it after external
changes. No per-entry columns, editable comments or checksum calculation are added.

On a Mac: open ZIP, TAR and a multi-file solid 7z, press Command-I, copy the path,
and check sizes/counts. Repeat with 7z encryption and Encrypt filenames on/off.
Verify empty ZIP has zero counts and no ratio, and ZIP/TAR do not show invented
solid/encryption rows. Closing the sheet must leave browser selection unchanged.
