ARKO — GPT-6 ASTRA MASTER IMPLEMENTATION BRIEF

Repository:
https://github.com/ish4ra/Arko

Application name:
Arko

IMPORTANT REPOSITORY STATE
The repository is currently completely empty. There are no commits and no branches yet, including no main branch.
Initialize the repository properly as part of this task. Create the native Arko macOS project from scratch, establish main as the primary branch, commit stable milestones, and push the completed work to GitHub.
Do not treat the empty repository as an error or wait for starter code.

EXECUTION GOAL
Build Arko as a serious production-quality, macOS-only archive manager.
Do not only plan, explain, or create mockups. Research first, then implement, build, test, debug, commit, and push stable work.

PRODUCT VISION
Arko should provide the depth and workflow of serious desktop archive managers such as 7-Zip File Manager and WinRAR, but redesigned properly for modern macOS.
It must NOT be a simple “drop archive -> extract everything” app.

When a user opens an archive, it must open inside Arko as a browsable container. Users should be able to:
- browse folders and files inside archives
- inspect metadata
- sort/search/filter
- preview and open individual files
- selectively extract files/folders
- extract all
- create archives
- add/update/delete entries where safely supported
- configure compression
- use encryption/passwords
- test archive integrity
- inspect archive properties
- use Finder right-click actions
- drag files in/out where appropriate
- handle multipart archives
- calculate checksums
- split/combine files
- use keyboard-first desktop workflows

The goal is:
“7-Zip / WinRAR-class archive management reimagined as a polished native macOS application.”

DO NOT CLONE
Do not clone Keka, WinRAR, or 7-Zip visually.
Do not copy their branding, icons, mascot, UI composition, artwork, or proprietary assets.
Study workflows and capabilities only.

CRITICAL DESIGN RULE: DO NOT MAKE A GENERIC APP
Previous apps have ended up looking like generic AI-generated utilities. That is unacceptable here.

Avoid:
- generic dashboard layouts
- giant cards everywhere
- random gradients
- excessive empty space
- web/SaaS dashboard styling
- generic blue/purple developer-tool aesthetics
- meaningless stat cards
- mobile UI stretched onto desktop
- huge rounded buttons for basic file actions
- glassmorphism without purpose
- generic SwiftUI sample-project appearance

Arko is a desktop file/archive management utility.
The UI should be information-dense, keyboard-friendly, practical, and visually refined.

Design direction:
- archive/file manager first
- modern native macOS
- Finder-like familiarity where useful
- traditional archive manager productivity
- proper toolbar
- proper menus/context menus
- native table/list presentation
- native sheets and dialogs
- restrained animation
- high information density without clutter
- excellent light/dark mode behavior
- clear hierarchy
- polished but not decorative

NATIVE MACOS STACK
Prefer:
- Swift
- SwiftUI where appropriate
- AppKit where needed
- NSTableView / NSOutlineView when better for desktop behavior
- NSMenu
- native toolbar/window APIs
- Uniform Type Identifiers
- NSWorkspace
- Quick Look APIs
- native drag and drop
- Keychain for saved secrets/passwords
- Security Scoped Bookmarks where required
- appropriate modern Finder extension / Services / Quick Action APIs

Do NOT use:
- Electron
- Chromium
- a browser UI
- Node.js as the application runtime
- a localhost web app wrapped as a desktop app

Apple Silicon is first-class.
Target arm64. Add x86_64/Universal support if practical without compromising quality.

RESEARCH ARCHIVE BACKENDS FIRST
Research current versions, licenses, capabilities, security, and redistribution implications of:
- 7-Zip / LZMA SDK
- libarchive
- UnRAR where relevant
- native macOS archive/compression APIs
- other mature libraries where justified

Do not reinvent compression algorithms.
Normal users must not need Homebrew, MacPorts, manually installed 7z/unrar, Python, Node, or external command-line tools.
Bundle required components where licensing permits.
Document third-party licenses.

