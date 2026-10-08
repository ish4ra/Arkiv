#!/usr/bin/env python3
"""Generate/validate a single-version development appcast, never an unsigned release."""
import argparse
import base64
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)
BASE = 'https://github.com/ish4ra/Arkiv/releases/download/'


def create(info, archive, signature=None):
    version = info['CFBundleVersion']
    if not version.isascii() or not version.isdecimal() or int(version) < 3:
        raise ValueError('Invalid machine version')
    if signature is not None and len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid EdDSA signature')
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Arkiv Development Updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Arkiv {info["CFBundleShortVersionString"]} Development ({version})'
    ET.SubElement(item, 'description').text = f'Development/testing build {version}. Ad-hoc signed, not notarized. Includes the latest Arkiv changes. https://github.com/ish4ra/Arkiv/releases/tag/dev-{version}'
    ET.SubElement(item, f'{{{NS}}}version').text = version
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = info['CFBundleShortVersionString'] + ' Development'
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '13.0'
    enclosure = ET.SubElement(item, 'enclosure', url=f'{BASE}dev-{version}/{archive.name}',
                              length=str(archive.stat().st_size), type='application/octet-stream')
    if signature:
        enclosure.set(f'{{{NS}}}edSignature', signature)
    return root


def validate(root, info, archive, publishable):
    item = root.find('./channel/item')
    if item is None or len(root.findall('./channel/item')) != 1:
        raise ValueError('Expected one update')
    expected = create(info, archive, item.find('enclosure').get(f'{{{NS}}}edSignature'))
    if ET.tostring(root) != ET.tostring(expected):
        raise ValueError('Unexpected appcast metadata')
    if publishable and not item.find('enclosure').get(f'{{{NS}}}edSignature'):
        raise ValueError('Publishable updates require EdDSA signing')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('plist', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--signature')
    parser.add_argument('--draft', action='store_true')
    args = parser.parse_args()
    info = plistlib.loads(args.plist.read_bytes())
    root = create(info, args.archive, args.signature)
    validate(root, info, args.archive, not args.draft)
    ET.ElementTree(root).write(args.output, encoding='utf-8', xml_declaration=True)
    validate(ET.parse(args.output).getroot(), info, args.archive, not args.draft)
    print('Verified ' + ('NON-PUBLISHABLE draft' if args.draft else 'signed archive') + ' appcast metadata')
