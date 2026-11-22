#!/usr/bin/env python3
"""Check document-type registrations, committed icon sources, protected app
branding and every packaged ICNS representation.

Usage: verify-document-icons.py [/path/to/Arkiv.app]
Without an app path only the repository (Info.plist, iconset sources,
checksums, branding) is checked; that part needs no macOS tools.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zlib

# Resource name -> the content type Finder resolves for that document.
# Keep in sync with design/document-icons/generate-config.mjs (ICONS).
ICONS = {
    'ZIP': 'public.zip-archive',
    'TAR': 'public.tar-archive',
    '7z': 'org.7-zip.7-zip-archive',
    'RAR': 'com.rarlab.rar-archive',
    'GZIP': 'org.gnu.gnu-zip-archive',
    'BZIP2': 'public.bzip2-archive',
    'XZ': 'org.tukaani.xz-archive',
    'ZSTD': 'org.zstandard.zstd',
    'TGZ': 'org.gnu.gnu-zip-tar-archive',
}
FORMATS = {name: ICONS[name] for name in ('ZIP', 'TAR', '7z', 'RAR')}
STREAM_FORMATS = {'org.gnu.gnu-zip-archive': 'gz', 'public.bzip2-archive': 'bz2',
                  'org.tukaani.xz-archive': 'xz', 'org.zstandard.zstd': 'zst'}
# Types Arkiv imports (never exports). The extension lists are exact: .tzst stays
# on the Zstandard type so existing associations for it are not moved.
IMPORTED = {'org.7-zip.7-zip-archive': ['7z'], 'com.rarlab.rar-archive': ['rar'],
            'org.gnu.gnu-zip-archive': ['gz'], 'public.bzip2-archive': ['bz2'],
            'org.tukaani.xz-archive': ['xz'], 'org.zstandard.zstd': ['zst', 'tzst']}
# Declared by macOS itself; Arkiv only attaches a Viewer/Alternate document type.
SYSTEM_DECLARED = {'org.gnu.gnu-zip-tar-archive': 'tgz'}
# Split-volume and generic numeric suffixes are shared with unrelated software.
GENERIC_EXTENSION = re.compile(r'^(\d+|[a-z]\d{2,}|part\d+)$', re.IGNORECASE)
REPRESENTATIONS = [(pt, scale) for pt in (16, 32, 128, 256, 512) for scale in (1, 2)]
SOURCES = Path('Resources/DocumentIcons')


def rep_name(pt, scale):
    return f'icon_{pt}x{pt}{"@2x" if scale == 2 else ""}.png'


def verify_metadata(info):
    assert info['CFBundleIconFile'] == 'Arkiv'
    assert info['CFBundleIdentifier'] == 'xyz.isharalakshan.arkiv'
    declarations = info['CFBundleDocumentTypes']
    assert len(declarations) == len(ICONS)
    for name, uti in ICONS.items():
        matches = [d for d in declarations if d['LSItemContentTypes'] == [uti]]
        assert len(matches) == 1, uti
        d = matches[0]
        assert d['CFBundleTypeIconFile'] == f'Arkiv-{name}.icns', uti
        assert d['CFBundleTypeRole'] == 'Viewer' and d['LSHandlerRank'] == 'Alternate', uti
        assert not {'CFBundleTypeExtensions', 'CFBundleTypeOSTypes', 'LSTypeIsPackage'} & set(d), 'No legacy extension claims'
    imported = {d['UTTypeIdentifier']: d for d in info['UTImportedTypeDeclarations']}
    assert set(imported) == set(IMPORTED)
    for uti, extensions in IMPORTED.items():
        assert imported[uti]['UTTypeTagSpecification']['public.filename-extension'] == extensions, uti
        assert imported[uti]['UTTypeConformsTo'] == ['public.archive'], uti
    assert not set(SYSTEM_DECLARED) & set(imported), 'System-declared types are not redeclared'
    assert not info.get('UTExportedTypeDeclarations'), 'Arkiv does not own these standard formats'
    verify_no_generic_extensions(info)


def verify_no_generic_extensions(info):
    for declaration in info.get('UTImportedTypeDeclarations', []) + info.get('UTExportedTypeDeclarations', []):
        for extension in declaration.get('UTTypeTagSpecification', {}).get('public.filename-extension', []):
            assert not GENERIC_EXTENSION.match(extension), f'Generic volume extension claimed: .{extension}'
    for declaration in info.get('CFBundleDocumentTypes', []):
        for extension in declaration.get('CFBundleTypeExtensions', []):
            assert not GENERIC_EXTENSION.match(extension), f'Generic volume extension claimed: .{extension}'


def read_png(path):
    """Return (width, height, rgba bytes) for an 8-bit RGBA, non-interlaced PNG."""
    data = Path(path).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    offset, idat, header = 8, bytearray(), None
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        offset += 12 + length
    width, height, depth, color, _, _, interlace = header
    assert depth == 8 and color == 6 and interlace == 0, f'{path}: expected 8-bit RGBA'
    raw, stride, out = zlib.decompress(bytes(idat)), width * 4, bytearray()
    previous = bytearray(stride)
    for row in range(height):
        start = row * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b, c = previous[i], previous[i - 4] if i >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        else:
            assert kind == 0, f'{path}: bad filter {kind}'
        out += line
        previous = line
    return width, height, bytes(out)


def png_size(path):
    data = Path(path).read_bytes()[:33]
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR', path
    width, height, depth, color = struct.unpack('>IIBB', data[16:26])
    assert depth == 8 and color == 6, f'{path}: expected 8-bit RGBA'
    return width, height


def verify_transparency(path):
    width, height, rgba = read_png(path)
    alpha = rgba[3::4]
    for x, y in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]:
        assert alpha[y * width + x] == 0, f'{path}: corner ({x},{y}) is not transparent'
    assert alpha[(height // 2) * width + width // 2] == 255, f'{path}: document centre is not opaque'
    assert any(0 < a < 255 for a in alpha), f'{path}: no anti-aliased edge'
    transparent = alpha.count(0) / len(alpha)
    assert 0.08 < transparent < 0.6, f'{path}: unexpected transparent area {transparent:.2f}'


def verify_sources(root=SOURCES, decode_limit=1024):
    root = Path(root)
    expected = {f'Arkiv-{name}.iconset' for name in ICONS}
    present = {p.name for p in root.iterdir() if p.is_dir()}
    assert present == expected, f'Iconsets {sorted(present ^ expected)}'
    listed = {}
    for line in (root / 'SHA256SUMS').read_text().splitlines():
        digest, relative = line.split('  ', 1)
        listed[relative] = digest
    files = set()
    for name in ICONS:
        iconset = root / f'Arkiv-{name}.iconset'
        names = {p.name for p in iconset.iterdir()}
        assert names == {rep_name(pt, s) for pt, s in REPRESENTATIONS}, f'{iconset}: {sorted(names)}'
        for pt, scale in REPRESENTATIONS:
            path = iconset / rep_name(pt, scale)
            assert png_size(path) == (pt * scale, pt * scale), path
            if pt * scale <= decode_limit:
                verify_transparency(path)
            relative = f'{iconset.name}/{path.name}'
            files.add(relative)
            assert hashlib.sha256(path.read_bytes()).hexdigest() == listed.get(relative), f'Checksum mismatch: {relative}'
    assert files == set(listed), 'SHA256SUMS must list exactly the committed representations'


def verify_branding():
    for path, expected in json.loads(Path('branding/app-icon-preservation.json').read_text()).items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, path


def verify_app(app):
    verify_metadata(plistlib.loads((app / 'Contents/Info.plist').read_bytes()))
    verify_branding()
    verify_sources()
    resources = app / 'Contents/Resources'
    packaged = {p.name for p in resources.glob('Arkiv-*.icns')}
    assert packaged == {f'Arkiv-{name}.icns' for name in ICONS}, f'Unexpected document icons: {sorted(packaged)}'
    with tempfile.TemporaryDirectory(prefix='arkiv-icon-verification-') as tmp:
        for name in ICONS:
            icon = resources / f'Arkiv-{name}.icns'
            assert icon.read_bytes()[:4] == b'icns', icon
            output = Path(tmp) / f'{name}.iconset'
            subprocess.run(['iconutil', '-c', 'iconset', str(icon), '-o', str(output)], check=True)
            assert {p.name for p in output.iterdir()} == {rep_name(pt, s) for pt, s in REPRESENTATIONS}, icon
            subprocess.run(['swift', 'scripts/verify-document-icon-images.swift', str(output)], check=True)
    subprocess.run(['swift', 'scripts/diagnose-document-types.swift'], check=True)
    print(f'Packaged {len(ICONS)} archive document icons and original branding verified')


if __name__ == '__main__':
    if len(sys.argv) > 1:
        verify_app(Path(sys.argv[1]))
    else:
        verify_metadata(plistlib.loads(Path('Resources/Info.plist').read_bytes()))
        verify_sources()
        verify_branding()
        print('Document icon sources, registrations and branding verified')