ARCHIVE ENGINE ARCHITECTURE
Do not tightly couple UI to one library.
Create a clean archive engine abstraction capable of:
- inspect archive
- enumerate entries
- browse hierarchy
- extract individual/selected/all entries
- create archive
- add/replace/update/delete/rename entries where supported
- test integrity
- read metadata/comments
- write comments where supported
- detect encryption
- request password
- report compression method/capabilities
- multipart handling
- progress reporting
- cancellation
- meaningful error mapping

The UI must query per-format capabilities and disable unsupported actions honestly.

FORMAT SUPPORT
First-class READ/BROWSE/EXTRACT target:
- 7z
- ZIP
- ZIPX where reliable
- RAR / RAR5
- TAR
- TGZ / TAR.GZ
- GZIP
- TAR.BZ2 / BZIP2
- TAR.XZ / XZ
- LZMA
- ZSTD / ZST
- XAR
- CPIO
- CAB
- AR
- LHA / LZH

Investigate practical read-only support for advanced image/package formats supported by modern archive engines, such as:
- APFS images
- ARJ
- CHM
- CramFS
- DMG
- EXT images
- FAT images
- GPT
- HFS/HFS+
- IHEX
- ISO
- MBR
- MSI
- NSIS
- NTFS images
- QCOW2
- RPM
- SquashFS
- UDF
- UEFI
- VDI
- VHD
- VHDX
- VMDK
- WIM
- Unix .Z

Do not advertise a format until actually verified.

CREATE/COMPRESS target:
- 7z
- ZIP
- TAR
- TAR.GZ
- TAR.BZ2
- TAR.XZ
Also add GZIP/BZIP2/XZ/ZSTD/XAR where robustly supported.

RAR creation is not required. Do not reverse-engineer proprietary RAR compression and do not fake RAR creation.

Maintain a per-format capability matrix:
- browse
- extract
- create
- modify
- encryption
- filename encryption
- multipart
- comments
- integrity test

CORE ARCHIVE BROWSER
Opening an archive must show a real native browser, primarily a table/list rather than cards.

Useful optional columns:
- Name
- Size
- Packed Size
- Ratio
- Type
- Modified
- Created
- Compression Method
- CRC/checksum
- Attributes
- Encrypted

Support:
- sortable/resizable columns
- customizable visible columns
- multi-selection
- Shift/Command selection
- Select All
- keyboard navigation
- folder navigation
- breadcrumb/path navigation
- Back / Forward / Up / archive root
- double-click folder
- double-click file
- contextual menus
- native file icons where practical
- status information

OPEN FILES INSIDE ARCHIVES
Double-clicking a normal file should:
1. extract only that file to a controlled temporary workspace
2. open with the appropriate macOS app
3. track temp data
4. clean safely later
Do not extract the whole archive unnecessarily.

QUICK LOOK
Space on an archive entry should use native Quick Look where practical by temporarily extracting only the selected file.

NESTED ARCHIVES
Allow opening archives contained inside another archive using controlled temporary extraction, without extracting the entire outer archive.
Support current-window or new-window/tab behavior as appropriate.

EXTRACTION
Implement:
- Extract
- Extract Selected
- Extract All
- Extract Here
- Extract To...
- Extract to "<ArchiveName>/"

Options:
- preserve hierarchy
- flatten when explicitly requested
- choose destination
- overwrite policy
- timestamps
- permissions where appropriate
- safe symlink handling
- reveal output in Finder

Conflict policies where appropriate:
- Ask
- Replace
- Skip
- Keep Both / Auto Rename
- Replace Older
- Apply to All

Progress UI should show useful data:
- action
- archive
- current file
- overall progress
- files completed/total
- bytes processed/total
- throughput
- elapsed time
- ETA when reliable
- Cancel

EXTRACTION SECURITY
Protect against:
- Zip Slip
- ../ traversal
- absolute path escape
- symlink traversal/chains
- unsafe hard links
- unsafe device paths
- writes outside selected destination
- malformed names
- hostile metadata
- decompression bombs where reasonable

Never allow silent extraction outside the selected root.
Add regression tests for malicious archives.

CREATE ARCHIVE
Provide a polished native Create/Add Archive sheet:
- files/folders
- drag/drop
- destination
- archive name
- format
- simple defaults
- expandable advanced settings

