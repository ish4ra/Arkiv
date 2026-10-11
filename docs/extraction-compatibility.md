# Link-aware extraction

Arkiv preserves symbolic links as link objects, including relative, absolute and
`../` targets. It never follows an archive-created link to write another entry.
Every output parent is opened relative to the private extraction root with
`O_NOFOLLOW`; new files use exclusive creation. An archive entry named
`../../outside`, or a later entry below a symbolic link, is rejected and the
private staging output is discarded. Existing destination items are never
replaced or merged.

Hard links are resolved after file extraction, allowing forward references and
chains. Targets must be regular files created by this extraction, with matching
filesystem identity. External, cyclic, missing or unselected targets fail with a
clear error; Arkiv never links an arbitrary pre-existing file into its output.

Unsupported special entries such as FIFO/device/socket are skipped. Ordinary
entries continue extracting, and a native completion warning lists each skipped
entry and its reason. Browser and Finder extraction both expose these warnings.
Cancellation, expanded-size/entry limits and archive source revalidation remain
in effect.

Safe executable/read permission bits are retained so app/framework executables
remain usable. Owner read/write access and directory traversal are guaranteed;
setuid/setgid and group/other write permission are not restored. This is not full
macOS metadata restoration: resource forks, extended attributes, ACLs, ownership
and timestamps are not reconstructed. An absolute/outward symlink may point
outside the extraction folder if subsequently opened by another application;
Arkiv preserves its text but does not follow it during extraction.

The bundled 7z decoder uses a private TAR spool so decoded link/special-file
metadata can reach the same extractor without being disguised as regular files.
Passwords and spools remain transient; archive creation behavior is unchanged.

## Real package regression

Each macOS CI architecture packages the actual signed Arkiv.app ZIP, then invokes
`LibArchiveEngine` through `PackageExtractionTests` to browse and extract that ZIP.
CI compares every app path, regular-file byte hash, symlink target and executable
bit against the packaged source. It then runs the existing app verification on
the extracted bundle: architecture coverage, nested code signing, Finder extension,
Sparkle metadata/helpers and updater runtime checks. No re-signing repairs the
extracted app. The previous published Universal ZIP is also used during local
compatibility validation.

For a real-Mac check, download the official Universal development ZIP, open it in
Arkiv and extract all to a fresh folder. Confirm Sparkle.framework/Versions/Current
is a symlink to `B`, then launch the extracted Arkiv.app and check its updater.
Use a fresh destination for repeated tests; no-overwrite rules still apply.
