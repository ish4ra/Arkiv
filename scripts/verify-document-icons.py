#!/usr/bin/env python3
"""Check document-type registrations, committed icon sources, protected app
branding and every packaged ICNS representation.

Usage: verify-document-icons.py [/path/to/Arkiv.app]
Without an app path only the repository (Info.plist, iconset sources,
checksums, branding) is checked; that part needs no macOS tools.
"""
import hashlib
import importlib.util
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
    'TBZ2': 'public.tar-bzip2-archive',
    'TXZ': 'org.tukaani.tar-xz-archive',
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
SYSTEM_DECLARED = {'org.gnu.gnu-zip-tar-archive': ['tgz'], 'public.tar-bzip2-archive': ['tbz2', 'tbz'],
                   'org.tukaani.tar-xz-archive': ['txz']}
# Split-volume and generic numeric suffixes are shared with unrelated software.
GENERIC_EXTENSION = re.compile(r'^(\d+|[a-z]\d{2,}|part\d+)$', re.IGNORECASE)
REPRESENTATIONS = [(pt, scale) for pt in (16, 32, 128, 256, 512) for scale in (1, 2)]
SOURCES = Path('Resources/DocumentIcons')
# Committed PNGs carry only these chunks: no colour profile, gamma or text
# metadata that could change how macOS renders them.
PNG_CHUNKS = {b'IHDR', b'IDAT', b'IEND'}
# ICNS element type -> the iconset representation it holds.
ICNS_TYPES = {'ic04': 'icon_16x16.png', 'icp4': 'icon_16x16.png', 'ic11': 'icon_16x16@2x.png',
              'ic05': 'icon_32x32.png', 'icp5': 'icon_32x32.png', 'ic12': 'icon_32x32@2x.png',
              'ic07': 'icon_128x128.png', 'ic13': 'icon_128x128@2x.png', 'ic08': 'icon_256x256.png',
              'ic14': 'icon_256x256@2x.png', 'ic09': 'icon_512x512.png', 'ic10': 'icon_512x512@2x.png'}


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


def png_chunks(data):
    """Yield (type, body) for every chunk of PNG bytes, checking each CRC."""
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    offset = 8
    while offset < len(data):
        assert offset + 12 <= len(data), 'truncated PNG chunk'
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        assert len(body) == length and offset + 12 + length <= len(data), 'truncated PNG chunk'
        assert struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0] == zlib.crc32(kind + body), 'PNG chunk CRC'
        yield kind, body
        offset += 12 + length


def read_png(path):
    """Return (width, height, rgba bytes) for an 8-bit RGBA, non-interlaced PNG."""
    return decode_png(Path(path).read_bytes(), path)


def decode_png(data, path='PNG data'):
    idat, header = bytearray(), None
    for kind, body in png_chunks(data):
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
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


def pixel_digest(width, height, rgba):
    """Encoder-independent identity of an image: SHA-256 of `WIDTHxHEIGHT\\n` + RGBA bytes.

    Same format as the archived PIXELS.sha256 manifests on
    archive/document-icon-concepts-v2.
    """
    return hashlib.sha256(f'{width}x{height}\n'.encode() + rgba).hexdigest()


def read_manifest(path):
    listed = {}
    for line in Path(path).read_text().splitlines():
        digest, relative = line.split('  ', 1)
        assert relative not in listed, f'{path}: duplicate {relative}'
        listed[relative] = digest
    return listed