COMPRESSION SETTINGS
Expose supported options only.
Where applicable:
- Store
- Fastest
- Fast
- Normal
- Maximum
- Ultra

Methods where genuinely supported:
- LZMA
- LZMA2
- Deflate
- Deflate64
- BZip2
- PPMd
- Zstandard

Advanced where applicable:
- dictionary size
- word size
- fast bytes
- solid archive
- solid block
- threads
- memory estimate
- presets

ENCRYPTION
7z:
- AES-256
- content encryption
- header/filename encryption where supported

ZIP:
- secure AES where backend/interoperability permits
- clearly label legacy ZipCrypto if supported at all

Password UI:
- Password
- Confirm Password
- Show Password
- method
- filename encryption toggle where available

Never log passwords.
Never store passwords in plaintext.
Use macOS Keychain if opt-in password saving is later added.

MODIFY EXISTING ARCHIVES
Where safely supported:
- Add files
- Add folders
- Replace/update
- Rename
- Delete
- Create folder
- drag Finder files into archive

For formats requiring full rewrite, use safe transactional behavior:
temporary archive -> success -> atomic replacement.

DRAG AND DROP
Drag OUT from archive to Finder with transparent extraction.
Drag IN from Finder for writable formats.
Show clear unsupported behavior for read-only formats.

SEARCH/FILTER
At minimum:
- name
- path
- extension/type
Advanced filters may include:
- size
- date
- encrypted
- compression method
Do not extract contents merely for filename search.

TEST ARCHIVE / INTEGRITY
Provide dedicated Test Archive:
- structure
- CRC/checksum
- encrypted readability
- missing multipart volumes
- corruption
- unsupported compression methods

Clear result states:
- OK
- Warning
- Corrupt
- CRC Error
- Wrong Password
- Missing Volume
- Unsupported Method

ARCHIVE INFO / INSPECTOR
Show where available:
- filename
- format
- physical size
- total unpacked size
- ratio
- files/folders count
- methods
- solid state
- encryption
- filename encryption
- volumes
- timestamps
- comments
- checksum details

COMMENTS
Read archive comments when supported.
Write/edit only where genuinely supported.

MULTI-VOLUME
Support common 7z and RAR multipart conventions.
Detect related parts automatically where possible.
Report exact missing volume.
For creation where supported, offer split sizes:
- 100 MB
- 650 MB
- 700 MB
- 1 GB
- 2 GB
- 4 GB
- custom

SPLIT / COMBINE FILES
Provide 7-Zip-like utility functionality:
largefile.iso.001
largefile.iso.002
...
Allow preset/custom chunk size and recombination.

HASH / CHECKSUM TOOLS
Support reliable algorithms such as:
- CRC32
- CRC64 where practical
- SHA-1
- SHA-256
- SHA-512
- BLAKE2 where practical

Allow calculate, copy, compare expected value.

BENCHMARK
Add an archive/compression benchmark under Tools:
- compression throughput
- decompression throughput
- threads
- dictionary config
- CPU use if practical
- duration
Do not clutter normal archive browsing UI.

FINDER INTEGRATION — CRITICAL
Research current recommended Apple APIs before implementation.
Evaluate:
- Finder Sync extension
- contextual actions
- Services
- Quick Actions
- modern app extension APIs
- distribution/sandbox implications

Do not blindly force Finder Sync if a more appropriate current approach exists.

For archive files, target:
- Open in Arko
- Extract Here
- Extract to "<ArchiveName>/"
- Extract To...
- Test Archive

For normal files/folders:
- Add to Archive...
- Compress to ZIP
- Compress to 7z
- Compress to "<Name>.zip"
- Compress to "<Name>.7z"
- Compress with Password...

Keep Finder menus clean; use a submenu where appropriate.
Support multiple selected Finder items.

FILE ASSOCIATIONS
Register proper UTTypes/document types.
Users should be able to set Arko as default for supported archives.
Double-click should open archive in Arko, NOT automatically extract it.

FINDER QUICK LOOK
Investigate a Quick Look extension for archive files showing compact metadata and a limited file tree/list:
- format
- compressed size
- unpacked size
- file/folder count
- encryption
- limited contents preview

