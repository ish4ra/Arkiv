#!/usr/bin/env python3
"""Build-time public configuration; never accepts or stores a private key."""
import base64
import os
from pathlib import Path
import plistlib
import sys

FEED = 'https://raw.githubusercontent.com/ish4ra/Arkiv/updates/appcast.xml'


def configured(source, env):
    info = dict(source)
    version = env.get('ARKIV_BUILD_VERSION', '3')
    if not version.isascii() or not version.isdecimal() or int(version) < 3:
        raise ValueError('ARKIV_BUILD_VERSION must be an integer >= 3')
    info['CFBundleVersion'] = version
    info.update(SUFeedURL=FEED, SUVerifyUpdateBeforeExtraction=True,
                SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0,
                SUAllowsAutomaticUpdates=False)
    key = env.get('SPARKLE_PUBLIC_ED_KEY', '').strip()
    if key:
        if len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError('SPARKLE_PUBLIC_ED_KEY must encode a 32-byte public key')
        info['SUPublicEDKey'] = key
    return info


if __name__ == '__main__':
    source = plistlib.loads(Path('Resources/Info.plist').read_bytes())
    expected = configured(source, os.environ)
    path = Path(sys.argv[2])
    if sys.argv[1] == 'write':
        path.write_bytes(plistlib.dumps(expected))
    elif sys.argv[1] == 'verify':
        if plistlib.loads(path.read_bytes()) != expected:
            raise SystemExit('Packaged metadata does not match the source and public build configuration')
    else:
        raise SystemExit('Use write or verify')
