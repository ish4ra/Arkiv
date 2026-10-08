#!/usr/bin/env python3
"""Validate the extension actually shipped in the app, keeping versions in sync."""
import plistlib
from pathlib import Path
import sys


def expected(app_info):
    info = plistlib.loads(Path('Resources/FinderSync-Info.plist').read_bytes())
    info['CFBundleVersion'] = app_info['CFBundleVersion']
    info['CFBundleShortVersionString'] = app_info['CFBundleShortVersionString']
    return info


def validate(info, app_info):
    if info != expected(app_info):
        raise ValueError('Packaged Finder Sync metadata does not match its source and app version')
    if info['CFBundleIdentifier'] != app_info['CFBundleIdentifier'] + '.finder-sync':
        raise ValueError('Extension must use its containing app identifier prefix')
    if info['NSExtension'] != {'NSExtensionPointIdentifier': 'com.apple.FinderSync', 'NSExtensionPrincipalClass': 'ArkivFinderSync'}:
        raise ValueError('Invalid Finder Sync extension point or principal class')
    if info['CFBundlePackageType'] != 'XPC!' or info['LSMinimumSystemVersion'] != '13.0':
        raise ValueError('Invalid extension bundle type or deployment target')
    schemes = [scheme for item in app_info.get('CFBundleURLTypes', []) for scheme in item.get('CFBundleURLSchemes', [])]
    if schemes.count('arkiv-finder') != 1:
        raise ValueError('Containing app must register the Finder handoff scheme once')


if __name__ == '__main__':
    app = Path(sys.argv[2])
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    path = app / 'Contents/PlugIns/ArkivFinderSync.appex/Contents/Info.plist'
    if sys.argv[1] == 'write':
        path.write_bytes(plistlib.dumps(expected(info)))
    elif sys.argv[1] != 'verify':
        raise SystemExit('Use write or verify')
    validate(plistlib.loads(path.read_bytes()), info)
    print('Verified packaged Finder Sync extension metadata and matching app version')
