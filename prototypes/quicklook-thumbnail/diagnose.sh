#!/bin/bash
# Quick Look thumbnail feasibility diagnostic. CI runners only (ephemeral).
#
# Builds the prototype extension into a COPY of the built app (the shipped
# app, DMG and ZIP are never touched), registers that copy on this runner,
# and asks Quick Look for thumbnails with qlmanage:
#   1. bundled Seal Dark artwork for .zip, and different artwork for
#      .tar.gz than for .gz (compound suffixes, which Finder icons cannot do);
#   2. a throwaway installed theme selected through Arkiv's preference domain
#      is drawn on the next request (theme switching without touching files);
#   3. a split volume name (.7z.001) is NOT routed to Arkiv (no claim on .001).
# Prints a report; never modifies anything outside build/ and this runner's
# own preference/theme folders, which it restores.
set -uo pipefail
cd "$(dirname "$0")/../.."
app=${1:?Built Arkiv.app required}
work="$PWD/build/thumbnail-prototype"
rm -rf "$work"; mkdir -p "$work/out"
copy="$work/Arkiv.app"
ditto "$app" "$copy"
arch=$(uname -m)
sdk=$(xcrun --sdk macosx --show-sdk-path)
appex="$copy/Contents/PlugIns/ArkivThumbnail.appex"
mkdir -p "$appex/Contents/MacOS"
xcrun swiftc -O -parse-as-library -application-extension -sdk "$sdk" -target "$arch-apple-macosx13.0" \
  -module-name ArkivThumbnail prototypes/quicklook-thumbnail/ArkivThumbnailProvider.swift \
  -framework QuickLookThumbnailing -framework AppKit -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$appex/Contents/MacOS/ArkivThumbnail" || { echo "RESULT build: FAILED"; exit 1; }
cp prototypes/quicklook-thumbnail/Info.plist "$appex/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements prototypes/quicklook-thumbnail/ArkivThumbnail.entitlements "$appex"
codesign --force --sign - --options runtime --entitlements Resources/Development.entitlements "$copy"
codesign --verify --strict "$copy" && echo "RESULT ad-hoc signature of the prototype copy: valid"
echo "Extension size: $(du -sk "$appex" | cut -f1) KiB"

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f -R -trusted "$copy"
pluginkit -a "$appex"
registered=no
for attempt in 1 2 3 4 5 6; do
  if pluginkit -m -v -p com.apple.quicklook.thumbnail | grep -q thumbnail-prototype; then registered=yes; break; fi
  sleep 5
done
pluginkit -m -v -p com.apple.quicklook.thumbnail | grep -i arkiv
echo "RESULT registered with PlugInKit (ad-hoc signed, no Developer ID): $registered"

fixtures="$work/fixtures"; mkdir -p "$fixtures"
for name in sample.zip sample.tar.gz sample.gz sample.7z sample.7z.001 sample.tar.xz; do
  printf 'arkiv thumbnail prototype fixture\n' > "$fixtures/$name"
done
measure() { swift prototypes/quicklook-thumbnail/measure.swift "$@"; }
thumbs() { rm -f "$work/out/"*.png; qlmanage -t -s 256 -o "$work/out" "$fixtures"/sample.* > "$work/qlmanage-$1.log" 2>&1; ls "$work/out"; }

thumbs bundled
measure "$work/out" > "$work/bundled.txt"; cat "$work/bundled.txt"
mkdir -p "$work/report"; cp "$work/out/"*.png "$work/report/" 2>/dev/null
for f in "$work/report/"*.png; do mv "$f" "${f%.png}.bundled.png"; done

# A throwaway theme: solid jade ZIP artwork, verified by manifest like a real pack.
theme_root="$HOME/Library/Application Support/Arkiv/DocumentIconThemes"
had_theme_root=no; [[ -d "$theme_root" ]] && had_theme_root=yes
old_selection=$(defaults export xyz.isharalakshan.arkiv - 2>/dev/null | plutil -extract Arkiv.DocumentIconTheme json -o - - 2>/dev/null || true)
python3 prototypes/quicklook-thumbnail/make-test-theme.py "$theme_root/proto-test/1"
defaults write xyz.isharalakshan.arkiv Arkiv.DocumentIconTheme -dict id proto-test version -int 1
thumbs themed
measure "$work/out" > "$work/themed.txt"; cat "$work/themed.txt"
for f in "$work/out/"*.png; do cp "$f" "$work/report/$(basename "${f%.png}").themed.png"; done

# Restore this runner's state.
if [[ -n "$old_selection" ]]; then echo "(previous selection existed; left for inspection)"; else defaults delete xyz.isharalakshan.arkiv Arkiv.DocumentIconTheme 2>/dev/null; fi
rm -rf "$theme_root/proto-test"
[[ $had_theme_root == no ]] && rm -rf "$HOME/Library/Application Support/Arkiv"
pluginkit -r "$appex" 2>/dev/null
"$lsregister" -u "$copy" 2>/dev/null

python3 - "$work" <<'PY'
import sys, pathlib
work = pathlib.Path(sys.argv[1])
def load(name):
    rows = {}
    for line in (work / name).read_text().splitlines():
        parts = line.split()
        if len(parts) >= 5: rows[parts[0]] = tuple(float(x) for x in parts[1:5])
    return rows
b, t = load('bundled.txt'), load('themed.txt')
def dark_plum(rgb): return rgb[0] < 0.45 and rgb[2] < 0.45 and rgb[3] > 0.2
def jade(rgb): return rgb[1] > rgb[0] + 0.15 and rgb[1] > 0.4
z = 'sample.zip.png'
print('RESULT .zip uses Arkiv artwork (Seal Dark is dark plum):', 'yes' if z in b and dark_plum(b[z]) else 'no', b.get(z))
print('RESULT .tar.gz differs from .gz (compound suffix):', 'yes' if b.get('sample.tar.gz.png') and b.get('sample.gz.png') and b['sample.tar.gz.png'] != b['sample.gz.png'] else 'no')
print('RESULT selected theme drawn on the next request:', 'yes' if z in t and jade(t[z]) else 'no', t.get(z))
print('RESULT .7z.001 routed to Arkiv:', 'yes (unexpected)' if 'sample.7z.001.png' in b and b.get('sample.7z.001.png') == b.get('sample.7z.png') else 'no (expected: .001 is not claimed)')
PY
