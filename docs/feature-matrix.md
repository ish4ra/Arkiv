# Milestone status

| Capability | State |
| --- | --- |
| Native archive browser | Implemented: AppKit table, resize/sort columns, multi-selection, search, folder/back/forward/up navigation, multiple windows |
| Selective/all extraction | Implemented: new destination folder, bounded streaming, cancellation, progress and cleanup |
| Extraction safety | Automated hostile-path/link/overwrite/CRC/limit regression suite |
| macOS application validation | CI configured; result unobserved; interactive validation outstanding |
| Create / modify / encryption / AES-256 / filename encryption | Deferred; no enabled UI claims |
| Solid archives / multipart / comments | Deferred compatibility work |
| Integrity test command | Deferred; extraction checks data/CRC but is not a dedicated Test action |
| Checksums / split-combine / benchmark / CLI | Deferred |
| Finder integration / drag in-out | Deferred |
| ZIP/TAR associations | Viewer/alternate registration implemented; real-Mac validation pending |
| Open internal file / Quick Look / nested archives | Deferred to next Priority A increment |
| Icon / document icons | Original procedural app icon implemented, visual validation pending; document family deferred |
| Recents / Settings / advanced columns / metadata preservation | Deferred |

See `archive-formats.md` for the narrower per-format evidence. This is an early development foundation, not a production-ready archive manager or completion of Priority A.