MACOS METADATA
Research preservation of:
- POSIX permissions
- executable bits
- symlinks
- modified/creation dates
- extended attributes
- Finder metadata
- resource forks where relevant
Security takes priority.

WINDOWS-SPECIFIC FEATURE MAPPING
Translate capabilities instead of copying Windows concepts:
- shell integration -> Finder integration
- drive letters -> POSIX/mounted volumes
- NTFS-specific behavior -> appropriate macOS/POSIX metadata
- Windows SFX -> only investigate a legitimate macOS equivalent

SELF-EXTRACTING ARCHIVES
Investigate a safe macOS equivalent only if justified, potentially signed/notarized .app bundles.
Consider Gatekeeper, Developer ID, notarization, quarantine, and security.
Do not implement unsafe pseudo-SFX just for parity.

CORRUPTED ARCHIVES
Provide strong diagnostics:
- malformed
- CRC failure
- truncated
- missing volumes
- partial extraction where safe
Do not claim generic repair capability unless real backend support exists.
Do not fake WinRAR RAR recovery features.

PERFORMANCE
Keep UI responsive during:
- indexing
- compression
- extraction
- hashing
- testing
- huge archives

Use background work/streaming where possible.
Avoid loading entire archives into RAM.
Use CPU cores appropriately.
Support cancellation.
Warn before extreme memory configurations.

LARGE ARCHIVES
Test:
- tens of thousands of entries
- deeply nested directories
- multi-GB archives
- huge individual files
Use virtualization/lazy list behavior if needed.

TASK/PROGRESS UX
Use compact native progress UI, not a dashboard.
Show useful task information and clear success/warning/failure outcomes.

ERROR HANDLING
Map backend errors to human-readable states:
- Wrong password
- Unsupported method
- Corrupt archive
- CRC mismatch
- Missing volume
- File conflict
- Permission denied
- Read-only destination
- Insufficient space
- Unsupported modification
- Unsafe path detected

Raw codes may be hidden in technical details.

DISK SPACE CHECKS
Estimate output and warn when clearly insufficient, without falsely blocking uncertain cases.

TEMP DATA
Use safe unique temp workspaces.
Clean after use.
Clean stale cache after crashes/restarts.
Do not leak passwords.
Provide Clear Temporary Data in Settings.

MULTI-WINDOW / TABS
Support multiple archives using real macOS multi-window behavior.
Investigate native window tabbing where useful.

RECENTS
Use standard File > Open Recent and Clear Menu.
Do not make a giant recent-files dashboard.

KEYBOARD-FIRST WORKFLOW
Use standard macOS shortcuts where appropriate:
- Command-O Open
- Command-N New Archive
- Command-F Search
- Command-A Select All
- Command-I Info
- Space Quick Look
- Command-Delete Delete entry where supported
- Command-Up Parent
Add sensible shortcuts for Extract, Add, Test, Settings, navigation.

ENTRY CONTEXT MENUS
Appropriate actions:
- Open
- Open With
- Quick Look
- Extract
- Extract To...
- Rename
- Delete
- Info
- Copy Path
- Calculate Checksum
Only enable supported operations.

TOOLBAR
Modern evolution of archive-manager toolbars.
Primary actions may include:
- Add
- Extract
- Test
- Delete
- Info
Secondary actions belong in menus/context menus.
Use native toolbar conventions and tooltips.

STATUS BAR
Subtle optional status:
- selection count
- selected size
- total entries
- total unpacked size
- compressed size

COMPRESSION PRESETS
Support presets such as:
- Fast ZIP
- Maximum 7z
- Encrypted 7z
- Compatibility ZIP
Never store actual passwords in presets.

SETTINGS
Create proper macOS Settings sections such as:
- General
- Extraction
- Compression
- Finder
- Security/Privacy
- Advanced
Keep settings purposeful and use smart defaults.

CLI COMPANION
Architect the engine so GUI and CLI can reuse it.
If practical, create a CLI target:
arko list archive.7z
arko extract archive.7z
arko extract archive.7z --output ~/Downloads
arko test archive.7z
arko create output.7z files...
arko hash file.iso
If CLI risks the primary GUI foundation, defer implementation but keep architecture ready.

