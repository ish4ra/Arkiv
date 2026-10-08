#!/usr/bin/env python3
"""Validate the documented file-Service contract in the distributed app plist."""
import plistlib
import sys
from pathlib import Path

EXPECTED = {
    'open': 'Open in Arkiv',
    'extractHere': 'Extract Here with Arkiv',
    'extractFolder': 'Extract to Folder with Arkiv',
    'extractTo': 'Extract To… with Arkiv',
}
FILE_TYPES = {'public.zip-archive', 'public.tar-archive'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(info):
    services = info.get('NSServices', [])
    require(len(services) == len(EXPECTED), 'Incorrect Finder service count')
    require({s.get('NSUserData') for s in services} == set(EXPECTED), 'Incorrect Finder actions')
    for service in services:
        require(service.get('NSMenuItem') == {'default': EXPECTED[service['NSUserData']]},
                'Use direct service titles, not slash-separated submenus')
        require(service.get('NSMessage') == 'performFinderAction', 'Incorrect provider selector')
        require(service.get('NSPortName') == info.get('CFBundleExecutable') == 'Arkiv', 'Incorrect provider port')
        require(set(service.get('NSSendFileTypes', [])) == FILE_TYPES, 'NSSendFileTypes must advertise ZIP and TAR UTIs')
        require(service.get('NSRequiredContext') == {}, 'Use an empty NSRequiredContext for these file Services')
        require('NSSendTypes' not in service, 'Do not declare pasteboard send types for these file Services')
        require('NSReturnTypes' not in service, 'These actions do not return pasteboard data')


if __name__ == '__main__':
    validate(plistlib.loads(Path(sys.argv[1]).read_bytes()))
    print('Verified four Arkiv file Services with NSSendFileTypes and direct titles.')
