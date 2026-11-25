#!/usr/bin/env python3
"""Copies the original document-icon artwork shown in the README. Design-time only.

    python3 design/readme/collect-artwork.py [--check]

Every file is a byte-identical copy of preserved artwork; nothing is resized,
recompressed, recoloured or redrawn:

* Seal Dark (bundled default, build 26501): Resources/DocumentIcons, the
  production 128 px tier (icon_128x128.png) and 32 pt @2x tier.
* Optional themes: the archived 256 px renders of
  archive/document-icon-concepts-v1 (7e9b736) and the preserved Restored
  Readability iconsets of archive/document-icon-concepts-v2 (8a1b92a), read
  with `git cat-file` at those pinned commits, never a branch tip.

The rejected Classic Extended candidate is never copied. Writes
docs/media/artwork/; --check verifies every copy instead.
Needs both archive commits: git fetch origin <v1> <v2>.
"""
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / 'docs/media'
V1 = '7e9b736b123274e28a64727d0e6fde22ca11daf7'
V2 = '8a1b92ae31f5ba4e649022f0cb38ccd9e24647a6'
BUNDLED = ['ZIP', '7z', 'TAR', 'RAR', 'GZIP', 'BZIP2', 'XZ', 'ZSTD', 'TGZ', 'TBZ2', 'TXZ']
TABLE = ['ZIP', '7z', 'TAR', 'RAR', 'GZIP', 'ZSTD']
# Theme id (as in design/document-icon-themes/themes.json) -> v1 render key.
V1_THEMES = {'seal-dark-aubergine': 'seal-dark', 'seal-wine': 'seal-dark-wine', 'seal-noir': 'seal-dark-noir',
             'seal': 'seal', 'folio': 'folio', 'folio-dark': 'folio-dark', 'strata': 'strata'}
SHOWN = {'zip': 'ZIP', '7z': '7z', 'tar': 'TAR'}


def blob(commit, path):
    return subprocess.run(['git', 'cat-file', 'blob', f'{commit}:{path}'], cwd=ROOT, check=True,
                          capture_output=True).stdout


def sources():
    """(destination relative to docs/media, source description, bytes)."""
    out = []
    for name in BUNDLED:
        path = f'Resources/DocumentIcons/Arkiv-{name}.iconset/icon_128x128.png'
        out.append((f'artwork/seal-dark/{name}-128.png', path, (ROOT / path).read_bytes()))
    for name in TABLE:
        path = f'Resources/DocumentIcons/Arkiv-{name}.iconset/icon_32x32@2x.png'
        out.append((f'artwork/seal-dark/{name}-32@2x.png', path, (ROOT / path).read_bytes()))
    for theme, key in V1_THEMES.items():
        for fmt in SHOWN:
            path = f'design/document-icon-concepts-v1/previews/{key}/{fmt}-256.png'
            out.append((f'artwork/{theme}/{SHOWN[fmt]}-256.png', f'{V1[:7]}:{path}', blob(V1, path)))
    for name in SHOWN.values():
        path = f'design/document-icon-concepts-v2/themes/seal-dark-restored-readability/iconsets/Arkiv-{name}.iconset/icon_256x256.png'
        out.append((f'artwork/seal-dark-restored/{name}-256.png', f'{V2[:7]}:{path}', blob(V2, path)))
    return out


def main(check):
    lines, failures = [], []
    for dest, source, data in sources():
        assert 'classic-extended' not in dest
        digest = hashlib.sha256(data).hexdigest()
        target = MEDIA / dest
        if check:
            if not target.is_file() or target.read_bytes() != data:
                failures.append(f'{dest} is not a byte-identical copy of {source}')
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        lines.append(f'{digest}  {dest}')
    if check:
        extra = sorted(str(p.relative_to(MEDIA)) for p in (MEDIA / 'artwork').rglob('*') if p.is_file()
                       and str(p.relative_to(MEDIA)) not in {line.split('  ')[1] for line in lines})
        failures += [f'{p} is not produced from a preserved source' for p in extra]
        if failures:
            raise SystemExit('\n'.join(failures))
        print(f'{len(lines)} artwork files are byte-identical to their preserved sources')
    else:
        print(f'Copied {len(lines)} artwork files')


if __name__ == '__main__':
    main('--check' in sys.argv[1:])
