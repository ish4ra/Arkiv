"""The format and document-icon coverage table agrees with the engine, the
Info.plist registrations, the bundled artwork and the theme packs. Adding an
archive format without its icon coverage fails here."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / 'docs/format-icon-coverage.json').read_text())
ROWS = DATA['rows']
INFO = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
ICONS = ['ZIP', '7z', 'TAR', 'RAR', 'GZIP', 'BZIP2', 'XZ', 'ZSTD', 'TGZ', 'TBZ2', 'TXZ']


def swift_extras():
    source = (ROOT / 'Sources/ArkivThemes/ThemeModels.swift').read_text()
    block = source[source.index('public enum DocumentIconExtra'):]
    block = block[:block.index('public var fallback')]
    return re.findall(r'= "([^"]+)"', block)


class CoverageTests(unittest.TestCase):
    def test_every_creation_suffix_is_covered(self):
        creator = (ROOT / 'Sources/ArkivCore/ArchiveCreator.swift').read_text()
        suffixes = set(re.findall(r'case \.\w+: return "(\.[a-z0-9.]+)"', creator))
        self.assertGreaterEqual(len(suffixes), 15)
        created = {row['create'] for row in ROWS if row['create']}
        self.assertEqual(suffixes - created, set(), 'A creation format has no coverage row')
        self.assertIn('.7z.001', created, 'Split 7z creation')

    def test_supported_rows_have_artwork_and_registrations(self):
        types = {}
        for t in INFO['CFBundleDocumentTypes']:
            for uti in t['LSItemContentTypes']:
                types[uti] = t['CFBundleTypeIconFile']
        extras = swift_extras()
        for row in ROWS:
            status = row['status']
            self.assertIn(status, DATA['statuses'], row['name'])
            if status in ('supported', 'finder-limited'):
                self.assertIn(row['inApp'], ICONS + extras, f"{row['name']}: no artwork inside Arkiv")
                if row['finderType']:
                    self.assertEqual(types.get(row['finderType']), f"Arkiv-{row['finderIcon']}.icns", row['name'])
            if status == 'finder-limited':
                self.assertNotEqual(row['inApp'], row['finderIcon'], row['name'])
            if status in ('planned', 'unrelated'):
                if row['inApp'] is not None:
                    self.assertIn(row['inApp'], ICONS, f"{row['name']}: planned formats use no dedicated artwork")

    def test_unsupported_and_generic_suffixes_are_never_claimed(self):
        claimed = set()
        for d in INFO.get('UTImportedTypeDeclarations', []) + INFO.get('UTExportedTypeDeclarations', []):
            claimed |= set(d.get('UTTypeTagSpecification', {}).get('public.filename-extension', []))
        for t in INFO['CFBundleDocumentTypes']:
            claimed |= set(t.get('CFBundleTypeExtensions', []))
        for row in ROWS:
            if row['status'] in ('planned', 'unrelated') or row['name'].endswith(('.001', '.002', '.0123')):
                last = row['name'].rsplit('.', 1)[1].lower()
                if last != 'rar':
                    self.assertNotIn(last, claimed, row['name'])

    def test_extras_agree_everywhere(self):
        extras = swift_extras()
        build = (ROOT / 'design/document-icon-themes/build.py').read_text()
        verify = (ROOT / 'scripts/verify-document-icons.py').read_text()
        listed = "['TAR.GZ', 'TAR.BZ2', 'TAR.XZ', 'TAR.ZST', 'TZST', '7z-volume']"
        self.assertEqual(str(extras), listed)
        self.assertIn(f'INAPP_EXTRAS = {listed}', build)
        self.assertIn(f'INAPP_EXTRAS = {listed}', verify)
        bundled = sorted(p.name for p in (ROOT / 'Resources/DocumentIconsInApp').iterdir() if p.is_dir())
        self.assertEqual(bundled, sorted(f'Arkiv-{e}' for e in extras), 'Bundled Seal Dark extras')
        themes = json.loads((ROOT / 'design/document-icon-themes/themes.json').read_text())
        self.assertTrue(set(extras) <= set(themes['extras']), 'Every pack format carries the in-app extras')

    def test_every_theme_covers_every_supported_format(self):
        inventory = json.loads((ROOT / 'design/document-icon-themes/inventory.json').read_text())
        for theme in inventory['themes']:
            if theme['id'] == 'classic':
                continue  # the pre-redesign reproduction: ZIP, 7z, TAR, RAR only (documented)
            self.assertEqual(theme['coverage'], '11/11 icons, 8/8 extras', theme['id'])

    def test_page_is_generated(self):
        subprocess.run([sys.executable, str(ROOT / 'scripts/format-icon-coverage.py'), '--check'], check=True)


if __name__ == '__main__':
    unittest.main()
