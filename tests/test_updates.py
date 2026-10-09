import base64
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
metadata = runpy.run_path(str(ROOT / 'scripts/update-metadata.py'))
feed = runpy.run_path(str(ROOT / 'scripts/update-feed.py'))


class UpdateTests(unittest.TestCase):
    def test_atomic_feed_url_is_embedded(self):
        info = metadata['configured']({}, {})
        self.assertEqual(info['SUFeedURL'],
                         'https://raw.githubusercontent.com/ish4ra/Arkiv/updates/appcast.xml')

    def test_keyless_build_is_not_configured(self):
        info = metadata['configured']({}, {})
        self.assertNotIn('SUPublicEDKey', info)
        self.assertTrue(info['SURequireSignedFeed'])
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
        self.assertEqual(info['SUSignedFeedFailureExpirationInterval'], 0)
        self.assertFalse(info['SUAllowsAutomaticUpdates'])

    def test_rejects_invalid_public_keys_and_versions(self):
        for key in ['not base64', base64.b64encode(b'x' * 31).decode()]:
            with self.assertRaises(ValueError):
                metadata['configured']({}, {'SPARKLE_PUBLIC_ED_KEY': key})
        for version in ['2', '-1', 'abc', '4.5', '１２']:
            with self.assertRaises(ValueError):
                metadata['configured']({}, {'ARKIV_BUILD_VERSION': version})

    def test_public_configuration_and_unsigned_feed_rejected(self):
        info = metadata['configured']({'CFBundleShortVersionString': '0.1.0'},
                                      {'ARKIV_BUILD_VERSION': '12001', 'SPARKLE_PUBLIC_ED_KEY': base64.b64encode(bytes(32)).decode()})
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'Arkiv-universal.zip'
            archive.write_bytes(b'fixture')
            root = feed['create'](info, archive)
            feed['validate'](root, info, archive, False)
            with self.assertRaisesRegex(ValueError, 'require EdDSA'):
                feed['validate'](root, info, archive, True)
            with self.assertRaises(ValueError):
                feed['create'](info, archive, 'bad-signature')

    def test_tampered_enclosure_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'Arkiv-universal.zip'
            archive.write_bytes(b'fixture')
            info = {'CFBundleVersion': '12001', 'CFBundleShortVersionString': '0.1.0'}
            root = feed['create'](info, archive)
            root.find('./channel/item/enclosure').set('url', 'http://attacker.invalid/update.zip')
            with self.assertRaises(ValueError):
                feed['validate'](root, info, archive, False)


if __name__ == '__main__':
    unittest.main()
