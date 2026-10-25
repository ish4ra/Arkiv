# 7z creation: dictionary, threads and memory

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
  Auto dictionary omits `0d`, retaining upstream preset/input-size derivation.
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
64 MiB + threadBudget × (24 × dictionaryBytes + 32 MiB)
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
The upstream non-solid update path derives its reduction bound from the largest
input entry (`7zUpdate.cpp`, `inSizeForReduce`); using total selected bytes is
conservative. Upstream's normal small-input reduction still applies to encoding.

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

There are no solid/block, codec, persistence or ZIP advanced controls in this phase.