ACCESSIBILITY
Support:
- VoiceOver
- keyboard-only navigation
- adequate contrast
- Reduce Motion
- appropriate text scaling
Do not communicate state by color alone.

LIGHT/DARK MODE
Support both properly using semantic native colors/materials.
Validate tables, selections, toolbar, dialogs, inspectors, settings, context menus, progress UI.

ATTACHED KEKA SCREENSHOT
The attached Keka screenshot is only a reference for the LEVEL of uniqueness, charm, memorability, craftsmanship, and product identity desired.
Do NOT copy:
- mascot
- animal
- pose
- silhouette
- colors
- composition
- lighting
- UI
- branding
- object concept

ARKO APP ICON — EXTREMELY IMPORTANT
Do NOT create a generic archive utility icon.

Do NOT use:
- plain folder
- plain ZIP document
- generic cardboard box
- normal zipper pasted over a square
- generic file stack
- random gradient rounded square
- single generic SF Symbol
- boring package glyph

Create/explore at least 2-3 genuinely different original concepts before choosing the strongest direction.

Possible broad direction:
an original archive/storage/compression-inspired object, possibly with subtle personality or tactile sculpted qualities, representing compacting, holding, wrapping, bundling, or storing files.

Do not force a mascot if an original iconic object is stronger.

The final icon should be:
- completely original
- premium
- modern
- distinctive
- memorable
- slightly charming
- not childish
- recognizable at tiny sizes
- strong in Dock/Finder
- appropriate beside premium macOS apps

No text inside the app icon.
Create correct macOS AppIcon assets and verify readability at:
16, 32, 64, 128, 256, 512, 1024 px.

Do not leave a generic placeholder icon.

ARCHIVE DOCUMENT ICONS
Create a coherent family for:
- ZIP
- 7Z
- RAR
- TAR
- GZ
- XZ
- ZST
These may use subtle format labels and should share Arko's visual language without becoming the app icon.

BRAND SYSTEM
Keep branding restrained:
- signature app icon
- archive document icons
- subtle accent color
- native system typography
- tasteful empty-state artwork
Functionality remains primary.

EMPTY STATE
Compact, polished, not dashboard-like.
Possible controls:
- Open Archive
- Create Archive
- Drop an archive here to open it

WINDOW UX
Use native macOS windows, sheets, pickers, title bars, toolbar behavior, Finder reveal, and document proxy icons where appropriate.

SANDBOX / SECURITY / DISTRIBUTION
Research:
- App Sandbox
- security-scoped bookmarks
- Finder integration
- helper extensions/processes
- Hardened Runtime
- Developer ID direct distribution
- Mac App Store restrictions
Choose architecture that preserves essential archive-manager functionality.
Document tradeoffs.

SIGNING / NOTARIZATION
Prepare for:
- Developer ID
- Hardened Runtime
- notarization
- stapling
Do not fabricate credentials.
Unsigned local builds should work.
Document release steps and automation for later credentials.

CI / BUILD
Add GitHub Actions suitable for macOS:
- clean build
- tests
- useful static analysis/lint if justified
Prepare release tooling for:
- Arko.app
- DMG
- optional ZIP bundle
Prefer Universal binaries if practical.
Do NOT publish a public release unless explicitly requested.

TEST SUITE
Create real fixtures/tests covering:
- normal ZIP
- normal 7z
- TAR
- RAR read/extract if supported
- empty archive
- nested directories
- Unicode names
- emoji names
- spaces
- long filenames
- password-protected
- wrong password
- corrupted
- CRC failure
- multipart
- symlinks
- malicious ../ path
- malicious absolute path
- nested archive
- many-entry archive

REAL-WORLD VALIDATION
Where environment permits, validate workflows such as:
1. Open ZIP -> browse -> open file -> Quick Look -> selective extract -> extract all
2. Open 7z -> browse -> test -> extract
3. Encrypted archive -> wrong password -> recover -> correct password -> extract
4. Create ZIP -> reopen -> extract -> verify
5. Create encrypted 7z -> reopen -> decrypt -> extract
6. Finder right-click archive -> Extract Here
7. Finder right-click files -> Compress to ZIP
8. Drag archive entry to Finder
9. Drag Finder file into writable archive
10. Cancel long operation
11. Open corrupted archive

