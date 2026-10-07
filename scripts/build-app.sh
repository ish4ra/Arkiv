#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'Arko.app requires macOS and Xcode command line tools.' >&2; exit 1; }
architecture=${ARKO_ARCH:-arm64}
swift build -c release --arch "$architecture"
binary_dir=$(swift build -c release --arch "$architecture" --show-bin-path)
app="$PWD/build/Arko.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Arko" "$app/Contents/MacOS/Arko"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/render-icon.swift "$PWD/build/Arko.iconset"
iconutil -c icns build/Arko.iconset -o "$app/Contents/Resources/Arko.icns"
cp docs/third-party-licenses.md "$app/Contents/Resources/ThirdPartyNotices.txt"
codesign --force --sign - --options runtime "$app"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
echo "Built $app ($architecture; ad-hoc signed, not notarized)"
