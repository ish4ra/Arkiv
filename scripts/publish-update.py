#!/usr/bin/env python3
"""CI-only publisher. Secrets stay in memory/stdin, never argv/files/logs."""
import os
import json
import hashlib
import time
from update_channel import FEED, FeedBranch, feed_state, require_newer, publish_transaction, legacy_needs_migration, migrate_if_needed
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
import urllib.error
import urllib.request

key = os.environ.pop('SPARKLE_PRIVATE_ED_KEY', '').strip()
if not key or not os.environ.get('SPARKLE_PUBLIC_ED_KEY', '').strip():
    print('::notice::Development update publishing skipped: configure SPARKLE_PRIVATE_ED_KEY secret and SPARKLE_PUBLIC_ED_KEY variable.')
    sys.exit(0)

# Reject accidental inclusion of the configured secret in any tracked file.
files = subprocess.check_output(['git', 'ls-files', '-z']).split(b'\0')
for name in files:
    if name and key.encode() in Path(os.fsdecode(name)).read_bytes():
        raise SystemExit('Private signing material detected in tracked content; publication refused')


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def sign(args):
    # Suppress even error output: no signing-tool failure can echo the secret.
    result = subprocess.run([str(tool), '--ed-key-file', '-', *args], input=key,
                            text=True, capture_output=True)
    if result.returncode:
        raise SystemExit('Sparkle signing/verification failed; private diagnostic output suppressed')
    return result.stdout.strip()


app = Path('build/Arkiv.app')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleVersion']
if info.get('SUPublicEDKey') != os.environ['SPARKLE_PUBLIC_ED_KEY'].strip():
    raise SystemExit('Payload public key does not match configured key')
if info.get('SUFeedURL') != FEED:
    raise SystemExit('Payload must use the atomic update feed')
if info.get('SURequireSignedFeed') is not True:
    raise SystemExit('Payload must require signed feeds')
tool = next(Path('.build/artifacts').glob('**/bin/sign_update'))
archive = Path('build/Arkiv-universal.zip')
signature = sign(['-p', str(archive)])
run(['swift', 'scripts/verify-update-signature.swift', str(app / 'Contents/Info.plist'), str(archive), signature])
feed = Path('build/appcast.xml')
run(['python3', 'scripts/update-feed.py', str(app / 'Contents/Info.plist'), str(archive), str(feed), '--signature', signature])
sign([str(feed)])
sign(['--verify', str(feed)])

# Read the branch through Git (not a possibly stale raw CDN response). Its
# signatures and version must validate before creating any new public release.
repo = 'ish4ra/Arkiv'
channel = 'development-updates'
branch = FeedBranch(Path.cwd())
current = branch.read()
previous = []
if current:
    previous_feed = Path('build/previous-branch-appcast.xml')
    previous_feed.write_bytes(current[1])
    sign(['--verify', str(previous_feed)])
    previous.append(current[1])

# Legacy is retained indefinitely as a migration bridge. Distinguish a missing
# asset (interrupted one-time replacement) from a network/auth/release error.
release = json.loads(subprocess.check_output(['gh', 'release', 'view', channel, '--repo', repo, '--json', 'assets']))
assets = [asset for asset in release['assets'] if asset['name'] == 'appcast.xml']
if len(assets) > 1:
    raise SystemExit('Ambiguous legacy feed assets')
legacy = None
if assets:
    old = Path('build/previous-feed')
    old.mkdir(exist_ok=True)
    run(['gh', 'release', 'download', channel, '--repo', repo, '--pattern', 'appcast.xml', '--dir', str(old), '--clobber'])
    legacy = (old / 'appcast.xml').read_bytes()
    sign(['--verify', str(old / 'appcast.xml')])
    previous.append(legacy)
needs_migration = legacy_needs_migration(current[1] if current else None, legacy)
require_newer(version, previous)

# Validate generated metadata again after feed signing, which adds an XML comment.
feed_module = __import__('runpy').run_path('scripts/update-feed.py')
feed_module['validate'](ET.parse(feed).getroot(), info, archive, True)
feed_state(feed.read_bytes())


def verify_public(url, expected, destination):
    # CDN propagation may serve an older *valid* appcast. Never delete the old
    # feed; wait for byte-identical new content. Query avoids stale cache entries.
    for attempt in range(12):
        try:
            request = urllib.request.Request(url + '?arkiv-build=' + version + '-' + str(attempt),
                                             headers={'Cache-Control': 'no-cache'})
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(len(expected) + 1)
            if hashlib.sha256(data).digest() == hashlib.sha256(expected).digest():
                destination.write_bytes(data)
                return
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(5)
    raise SystemExit('Public update content unavailable or mismatched; publication stopped')


tag = 'dev-' + version
payload_url = f'https://github.com/{repo}/releases/download/{tag}/Arkiv-universal.zip'


def create_payload():
    # No --clobber: an existing immutable release is an error, never overwritten.
    run(['gh', 'release', 'create', tag, str(archive), str(feed), '--repo', repo,
         '--target', os.environ['GITHUB_SHA'], '--prerelease', '--title', 'Arkiv Development ' + version,
         '--notes', 'Development/testing build. Universal Intel + Apple Silicon. Ad-hoc signed, not notarized. Sparkle EdDSA-signed update.'])


def verify_payload():
    downloaded = Path('build/downloaded-update.zip')
    verify_public(payload_url, archive.read_bytes(), downloaded)
    run(['swift', 'scripts/verify-update-signature.swift', str(app / 'Contents/Info.plist'), str(downloaded), signature])


def verify_feed():
    downloaded = Path('build/downloaded-appcast.xml')
    verify_public(FEED, feed.read_bytes(), downloaded)
    sign(['--verify', str(downloaded)])
    if feed_state(downloaded.read_bytes())[0] != int(version):
        raise SystemExit('Published feed version mismatch')


def migrate_legacy():
    if needs_migration:
        # One final replacement is unavoidable for installed legacy clients.
        # Future runs leave this signed migration feed untouched.
        run(['gh', 'release', 'upload', channel, str(feed), '--repo', repo, '--clobber'])
        downloaded = Path('build/migration-appcast.xml')
        verify_public(f'https://github.com/{repo}/releases/download/{channel}/appcast.xml', feed.read_bytes(), downloaded)
        sign(['--verify', str(downloaded)])
        print('Legacy feed now points to the migration build; future publications leave it unchanged')



if not needs_migration:
    print('Legacy migration feed preserved unchanged')
publish_transaction(create_payload, verify_payload,
                    lambda: branch.advance(feed.read_bytes(), current[0] if current else None),
                    lambda: migrate_if_needed(needs_migration, migrate_legacy), verify_feed)
print('Published and verified signed Universal development update ' + version + ' through atomic feed')
