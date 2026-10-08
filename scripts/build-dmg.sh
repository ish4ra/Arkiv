#!/bin/bash
# Package an already-built app. The source app, mounted copy, and install copy
# must all pass the same checks before the final DMG is published to build/.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'DMG packaging requires macOS.' >&2; exit 1; }
architecture=${ARKIV_ARCH:-arm64}
case "$architecture" in
  arm64|x86_64|universal) ;;
  *) echo 'ARKIV_ARCH must be arm64, x86_64, or universal.' >&2; exit 1 ;;
esac
app="$PWD/build/Arkiv.app"
scripts/verify-app.sh "$app" "$architecture"
work=$(mktemp -d "$PWD/build/dmg-work.XXXXXX")
mountpoint="$work/mounted"
mounted=0
cleanup() {
  result=$?
  trap - EXIT
  if [[ "$mounted" == 1 ]]; then
    if ! hdiutil detach "$mountpoint" -quiet; then
      if ! hdiutil detach "$mountpoint" -force -quiet; then
        echo 'Could not detach the temporary DMG; leaving its workspace intact.' >&2
        exit 1
      fi
    fi
  fi
  rm -rf "$work"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work/source" "$mountpoint" "$work/install-test"
ditto "$app" "$work/source/Arkiv.app"
ln -s /Applications "$work/source/Applications"
image="$work/Arkiv.dmg"
hdiutil create -volname Arkiv -srcfolder "$work/source" -fs HFS+ -format UDZO "$image"
hdiutil verify "$image"
# Mark cleanup responsibility before attaching, so interrupted attaches are handled.
mounted=1
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$image"
[[ -d "$mountpoint/Arkiv.app" ]] || { echo '::error::Mounted DMG is missing Arkiv.app.' >&2; exit 1; }
[[ -L "$mountpoint/Applications" && $(readlink "$mountpoint/Applications") == /Applications ]] || {
  echo '::error::Mounted DMG has an invalid Applications link.' >&2; exit 1;
}
diskutil info -plist "$mountpoint" > "$work/volume.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :VolumeName' "$work/volume.plist") == Arkiv ]] || {
  echo '::error::Mounted DMG has an unexpected volume name.' >&2; exit 1;
}
scripts/verify-app.sh "$mountpoint/Arkiv.app" "$architecture"
cmp "$app/Contents/MacOS/Arkiv" "$mountpoint/Arkiv.app/Contents/MacOS/Arkiv"
# Simulate copying out of the read-only image, without touching /Applications.
ditto "$mountpoint/Arkiv.app" "$work/install-test/Arkiv.app"
scripts/verify-app.sh "$work/install-test/Arkiv.app" "$architecture"
hdiutil detach "$mountpoint" -quiet
mounted=0
output="$PWD/build/Arkiv-$architecture-development.dmg"
mv -f "$image" "$output"
(cd build && shasum -a 256 "Arkiv-$architecture-development.dmg" > "Arkiv-$architecture-development.dmg.sha256")
echo "Verified development DMG: $output"
echo 'App: ad-hoc signed. DMG: unsigned. Not notarized.'
