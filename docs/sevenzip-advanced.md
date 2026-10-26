# 7z creation: dictionary, threads, solid blocks and memory

Create Archive / Add to Archive shows an Advanced disclosure for 7z only. The
memory estimate stays visible even when the controls are collapsed. ZIP is unchanged.
Finder's direct Compress to 7z still uses Normal, Auto dictionary and Auto threads.
No preferences are persisted, and existing archive-edit operations are unchanged.

## Capabilities and mapping

- Dictionary: Auto, 1, 2, 4, 8, 16, 32 or 64 MiB.
- Threads: Auto, then 1 through `min(4, max(2, activeProcessorCount))`.
  Auto keeps the previous two-thread setting. This is an encoder thread budget;
  small input may use fewer threads.
- Presets still select upstream `x=1/3/5/7/9`, with `0=LZMA2`, `s=false`.
  Solid defaults to Off; its properties are described below. Auto dictionary omits `0d`, retaining upstream preset/input-size derivation.
  Explicit dictionary sets numeric `0d=log2(bytes)` (20–26), as required by
  7-Zip's `SetLogSizeProp`; it does **not** pass a byte count to that numeric property.
  Threads sets `mt=1…4`. Each override changes only its corresponding setting.
- AES-256 and `he` filename/header encryption retain the existing password flow.

`SevenZipCreationOptions` exposes capabilities and validates options in ArkivCore.
The shared backend estimate and encoder independently reject invalid or unsafe
configurations. No method, preset or format is silently substituted.

## Approximate memory admission

The conservative compression-workspace estimate is:

```
64 MiB + threadBudget × (24 × dictionaryBytes + 32 MiB) + (solid ? 16 MiB : 0)
```

The supported ceiling is **2 GiB**. Estimates above it reject creation; settings
are never automatically lowered to fit. The formula budgets match-finder/window
storage, LZMA2 block buffers and overhead, with per-thread overestimation. It is an
approximation, not a guarantee of total process RSS or available system memory.
Existing decoder/entry/output limits and full verification still apply.

For explicit dictionaries the estimate always uses the requested size, even for
small inputs. Auto uses the preset nominal dictionary (256 KiB, 4 MiB, 32 MiB,
128 MiB, 512 MiB respectively), bounded by selected input bytes rounded upward to
a power of two, with a 4 KiB minimum. Unknown input size uses the nominal value.
The upstream update path derives its reduction bound from the largest input entry
for non-solid creation and the sum of new entries for solid creation
(`7zUpdate.cpp`, `inSizeForReduce`). Using total selected bytes is conservative for
both; a smaller explicit block does not reduce Arkiv’s memory estimate. Upstream's normal small-input reduction still applies to encoding.

Examples: 64 MiB with one thread estimates 1632 MiB and is allowed; 64 MiB with
Auto/two threads estimates 3200 MiB and is rejected. 16 MiB/four threads estimates
1728 MiB. Normal Auto with a full 32 MiB dictionary/two threads estimates 1664 MiB.
Thus not every individually listed dictionary/thread combination is supported.

The sheet scans source metadata asynchronously and disables Create while estimating
or when options exceed the ceiling. The backend repeats admission against the actual
private staged input before encoding, so changed source sizes cannot bypass it.

## Validation on a Mac

1. Choose Create Archive, select 7z and expand Advanced. Check Auto defaults and the
   approximate-memory label. Switch to ZIP: advanced controls disappear.
2. Create/extract a folder containing Unicode names and empty files/directories with
   1 MiB/two threads, then 64 MiB/one thread. Compare extracted contents.
3. Choose 64 MiB/Auto: Create must be disabled with a ceiling explanation. Choose
   one thread: it becomes available. Changing presets keeps explicit overrides.
4. Repeat with AES-256, filename encryption on and off; unlock, test and extract.
5. Check direct Finder Compress to 7z still uses Normal/Auto without a sheet.

There are no additional codecs, persistence or ZIP advanced controls in this phase.

## Solid creation (7-Zip 26.04)

The Advanced section offers Solid Off (default) or On. Solid block is disabled
while Off. On offers Auto, 16 MiB, 64 MiB, 256 MiB or 1024 MiB (1 GiB). No Full
option is exposed. These choices apply to **new archives only**, never edit calls.

`SevenZipSolidPolicy` makes Off-with-a-block unrepresentable in ArkivCore; unsupported
sizes fail validation. The C boundary also rejects invalid flags, Off with a block,
and unsupported sizes. The original advanced/compatibility entry points still use
Off, as do direct Finder Normal/Auto requests.

Exact upstream `ISetProperties` mappings:

| Arkiv choice | Property `s` value |
| --- | --- |
| Off | `VT_BOOL false` |
| On / Auto | `VT_BOOL true` |
| On / explicit block | `VT_BSTR "16m"`, `"64m"`, `"256m"`, or `"1024m"` |

Evidence: `COutHandler::SetSolidFromPROPVARIANT` and `SetSolidFromString` in
`Vendor/7zip/CPP/7zip/Archive/7z/7zHandlerOut.cpp`. Auto resets to upstream defaults;
LZMA2 derives its default block size from its dictionary/chunk policy, capped at
16 GiB. Arkiv does not translate Auto to a guessed numeric value. Explicit `m`
means a binary MiB shift, not decimal MB. Preset, dictionary, threads, AES-256 and
`he` settings are passed independently, exactly as before.

Blocks group whole files. `7zUpdate.cpp` stops grouping when adding another file
would exceed `NumSolidBytes`, but always accepts at least one file. Thus a single
file larger than the chosen block limit occupies a block alone: this is upstream
semantics, not multipart or a promise to split a file at that size. Small groups,
single-file inputs or empty archives can result in an actually non-solid archive.
Modification eligibility uses the actual archive layout, not the original UI choice.

Solid blocks stream through the encoder and do not require retaining the whole
block in memory. Admission adds a conservative 16 MiB bookkeeping reserve to the
existing estimate, retains the 2 GiB ceiling, and rechecks actual staged input in
the backend. The 100,000-entry / 20 GiB input limits and decoder limits remain.
The estimate is independent of the selected explicit block size: it deliberately
uses total input as the dictionary-reduction bound. Unsafe combinations fail; no
block, dictionary or thread setting is lowered to fit.

Actual solid archives are detected via the official `kpidSolid` property and remain
read-only for Add/Delete/Rename/Replace, including when encrypted. Browsing, Test
Archive and extraction continue through the existing backend. The policy inspection
result exposes `isSolid` but grants no new edit permission.

Validation covers all block choices with AES/header encryption on/off and exact
extracted bytes, plus two 9 MiB files: 16 MiB produces separate streams, while
64 MiB actually groups them as solid. Invalid options, cancellation, read-only edit
gating and native control defaults/dependencies are also tested.

Real-Mac check: create a multi-file 7z with On/Auto, then an explicit block; reopen,
Test Archive and extract/compare. Repeat with password and Encrypt filenames both
on/off. Confirm edit actions are disabled for an actual solid archive. Turn Solid
Off and confirm normal creation/editing behavior remains available. ZIP must not
show these controls, and direct Finder Compress to 7z remains non-solid.
