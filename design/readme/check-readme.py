#!/usr/bin/env python3
"""Checks the README and its media. Standard library only; no network.

    python3 design/readme/check-readme.py

* every relative link and image in README.md and docs/media/README.md exists,
  and every #anchor resolves to a heading (GitHub's slug rules)
* the hero GIF is a looping GIF89a of the expected size, frame count and timing
* README media stays within its size budget
* the gallery artwork is byte-identical to its preserved sources
  (collect-artwork.py --check)
"""
import re
from pathlib import Path
import struct
import subprocess
import sys
import urllib.parse

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / 'docs/media'
DOCUMENTS = [ROOT / 'README.md', MEDIA / 'README.md', ROOT / 'docs/user-guide.md',
             ROOT / 'docs/document-icon-theme-launch.md']
HERO = dict(width=1280, height=440, frames=120, delay_cs=5)
BUDGET = {'arkiv-hero.gif': 1_000_000, 'arkiv-hero.jpg': 250_000, 'total': 2_000_000}


def slug(heading):
    text = re.sub(r'<[^>]+>', '', heading).strip().lower()
    text = re.sub(r'[`*_]', '', text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'[^\w\- ]', '', text, flags=re.UNICODE)
    return text.replace(' ', '-')


def anchors(path):
    found, counts = set(), {}
    in_code = False
    for line in path.read_text().splitlines():
        if line.startswith('```'):
            in_code = not in_code
        if in_code:
            continue
        match = re.match(r'#{1,6} (.+)', line)
        if match:
            base = slug(match.group(1))
            n = counts.get(base, 0)
            counts[base] = n + 1
            found.add(base if n == 0 else f'{base}-{n}')
    return found


def links(text):
    text = re.sub(r'```.*?```', '', text, flags=re.S)
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    out = re.findall(r'\]\(([^)\s]+)\)', text)
    out += re.findall(r'(?:src|srcset|href)="([^"]+)"', text)
    return out


def check_links(errors):
    for document in DOCUMENTS:
        for target in links(document.read_text()):
            if re.match(r'[a-z]+:', target):
                continue
            path, _, fragment = target.partition('#')
            file = (document.parent / urllib.parse.unquote(path)).resolve() if path else document
            if not file.exists():
                errors.append(f'{document.relative_to(ROOT)}: missing {target}')
            elif fragment and file.suffix == '.md' and fragment not in anchors(file):
                errors.append(f'{document.relative_to(ROOT)}: no heading for #{fragment} in {file.relative_to(ROOT)}')


def gif_info(data):
    """(width, height, loops forever, frame count, delays in centiseconds)."""
    if data[:6] != b'GIF89a':
        raise ValueError('not GIF89a')
    width, height, flags = struct.unpack('<HHB', data[6:11])
    pos = 13 + (3 * 2 ** ((flags & 7) + 1) if flags & 0x80 else 0)
    loops, frames, delays, delay = False, 0, [], 0
    while True:
        block = data[pos]
        if block == 0x3B:
            return width, height, loops, frames, delays
        if block == 0x21:
            label = data[pos + 1]
            pos += 2
            first = True
            while data[pos]:
                size = data[pos]
                chunk = data[pos + 1:pos + 1 + size]
                if label == 0xFF and first and chunk.startswith(b'NETSCAPE2.0'):
                    loops = True
                if label == 0xFF and not first and size == 3 and chunk[0] == 1:
                    loops = loops and struct.unpack('<H', chunk[1:3])[0] == 0
                if label == 0xF9 and first:
                    delay = struct.unpack('<H', chunk[1:3])[0]
                first = False
                pos += size + 1
            pos += 1
        elif block == 0x2C:
            flags = data[pos + 9]
            pos += 10 + (3 * 2 ** ((flags & 7) + 1) if flags & 0x80 else 0)
            pos += 1  # LZW minimum code size
            while data[pos]:
                pos += data[pos] + 1
            pos += 1
            frames += 1
            delays.append(delay)
        else:
            raise ValueError(f'unexpected GIF block {block:#x} at {pos}')


def check_media(errors):
    width, height, loops, frames, delays = gif_info((MEDIA / 'arkiv-hero.gif').read_bytes())
    if (width, height) != (HERO['width'], HERO['height']):
        errors.append(f'hero GIF is {width}x{height}')
    if not loops:
        errors.append('hero GIF does not loop forever')
    if frames != HERO['frames'] or set(delays) != {HERO['delay_cs']}:
        errors.append(f'hero GIF has {frames} frames with delays {sorted(set(delays))}')
    total = 0
    for file in sorted(MEDIA.rglob('*')):
        if file.is_file() and file.name != 'README.md':
            total += file.stat().st_size
            limit = BUDGET.get(file.name)
            if limit and file.stat().st_size > limit:
                errors.append(f'{file.name} is {file.stat().st_size} bytes (budget {limit})')
    if total > BUDGET['total']:
        errors.append(f'README media total {total} bytes (budget {BUDGET["total"]})')
    print(f'hero GIF: {width}x{height}, {frames} frames x {delays[0] * 10} ms, loops; media total {total:,} bytes')


def main():
    errors = []
    check_links(errors)
    check_media(errors)
    artwork = subprocess.run([sys.executable, str(Path(__file__).with_name('collect-artwork.py')), '--check'],
                             capture_output=True, text=True)
    print(artwork.stdout.strip())
    if artwork.returncode:
        errors.append(artwork.stderr.strip() or artwork.stdout.strip())
    if errors:
        raise SystemExit('\n'.join(errors))
    print('README links, anchors, images and media are valid')


if __name__ == '__main__':
    main()
