import copy
import importlib.util
from pathlib import Path
import plistlib
import unittest
spec = importlib.util.spec_from_file_location('icons', 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)

class DocumentIconTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads(Path('Resources/Info.plist').read_bytes())

    def test_supported_viewer_alternate_registrations(self):
        icons.verify_metadata(self.info)

    def test_original_artwork_preserved(self):
        icons.verify_branding()

    def test_bad_icon_and_default_claim_rejected(self):
        for field, value in [('CFBundleTypeIconFile', 'Missing.icns'), ('LSHandlerRank', 'Owner'), ('CFBundleTypeRole', 'Editor')]:
            changed = copy.deepcopy(self.info)
            changed['CFBundleDocumentTypes'][0][field] = value
            with self.assertRaises(AssertionError):
                icons.verify_metadata(changed)

    def test_build_and_packaged_verification_hooks(self):
        self.assertIn('render-document-icons.swift', Path('scripts/build-app.sh').read_text())
        self.assertIn('verify-document-icons.py', Path('scripts/verify-app.sh').read_text())

if __name__ == '__main__':
    unittest.main()