CLOUD ENVIRONMENT REALITY
Do not falsely claim local macOS/Xcode validation if this cloud environment cannot provide it.
Use GitHub Actions macOS runners for actual Swift/Xcode compilation and automated tests where possible.
Clearly mark any remaining interactive real-Mac validation requirements.
Do not switch to cross-platform frameworks merely because the current execution environment is not macOS.

DOCUMENTATION
At minimum:
README.md
docs/architecture.md
docs/archive-formats.md
docs/feature-matrix.md
docs/security.md
docs/finder-integration.md
docs/release.md
docs/third-party-licenses.md

README should explain what Arko is, status, verified formats, major features, build instructions, architecture overview, release state, and screenshots when useful.
Avoid marketing fluff.

FEATURE MATRIX
Track:
- archive browser
- selective extraction
- create
- modify
- encryption
- AES-256
- filename encryption
- solid archives
- multipart
- integrity test
- comments
- checksums
- split/combine
- Finder integration
- Quick Look
- CLI
- benchmark
- nested archives
- drag/drop
Also track per-format support.

NON-GOALS
Do NOT add:
- accounts/login
- cloud sync
- AI features
- chat
- subscriptions
- social features
- unrelated productivity tools
- telemetry by default
- unnecessary network services

IMPLEMENTATION PRIORITY
Do not attempt everything simultaneously and leave it half-finished.

PRIORITY A:
- initialize repository
- project architecture
- native macOS app shell
- archive engine abstraction
- ZIP
- 7z
- TAR
- RAR read/extract
- archive browser
- navigation
- open/Quick Look
- extraction
- safe temp management
- progress
- cancellation
- basic archive creation
- security tests
- macOS CI

PRIORITY B:
- encryption
- archive modification
- advanced compression options
- Finder integration
- file associations
- drag/drop
- integrity test
- archive info
- multipart
- checksums

PRIORITY C:
- split/combine
- benchmark
- Finder Quick Look extension
- CLI
- wider format support
- advanced metadata
- final branding polish

Complete implemented features properly before expanding.

CONTEXT / EXECUTION LIMIT SAFETY
If remaining execution/context budget becomes low:
1. do not start a new major subsystem
2. finish the current subsystem
3. ensure project compiles through available macOS CI
4. run relevant tests
5. fix regressions
6. commit stable work
7. push stable work
8. clearly report what remains

A smaller stable milestone is better than a larger broken one.

GIT HYGIENE
Inspect before modifying.
Use meaningful milestone commits.
Do not add AI attribution footers.
Do not commit:
- DerivedData
- build output
- local Xcode state
- temp extracted data
- credentials
- certificates
- secrets
- irrelevant scratch files

Do not damage working code once it exists.
Avoid unnecessary rewrites and architecture churn.

QUALITY PRIORITY
1. correctness
2. data safety
3. extraction security
4. reliability
5. archive compatibility
6. desktop productivity
7. performance
8. native macOS UX
9. visual polish
10. branding

FINAL VALIDATION BEFORE STOPPING
- clean build via available macOS CI
- all tests
- inspect warnings
- representative fixtures
- failure cases
- malicious-path security tests
- light/dark mode code/state review
- keyboard navigation
- cancellation
- memory/performance where practical
- no manually installed runtime dependency required for users
- no generic placeholder icon
- no false support claims

FINAL REPORT
Provide concise factual report:
- branch
- commits
- architecture
- archive backend(s)
- why chosen
- licenses
- completed features
- formats verified for read/extract/create
- encryption
- modification
- Finder integration
- associations
- Quick Look
- icon/branding
- CI/build results
- tests
- limitations
- remaining items
- exact next recommended phase

MOST IMPORTANT:
Do not spend the task merely explaining how Arko could be built.

Actually work in:
https://github.com/ish4ra/Arko

Research.
Implement.
Build.
Test.
Debug.
Commit.
Push.

Create a strong stable foundation for Arko as a genuine native modern macOS archive manager with serious archive-management capabilities and its own recognizable product identity.
