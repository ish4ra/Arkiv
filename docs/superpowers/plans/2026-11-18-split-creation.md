# Split 7z Creation Plan

Goal: the user's Multipart Phase 2 specification; preserve Phase 1 and main until its release is verified.
Design: reuse the existing source manifest and official in-process 7z encoder. Verify ordinary output, stream exact bytes into private numbered parts, reconstruct using Phase 1, compare bytes, revalidate sources/destination, and publish exclusively with identity-checked rollback. No crash-atomic multi-file claim. No second encoder or general split utility.
Alternative direct volume encoder output would complicate verification and upstream callbacks; use the explicitly requested verified ordinary archive approach.
Limits: 2–128 volumes, 4 GiB physical, 20 GiB decoded; decimal MB/GB presets. Small/custom sizes >=32 bytes; result must exceed chosen size. ZIP remains default; passwords stay operation-local.

- [ ] Core policy + backend bounded splitting, reconstruction, source/destination checks and rollback; focused tests then checkpoint push.
- [ ] Native existing creation sheet controls, validation and UI tests; docs accurately describe limitations.
- [ ] Full local tests, independent upstream verification, native branch CI and review. No main merge/publication until Phase 1 release integrity established.

Review focus: publication collision races and identity-safe rollback; source changes after compression; directory substitution; cancellation/disk exhaustion; encrypted/solid interoperability. Test actual results and unchanged inputs, never weaken assertions.
Phase 1 attempt 2: arm64 green; Universal native tests/app build green but PlugInKit diagnostic failed (details unavailable publicly). Release skipped; feed 24001. No pipeline/security changes in Phase 2.

Core checkpoint: 184 Swift tests (1 skip), 155 engine/security tests (2 platform skips) passed locally. Four creation Swift tests cover round-trip/encryption/solid, boundaries, late collision/cancel/source/destination replacement, exact two-part bytes and invalid requests. Backend tests compare encoded bytes exactly and inject write exhaustion. Destination-move test exposed empty staging left behind: C now cleans via pinned directory descriptor; Swift never recursively removes a substituted split staging path.

Review fix checkpoint: publication mutation/extra/foreign-replacement tests failed against the first checkpoint, now pass with final public-set reconstruction/identity/byte validation. Replaced-output-parent regression failed by deleting foreign spool; now passed with descriptor-owned cleanup. Split staging created exclusively inside pinned C transaction (no pre-C cancel leak). Final decoded 7z TAR verified by manifest member name/type/size/bytes; upstream encoder does not store POSIX mode/mtime, documented rather than fabricated.
Native sheet now carries optional split policy, 7z-only controls and custom validation; macOS CI required. Fresh full local tests: 184 Swift (1 expected skip), 156 engine/security (2 platform skips). Independent upstream 26.01 accepted plain, content encrypted and header encrypted/solid generated sets; exact bytes checked in test. Phase 1 main/release remains untouched. Ruling: dedicated branch retained while PlugInKit diagnostic failure is unresolved; no assertion that it was infrastructure-only, no merge/publication.
