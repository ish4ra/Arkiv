# Architecture

Arkiv is a macOS 13+ AppKit application built with Swift Package Manager. `ArkivApp` owns native windows, menus, toolbars and an `NSTableView`. `ArkivCore` exposes an `ArchiveEngine` protocol, immutable catalog snapshots, folder indexing, progress and cancellation. `CArkiv` is a small streaming libarchive adapter. Neither app nor engine launches a shell or external compressor.

Archive operations run on a serial background queue per window. The C cancellation token is atomic; callbacks are synchronous and UI progress is throttled. A snapshot records source identity, size, and modification time; extraction rechecks these plus the entry catalog and refuses changed archives. The browser index creates implicit folders without extracting contents. Per-entry IDs are ordinals within that snapshot, not filenames, so selection is unambiguous for duplicate records.

Extraction writes to a private sibling staging directory, with a 100,000-entry/20-GiB budget. Successful output is moved to a new UUID-named directory; failures remove staging. There is no overwrite or modification mode. Backend registration is limited to ZIP, TAR, 7z and RAR/RAR5, with no external-program filter fallbacks. Format support claims follow fixtures, not registration.

System libarchive is the initial backend to avoid distributing an unreviewed binary dependency. It is independently replaceable; a future bundled/pinned backend must have a documented patch/update process, redistributable sources and licenses. GUI and future CLI can share ArkivCore. No network services, accounts, telemetry, or runtime package managers.

Deferred boundaries: capability negotiation for write/encryption options, private temporary preview workspaces, secure persistence/bookmarks, richer errors, creation and mutation transactions. Do not add those directly to the window controller.
