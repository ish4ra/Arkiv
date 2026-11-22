#!/bin/bash
# Read-only diagnostic: why might Finder's Desktop show a generic icon for an
# archive while Get Info shows Arkiv's document icon?
#
# It changes nothing. It never resets LaunchServices, Quick Look or icon
# caches, never registers apps, never changes default applications and never
# modifies the file. Temporary output goes to a new private directory under
# $TMPDIR, which is printed so you can inspect and delete it.
#
# Usage: scripts/diagnose-finder-document-icons.sh ~/Desktop/Arkiv-Test.zip
set -u
[[ $(uname -s) == Darwin ]] || { echo 'Run this on the Mac that shows the icon.' >&2; exit 1; }
file=${1:?Usage: diagnose-finder-document-icons.sh /path/to/archive}
[[ -e "$file" ]] || { echo "No such file: $file" >&2; exit 1; }
out=$(mktemp -d "${TMPDIR:-/tmp}/arkiv-icon-diagnostic.XXXXXX")

section() { printf '\n== %s\n' "$1"; }

section 'File and its type'
ls -l@ "$file"
mdls -name kMDItemContentType -name kMDItemContentTypeTree -name kMDItemFSCreationDate -name kMDItemDateAdded "$file"

section 'Extended attributes (a per-file custom icon would appear as com.apple.FinderInfo / com.apple.ResourceFork)'
xattr -l "$file" | head -40 || true

section 'Default handler and the icon Icon Services returns now (same source as Get Info)'
cat > "$out/probe.swift" <<'SWIFT'
import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
if let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
    let info = Bundle(url: app)?.infoDictionary ?? [:]
    print("default handler: \(app.path)")
    print("handler version: \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")
} else {
    print("default handler: none")
}
let icon = NSWorkspace.shared.icon(forFile: url.path)
icon.size = NSSize(width: 256, height: 256)
if let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: out.appendingPathComponent("icon-services-256.png"))
    print("Icon Services image: \(out.appendingPathComponent("icon-services-256.png").path)")
}
SWIFT
swift "$out/probe.swift" "$file" "$out" 2>&1 | grep -v '^warning:' || true

section 'Arkiv copies known to Spotlight (an old copy can be registered too)'
mdfind "kMDItemCFBundleIdentifier == 'xyz.isharalakshan.arkiv'" 2>/dev/null | while IFS= read -r app; do
  version=$(defaults read "$app/Contents/Info" CFBundleVersion 2>/dev/null || echo '?')
  icons=$(ls "$app/Contents/Resources" 2>/dev/null | grep -c '^Arkiv-.*\.icns$')
  echo "$app  build $version  document icons: $icons"
done

section 'Desktop view options (showIconPreview uses Quick Look thumbnails instead of the document icon)'
defaults read com.apple.finder DesktopViewSettings 2>/dev/null | grep -E 'showIconPreview|iconSize' || echo 'no Desktop-specific settings stored'

section 'Quick Look thumbnail rendered fresh for this file (not taken from the cache)'
qlmanage -t -s 256 -o "$out" "$file" >/dev/null 2>&1 && ls "$out"/*.png 2>/dev/null | grep -v icon-services || echo 'Quick Look produced no thumbnail (Finder then uses the document icon)'

section 'Quick Look thumbnail extensions that could answer for this type'
pluginkit -mAv -p com.apple.quicklook.thumbnail 2>/dev/null | head -20 || true

cat <<EOF

== How to read this
* If "Icon Services image" shows the Seal Dark icon (as Get Info does), Arkiv's
  registration is correct. A generic icon on the Desktop then comes from
  Finder's own view state, not from Arkiv.
* If the file's creation or added date is before Arkiv build 26501 was
  installed, the Desktop is most likely still drawing the icon it cached for
  that item. Create a new archive on the Desktop and compare. If the new one
  shows the Seal Dark icon, only the older item is stale.
* If showIconPreview is 1, the Desktop draws Quick Look thumbnails. A thumbnail
  cached before the update can still be the generic icon, while Get Info asks
  Icon Services directly.
* Several Arkiv copies with different builds can confuse which bundle's
  resources are used. Keep only the installed copy.
Nothing was reset or changed. Temporary files: $out
EOF
