#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:?App bundle path required}
architecture=${2:?Architecture required}
extension="$app/Contents/PlugIns/ArkivFinderSync.appex"
binary="$extension/Contents/MacOS/ArkivFinderSync"
[[ -d "$extension" && ! -L "$extension" && -x "$binary" ]]
plutil -lint "$extension/Contents/Info.plist"
python3 scripts/finder-extension-metadata.py verify "$app"
actual=$(lipo -archs "$binary")
if [[ "$architecture" == universal ]]; then
  [[ "$actual" == 'arm64 x86_64' || "$actual" == 'x86_64 arm64' ]]
else
  [[ "$actual" == "$architecture" ]]
fi
codesign --verify --strict --all-architectures "$extension"
# Validate the actual signed entitlements, not just the source plist.
work=$(mktemp -d "$PWD/build/finder-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
codesign -d --entitlements :- "$extension" > "$work/entitlements.plist" 2>/dev/null
python3 - "$work/entitlements.plist" <<'PY'
import plistlib, sys
from pathlib import Path
actual = plistlib.loads(Path(sys.argv[1]).read_bytes())
expected = plistlib.loads(Path('Resources/FinderSync.entitlements').read_bytes())
if actual != expected or actual.get('com.apple.security.app-sandbox') is not True:
    raise SystemExit('Finder extension must retain its minimal sandbox entitlements')
PY
# No archive engine, Sparkle dependency or custom third-party framework in Finder.
otool -L "$binary" > "$work/libraries.txt"
python3 - "$work/libraries.txt" <<'PYCODE'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().lower()
if any(name in text for name in ['libarchive', 'sparkle', 'arkivcore']):
    raise SystemExit('Unexpected extension dependency')
PYCODE
"$binary" --verify-principal-class
echo "Verified sandboxed Finder Sync extension ($actual)"
