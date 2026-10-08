"""Registration regressions: validate both source metadata and a packaged plist copy."""
import copy
import plistlib
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / 'scripts/verify-finder-services.py'
validate = runpy.run_path(str(VERIFY))['validate']


class FileServiceRegistrationTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())

    def test_current_source_is_a_file_service_provider(self):
        validate(self.info)

    def test_rejects_previous_pasteboard_registration(self):
        for service in self.info['NSServices']:
            service.pop('NSSendFileTypes')
            service['NSSendTypes'] = ['public.file-url', 'NSFilenamesPboardType']
            service['NSRequiredContext'] = {'NSTextContentFileTypes': ['public.zip-archive', 'public.tar-archive']}
        with self.assertRaisesRegex(ValueError, 'NSSendFileTypes'):
            validate(self.info)

    def test_rejects_legacy_submenu_for_each_action(self):
        for index in range(4):
            with self.subTest(index=index):
                info = copy.deepcopy(self.info)
                title = info['NSServices'][index]['NSMenuItem']['default']
                info['NSServices'][index]['NSMenuItem']['default'] = 'Arkiv/' + title
                with self.assertRaisesRegex(ValueError, 'direct service titles'):
                    validate(info)

    def test_rejects_context_filter_and_unused_pasteboard_keys(self):
        for key, value in [('NSRequiredContext', {'NSTextContentFileTypes': ['public.zip-archive']}),
                           ('NSSendTypes', ['public.file-url']), ('NSReturnTypes', [])]:
            with self.subTest(key=key):
                info = copy.deepcopy(self.info)
                info['NSServices'][0][key] = value
                with self.assertRaises(ValueError):
                    validate(info)

    def test_rejects_missing_or_broadened_file_types(self):
        for types in [[], ['public.zip-archive'], ['public.data'], ['public.zip-archive', 'public.tar-archive', 'public.item']]:
            with self.subTest(types=types):
                self.info['NSServices'][0]['NSSendFileTypes'] = types
                with self.assertRaisesRegex(ValueError, 'NSSendFileTypes'):
                    validate(self.info)

    def test_validates_given_packaged_file_instead_of_source(self):
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / 'Arkiv.app/Contents/Info.plist'
            plist.parent.mkdir(parents=True)
            plist.write_bytes(plistlib.dumps(self.info))
            self.assertEqual(subprocess.run([sys.executable, str(VERIFY), str(plist)], capture_output=True).returncode, 0)
            self.info['NSServices'][0].pop('NSSendFileTypes')
            plist.write_bytes(plistlib.dumps(self.info))
            self.assertNotEqual(subprocess.run([sys.executable, str(VERIFY), str(plist)], capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
