#!/usr/bin/env python3
"""Copy original PNG representations from an installed Arko.icns; never redraw them.

Requires Pillow for decoded dimension/alpha validation only. PNG bytes are not
re-encoded. Usage: python3 branding/extract-icns.py /path/to/Arko.icns [output-dir]
"""
import argparse
import hashlib
import io
from pathlib import Path
import struct

from PIL import Image


def extract(source, output):
    data = source.read_bytes()
    if len(data) < 8 or data[:4] != b"icns" or struct.unpack(">I", data[4:8])[0] != len(data):
        raise ValueError("Invalid ICNS header or length")
    chunks = {}
    offset = 8
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("Truncated ICNS chunk header")
        kind, length = struct.unpack(">4sI", data[offset:offset + 8])
        if length < 8 or offset + length > len(data):
            raise ValueError("Invalid ICNS chunk length")
        if kind in chunks:
            raise ValueError("Duplicate ICNS representation")
        chunks[kind] = data[offset + 8:offset + length]
        offset += length

    exports = {}
    for size, kind in [(1024, b"ic10"), (512, b"ic09"), (256, b"ic08"), (128, b"ic07")]:
        png = chunks[kind]
        if not png.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"{kind!r} is not an embedded PNG; no conversion attempted")
        with Image.open(io.BytesIO(png)) as image:
            image.load()
            if image.format != "PNG" or image.size != (size, size) or "A" not in image.getbands():
                raise ValueError(f"{size}: incorrect dimensions or missing alpha")
            alpha = image.getchannel("A")
            histogram = alpha.histogram()
            corners = [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)]
            if any(alpha.getpixel(point) != 0 for point in corners):
                raise ValueError(f"{size}: corners are not transparent")
            if not (histogram[0] and histogram[255] and sum(histogram[1:255])):
                raise ValueError(f"{size}: missing transparent, opaque, or partial-alpha pixels")
            print(f"{size} × {size}: transparent={histogram[0]}, "
                  f"partial={sum(histogram[1:255])}, opaque={histogram[255]}")
        exports[f"Arko-AppIcon-{size}.png"] = png
        if size in (1024, 512):
            exports[f"Arko-Mark-Transparent-{size}.png"] = png

    # Validate every source representation before writing any assets.
    output.mkdir(parents=True, exist_ok=True)
    for name, png in exports.items():
        destination = output / name
        destination.write_bytes(png)
        if destination.read_bytes() != png:
            raise OSError(f"Written PNG differs from source: {name}")
        print(f"{hashlib.sha256(png).hexdigest()}  {name}")
    print(f"Source ICNS SHA-256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", nargs="?", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    extract(args.source, args.output)
