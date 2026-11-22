import copy
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('icons', 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)


class DocumentIconTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads(Path('Resources/Info.plist').read_bytes())

    # Registrations -----------------------------------------------------------
    def test_supported_viewer_alternate_registrations(self):
        icons.verify_metadata(self.info)

    def test_every_supported_format_has_its_own_icon(self):
        declared = {d['LSItemContentTypes'][0]: d['CFBundleTypeIconFile'] for d in self.info['CFBundleDocumentTypes']}
        self.assertEqual(set(declared), set(icons.ICONS.values()))
        self.assertEqual(len(set(declared.values())), len(icons.ICONS), 'No two document types share artwork')

    def test_registration_never_claims_default_handler(self):
        for uti in icons.ICONS.values():
            for field, value in [('LSHandlerRank', 'Owner'), ('LSHandlerRank', 'Default'), ('CFBundleTypeRole', 'Editor')]:
                changed = copy.deepcopy(self.info)
                next(d for d in changed['CFBundleDocumentTypes'] if d['LSItemContentTypes'] == [uti])[field] = value
                with self.assertRaises(AssertionError):
                    icons.verify_metadata(changed)

    def test_stream_registration_keeps_existing_default_handlers(self):
        for uti in icons.STREAM_FORMATS:
            changed = copy.deepcopy(self.info)
            next(d for d in changed['CFBundleDocumentTypes'] if d['LSItemContentTypes'] == [uti])['LSHandlerRank'] = 'Owner'
            with self.assertRaises(AssertionError):
                icons.verify_metadata(changed)

    def test_bad_icon_reference_rejected(self):
        changed = copy.deepcopy(self.info)
        changed['CFBundleDocumentTypes'][0]['CFBundleTypeIconFile'] = 'Missing.icns'
        with self.assertRaises(AssertionError):
            icons.verify_metadata(changed)

    def test_alias_mappings(self):
        imported = {d['UTTypeIdentifier']: d['UTTypeTagSpecification']['public.filename-extension']
                    for d in self.info['UTImportedTypeDeclarations']}
        extensions = [e for values in imported.values() for e in values]
        # .tgz: attached to the macOS-declared type; never redeclared by Arkiv.
        self.assertIn('org.gnu.gnu-zip-tar-archive', icons.ICONS.values())
        self.assertNotIn('org.gnu.gnu-zip-tar-archive', imported)
        self.assertNotIn('tgz', extensions)
        # .tbz2/.tbz and .txz: macOS-declared types, likewise never redeclared.
        for uti in ['public.tar-bzip2-archive', 'org.tukaani.tar-xz-archive']:
            self.assertIn(uti, icons.ICONS.values())
            self.assertNotIn(uti, imported)
        self.assertEqual(set(icons.SYSTEM_DECLARED), {'org.gnu.gnu-zip-tar-archive', 'public.tar-bzip2-archive', 'org.tukaani.tar-xz-archive'})
        # .tzst stays on the existing Zstandard type so current associations do not move.
        self.assertEqual(imported['org.zstandard.zstd'], ['zst', 'tzst'])
        # No alias or double suffix is declared by Arkiv itself.
        for ext in ['tbz2', 'tbz', 'txz', 'tar.gz', 'tar.bz2', 'tar.xz', 'tar.zst']:
            self.assertNotIn(ext, extensions)
        changed = copy.deepcopy(self.info)
        changed['UTImportedTypeDeclarations'].append({'UTTypeIdentifier': 'org.gnu.gnu-zip-tar-archive', 'UTTypeConformsTo': ['public.archive'],
                                                      'UTTypeTagSpecification': {'public.filename-extension': ['tgz']}})
        with self.assertRaises(AssertionError):
            icons.verify_metadata(changed)

    def test_no_generic_numeric_extension_registration(self):
        icons.verify_no_generic_extensions(self.info)
        text = Path('Resources/Info.plist').read_text()
        for ext in ['001', '002', '003', 'z01', 'r00', 'part1']:
            self.assertNotIn(f'<string>{ext}</string>', text)
        for ext in ['001', 'z01', 'r00', 'part1']:
            changed = copy.deepcopy(self.info)
            changed['UTImportedTypeDeclarations'][0]['UTTypeTagSpecification']['public.filename-extension'].append(ext)
            with self.assertRaises(AssertionError):
                icons.verify_no_generic_extensions(changed)

    # Icon sources --------------------------------------------------------------
    def test_iconset_sizes_transparency_and_checksums(self):
        icons.verify_sources()

    def test_tampered_or_missing_representation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'DocumentIcons'
            shutil.copytree(icons.SOURCES, root)
            target = root / 'Arkiv-ZIP.iconset/icon_16x16.png'
            target.write_bytes(target.read_bytes() + b'\0')
            with self.assertRaises(AssertionError):
                icons.verify_sources(root, decode_limit=0)
            shutil.copytree(icons.SOURCES, root, dirs_exist_ok=True)
            (root / 'Arkiv-ZIP.iconset/icon_512x512@2x.png').unlink()
            with self.assertRaises(AssertionError):
                icons.verify_sources(root, decode_limit=0)

    def test_png_decoder_detects_opaque_corners(self):
        width, height, rgba = icons.read_png(icons.SOURCES / 'Arkiv-7z.iconset/icon_32x32.png')
        self.assertEqual((width, height), (32, 32))
        self.assertEqual(rgba[3], 0)
        self.assertEqual(rgba[((16 * 32) + 16) * 4 + 3], 255)

    def test_generator_table_matches_verification(self):
        config = Path('design/document-icons/generate-config.mjs').read_text()
        names = set(re.findall(r"^\s+'?([\w.]+)'?: \{ format:", config, re.M))
        self.assertEqual(names, set(icons.ICONS))
        for path in ['design/document-icons/generate.mjs', 'design/document-icons/seal-dark.mjs',
                     'design/document-icons/outline.mjs', 'design/document-icons/fonts/OFL.txt',
                     'design/document-icons/package-lock.json']:
            self.assertTrue(Path(path).is_file(), path)

    # Branding and packaging ----------------------------------------------------
    def test_original_artwork_preserved(self):
        icons.verify_branding()
        pins = Path('branding/app-icon-preservation.json').read_text()
        self.assertIn('scripts/render-icon.swift', pins)

    def test_build_and_packaged_verification_hooks(self):
        build = Path('scripts/build-app.sh').read_text()
        self.assertIn('shasum -a 256 -c SHA256SUMS', build)
        self.assertIn('Resources/DocumentIcons/Arkiv-*.iconset', build)
        self.assertIn('iconutil -c icns "$iconset"', build)
        self.assertIn('swift scripts/render-icon.swift', build, 'App icon still comes from its original renderer')
        self.assertNotIn('render-document-icons.swift', build)
        for tool in ['node ', 'npm ', 'npx ', 'playwright']:
            self.assertNotIn(tool, build, 'Icon generation is design-time only')
        self.assertIn('verify-document-icons.py', Path('scripts/verify-app.sh').read_text())
        self.assertTrue(Path('scripts/diagnose-document-types.swift').is_file())

    def test_design_sources_stay_out_of_runtime(self):
        package = Path('Package.swift').read_text()
        self.assertNotIn('design/', package)
        self.assertNotIn('DocumentIcons', package)
        ignored = Path('design/document-icons/.gitignore').read_text()
        self.assertIn('node_modules/', ignored)
        self.assertIn('out/', ignored)


if __name__ == '__main__':
    unittest.main()
