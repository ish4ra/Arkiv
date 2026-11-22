#!/usr/bin/env python3
"""Encoder-independent artwork check: compares the decoded RGBA pixels of
freshly rendered PNGs with a pixel manifest.

PNG bytes depend on the encoder settings of the Playwright build that took the
screenshot (for example, a patched build that requests `optimizeForSpeed`), so
byte hashes can differ while the artwork is identical. A pixel manifest line
is `<sha256 of WIDTHxHEIGHT + RGBA bytes>  <relative path>`.

  python3 tooling/verify-pixels.py reference/v1-pixels.sha256 <render-root>
  python3 tooling/verify-pixels.py --write <manifest> <root> [glob ...]   # create a manifest

Needs Pillow (design-time only).
"""
import glob
import hashlib
import os
import sys

from PIL import Image


def pixel_hash(path):
    with Image.open(path) as image:
        rgba = image.convert('RGBA')
        digest = hashlib.sha256(f'{rgba.width}x{rgba.height}\n'.encode())
        digest.update(rgba.tobytes())
        return digest.hexdigest()


def main(argv):
    if argv and argv[0] == '--write':
        manifest, root, patterns = argv[1], argv[2], argv[3:] or ['**/*.png']
        files = sorted({os.path.relpath(p, root) for pat in patterns for p in glob.glob(os.path.join(root, pat), recursive=True)})
        with open(manifest, 'w') as out:
            for rel in files:
                out.write(f'{pixel_hash(os.path.join(root, rel))}  {rel}\n')
        print(f'wrote {len(files)} pixel hashes to {manifest}')
        return 0
    manifest, root = argv[0], argv[1]
    checked = missing = 0
    bad = []
    for line in open(manifest):
        digest, rel = line.rstrip('\n').split('  ', 1)
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            missing += 1
            bad.append(f'missing {rel}')
            continue
        checked += 1
        if pixel_hash(path) != digest:
            bad.append(rel)
    print(f'{checked} images checked, {len(bad) - missing} differ, {missing} missing')
    print('\n'.join(bad[:20]))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
