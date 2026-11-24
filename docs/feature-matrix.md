# Milestone status

| Capability | State |
| --- | --- |
| Native archive browser | Implemented: AppKit table, resize/sort columns, persistent header-menu column visibility/widths (Name mandatory), multi-selection, search, folder/back/forward/up navigation, multiple windows |
| Selective/all extraction | Implemented: new destination folder, bounded streaming, cancellation, progress and cleanup |
| Extraction safety | Automated hostile-path/link/overwrite/CRC/limit regression suite |
| macOS application validation | Native compilation, tests, arm64 app/icon packaging and signature verification passed macOS CI; interactive validation outstanding |
| Standalone GZIP / BZIP2 / XZ | Read, single-row browse, extract, Test, Open/Quick Look/drag and single-file creation; strict checksums/limits; [details](standalone-compression.md) |
| Create TAR / compressed TAR | PAX TAR; gzip/bzip2/XZ with long/short suffixes in Create Archive / Finder Add to Archive; bounded encoders, byte verification, no encryption or editing; [details](creation.md#tar-and-compressed-tar-creation) |
| Create ZIP | Store/Deflate, native creation setup, direct Finder multi-selection compression; [details](creation.md) |
| WinZip AES ZIP Phase 1 | AE-1/AE-2 AES-128/192/256 read/extract/Test/Open/Quick Look; AES-256 Store/Deflate creation; encrypted editing disabled; [policy](zip-aes.md) |
| Create/read 7z / AES-256 / filename encryption | LZMA2, content/header encryption, native password prompt/retry; [backend and limits](sevenzip.md) |
| Compression presets | ZIP Store/Fastest/Fast/Normal/Maximum; 7z Fastest/Fast/Normal/Maximum/Ultra; [mappings and limits](compression-presets.md) |
| 7z advanced creation | Auto or 1–64 MiB dictionary; Auto or up to four threads; optional solid creation with Auto/16–1024 MiB blocks; conservative 2 GiB memory admission; [combinations and limits](sevenzip-advanced.md) |
| Add to existing ZIP | Add Files/Add Folder at root; verified atomic rewrite of supported ZIP32; [limits](zip-additions.md) |
| ZIP Delete / Rename / Replace File / New Folder | Verified transactional edits for eligible ZIP32 archives; [details](zip-edits.md) |
| ZIP Replace Folder / Update Folder | One selected folder/package in an eligible ZIP: Replace removes old descendants; Update merges matching/new paths and keeps archive-only descendants; native picker, confirmation and atomic verification; [details](zip-edits.md) |
| ZIP Update Selected Files | Two or more regular files in one ZIP folder; strict same-basename local mapping; Replace All or conservative Replace Older; one verified atomic transaction; [details](zip-edits.md#update-selected-files) |
| Arbitrary multi-selection mapping / folder update-by-date | Deferred; no enabled UI claims |
| Multipart creation | 7z only: verified private splitting, 2–128 parts, 4 GiB packed limit; native creation Advanced controls |
| RAR multipart / comments | Deferred compatibility work; RAR multipart reading is roadmap milestone 5, split ZIP milestone 6 ([roadmap](roadmap.md)) |
| RAR4 / RAR5 Phase 1 | Evidence-gated plain single-volume read/extract/Test/Open/Quick Look/drag; [compatibility](rar-compatibility.md); no creation/editing |
| Integrity test command | ZIP/7z/RAR full-data/CRC checks; TAR structure/readability with explicit checksum warning; native progress/cancellation/password retry |
| Checksums / split-combine / benchmark / CLI | Deferred |
| Finder integration | Sandboxed Finder Sync **Arkiv** submenu (user enablement required; home folder only): Open, Extract Here, Extract to folder, Extract To and Test Archive for one ZIP/7z/uncompressed TAR, plus Add to Archive and ZIP/7z/password compression for normal items; [details](finder-sync.md). AppKit Services fallback for one ZIP/uncompressed TAR; [details](finder-integration.md). Extension registration and the direct menu were confirmed on a real M1 Mac; broader interactive acceptance pending |
| Drag out | Native lazy file promises; selected files/folders to Finder; [details](drag-out.md) |
| Drag in | Native Finder file URLs into writable ZIPs; current folder or folder-row destination |
| Document icon themes | Implemented (milestone 2, in review): 20 optional themes built from the preserved archives (every family, surface study, candidate, the pre-redesign icons and all 11 variations); Ed25519-signed catalogue verified with CryptoKit, rollback protection, bounded verified downloads with progress and cancel, hardened staged installation with atomic publication, offline use, removal and Restore Default; Settings → Appearance → Document Icon Theme. Applies inside Arkiv (archive rows, title-bar proxy icon, Archive Info), including dedicated compound-suffix (`.tar.xz` …) and split-7z-volume artwork; [coverage matrix](format-icon-coverage.md); Finder and Quick Look keep the bundled Seal Dark icons (milestone 4). Production signing key and first publication pending maintainer provisioning; [details](document-icon-themes.md), [inventory](document-icon-theme-inventory.md) |
| Lightweight size optimisations | Lossless icon recompression implemented (in review): the 110 PNGs go from 7,808,654 to 6,334,859 bytes (−18.9%) and the packaged ICNS from 10,368,446 to 6,359,786 bytes, with every decoded pixel verified identical; Universal update archive 14.30 → 10.15 MB, DMG 14.70 → 10.42 MB; [details](document-icons.md#lossless-optimization). Duplicate-representation elimination investigated and deferred pending real-Mac compatibility evidence. Signed Sparkle delta updates and real-Mac size/launch/memory measurements remain planned |
| ZIP/TAR associations | Viewer/alternate registration implemented; real-Mac validation pending |
| Open regular internal file | Selective extraction into an owned temporary copy; default macOS application; [details](open-files.md) |
| Quick Look | Native single regular-file preview using the existing owned Open-file session; Space or Quick Look menu |
| Nested archives | Single regular entry opens in a new window after content inspection; [details](nested-archives.md) |
| Icon / document icons | Original procedural app icon generated and packaged in macOS CI, visual validation pending; Seal Dark document icons bundled ([details](document-icons.md)) |
| Advanced columns | Packed Size, Ratio, Modified, Method, Encrypted, stored CRC32 and Attributes implemented; unknown evidence stays blank |
| Open Recent | Native AppKit recent-document storage and File menu; successful normal archives only; nested/private temporary archives excluded |
| Settings | Implemented: native General/Updates/Finder/Appearance tabs, persisted appearance (default Dark), clear recents, Sparkle controls, existing Finder setup, and Document Icon Theme; see [Settings](settings.md) |

See `archive-formats.md` for the narrower per-format evidence. This is an early development foundation, not a production-ready archive manager or completion of Priority A.

Archive document icons: the Seal Dark family covers ZIP, 7z, RAR, TAR, GZIP, BZIP2, XZ, Zstandard, TGZ, TBZ2 and TXZ, each with its own artwork; the Tension Seal app icon is unchanged. Packaged resources are validated; Finder visual acceptance requires a real Mac. See [document icons](document-icons.md).

Compressed TAR: read/browse/extract/Test via bounded gzip/bzip2/XZ decoding; shared Open/Quick Look/nested/drag workflows. Creation also supported; editing remains unavailable. [Limits](compressed-tar.md).

## Zstandard

ZSTD standalone (`.zst`) and compressed TAR (`.tar.zst`, `.tzst`) support content-based browse, extract, Test, Open File, Quick Look, drag-out and creation through the existing shared workflows. Standalone creation requires one regular file; TAR creation accepts file/folder selections. Checksum-less frames produce an integrity warning. Editing, dictionaries, concatenated/skippable frames and advanced controls are unavailable. See [verified policy and limits](zstandard.md).

Split 7z Phase 1: verified Copy/LZMA2 and AES-256 header on/off reading through bounded private reconstruction; first/later-volume opening and safe sibling discovery. Split 7z creation uses exact verified encoder bytes; multipart editing and RAR multipart remain disabled. [Policy](multipart.md).
