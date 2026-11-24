#!/bin/bash
# Records how Keka, a widely used macOS archiver, registers archive document
# types, from its official GitHub release and its public wiki. Research only,
# for docs/keka-comparison.md: it prints metadata (type identifiers,
# extensions, roles, ranks, icon file names and Quick Look extensions). It never
# copies, extracts or redistributes Keka's artwork or code, and it changes
# nothing on the machine except a private temporary folder.
#   scripts/research-keka-document-types.sh <report directory>
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Run on macOS (CI)' >&2; exit 1; }
out=${1:?usage: research-keka-document-types.sh <report directory>}
mkdir -p "$out"
work=$(mktemp -d)
trap 'hdiutil detach -quiet "$work/mnt" 2>/dev/null || true; rm -rf "$work"' EXIT
curl -sSfL https://api.github.com/repos/aonez/Keka/releases/latest -o "$work/release.json"
python3 - "$work/release.json" > "$work/asset" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
assets = [a for a in release['assets'] if a['name'].endswith('.dmg') and 'Keka' in a['name'] and 'Helper' not in a['name']]
a = assets[0]
print(release['tag_name'], a['name'], a['browser_download_url'], a.get('digest', ''), sep='\t')
PY
IFS=$'\t' read -r tag name url digest < "$work/asset"
curl -sSfL "$url" -o "$work/$name"
actual=sha256:$(shasum -a 256 "$work/$name" | cut -d' ' -f1)
{
  echo "Keka release: $tag ($name)"
  echo "Source: $url"
  echo "SHA-256: $actual (GitHub asset digest: ${digest:-not provided})"
} > "$out/keka-release.txt"
[[ -z "$digest" || "$digest" == "$actual" ]] || { echo 'Downloaded Keka does not match its GitHub digest' >&2; exit 1; }
mkdir "$work/mnt"
hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$work/mnt" "$work/$name"
app=$(find "$work/mnt" -maxdepth 1 -name 'Keka.app' -print -quit)
plutil -convert json -o "$work/Info.json" "$app/Contents/Info.plist"
python3 - "$work/Info.json" "$app" >> "$out/keka-release.txt" <<'PY'
import json, os, sys
info, app = json.load(open(sys.argv[1])), sys.argv[2]
print('Bundle:', info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), info.get('CFBundleVersion'))
print('\n== CFBundleDocumentTypes')
for t in info.get('CFBundleDocumentTypes', []):
    print(f"- {t.get('CFBundleTypeName')}: role={t.get('CFBundleTypeRole')} rank={t.get('LSHandlerRank')} "
          f"types={t.get('LSItemContentTypes')} extensions={t.get('CFBundleTypeExtensions')} icon={t.get('CFBundleTypeIconFile') or t.get('CFBundleTypeIconSystemGenerated')}")
for key in ['UTExportedTypeDeclarations', 'UTImportedTypeDeclarations']:
    print(f'\n== {key}')
    for d in info.get(key, []):
        tags = d.get('UTTypeTagSpecification', {})
        print(f"- {d.get('UTTypeIdentifier')}: extensions={tags.get('public.filename-extension')} conforms={d.get('UTTypeConformsTo')} icon={d.get('UTTypeIconFile') or d.get('UTTypeIcons')}")
resources = os.path.join(app, 'Contents/Resources')
icons = sorted(f for f in os.listdir(resources) if f.endswith('.icns'))
print(f'\n== Icon resources ({len(icons)} ICNS files; names only)')
print(', '.join(icons))
plugins = os.path.join(app, 'Contents/PlugIns')
print('\n== App extensions')
for appex in sorted(os.listdir(plugins)) if os.path.isdir(plugins) else []:
    try:
        import plistlib
        p = plistlib.load(open(os.path.join(plugins, appex, 'Contents/Info.plist'), 'rb'))
        ext = p.get('NSExtension', {})
        attrs = ext.get('NSExtensionAttributes', {})
        print(f"- {appex}: {ext.get('NSExtensionPointIdentifier')} QLSupportedContentTypes={attrs.get('QLSupportedContentTypes')}")
    except Exception as error:
        print(f'- {appex}: unreadable ({error})')
PY
# Documented behaviour, from the public wiki (text only).
if git clone -q --depth 1 https://github.com/aonez/Keka.wiki.git "$work/wiki" 2>/dev/null; then
  { echo "Wiki commit: $(git -C "$work/wiki" rev-parse HEAD)"; grep -rn -i -E 'tar\.xz|\btxz\b|\.xz\b|default app|file association|extension|icon|\.001|part1' "$work/wiki" --include='*.md' | sed "s#$work/wiki/##" | head -200; } > "$out/keka-wiki.txt"
else
  echo 'Wiki not reachable' > "$out/keka-wiki.txt"
fi
cat "$out/keka-release.txt"
