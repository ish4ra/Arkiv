#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'Arko.app requires macOS and Xcode command line tools.' >&2; exit 1; }
architecture=${ARKO_ARCH:-arm64}
stage=prepare
trap 'echo "::error title=Arko packaging stage::Failed at $stage" >&2' ERR
case "$architecture" in
  arm64|x86_64) architectures=("$architecture") ;;
  universal) architectures=(arm64 x86_64) ;;
  *) echo 'ARKO_ARCH must be arm64, x86_64, or universal.' >&2; exit 1 ;;
esac
mkdir -p build
slices=$(mktemp -d "$PWD/build/app-slices.XXXXXX")
trap 'rm -rf "$slices"' EXIT
for arch in "${architectures[@]}"; do
  stage="compile-$arch"
  swift build -c release --arch "$arch"
  binary_dir=$(swift build -c release --arch "$arch" --show-bin-path)
  stage="check-slice-$arch"
  cp "$binary_dir/Arko" "$slices/Arko-$arch"
  lipo -verify_arch "$arch" "$slices/Arko-$arch"
done
app="$PWD/build/Arko.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "$architecture" == universal ]]; then
  stage=combine-universal
  lipo -create "$slices/Arko-arm64" "$slices/Arko-x86_64" -output "$app/Contents/MacOS/Arko"
else
  cp "$slices/Arko-$architecture" "$app/Contents/MacOS/Arko"
fi
stage=resources
cp Resources/Info.plist "$app/Contents/Info.plist"
stage=render-icon
swift scripts/render-icon.swift "$PWD/build/Arko.iconset"
iconutil -c icns build/Arko.iconset -o "$app/Contents/Resources/Arko.icns"
cp docs/third-party-licenses.md "$app/Contents/Resources/ThirdPartyNotices.txt"
mkdir -p "$app/Contents/Resources/licenses"
cp licenses/libarchive-COPYING.txt "$app/Contents/Resources/licenses/"
stage=sign
codesign --force --sign - --options runtime "$app"
stage=verify
scripts/verify-app.sh "$app" "$architecture"
echo "Built $app ($architecture; ad-hoc signed, not notarized)"
