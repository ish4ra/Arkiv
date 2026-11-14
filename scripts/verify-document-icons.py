#!/usr/bin/env python3
"""Check registrations, protected branding and every packaged ICNS representation."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

FORMATS = {'ZIP': 'public.zip-archive', 'TAR': 'public.tar-archive',
           '7z': 'org.7-zip.7-zip-archive', 'RAR': 'com.rarlab.rar-archive'}

STREAM_FORMATS = {'org.gnu.gnu-zip-archive': 'gz', 'public.bzip2-archive': 'bz2', 'org.tukaani.xz-archive': 'xz'}

def verify_metadata(info):
    assert info['CFBundleIconFile'] == 'Arkiv'
    assert info['CFBundleIdentifier'] == 'xyz.isharalakshan.arkiv'
    declarations = info['CFBundleDocumentTypes']
    assert len(declarations) == 4 + len(STREAM_FORMATS)
    for name, uti in FORMATS.items():
        matches = [d for d in declarations if d['LSItemContentTypes'] == [uti]]
        assert len(matches) == 1
        d = matches[0]
        assert d['CFBundleTypeIconFile'] == f'Arkiv-{name}.icns'
        assert d['CFBundleTypeRole'] == 'Viewer' and d['LSHandlerRank'] == 'Alternate'
    imported = {d['UTTypeIdentifier']: d for d in info['UTImportedTypeDeclarations']}
    assert set(imported) == {FORMATS['7z'], FORMATS['RAR']} | set(STREAM_FORMATS)
    for uti, ext in STREAM_FORMATS.items():
        matches = [d for d in declarations if d['LSItemContentTypes'] == [uti]]
        assert len(matches) == 1
        assert matches[0]['CFBundleTypeRole'] == 'Viewer' and matches[0]['LSHandlerRank'] == 'Alternate'
        assert 'CFBundleTypeIconFile' not in matches[0], 'No new document artwork claimed'
        assert imported[uti]['UTTypeTagSpecification']['public.filename-extension'] == [ext]
        assert imported[uti]['UTTypeConformsTo'] == ['public.archive']
    for name, ext in [('7z', '7z'), ('RAR', 'rar')]:
        assert imported[FORMATS[name]]['UTTypeTagSpecification']['public.filename-extension'] == [ext]
    assert not info.get('UTExportedTypeDeclarations'), 'Arkiv does not own these standard formats'

def verify_branding():
    for path, expected in json.loads(Path('branding/app-icon-preservation.json').read_text()).items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, path

def verify_app(app):
    verify_metadata(plistlib.loads((app / 'Contents/Info.plist').read_bytes()))
    verify_branding()
    with tempfile.TemporaryDirectory(prefix='arkiv-icon-verification-') as tmp:
        for name in FORMATS:
            icon = app / f'Contents/Resources/Arkiv-{name}.icns'
            assert icon.read_bytes()[:4] == b'icns', icon
            output = Path(tmp) / f'{name}.iconset'
            subprocess.run(['iconutil', '-c', 'iconset', str(icon), '-o', str(output)], check=True)
            subprocess.run(['swift', 'scripts/verify-document-icon-images.swift', str(output)], check=True)
    print('Packaged archive document icons and original branding verified')

if __name__ == '__main__':
    verify_app(Path(sys.argv[1]))
