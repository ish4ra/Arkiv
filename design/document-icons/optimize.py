#!/usr/bin/env python3
"""Lossless, deterministic recompression of the document-icon PNGs.

Design-time only: the app build packages the committed PNGs and never runs
this. Needs the pinned optimizer from requirements-optimize.txt:

  python3 -m pip install --require-hashes -r design/document-icons/requirements-optimize.txt

  python3 design/document-icons/optimize.py [ROOT]              # optimize ROOT in place
  python3 design/document-icons/optimize.py --check [ROOT]      # committed files are a fixed point
  python3 design/document-icons/optimize.py --reproduce SOURCE  # SOURCE (unoptimized renders) optimizes to ROOT exactly
  python3 design/document-icons/optimize.py --record-pixels ROOT # approved artwork change only (generate.mjs)

ROOT defaults to Resources/DocumentIcons. Every output is checked before it is
written: the decoded 8-bit RGBA pixels, including fully transparent pixels,
must equal the input exactly, the PNG must stay 8-bit RGBA, non-interlaced,
with only IHDR/IDAT/IEND, and it must match PIXELS.sha256 (the build 26501
decoded-pixel manifest). Colour type, bit depth, palette and alpha
reductions are disabled, so pixels and the PNG layout macOS reads are
unchanged; only the filter choice and Deflate stream differ. No timeout is
used, so the result never depends on machine speed.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import shutil
import struct
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
DEFAULT_ROOT = REPO / 'Resources/DocumentIcons'
OXIPNG_VERSION = '9.1.1'  # pyoxipng, pinned with hashes in requirements-optimize.txt
LEVEL = 6

_spec = importlib.util.spec_from_file_location('verify_document_icons', REPO / 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(icons)


def oxipng_module():
    try:
        import oxipng
    except ImportError:
        raise SystemExit('pyoxipng is not installed; see requirements-optimize.txt')
    from importlib.metadata import version
    if version('pyoxipng') != OXIPNG_VERSION:
        raise SystemExit(f'pyoxipng {OXIPNG_VERSION} required for reproducible output, found {version("pyoxipng")}')
    return oxipng


def options(oxipng):
    return dict(level=LEVEL, fix_errors=False, force=False, interlace=None, optimize_alpha=False,
                bit_depth_reduction=False, color_type_reduction=False, palette_reduction=False,
                grayscale_reduction=False, idat_recoding=True, scale_16=False,
                strip=oxipng.StripChunks.none(), deflate=oxipng.Deflaters.libdeflater(12),
                fast_evaluation=False, timeout=None)


def chunks(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    offset, kinds = 8, []
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        kinds.append(kind)
        offset += 12 + length
    return kinds


def decode(data):
    with tempfile.NamedTemporaryFile(suffix='.png') as handle:
        handle.write(data)
        handle.flush()
        return icons.read_png(handle.name)  # asserts 8-bit RGBA, non-interlaced


def optimize_bytes(data, oxipng):
    """Return the optimized PNG, or the input when it cannot be made smaller."""
    output = oxipng.optimize_from_memory(data, **options(oxipng))
    if len(output) >= len(data):
        return data
    if decode(output) != decode(data):
        raise SystemExit('Optimizer changed decoded pixels; refusing to write')
    kinds = set(chunks(output))
    if kinds - {b'IHDR', b'IDAT', b'IEND'}:
        raise SystemExit(f'Optimizer added chunks {sorted(kinds)}')
    if output[16:29] != data[16:29]:
        raise SystemExit('Optimizer changed the PNG header (size, depth, colour type or interlace)')
    return output


def representations(root):
    return [root / f'Arkiv-{name}.iconset' / icons.rep_name(pt, scale)
            for name in icons.ICONS for pt, scale in icons.REPRESENTATIONS]


def write_sums(root):
    lines = sorted(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root)}'
                   for path in representations(root))
    (root / 'SHA256SUMS').write_text('\n'.join(sorted(lines, key=lambda line: line[66:])) + '\n')


def optimize_tree(root, oxipng):
    before = after = 0
    for path in representations(root):
        data = path.read_bytes()
        output = optimize_bytes(data, oxipng)
        before, after = before + len(data), after + len(output)
        if output != data:
            path.write_bytes(output)
    return before, after


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='fail if any committed PNG is not already optimized')
    mode.add_argument('--reproduce', metavar='SOURCE', type=Path, help='optimize a copy of SOURCE and compare with ROOT')
    mode.add_argument('--record-pixels', action='store_true',
                      help='rewrite PIXELS.sha256 from ROOT before optimizing (an approved artwork change)')
    parser.add_argument('root', nargs='?', type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args(argv)
    oxipng = oxipng_module()
    root = args.root.resolve()
    if args.check:
        stale = [str(p.relative_to(root)) for p in representations(root) if optimize_bytes(p.read_bytes(), oxipng) != p.read_bytes()]
        if stale:
            raise SystemExit(f'{len(stale)} PNGs are not at the pinned optimizer fixed point: {stale[:5]}')
        icons.verify_sources(root, pixels=root / 'PIXELS.sha256')
        print(f'{len(representations(root))} document-icon PNGs are optimized, checksummed and pixel-identical to build 26501')
        return
    if args.reproduce:
        with tempfile.TemporaryDirectory(prefix='arkiv-icon-reproduce-') as tmp:
            copy = Path(tmp) / 'DocumentIcons'
            shutil.copytree(args.reproduce.resolve(), copy)
            shutil.copy(root / 'PIXELS.sha256', copy / 'PIXELS.sha256')
            before, after = optimize_tree(copy, oxipng)
            write_sums(copy)
            icons.verify_sources(copy, pixels=copy / 'PIXELS.sha256')
            if (copy / 'SHA256SUMS').read_bytes() != (root / 'SHA256SUMS').read_bytes():
                raise SystemExit('Optimizing the source renders does not reproduce the committed PNGs byte-for-byte')
        print(f'Reproduced {len(representations(root))} committed PNGs byte-for-byte from {args.reproduce} '
              f'({before:,} -> {after:,} bytes), pixel-identical to PIXELS.sha256')
        return
    if args.record_pixels:
        (root / 'PIXELS.sha256').write_text(''.join(
            f'{icons.pixel_digest(*icons.read_png(path))}  {path.relative_to(root)}\n'
            for path in sorted(representations(root), key=lambda p: str(p.relative_to(root)))))
    before, after = optimize_tree(root, oxipng)
    write_sums(root)
    icons.verify_sources(root, pixels=root / 'PIXELS.sha256')
    print(f'Optimized {len(representations(root))} PNGs: {before:,} -> {after:,} bytes '
          f'({(1 - after / before) * 100:.2f}% smaller), pixels unchanged')


if __name__ == '__main__':
    main(sys.argv[1:])
