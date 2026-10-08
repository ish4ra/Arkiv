#!/usr/bin/env python3
"""Reject conventional exported-key paths and private-key blocks in tracked files.

An arbitrary Ed25519 seed is indistinguishable from other random data. This guard
is defense in depth, not a substitute for never exporting a key into a checkout.
The publishing job also checks for the exact configured secret in tracked bytes.
"""
from pathlib import Path
import subprocess

for raw in subprocess.check_output(['git', 'ls-files', '-z']).split(b'\0'):
    if not raw:
        continue
    path = Path(raw.decode())
    name = path.name.lower()
    if name.endswith('.private-key') or name.startswith('sparkle-private-key'):
        raise SystemExit('Exported signing-key path must not be tracked')
    data = path.read_bytes()
    markers = [b'-----BEGIN ' + kind + b'PRIVATE KEY-----' for kind in [b'', b'RSA ', b'EC ', b'OPENSSH ']]
    if any(marker in data for marker in markers):
        raise SystemExit('Private key block found in tracked content')
print('Tracked signing-material guard passed')
