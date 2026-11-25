"""Writes a throwaway, manifest-verified theme with solid jade ZIP artwork.

Used only by diagnose.sh on an ephemeral CI runner to show that the prototype
extension follows Arkiv's theme selection. Not a real theme; never published.
"""
import hashlib, json, pathlib, struct, sys, zlib

def png(size, rgb):
    raw = b''.join(b'\x00' + bytes(rgb + (255,)) * size for _ in range(size))
    chunk = lambda kind, data: struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
files, reps = [], {}
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon_{points}x{points}{"@2x" if scale == 2 else ""}.png'
        data = png(points * scale, (0x4A, 0x9C, 0x82))
        (out / name).write_bytes(data)
        files.append({'path': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'width': points * scale, 'height': points * scale})
        reps[name] = name
manifest = {'schema': 1, 'id': 'proto-test', 'version': 1, 'name': 'Prototype test', 'icons': {'ZIP': reps}, 'extras': {}, 'files': files}
(out / 'theme.json').write_text(json.dumps(manifest))
