# Creation compression presets

Create Archive / Add to Archive offers presets for the selected format. ZIP remains
the default format. Both formats default to Normal, including direct Finder Compress
to ZIP / 7z. Changing format resets the selector to Normal. No persistent preference
is stored. 7z offers optional [dictionary/thread controls](sevenzip-advanced.md);
solid/block controls are available for new 7z creation only.

| Preset | ZIP | 7z |
| --- | --- | --- |
| Store | ZIP method 0, no compression, level 0 | Unavailable |
| Fastest | Deflate (method 8), zlib level 1 | LZMA2, upstream `x=1` |
| Fast | Deflate, zlib level 3 | LZMA2, `x=3` |
| Normal | Deflate, zlib level 6 | LZMA2, `x=5` |
| Maximum | Deflate, zlib level 9 | LZMA2, `x=7` |
| Ultra | Unavailable | LZMA2, `x=9` |

`CompressionPreset.backend(for:)` validates the format/preset pair in ArkivCore.
Conflicting legacy Store/Deflate arguments and presets fail before output creation.
The C bridge validates numeric levels too. ZIP uses libarchive's `zip:compression`
and `zip:compression-level` options; an unsupported option/error aborts creation.
7z sets the official bundled 7-Zip encoder's `0=LZMA2` and `x` level explicitly.
It defaults to non-solid behavior and retains AES-256/header encryption. Auto threads remains
two; explicit 7z creation overrides are described in the advanced-controls guide.
The compatibility bridge and all existing editing operations retain their prior
Normal encoding policy. There is no method or format substitution on an error.

Limits:

- Compression levels are effort presets, not promises of a particular size or ratio.
- Empty ZIP files/directories may be represented as Store by libarchive even when a
  Deflate preset is requested; there is no content to compress. Nonempty ZIP files
  use the requested Store or Deflate method.
- 7-Zip derives internal dictionary/match-finder settings from its upstream level
  and input size. Higher presets, especially Ultra, can need substantially more RAM
  and time. Arkiv enforces a conservative 2 GiB creation-memory estimate and does not
  raise existing decoder resource limits (256 MiB memory setting, existing entry/byte limits). An output
  exceeding verification/resource limits fails safely and is not published; Arkiv
  does not lower the requested preset as a fallback.
- The existing creation pipeline stages selected input as a private ZIP, then uses
  the in-process 7-Zip encoder for 7z. No installed CLI/Homebrew tools are required.
- ZIP AES and other codecs remain unavailable. Existing encrypted 7z passwords are
  never placed in URLs, command arguments or persistent settings.

Tests cover each preset, ZIP raw Store bytes and method identifiers, plain/encrypted
7z with filename encryption on/off, byte-accurate extraction, invalid combinations,
and native selector defaults/format changes/submission. All output still passes the
existing verification and no-overwrite publication pipeline.
