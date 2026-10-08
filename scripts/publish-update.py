#!/usr/bin/env python3
"""CI-only publisher. Secrets stay in memory/stdin, never argv/files/logs."""
import os
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

# Serialized job plus remote monotonicity check prevents an older queued run from
# replacing a newer feed. Any unexpected network/API error fails closed.
repo = 'ish4ra/Arkiv'
channel = 'development-updates'
request = urllib.request.Request(
    f'https://api.github.com/repos/{repo}/releases/tags/{channel}',
    headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
             'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        exists = response.status == 200
        if not exists:
            raise SystemExit('Unexpected channel lookup response; publication refused')
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise SystemExit('Channel lookup failed; publication refused') from None
    exists = False
except urllib.error.URLError:
    raise SystemExit('Channel lookup unavailable; publication refused') from None
if exists:
    old = Path('build/previous-feed')
    old.mkdir(exist_ok=True)
    run(['gh', 'release', 'download', channel, '--repo', repo, '--pattern', 'appcast.xml', '--dir', str(old), '--clobber'])
    previous = ET.parse(old / 'appcast.xml').find('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
    if previous is None or int(previous.text) >= int(version):
        raise SystemExit('Refusing to replace the channel with a non-increasing version')

# Publish immutable payload first; switch the stable feed asset only afterwards.
tag = 'dev-' + version
run(['gh', 'release', 'create', tag, str(archive), str(feed), '--repo', repo,
     '--target', os.environ['GITHUB_SHA'], '--prerelease', '--title', 'Arkiv Development ' + version,
     '--notes', 'Development/testing build. Universal Intel + Apple Silicon. Ad-hoc signed, not notarized. Sparkle EdDSA-signed update.'])
if not exists:
    run(['gh', 'release', 'create', channel, str(feed), '--repo', repo, '--target', os.environ['GITHUB_SHA'],
         '--prerelease', '--title', 'Arkiv Development Update Channel', '--notes',
         'Signed Sparkle development feed. Not a stable production release. Do not delete or recreate this channel.'])
else:
    run(['gh', 'release', 'upload', channel, str(feed), '--repo', repo, '--clobber'])
print('Published signed Universal development update ' + version)
