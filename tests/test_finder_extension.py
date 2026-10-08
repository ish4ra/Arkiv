import copy
from pathlib import Path
import plistlib
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
metadata = runpy.run_path(str(ROOT / 'scripts/finder-extension-metadata.py'))


class FinderExtensionMetadataTests(unittest.TestCase):
    def setUp(self):
        self.app = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        self.app['CFBundleVersion'] = '12345'
        self.extension = metadata['expected'](self.app)

    def test_matching_version_and_extension_contract(self):
        metadata['validate'](self.extension, self.app)
        self.assertEqual(self.extension['CFBundleVersion'], '12345')

    def test_rejects_stale_version_wrong_identity_or_principal(self):
        for key, value in [('CFBundleVersion', '3'), ('CFBundleIdentifier', 'other.app'),
                           ('NSExtension', {'NSExtensionPointIdentifier': 'wrong'})]:
            info = copy.deepcopy(self.extension)
            info[key] = value
            with self.assertRaises(ValueError):
                metadata['validate'](info, self.app)

    def test_rejects_missing_handoff_registration(self):
        self.app.pop('CFBundleURLTypes')
        with self.assertRaises(ValueError):
            metadata['validate'](self.extension, self.app)

    def test_minimal_sandbox_permissions(self):
        entitlements = plistlib.loads((ROOT / 'Resources/FinderSync.entitlements').read_bytes())
        self.assertEqual(entitlements, {'com.apple.security.app-sandbox': True,
                                       'com.apple.security.files.user-selected.read-only': True})


if __name__ == '__main__':
    unittest.main()
