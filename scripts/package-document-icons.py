#!/usr/bin/env python3
"""Package the committed document iconsets as ICNS without losing their
lossless compression.

Usage: package-document-icons.py ICONSET_ROOT OUTPUT_DIR   (macOS; build-app.sh)

Apple's iconutil writes each ICNS, and it decides the element types, their
order, the non-PNG 16/32 pt elements and the `info` element. iconutil
re-encodes every PNG it embeds, which discards the committed lossless
optimization. So, for each PNG element iconutil wrote, this keeps iconutil's
PNG exactly (signature, IHDR, every ancillary chunk such as a colour profile,
chunk order, IEND) and replaces only its IDAT data with the IDAT data of the
committed PNG for that representation. That is done only when:

* both IHDRs are byte-identical (same size, 8-bit RGBA, non-interlaced),
* the committed PNG has no ancillary chunks of its own,
* the spliced PNG decodes to exactly iconutil's pixels, which must equal
  PIXELS.sha256, and
* the result is smaller.

Otherwise iconutil's element is kept unchanged. Everything else in the file is
byte-for-byte iconutil's output, so the packaged icon is the one iconutil
would write, with a smaller Deflate stream. The result is deterministic.
"""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('icons', ROOT / 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(icons)


def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))


def splice_png(packaged, committed, expected_digest, verify_pixels=True):
    """Return `packaged` with its IDAT data taken from `committed`, or None if unsafe.

    With verify_pixels=False the decode checks are skipped; only packaged-app
    verification uses that, to rebuild the exact bytes the build produced
    (with full checks) and compare them without decoding again."""
    ours = list(icons.png_chunks(committed))
    theirs = list(icons.png_chunks(packaged))
    if {kind for kind, _ in ours} - icons.PNG_CHUNKS:
        return None
    if theirs[0] != ours[0]:  # IHDR: size, depth, colour type, compression, filter, interlace
        return None
    kinds = [kind for kind, _ in theirs]
    first, last = kinds.index(b'IDAT'), len(kinds) - 1 - kinds[::-1].index(b'IDAT')
    if any(kind != b'IDAT' for kind in kinds[first:last + 1]):
        return None
    data = b'\x89PNG\r\n\x1a\n' + b''.join(chunk(kind, body) for kind, body in theirs[:first])
    data += b''.join(chunk(kind, body) for kind, body in ours if kind == b'IDAT')
    data += b''.join(chunk(kind, body) for kind, body in theirs[last + 1:])
    if verify_pixels:
        decoded = icons.decode_png(data)
        if decoded != icons.decode_png(packaged) or icons.pixel_digest(*decoded) != expected_digest:
            return None
    return data


def splice_icns(icns, iconset, pixels, verify_pixels=True):
    """Return (new ICNS bytes, [(type, before, after)]) for iconutil output `icns`."""
    assert icns[:4] == b'icns' and struct.unpack('>I', icns[4:8])[0] == len(icns), 'bad ICNS header'
    offset, body, report = 8, b'', []
    while offset < len(icns):
        kind, length = struct.unpack('>4sI', icns[offset:offset + 8])
        assert length >= 8 and offset + length <= len(icns), 'bad ICNS element'
        payload = icns[offset + 8:offset + length]
        name = kind.decode('latin-1')
        if payload.startswith(b'\x89PNG') and name in icons.ICNS_TYPES:
            source = Path(iconset) / icons.ICNS_TYPES[name]
            spliced = splice_png(payload, source.read_bytes(), pixels[f'{Path(iconset).name}/{source.name}'], verify_pixels)
            if spliced is not None and len(spliced) < len(payload):
                report.append((name, len(payload), len(spliced)))
                payload = spliced
            else:
                report.append((name, len(payload), len(payload)))
        body += kind + struct.pack('>I', len(payload) + 8) + payload
        offset += length
    return b'icns' + struct.pack('>I', len(body) + 8) + body, report


def main(root, output):
    root, output = Path(root), Path(output)
    pixels = icons.read_manifest(root / 'PIXELS.sha256')
    total_before = total_after = 0
    with tempfile.TemporaryDirectory(prefix='arkiv-document-icns-') as tmp:
        for name in icons.ICONS:
            iconset = root / f'Arkiv-{name}.iconset'
            plain = Path(tmp) / f'Arkiv-{name}.icns'
            subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(plain)], check=True)
            original = plain.read_bytes()
            packaged, report = splice_icns(original, iconset, pixels)
            (output / f'Arkiv-{name}.icns').write_bytes(packaged)
            total_before, total_after = total_before + len(original), total_after + len(packaged)
            ancillary = sorted({kind.decode() for kind_, payload in icons.icns_elements(plain)
                                if payload.startswith(b'\x89PNG')
                                for kind, _ in icons.png_chunks(payload)} - {'IHDR', 'IDAT', 'IEND'})
            kept = [kind for kind, before, after in report if before == after]
            print(f'Arkiv-{name}.icns: iconutil {len(original):,} -> {len(packaged):,} bytes; '
                  f'{len(report) - len(kept)} PNG elements recompressed, kept as written: {kept or "none"}; '
                  f'iconutil PNG ancillary chunks preserved: {ancillary or "none"}')
    print(f'Document ICNS: iconutil {total_before:,} -> packaged {total_after:,} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.split('\n\n')[1])
    main(*sys.argv[1:])
