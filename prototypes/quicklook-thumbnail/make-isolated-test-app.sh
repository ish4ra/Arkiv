#!/bin/bash
# Builds "Arkiv Thumbnail Test.app": an isolated host for the Quick Look
# thumbnail PROTOTYPE, for real-Mac evaluation only.
#
# Made from a COPY of a built Arkiv.app. The copy gets its own bundle
# identifier and loses everything that could interact with the real Arkiv or
# the system: document types and type declarations (it can never become a
# default app), URL schemes, Services, the Finder Sync extension and the
# Sparkle feed and key (it cannot update itself). It keeps Arkiv's bundled
# Seal Dark icons, which the extension draws when no theme is selected.
# The installed /Applications/Arkiv.app is never read from or written to
# unless you pass it as the source; it is only copied.
#
#   make-isolated-test-app.sh <built Arkiv.app> <output folder>
set -euo pipefail
cd "$(dirname "$0")/../.."
source_app=${1:?Built Arkiv.app required}
out=${2:?Output folder required}
host_id=xyz.isharalakshan.arkiv-thumbnail-test
appex_id=$host_id.thumbnails
mkdir -p "$out"
app="$out/Arkiv Thumbnail Test.app"
rm -rf "$app"
ditto "$source_app" "$app"
plist="$app/Contents/Info.plist"
buddy=/usr/libexec/PlistBuddy
"$buddy" -c "Set :CFBundleIdentifier $host_id" "$plist"
"$buddy" -c "Set :CFBundleName Arkiv Thumbnail Test" "$plist"
"$buddy" -c "Add :CFBundleDisplayName string Arkiv Thumbnail Test" "$plist" 2>/dev/null || "$buddy" -c "Set :CFBundleDisplayName Arkiv Thumbnail Test" "$plist"
for key in CFBundleDocumentTypes UTExportedTypeDeclarations UTImportedTypeDeclarations CFBundleURLTypes NSServices \
           SUFeedURL SUPublicEDKey SUEnableAutomaticChecks ArkivDocumentIconThemeCatalogURL ArkivDocumentIconThemePublicEDKey; do
  "$buddy" -c "Delete :$key" "$plist" 2>/dev/null || true
done
rm -rf "$app/Contents/PlugIns/ArkivFinderSync.appex"

arch=$(uname -m)
sdk=$(xcrun --sdk macosx --show-sdk-path)
appex="$app/Contents/PlugIns/ArkivThumbnail.appex"
mkdir -p "$appex/Contents/MacOS"
xcrun swiftc -O -parse-as-library -application-extension -sdk "$sdk" -target "$arch-apple-macosx13.0" \
  -module-name ArkivThumbnail prototypes/quicklook-thumbnail/ArkivThumbnailProvider.swift \
  -framework QuickLookThumbnailing -framework AppKit -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$appex/Contents/MacOS/ArkivThumbnail"
cp prototypes/quicklook-thumbnail/Info.plist "$appex/Contents/Info.plist"
"$buddy" -c "Set :CFBundleIdentifier $appex_id" "$appex/Contents/Info.plist"
"$buddy" -c "Set :CFBundleDisplayName Arkiv Thumbnail Test" "$appex/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements prototypes/quicklook-thumbnail/ArkivThumbnail.entitlements "$appex"
codesign --force --sign - --options runtime --entitlements Resources/Development.entitlements "$app"
codesign --verify --strict "$app"
# Checks that nothing which could claim files, schemes or updates is left.
for key in CFBundleDocumentTypes UTExportedTypeDeclarations UTImportedTypeDeclarations CFBundleURLTypes NSServices SUFeedURL; do
  if "$buddy" -c "Print :$key" "$plist" >/dev/null 2>&1; then echo "error: $key still present" >&2; exit 1; fi
done
test ! -e "$app/Contents/PlugIns/ArkivFinderSync.appex"
(cd "$out" && ditto -c -k --sequesterRsrc --keepParent "Arkiv Thumbnail Test.app" "Arkiv-Thumbnail-Test-$arch.zip")
shasum -a 256 "$out/Arkiv-Thumbnail-Test-$arch.zip" | tee "$out/Arkiv-Thumbnail-Test-$arch.zip.sha256"
echo "Isolated test host: $app (bundle $host_id, extension $appex_id)"