def verify_transparency(path, decoded=None):
    width, height, rgba = decoded or read_png(path)
    alpha = rgba[3::4]
    for x, y in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]:
        assert alpha[y * width + x] == 0, f'{path}: corner ({x},{y}) is not transparent'
    assert alpha[(height // 2) * width + width // 2] == 255, f'{path}: document centre is not opaque'
    assert any(0 < a < 255 for a in alpha), f'{path}: no anti-aliased edge'
    transparent = alpha.count(0) / len(alpha)
    assert 0.08 < transparent < 0.6, f'{path}: unexpected transparent area {transparent:.2f}'


def verify_sources(root=SOURCES, decode_limit=1024, pixels=None):
    """Check the committed iconsets. Every representation up to `decode_limit`
    pixels is decoded and must match the decoded-pixel manifest exactly, so a
    lossless re-encode passes and any visible or invisible pixel change fails."""
    root = Path(root)
    expected = {f'Arkiv-{name}.iconset' for name in ICONS}
    present = {p.name for p in root.iterdir() if p.is_dir()}
    assert present == expected, f'Iconsets {sorted(present ^ expected)}'
    listed = read_manifest(root / 'SHA256SUMS')
    pixel_digests = read_manifest(pixels or root / 'PIXELS.sha256')
    assert set(pixel_digests) == set(listed), 'PIXELS.sha256 must list exactly the committed representations'
    files = set()
    for name in ICONS:
        iconset = root / f'Arkiv-{name}.iconset'
        names = {p.name for p in iconset.iterdir()}
        assert names == {rep_name(pt, s) for pt, s in REPRESENTATIONS}, f'{iconset}: {sorted(names)}'
        for pt, scale in REPRESENTATIONS:
            path = iconset / rep_name(pt, scale)
            assert png_size(path) == (pt * scale, pt * scale), path
            relative = f'{iconset.name}/{path.name}'
            data = path.read_bytes()
            kinds = [kind for kind, _ in png_chunks(data)]
            assert set(kinds) <= PNG_CHUNKS and kinds[0] == b'IHDR' and kinds[-1] == b'IEND', f'{path}: chunks {kinds}'
            if pt * scale <= decode_limit:
                decoded = decode_png(data, path)
                verify_transparency(path, decoded)
                assert pixel_digest(*decoded) == pixel_digests[relative], f'Pixels differ from PIXELS.sha256: {relative}'
            files.add(relative)
            assert hashlib.sha256(path.read_bytes()).hexdigest() == listed.get(relative), f'Checksum mismatch: {relative}'
    assert files == set(listed), 'SHA256SUMS must list exactly the committed representations'


def icns_elements(path):
    """Return [(type, payload)] for every element of an ICNS file."""
    return icns_elements_bytes(Path(path).read_bytes(), path)


def icns_elements_bytes(data, path='ICNS data'):
    assert data[:4] == b'icns' and struct.unpack('>I', data[4:8])[0] == len(data), f'{path}: bad ICNS header'
    offset, elements = 8, []
    while offset < len(data):
        kind, length = struct.unpack('>4sI', data[offset:offset + 8])
        assert length >= 8 and offset + length <= len(data), f'{path}: bad ICNS element'
        elements.append((kind.decode('latin-1'), data[offset + 8:offset + length]))
        offset += length
    return elements


def verify_icns(icon, iconset, pixels=None):
    return verify_icns_bytes(Path(icon).read_bytes(), iconset, pixels, icon)


def verify_icns_bytes(data, iconset, pixels=None, icon='ICNS data'):
    """Check that every PNG element in a packaged ICNS decodes to exactly the
    committed pixels of the representation it stands for. Returns
    (element types, PNG elements, PNG elements whose IDAT data is the committed PNG's)."""
    pixel_digests = read_manifest(pixels or SOURCES / 'PIXELS.sha256')
    iconset = Path(iconset)
    kinds, png, identical = [], 0, 0
    for kind, payload in icns_elements_bytes(data, icon):
        kinds.append(kind)
        if not payload.startswith(b'\x89PNG') or kind not in ICNS_TYPES:
            continue
        source = iconset / ICNS_TYPES[kind]
        decoded = decode_png(payload, f'{icon}:{kind}')
        assert pixel_digest(*decoded) == pixel_digests[f'{iconset.name}/{source.name}'], f'{icon}: {kind} pixels differ from {source.name}'
        png += 1
        idat = lambda data: b''.join(body for kind, body in png_chunks(data) if kind == b'IDAT')
        identical += idat(payload) == idat(source.read_bytes())
    return kinds, png, identical


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
    spec = importlib.util.spec_from_file_location('package_icons', Path(__file__).resolve().parent / 'package-document-icons.py')
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    pixels = read_manifest(SOURCES / 'PIXELS.sha256')
    with tempfile.TemporaryDirectory(prefix='arkiv-icon-verification-') as tmp:
        for name in ICONS:
            icon = resources / f'Arkiv-{name}.icns'
            assert icon.read_bytes()[:4] == b'icns', icon
            kinds, png, identical = verify_icns(icon, SOURCES / f'Arkiv-{name}.iconset')
            # The packaged file must be exactly iconutil's output with only
            # verified IDAT swaps, so its structure is the one Apple's tool writes.
            plain = Path(tmp) / f'{name}.icns'
            subprocess.run(['iconutil', '-c', 'icns', str(SOURCES / f'Arkiv-{name}.iconset'), '-o', str(plain)], check=True)
            expected, _ = packager.splice_icns(plain.read_bytes(), SOURCES / f'Arkiv-{name}.iconset', pixels)
            assert icon.read_bytes() == expected, f'{icon}: not the deterministic iconutil-based packaging'
            assert [k for k, _ in icns_elements(icon)] == [k for k, _ in icns_elements(plain)], icon
            print(f'{icon.name}: {icon.stat().st_size:,} bytes (iconutil alone {plain.stat().st_size:,}); '
                  f'elements {" ".join(kinds)}; {png} PNG elements pixel-identical, '
                  f'{identical} carry the committed optimized IDAT data')
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
