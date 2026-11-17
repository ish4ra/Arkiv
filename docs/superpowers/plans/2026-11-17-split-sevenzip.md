# Split 7z Reading Implementation Plan

> Use superpowers:executing-plans for tested checkpoints and independent final review.

Goal: read/test/extract conventional split 7z through existing archive workflows, never edit volumes.
Spec: user's Multipart Phase 1 request; ARKIV_SPEC.md.
Architecture: a dedicated descriptor-based sibling-volume reader streams into an owned private 7z spool. Existing official 7-Zip inspection/unlock/CRC verification then feeds the existing browser and selective TAR extraction. No segmented-random-access claim. A snapshot retains volume identities and revalidates the whole set before/after use.
Alternatives: segmented seekable input avoids disk duplication but changes the existing FD-only bridge; bounded reconstruction is smaller and reuses the proven backend. These are implementation decisions within the user's requested scope.
Limits: exact three-digit .7z.001–999 names, at most 128 volumes, 4 GiB packed input, directory scan bounded at 100000 names; existing 20 GiB decoded limit remains. No source writes, no follow at any path component, regular files with link count one, bounded streaming, cleanup on failure. Single-file split convention requires at least two volumes; encrypted reads retain existing password/security semantics. No edit capability for any multipart snapshot. Nested isolated parts fail safely rather than searching the parent archive or filesystem.

- [x] C volume access: strict discovery, descriptors, identity/stale checks, 7z signature/header length evidence, bounded copy; hostile tests.
- [x] Core snapshot lifetime/inspection/Test/extraction/Open/drag integration, read-only capability and metadata.
- [x] Independent upstream 7zz fixtures, native workflow tests, accurate technical docs.
- [ ] Focused and full local tests, checkpoint commit/push, independent review, native macOS CI/DMGs, signed release/feed verification.

Review focus: missing last part versus guessed name; symlink/hardlink and directory replacement; cancellation before publication; parent/child temporary ownership; multipart edit gating and encrypted CRC limitations.
Publication tracked separately: job has contents:write; repository rules API inaccessible, prior bot push denied. Never retry creation of an existing immutable release. No key/settings/protection changes.

Checkpoint: local 179-test full Swift suite (one package-CI-only skip), five focused split tests including added child lifetime case, and 153 engine/security tests (two macOS-only skips) pass. Independent upstream CLI tests all fixtures. Publication API/settings remain inaccessible. Main work is explicitly authorized by user; no worktree reset used.
