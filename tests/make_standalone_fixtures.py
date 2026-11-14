"""Independent, deterministic single-file fixtures (Python standard library codecs)."""
import bz2,gzip,lzma,io
from pathlib import Path
out=Path(__file__).parent/'fixtures'
raw='database content é 🐘\n'.encode()*10000
for ext,compress in [('gz',lambda b:gzip.compress(b,mtime=0)),('bz2',bz2.compress),('xz',lzma.compress)]:
    (out/('standalone.sql.'+ext)).write_bytes(compress(raw))
    (out/('standalone-empty.'+ext)).write_bytes(compress(b''))
buffer=io.BytesIO()
with gzip.GzipFile(filename='../outside.txt',fileobj=buffer,mode='wb',mtime=1700000000) as file:file.write(raw)
(out/'standalone-untrusted-name.gz').write_bytes(buffer.getvalue())
