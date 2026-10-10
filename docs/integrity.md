# Test Archive

Test Archive is a read-only operation on the source archive, separate from
extraction. It reads actual entry data through the existing in-process backends;
it does not treat successful enumeration as proof of integrity. It never
publishes extracted files, selects a destination, reveals anything in Finder, or
plays the extraction-complete sound.

## Format policy and verification scope

- **ZIP:** decompress all supported entries and verify their CRCs and archive
  structure. Store and Deflate are regression tested, including empty archives.
- **7z:** use the bundled official 7-Zip decoder to test streams and available
  CRCs, including AES-256 archives with and without encrypted filenames. The
  password stays in memory for the operation; it is never put into the Finder
  URL, stored in preferences, or logged.
- **Uncompressed TAR:** verify headers and read the declared payload. A successful
  read is a **Warning**, not a checksum guarantee: TAR has no file-content CRC,
  so a same-length payload modification can be undetectable.

A checksum is evidence of accidental corruption, not authentication of the
archive's author. A successful Test does not promise that all metadata or methods
are supported for extraction. Safety budgets and unsupported entries may prevent
completion. Multipart diagnosis is deferred; Arkiv does not invent a missing
volume result when the backend cannot identify one.

ZIP remains the primary/default creation format. 7z remains a secondary format
and the supported encrypted creation choice. RAR/RAR5 remain read-only within the
verified decoder capabilities; no RAR writer is included. See
[format evidence](archive-formats.md).

## Results and limits

Results distinguish **OK**, **Warning**, **Corrupt**, **CRC Error**, and
**Unsupported Method** when the backend provides that distinction. Missing
passwords open the native password prompt; a failed password shows **Wrong
Password** with retry. Damaged encrypted data can be indistinguishable from a
wrong password, and the prompt explains that limitation. Cancellation stops the
operation without a success result. Access, source-change, and safety-limit errors
remain operational failures, not a misleading OK.

The test uses bounded discard buffers, including for 7z; it does not create the
private plaintext ZIP used by archive browsing. Existing entry, expanded-size,
path/type, decoder-memory and password-work limits apply. ZIP directory records
(including ZIP64) are checked before payload decoding. Unusual ZIP extensions,
self-extracting layouts or multipart archives may be rejected rather than
receiving an incomplete success claim.

In the app, **File → Test Archive** (⌘T) and the toolbar test the current archive.
**File → Test Archive File…** (⇧⌘T) can select a damaged archive that cannot be
opened in the browser. Finder’s Test Archive supports one selected ZIP/7z/TAR.
Existing Services remain unchanged.

## Real-Mac checks

1. Update Arkiv, then right-click a known-good ZIP in Finder and choose
   **Arkiv → Test Archive**. Expect progress followed by an OK result, no output
   directory, no Finder navigation, and no extraction sound.
2. Repeat for a plain 7z and an empty ZIP. Test from the application as well.
3. Create an encrypted 7z, with filename encryption enabled. Test it, enter a
   wrong password, then retry correctly. Repeat without filename encryption.
4. Test a ZIP whose stored payload has been altered without updating its CRC;
   expect CRC Error. Test a truncated ZIP/7z; expect a failure, never OK.
5. Test an uncompressed TAR. Expect the warning explaining the absence of a
   payload checksum. A truncated entry must fail instead of reporting success.
6. Cancel a large test while it is running. No output files or completion sound
   should appear. Verify subsequent testing and extraction still work.
7. Recheck direct ZIP/7z compression, encrypted extraction, and Finder Extract
   Here to confirm their existing focus, sound, and collision behavior.

Automated regression coverage runs with the existing engine/security and Swift
suites in both macOS build jobs. Interactive window focus, password sheets, and
VoiceOver behavior still require real-Mac checks.
