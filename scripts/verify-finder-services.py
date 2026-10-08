#!/usr/bin/env python3
"""Verify Services declarations in the exact app bundle distributed in the DMG."""
import plistlib
import sys
from pathlib import Path

info = plistlib.loads(Path(sys.argv[1]).read_bytes())
expected = {
    'open': 'Arkiv/Open in Arkiv',
    'extractHere': 'Arkiv/Extract Here',
    'extractFolder': 'Arkiv/Extract to Archive Folder',
    'extractTo': 'Arkiv/Extract To…',
}
services = info.get('NSServices', [])
assert len(services) == len(expected), 'Incorrect Finder service count'
assert {s.get('NSUserData') for s in services} == set(expected), 'Incorrect Finder actions'
for service in services:
    assert service['NSMenuItem']['default'] == expected[service['NSUserData']]
    assert service['NSMessage'] == 'performFinderAction'
    assert service['NSPortName'] == info['CFBundleExecutable'] == 'Arkiv'
    assert set(service['NSSendTypes']) == {'public.file-url', 'NSFilenamesPboardType'}
    assert service['NSRequiredContext'] == {'NSTextContentFileTypes': ['public.zip-archive', 'public.tar-archive']}
    assert service['NSReturnTypes'] == []
print('Verified four file-type-restricted Arkiv Finder Services.')
