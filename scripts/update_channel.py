"""Atomic Git-backed Sparkle feed publication. No keys or signing side effects."""
import os
import subprocess
import xml.etree.ElementTree as ET

FEED = 'https://raw.githubusercontent.com/ish4ra/Arkiv/updates/appcast.xml'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def feed_state(data):
    root = ET.fromstring(data)
    items = root.findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one published update')
    version = items[0].findtext(f'{{{NS}}}version', '')
    if not version.isascii() or not version.isdecimal():
        raise ValueError('Invalid published version')
    enclosure = items[0].find('enclosure')
    expected = f'https://github.com/ish4ra/Arkiv/releases/download/dev-{version}/Arkiv-universal.zip'
    if enclosure is None or enclosure.get('url') != expected:
        raise ValueError('Feed must reference its immutable Universal release')
    return int(version), root.findtext('./channel/link') == FEED


def require_newer(version, previous):
    if not version.isascii() or not version.isdecimal():
        raise ValueError('Invalid candidate version')
    for data in previous:
        if int(version) <= feed_state(data)[0]:
            raise ValueError('Refusing a non-increasing published version')


def legacy_needs_migration(verified_current, verified_legacy):
    if verified_legacy is None:
        if verified_current is None:
            raise ValueError('Missing legacy feed without a verified recovery branch')
        return True  # Retry an interrupted one-time legacy asset replacement.
    return not feed_state(verified_legacy)[1]


def migrate_if_needed(needed, upload):
    if needed:
        upload()


class FeedBranch:
    """Git plumbing leaves the main checkout intact; normal push rejects races.

    Existing unrelated trees are refused. Never delete the ref or force-push.
    The only published tree entry is the byte-identical signed appcast.
    """
    def __init__(self, cwd):
        self.cwd = cwd

    def git(self, *args, input=None):
        env = dict(os.environ, GIT_AUTHOR_NAME='Arkiv Update Publisher',
                   GIT_AUTHOR_EMAIL='updates@users.noreply.github.com',
                   GIT_COMMITTER_NAME='Arkiv Update Publisher',
                   GIT_COMMITTER_EMAIL='updates@users.noreply.github.com')
        return subprocess.check_output(['git', *args], cwd=self.cwd, input=input, env=env)

    def read(self):
        # Successful empty output means absent; network/auth failures raise.
        if not self.git('ls-remote', '--heads', 'origin', 'refs/heads/updates').strip():
            return None
        self.git('fetch', '--no-tags', 'origin', 'refs/heads/updates')
        parent = self.git('rev-parse', 'FETCH_HEAD').decode().strip()
        entries = self.git('ls-tree', parent).decode().splitlines()
        if len(entries) != 1 or not entries[0].startswith('100644 blob ') or not entries[0].endswith('\tappcast.xml'):
            raise ValueError('Refusing unrelated update branch contents')
        return parent, self.git('show', parent + ':appcast.xml')

    def advance(self, data, parent):
        blob = self.git('hash-object', '-w', '--stdin', input=data).decode().strip()
        tree = self.git('mktree', input=f'100644 blob {blob}\tappcast.xml\n'.encode()).decode().strip()
        args = ['commit-tree', tree]
        if parent: args += ['-p', parent]
        commit = self.git(*args, input=b'Publish signed Arkiv development appcast\n').decode().strip()
        self.git('push', 'origin', commit + ':refs/heads/updates')
        return commit


def publish_transaction(create_payload, verify_payload, advance_feed, migrate_legacy, verify_feed):
    create_payload()
    verify_payload()
    advance_feed()
    verify_feed()
    migrate_legacy()
