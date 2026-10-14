# Arkiv

A native macOS archive manager, built for the depth of tools like 7-Zip and WinRAR and designed properly for the Mac.

Arkiv opens an archive as a browsable container rather than unpacking everything at once. Browse folders, search, preview and open individual files, extract exactly what you need, create ZIP and encrypted 7z archives, and edit supported ZIPs, all from a native AppKit app with Finder integration. No Electron, no web views, and no Homebrew or command-line tools to install.

[![macOS CI](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml)

> [!NOTE]
> **Arkiv is in active early development.** Development builds are available for testing on macOS 13 or later (Apple Silicon and Intel). They are ad-hoc signed and **not notarized**, and there is no stable public release yet. Several core workflows still await real-Mac validation. See [what is implemented](docs/feature-matrix.md).

## Highlights

- **Native archive browser.** A Finder-like table with sortable, resizable columns, multi-selection, folder navigation (Back, Forward, Up), archive-wide search and multiple windows.
- **Selective extraction.** Extract the current selection or the whole archive, with progress and cancellation. Existing files are never overwritten.
- **Open, Quick Look and nested archives.** Open a file from a private temporary copy in its default app, press Space to preview it, or open an archive stored inside another archive in a new window, without extracting the rest of the outer archive.
- **Create ZIP and 7z.** ZIP is the default. 7z adds LZMA2 compression and optional AES-256 encryption, including encrypted filenames.
- **Edit ZIP archives.** Add files and folders, delete, rename, or replace a single file. Every edit is verified before it replaces the original.
- **Finder integration.** An **Arkiv** submenu in Finder's context menu to extract, test and compress, with Services as a fallback.
- **Drag in and out.** Drag entries to Finder, and drag Finder items into writable ZIPs.
- **Test Archive.** Read and verify archive data without extracting anything.

## Format support

Arkiv only lists a format as supported once it passes automated fixture tests. Recognising a file extension does not mean every compression method or variant inside it works.

| Format | Browse & extract | Create | Edit existing | Encryption | Test Archive |
| --- | --- | --- | --- | --- | --- |
| **ZIP** | Store, Deflate | Store, Deflate (default format) | Add, Delete, Rename, Replace File¹ | Not supported | Data and CRC |
| **7z** | LZMA, LZMA2 | LZMA2 | — | AES-256, optional encrypted filenames | Data and CRC |
| **TAR** (uncompressed) | Yes | — | — | — | Structure only² |
| **RAR5** | Limited³ | Never | — | — | — |

¹ Ordinary single-disk ZIP32 archives. Encrypted, ZIP64 and multipart ZIPs are read-only.
² TAR has no content checksum, so a passing test is reported as a warning.
³ Verified against a single stored (uncompressed) RAR5 fixture. Broader RAR5 and RAR4 decoding is not yet verified, and RAR creation is out of scope.

**Not yet verified, so not advertised:** RAR4, RAR5 beyond the stored fixture, compressed TAR (`.tar.gz`, `.tar.bz2`, `.tar.xz`), ZIPX, disk images and the other formats in the [specification](ARKIV_SPEC.md). No support is claimed until fixture tests pass.

**Known unsupported:** encrypted ZIP (rejected rather than guessed at), multipart archives, and RAR creation. See [format evidence](docs/archive-formats.md) for details.

## Using Arkiv

### Browse, open and extract

Open an archive with **File → Open Archive…** (⌘O), by double-clicking a ZIP or TAR once Arkiv is set as its handler, or through Finder. Folders open on double-click. App and framework bundles appear as packages; use **Show Package Contents** to look inside.

- **Extract Selected…** (⌘E) and **Extract All…** (⇧⌘E) write to a new folder in the destination you choose.
- **Open** launches a single file in its default app from a private temporary copy. Changes to that copy are **not** written back to the archive, and the copy is removed when the archive window closes, so save elsewhere anything you want to keep.
- **Quick Look** (Space) previews one regular file using the same temporary copy.
- **Nested archives:** double-clicking an entry whose contents are a supported archive, or choosing **Open as Archive**, opens it in a new Arkiv window. Only that entry is extracted, to the same private temporary workspace. Encrypted inner archives use the normal password prompt. Changes made inside a nested ZIP affect only its temporary copy and are never written back to the outer archive. Arkiv does not open nested archives automatically or browse them in the current window.
- **Search** (⌘F) filters by name across the whole archive. **Back** (⌘[), **Forward** (⌘]) and **Parent Folder** (⌘↑) handle navigation.

Encrypted 7z archives ask for a password when opened, with retry on a wrong password. Passwords are never saved. Extraction preserves symbolic links and safe executable permission bits, including inside app and framework bundles. See [extraction compatibility](docs/extraction-compatibility.md), [open files and Quick Look](docs/open-files.md) and [nested archives](docs/nested-archives.md).

### Create archives

Use **File → Create Archive…** (⇧⌘N) or Finder's **Add to Archive…** to choose a name, destination, format and compression method. ZIP offers Store or Deflate. 7z offers LZMA2 with optional AES-256 encryption and optional encrypted filenames. **Compress with Password…** uses 7z, because ZIP encryption has not yet passed interoperability testing. Arkiv never falls back silently to legacy ZipCrypto.

New archives are reopened and verified before they appear, and existing files are never replaced: name clashes become `Name (2).zip` and so on. See [creation](docs/creation.md) and [7z and AES-256](docs/sevenzip.md).

### Edit ZIP archives

For eligible ZIPs, Arkiv can:

- **Add Files…** and **Add Folder…** to the archive root, or drag Finder items onto the current folder or a folder row
- **Delete…** (⌘⌫) files and folders, after confirmation
- **Rename…** one file or folder within its current folder
- **Replace File…**: swap one file's contents for a file on disk, keeping its name and path in the archive

Each edit builds a complete replacement archive, verifies it, and then swaps it in atomically. If anything fails or you cancel before that point, the original is left untouched. Updating folders or several files at once, creating new folders, and editing 7z, TAR or RAR are not yet available. See [ZIP additions](docs/zip-additions.md), [ZIP edits](docs/zip-edits.md) and [drag-in](docs/drag-in.md).

### Drag and drop

Drag files or folders from Arkiv into Finder. Nothing is extracted until you drop, and Finder's chosen destination is never overwritten. Drag-in works only for writable ZIPs. Read-only archives do not accept drops. See [drag-out](docs/drag-out.md).

### Test Archive

**File → Test Archive** (⌘T) reads and checks the open archive without writing any files. **Test Archive File…** (⇧⌘T) checks an archive that may be too damaged to open. Results distinguish OK, Warning, Corrupt, CRC Error, Wrong Password and Unsupported Method where the format allows. See [integrity checks](docs/integrity.md).

## Finder integration

Arkiv includes a Finder extension that adds an **Arkiv** submenu to Finder's context menu:

| Selection | Actions |
| --- | --- |
| One ZIP, 7z or uncompressed TAR | Open in Arkiv · Extract Here · Extract to "Name/" · Extract To… · Test Archive |
| Files and folders (up to 128, in the same folder) | Add to Archive… · Compress to "Name.zip" · Compress to "Name.7z" · Compress with Password… |

**Enabling it:** macOS requires you to turn the extension on yourself. Arkiv shows a setup window on first launch, also available from **Arkiv → Finder Integration…**, with a button and manual instructions:

- **macOS 15 and later:** System Settings → General → Login Items & Extensions → Extensions → Finder → enable **Arkiv Finder**
- **macOS 13–14:** System Settings → Privacy & Security → Extensions → Finder Extensions → enable **Arkiv Finder**

**Scope:** the submenu appears only for items inside your home folder. For archives elsewhere, such as external drives, use the fallback **Services** menu: right-click → Services → *Open in Arkiv*, *Extract Here with Arkiv*, *Extract to Folder with Arkiv* or *Extract To… with Arkiv*. These Services cover one ZIP or uncompressed TAR at a time. Enable them under System Settings → Keyboard → Keyboard Shortcuts → Services if needed.

Extract Here and Extract to Folder run immediately, play a short completion sound and never overwrite or merge existing items. See [Finder Sync](docs/finder-sync.md) and [Services](docs/finder-integration.md), including real-Mac test steps.

## Install a development build

There is no stable release yet. Two kinds of development build exist:

| Source | What it is | Use it for |
| --- | --- | --- |
| [GitHub Actions artifacts](https://github.com/ish4ra/Arkiv/actions/workflows/macos.yml?query=branch%3Amain) | arm64 and Universal DMGs (and ZIPs) from each CI run, with SHA-256 checksums | First installation |
| [Development prereleases](https://github.com/ish4ra/Arkiv/releases) (`dev-<build>`) | Signed Universal ZIPs published for Sparkle | Signed, user-confirmed in-app updates |

**First installation:**

1. Sign in to GitHub, open a successful `main` run of the **macOS foundation** workflow, and download **`Arkiv-arm64-development-dmg`** (Apple Silicon) or **`Arkiv-universal-development-dmg`** (Apple Silicon or Intel).
2. Unzip GitHub's artifact wrapper. Optionally verify the image with `shasum -a 256 -c Arkiv-*-development.dmg.sha256`.
3. Open the DMG, drag **Arkiv.app** to **Applications**, eject the volume and launch Arkiv from Applications.

**Gatekeeper:** these builds are ad-hoc signed, not Developer ID signed, and not notarized. macOS may block the first launch with a warning that it could not verify the app. If you trust the build, try to open it once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**. Do not disable Gatekeeper globally. See [release details](docs/release.md#signing-notarization-and-gatekeeper).

**Updates:** after installing once, use **Arkiv → Check for Updates…**. Sparkle installs updates only after verifying their EdDSA signature, and always asks before installing. This proves an update came from this project's signing key; it is not Apple notarization. See [development updates](docs/updates.md).

## Safety and privacy

Correctness and data safety come before features and polish.

- **The input archive is never modified** by browsing, testing or extraction. Edits to ZIPs are transactional and verified.
- **Extraction stays inside the destination you choose.** Path traversal, absolute paths, link tricks and unsafe special files are rejected, and output is staged privately before it is published. Hostile-archive cases are covered by automated regression tests.
- **No silent overwrites.** Extraction, creation and Finder actions never replace or merge existing files.
- **Resource limits.** Extraction is capped at 100,000 entries and 20 GiB of output.
- **Passwords are never persisted.** They are not saved, logged or passed through URLs. Opening an encrypted 7z does decode it to a private temporary plaintext spool on disk, kept while the archive is open and deleted on normal cleanup. A crash can leave it behind, and deletion is not secure erasure.
- **No accounts, telemetry or background network services.** The only network activity is Sparkle's update checks and downloads.

These protections have known limits. For example, the Finder extension's handoff URL does not authenticate its sender, and macOS metadata such as extended attributes and timestamps is not restored. See [security and known limits](docs/security.md).

## Build from source

Requires macOS 13 or later, Xcode command-line tools with Swift 5.9+, and Python 3 for the fixture tests.

```sh
python3 scripts/build-sevenzip.py
swift test -Xlinker -L"$PWD/.build/sevenzip" -Xlinker -rpath -Xlinker "$PWD/.build/sevenzip"
scripts/test-engine.sh
scripts/build-app.sh
scripts/build-dmg.sh
open build/Arkiv-arm64-development.dmg
```

The app builds for arm64 by default. Set `ARKIV_ARCH=universal` for both build scripts to produce a Universal app. On Linux you can build and test the archive engine (`ArkivCore`), but not the AppKit app. See [release and build details](docs/release.md).

**Architecture in brief:** a Swift Package Manager project with an AppKit app (`ArkivApp`) on top of a UI-independent engine (`ArkivCore`), so a future command-line tool can reuse it. ZIP, TAR and RAR go through the system libarchive. 7z uses a pinned, bundled build of the official 7-Zip source, with the RAR code excluded. Arkiv never shells out to external tools. See [architecture](docs/architecture.md).

## Roadmap

Planned work that is **not** in current builds:

- **Formats:** TAR creation, compressed TAR (`.tar.gz`, `.tar.bz2`, `.tar.xz`), broader RAR5 and RAR4 verification, multipart archives
- **Archive work:** encrypted ZIP after interoperability testing, folder and multi-file updates, editing more formats, archive comments
- **Tools:** checksums, split/combine, benchmark, a command-line companion
- **App:** Settings, Open Recent, more columns and an archive inspector, a Quick Look extension for archives in Finder
- **Distribution:** Developer ID signing and notarization, the final app icon and archive document icons

The full plan is in [`ARKIV_SPEC.md`](ARKIV_SPEC.md) and its current status in the [feature matrix](docs/feature-matrix.md).

## Documentation

| Topic | Documents |
| --- | --- |
| Status | [Feature matrix](docs/feature-matrix.md) · [Format evidence](docs/archive-formats.md) |
| Using Arkiv | [Creation](docs/creation.md) · [ZIP additions](docs/zip-additions.md) · [ZIP edits](docs/zip-edits.md) · [Open & Quick Look](docs/open-files.md) · [Nested archives](docs/nested-archives.md) · [Drag-in](docs/drag-in.md) · [Drag-out](docs/drag-out.md) · [Test Archive](docs/integrity.md) |
| Finder | [Finder Sync extension](docs/finder-sync.md) · [Services fallback](docs/finder-integration.md) |
| Safety | [Security](docs/security.md) · [Extraction compatibility](docs/extraction-compatibility.md) · [7z backend](docs/sevenzip.md) |
| Development | [Architecture](docs/architecture.md) · [Release & builds](docs/release.md) · [Updates](docs/updates.md) · [Browser UI notes](docs/ui-refinement.md) |

## Licensing

**Arkiv has not selected a project-wide license yet**, and the repository has no root `LICENSE` file.

Third-party components keep their own licenses:

- **7-Zip:** Arkiv bundles a library built from a pinned subset of the official 7-Zip 26.04 source, under LGPL-2.1-or-later (some files public domain), with no RAR code. Arkiv's bridge to this library is also LGPL-2.1-or-later. Source and rebuild instructions are in [`Vendor/7zip`](Vendor/7zip/README.md) and [7z backend](docs/sevenzip.md).
- **libarchive:** Arkiv uses the macOS system copy. Its BSD-licensed headers are included for building.
- **Sparkle 2.10.0:** bundled for updates. Its license file is included in the app.

See [third-party notices](docs/third-party-licenses.md).
