# How Keka registers archive types (research for Finder icons)

Purpose: understand how another widely used macOS archiver gets its document
icons into Finder, so Arkiv's behaviour can be judged fairly. No Keka
artwork, code or wording was copied. Only its public metadata was read.

## Sources

| Source | How it was read |
| --- | --- |
| Keka **1.6.8** official release `Keka-1.6.8.dmg` from `github.com/aonez/Keka` | The **Document type research** workflow (`scripts/research-keka-document-types.sh`) downloaded it on a GitHub macOS runner, mounted it read-only and printed `Keka.app/Contents/Info.plist`. SHA-256 `25a4daf0…2125`, equal to GitHub's published asset digest. |
| Keka wiki, commit `9071c846` | The same job cloned the public wiki and searched it for default-app and extension notes. |

## Confirmed observations

| Topic | Keka 1.6.8 | Arkiv |
| --- | --- | --- |
| XZ | Document type "XZ Archive": `org.tukaani.xz-archive`, `public.xz-archive`, extension `xz`, icon `xz.icns` | `org.tukaani.xz-archive` → `Arkiv-XZ.icns` |
| TXZ | "XZ Tarball Archive": `org.tukaani.tar-xz-archive` (+2 others), extension `txz`, icon `txz.icns` | `org.tukaani.tar-xz-archive` → `Arkiv-TXZ.icns` |
| `.tar.xz` | **No type or icon for the compound suffix.** No `tar.xz` extension appears anywhere in its plist | Same: Finder types `.tar.xz` as XZ. Arkiv uses TAR.XZ artwork only in its own windows |
| `.tar.gz`, `.tar.bz2`, `.tar.zst` | No compound entries. `tgz`, `tbz2`, `tzst` are single-suffix types with their own icons | Same approach for `tgz`, `tbz2`, `txz` |
| TZST | Its own imported type `com.facebook.zstandard-tar-archive` → `tzst.icns` | Shares `org.zstandard.zstd` with `.zst` (ZSTD icon), so no user association moves |
| Zstandard | Imports `com.facebook.zstandard-archive` for `zst` | Imports `org.zstandard.zstd` for `zst` and `tzst` |
| Imported type conformance | `public.data` and `public.archive` | Was `public.archive` only, which left `.rar`, `.zst` and `.tzst` unresolved by filename lookup. Now `public.data` and `public.archive` ([investigation](document-icons.md#tarxz-and-imported-type-investigation)) |
| Handler rank | **`Default`** for almost every archive type | **`Alternate`** for every type |
| Becoming the default app | Never automatic. The wiki says a separate **KekaExternalHelper** sets Keka as default for its formats (sandboxing limits); otherwise use Get Info → Open with → Change All | Never automatic; Get Info → Open with → Change All |
| Generic volumes | Claims `.001`–`.099` ("Generic Archive Volume", rank Alternate, `vol.icns`) and `.r00`–`.r99` | Never claims numeric suffixes; split 7z is recognised by the engine's `.7z.NNN` rule inside Arkiv only |
| Quick Look | No Quick Look extension in the app bundle (only a Finder Sync extension) | None yet (milestone 4) |
| Icon files | 58 ICNS files, one per format family | 11 ICNS document icons, plus 6 in-app-only PNG sets |

## What this means

* Keka's Finder icons depend on the same rule as Arkiv's: Finder draws a
  document icon from the **default** application's `CFBundleDocumentTypes`.
  Keka asks users to make it the default through its helper or Get Info.
* Neither app can give `.tar.xz` a different Finder icon from `.xz`. macOS
  types a file by its last extension; a compound extension in a type
  declaration is never matched (confirmed on macOS 15 by
  `scripts/diagnose-document-icon-coverage.swift`: the `tar.xz` tag resolves
  to no type).

## Assumptions, not verified

* `LSHandlerRank Default` may let Keka win the default role on Macs where no
  other app claims a type more strongly. On a stock Mac, Archive Utility is the
  default for ZIP, TAR, GZIP, BZIP2 and XZ (observed in CI). Whether Keka's rank
  displaces Archive Utility was not tested; Arkiv keeps `Alternate` and never
  takes defaults.
* If Keka and Arkiv are both installed, `.zst` has two imported declarations
  (`com.facebook.zstandard-archive` and `org.zstandard.zstd`). Which one
  LaunchServices picks for a file was not tested. It could decide whether
  Arkiv's ZSTD icon can apply.
