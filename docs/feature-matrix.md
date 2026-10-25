# Milestone status

| Capability | State |
| --- | --- |
| Native archive browser | Implemented: AppKit table, resize/sort columns, multi-selection, search, folder/back/forward/up navigation, multiple windows |
| Selective/all extraction | Implemented: new destination folder, bounded streaming, cancellation, progress and cleanup |
| Extraction safety | Automated hostile-path/link/overwrite/CRC/limit regression suite |
| macOS application validation | Native compilation, tests, arm64 app/icon packaging and signature verification passed macOS CI; interactive validation outstanding |
| Create ZIP | Store/Deflate, native creation setup, direct Finder multi-selection compression; [details](creation.md) |
| Create/read 7z / AES-256 / filename encryption | LZMA2, content/header encryption, native password prompt/retry; [backend and limits](sevenzip.md) |
| Compression presets | ZIP Store/Fastest/Fast/Normal/Maximum; 7z Fastest/Fast/Normal/Maximum/Ultra; [mappings and limits](compression-presets.md) |
| Add to existing ZIP | Add Files/Add Folder at root; verified atomic rewrite of supported ZIP32; [limits](zip-additions.md) |
| ZIP Delete / Rename / Replace File / New Folder | Verified transactional edits for eligible ZIP32 archives; [details](zip-edits.md) |
| ZIP Replace Folder / Update Folder | One selected folder/package in an eligible ZIP: Replace removes old descendants; Update merges matching/new paths and keeps archive-only descendants; native picker, confirmation and atomic verification; [details](zip-edits.md) |
| ZIP Update Selected Files | Two or more regular files in one ZIP folder; strict same-basename local mapping; Replace All or conservative Replace Older; one verified atomic transaction; [details](zip-edits.md#update-selected-files) |
| Arbitrary multi-selection mapping / folder update-by-date / ZIP AES | Deferred; no enabled UI claims |
| Solid archives / multipart / comments | Deferred compatibility work |
| Integrity test command | ZIP/7z full-data/CRC checks; TAR structure/readability with explicit checksum warning; native progress/cancellation/password retry |
| Checksums / split-combine / benchmark / CLI | Deferred |
| Finder integration | Sandboxed Finder Sync **Arkiv** submenu (user enablement required; home folder only): Open, Extract Here, Extract to folder, Extract To and Test Archive for one ZIP/7z/uncompressed TAR, plus Add to Archive and ZIP/7z/password compression for normal items; [details](finder-sync.md). AppKit Services fallback for one ZIP/uncompressed TAR; [details](finder-integration.md). Extension registration and the direct menu were confirmed on a real M1 Mac; broader interactive acceptance pending |
| Drag out | Native lazy file promises; selected files/folders to Finder; [details](drag-out.md) |
| Drag in | Native Finder file URLs into writable ZIPs; current folder or folder-row destination |
| ZIP/TAR associations | Viewer/alternate registration implemented; real-Mac validation pending |
| Open regular internal file | Selective extraction into an owned temporary copy; default macOS application; [details](open-files.md) |
| Quick Look | Native single regular-file preview using the existing owned Open-file session; Space or Quick Look menu |
| Nested archives | Single regular entry opens in a new window after content inspection; [details](nested-archives.md) |
| Icon / document icons | Original procedural app icon generated and packaged in macOS CI, visual validation pending; document family deferred |
| Recents / Settings / advanced columns / metadata preservation | Deferred |

See `archive-formats.md` for the narrower per-format evidence. This is an early development foundation, not a production-ready archive manager or completion of Priority A.
