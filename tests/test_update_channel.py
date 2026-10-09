"""Publication transactions use a real local Git remote; HTTP is injected."""
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'scripts/update_channel.py'


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), 'Atomic update branch publisher is missing')
        self.api = runpy.run_path(str(MODULE))

    def test_monotonic_and_migration_policy(self):
        feed = self.api['feed_state']
        xml = b'<rss><channel><item><sparkle:version xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">12801</sparkle:version><enclosure url="https://github.com/ish4ra/Arkiv/releases/download/dev-12801/Arkiv-universal.zip"/></item></channel></rss>'
        self.assertEqual(feed(xml), (12801, False))
        migrated = xml.replace(b'<channel>', b'<channel><link>' + self.api['FEED'].encode() + b'</link>')
        self.assertEqual(feed(migrated), (12801, True))
        for candidate in ['12801', '12701']:
            with self.assertRaises(ValueError): self.api['require_newer'](candidate, [xml])
        self.api['require_newer']('12901', [xml, migrated])
        with self.assertRaises(ValueError): feed(xml.replace(b'dev-12801/', b'dev-999/'))

    def test_missing_legacy_asset_recovers_only_with_verified_branch(self):
        policy = self.api.get('legacy_needs_migration')
        self.assertIsNotNone(policy, 'Missing migration recovery policy')
        with self.assertRaises(ValueError): policy(None, None)
        self.assertTrue(policy(b'verified branch bytes', None))

    def test_migrated_legacy_is_never_uploaded_again(self):
        xml = b'<rss><channel><link>' + self.api['FEED'].encode() + b'</link><item><sparkle:version xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">12901</sparkle:version><enclosure url="https://github.com/ish4ra/Arkiv/releases/download/dev-12901/Arkiv-universal.zip"/></item></channel></rss>'
        uploads = []
        needed = self.api['legacy_needs_migration'](xml, xml)
        self.api['migrate_if_needed'](needed, lambda: uploads.append('upload'))
        self.assertEqual(uploads, [])
        needed = self.api['legacy_needs_migration'](xml, None)
        self.api['migrate_if_needed'](needed, lambda: uploads.append('upload'))
        self.assertEqual(uploads, ['upload'])

    def test_payload_failure_never_advances_either_feed(self):
        calls = []
        def unavailable():
            calls.append('verify payload')
            raise ValueError('unavailable')
        with self.assertRaises(ValueError):
            self.api['publish_transaction'](lambda: calls.append('release'), unavailable,
                lambda: calls.append('branch'), lambda: calls.append('legacy'), lambda: calls.append('check'))
        self.assertEqual(calls, ['release', 'verify payload'])

    def test_branch_failure_never_replaces_legacy(self):
        calls = []
        def rejected():
            calls.append('branch')
            raise ValueError('rejected')
        with self.assertRaises(ValueError):
            self.api['publish_transaction'](lambda: calls.append('release'), lambda: calls.append('payload'),
                rejected, lambda: calls.append('legacy'), lambda: calls.append('check'))
        self.assertEqual(calls, ['release', 'payload', 'branch'])

    def test_publish_order(self):
        calls = []
        self.api['publish_transaction'](*[lambda name=name: calls.append(name)
            for name in ['release', 'payload', 'branch', 'legacy', 'check']])
        self.assertEqual(calls, ['release', 'payload', 'branch', 'check', 'legacy'])

    def test_real_git_branch_preserves_live_feed_and_rejects_races(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args, cwd=root):
                return subprocess.check_output(['git', *args], cwd=cwd, stderr=subprocess.DEVNULL).decode().strip()
            git('init', '--bare', 'remote.git')
            git('init', 'work')
            work = root / 'work'
            git('remote', 'add', 'origin', str(root / 'remote.git'), cwd=work)
            branch = self.api['FeedBranch'](work)
            self.assertIsNone(branch.read())
            first = branch.advance(b'first signed feed', None)
            self.assertEqual(branch.read(), (first, b'first signed feed'))
            second = branch.advance(b'second signed feed', first)
            self.assertEqual(git('show', first + ':appcast.xml', cwd=work), 'first signed feed')
            self.assertEqual(git('show', second + ':appcast.xml', cwd=work), 'second signed feed')
            self.assertEqual(git('rev-parse', second + '^', cwd=work), first)
            with self.assertRaises(subprocess.CalledProcessError): branch.advance(b'stale feed', first)
            self.assertEqual(branch.read(), (second, b'second signed feed'))
            self.assertEqual(git('ls-tree', '--name-only', second, cwd=work), 'appcast.xml')

    def test_unrelated_branch_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
            git('init'); git('config', 'user.name', 'Test'); git('config', 'user.email', 'test@example.invalid')
            (root / 'unrelated.txt').write_text('preserve')
            git('add', '.'); git('commit', '-m', 'unrelated'); git('branch', 'updates')
            git('remote', 'add', 'origin', str(root))
            with self.assertRaises(ValueError): self.api['FeedBranch'](root).read()


if __name__ == '__main__': unittest.main()
