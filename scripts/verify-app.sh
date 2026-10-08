#!/bin/bash
# Verify the exact bundle we distribute, including every Mach-O slice.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'App verification requires macOS.' >&2; exit 1; }
app=${1:?Usage: verify-app.sh /path/to/Arkiv.app arm64|x86_64|universal}
architecture=${2:-arm64}
fail() { echo "::error title=Arkiv app verification::$1" >&2; exit 1; }
[[ -d "$app" && ! -L "$app" ]] || fail 'App bundle is missing or is a symlink.'
binary="$app/Contents/MacOS/Arkiv"
[[ -x "$binary" ]] || fail 'App executable is missing or not executable.'
[[ -s "$app/Contents/Resources/Arkiv.icns" ]] || fail 'Original app icon is missing.'
[[ -s "$app/Contents/Resources/ThirdPartyNotices.txt" ]] || fail 'Third-party notices are missing.'
[[ -s "$app/Contents/Resources/licenses/libarchive-COPYING.txt" ]] || fail 'Libarchive license is missing.'
plutil -lint "$app/Contents/Info.plist"
python3 scripts/verify-finder-services.py "$app/Contents/Info.plist"
python3 scripts/update-metadata.py verify "$app/Contents/Info.plist"
actual=$(lipo -archs "$binary")
case "$architecture" in
  arm64|x86_64) [[ "$actual" == "$architecture" ]] || fail 'Unexpected executable architecture.' ;;
  universal)
    # -verify_arch consumes all remaining arguments; input must come first.
    lipo "$binary" -verify_arch arm64 x86_64
    [[ "$actual" == 'arm64 x86_64' || "$actual" == 'x86_64 arm64' ]] || fail 'Universal executable must contain exactly arm64 and x86_64.'
    ;;
  *) fail 'Unsupported architecture; use arm64, x86_64, or universal.' ;;
esac
framework="$app/Contents/Frameworks/Sparkle.framework"
[[ -L "$framework/Versions/Current" && -s "$framework/Sparkle" ]] || fail "Sparkle framework or symlinks missing."
[[ -s "$app/Contents/Resources/Sparkle-LICENSE.txt" ]] || fail "Sparkle license missing."
lipo "$framework/Sparkle" -verify_arch arm64 x86_64
for component in "$framework"/Versions/B/XPCServices/*.xpc "$framework/Versions/B/Updater.app" "$framework/Versions/B/Autoupdate" "$framework"; do
  codesign --verify --strict --all-architectures "$component"
done
codesign --verify --deep --strict --all-architectures "$app"
"$binary" --verify-updater-bundle
echo "Verified Arkiv.app ($actual)."
