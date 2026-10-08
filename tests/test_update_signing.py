#!/usr/bin/env python3
"""macOS integration test with an ephemeral key, never a publishing identity.

Signs the real Universal ZIP with Sparkle's pinned tool and exercises signature
verification/tampering. The ephemeral private seed stays in memory and stdin.
"""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
os.chdir(root)
tool = next(Path('.build/artifacts').glob('**/bin/sign_update'))
# CryptoKit creates a disposable test-only identity; stdout is captured, not logged.
source = '''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let data = try JSONSerialization.data(withJSONObject: ["private": key.rawRepresentation.base64EncodedString(), "public": key.publicKey.rawRepresentation.base64EncodedString()])
FileHandle.standardOutput.write(data)
'''
with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    generator = directory / 'test-key.swift'
    generator.write_text(source)
    keys = json.loads(subprocess.check_output(['swift', str(generator)]))
    info = plistlib.loads(Path('build/Arkiv.app/Contents/Info.plist').read_bytes())
    info['SUPublicEDKey'] = keys['public']
    plist = directory / 'Info.plist'
    plist.write_bytes(plistlib.dumps(info))
    archive = Path('build/Arkiv-universal.zip')

    def sign(args, success=True):
        result = subprocess.run([str(tool), '--ed-key-file', '-', *args], input=keys['private'], text=True, capture_output=True)
        if (result.returncode == 0) != success:
            raise SystemExit('Signing integration test failed (private diagnostics suppressed)')
        return result.stdout.strip()

    signature = sign(['-p', str(archive)])
    subprocess.run(['swift', 'scripts/verify-update-signature.swift', str(plist), str(archive), signature], check=True)
    feed = directory / 'appcast.xml'
    subprocess.run(['python3', 'scripts/update-feed.py', str(plist), str(archive), str(feed), '--signature', signature], check=True)
    sign([str(feed)])
    sign(['--verify', str(feed)])
    feed.write_bytes(feed.read_bytes().replace(b'Arkiv Development Updates', b'Changed Development Updates'))
    sign(['--verify', str(feed)], success=False)
    corrupted = directory / 'corrupted.zip'
    corrupted.write_bytes(b'not the signed archive')
    sign(['--verify', str(corrupted), signature], success=False)
    # A different embedded public key must not validate an otherwise intact ZIP.
    info['SUPublicEDKey'] = base64.b64encode(bytes(32)).decode()
    plist.write_bytes(plistlib.dumps(info))
    result = subprocess.run(['swift', 'scripts/verify-update-signature.swift', str(plist), str(archive), signature], capture_output=True)
    if result.returncode == 0:
        raise SystemExit('Wrong embedded public key was accepted')
print('Sparkle archive/feed signing, tampering and wrong-key tests passed (disposable test identity)')
