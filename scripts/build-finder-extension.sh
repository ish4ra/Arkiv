#!/bin/bash
# Build a genuine Finder Sync appex, using Apple's NSExtensionMain entry point.
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:?App bundle path required}
architecture=${2:?Architecture required}
case "$architecture" in
  arm64|x86_64) architectures=("$architecture") ;;
  universal) architectures=(arm64 x86_64) ;;
  *) exit 1 ;;
esac
work=$(mktemp -d "$PWD/build/finder-slices.XXXXXX")
trap 'rm -rf "$work"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
for arch in "${architectures[@]}"; do
  slice="$work/$arch"
  mkdir -p "$slice"
  xcrun swiftc -O -parse-as-library -whole-module-optimization -application-extension \
    -sdk "$sdk" -target "$arch-apple-macosx13.0" \
    -module-name ArkivFinderIntegration -emit-module -emit-object \
    -emit-module-path "$slice/ArkivFinderIntegration.swiftmodule" \
    Sources/ArkivFinderIntegration/*.swift -o "$slice/routing.o"
  xcrun swiftc -O -parse-as-library -emit-executable -application-extension \
    -sdk "$sdk" -target "$arch-apple-macosx13.0" \
    -module-name ArkivFinderSync -I "$slice" \
    Sources/ArkivFinderSync/*.swift "$slice/routing.o" \
    -framework FinderSync -framework AppKit -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$slice/ArkivFinderSync"
  lipo "$slice/ArkivFinderSync" -verify_arch "$arch"
done
extension="$app/Contents/PlugIns/ArkivFinderSync.appex"
mkdir -p "$extension/Contents/MacOS"
if [[ "$architecture" == universal ]]; then
  lipo -create "$work/arm64/ArkivFinderSync" "$work/x86_64/ArkivFinderSync" -output "$extension/Contents/MacOS/ArkivFinderSync"
else
  cp "$work/$architecture/ArkivFinderSync" "$extension/Contents/MacOS/ArkivFinderSync"
fi
python3 scripts/finder-extension-metadata.py write "$app"
codesign --force --sign - --options runtime --entitlements Resources/FinderSync.entitlements "$extension"
