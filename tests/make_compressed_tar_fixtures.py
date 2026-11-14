"""Independent Python stdlib fixtures, no Arkiv writer involved."""
import io, tarfile, zipfile, gzip, bz2, lzma
from pathlib import Path
out=Path(__file__).parent/'fixtures';out.mkdir(exist_ok=True)
z=io.BytesIO()
with zipfile.ZipFile(z,'w') as f:f.writestr(zipfile.ZipInfo('inside.txt',date_time=(2020,1,1,0,0,0)),b'nested')
t=io.BytesIO()
with tarfile.open(fileobj=t,mode='w',format=tarfile.PAX_FORMAT) as f:
    for name,body in [('folder/é 🐘.txt',b'hello'),('empty',b''),('nested.zip',z.getvalue())]:
        e=tarfile.TarInfo(name);e.size=len(body);e.mode=0o755;e.mtime=1700000000;f.addfile(e,io.BytesIO(body))
    e=tarfile.TarInfo('empty-folder');e.type=tarfile.DIRTYPE;f.addfile(e)
    for name,kind,target in [('symbolic',tarfile.SYMTYPE,'../outside'),('hard',tarfile.LNKTYPE,'folder/é 🐘.txt')]:
        e=tarfile.TarInfo(name);e.type=kind;e.linkname=target;f.addfile(e)
for suffix,compress in [('gz',lambda b:gzip.compress(b,mtime=0)),('bz2',bz2.compress),('xz',lzma.compress)]:
    (out/('compressed.tar.'+suffix)).write_bytes(compress(t.getvalue()))
for suffix,compress in [('gz',lambda b:gzip.compress(b,mtime=0)),('bz2',bz2.compress),('xz',lzma.compress)]:
    (out/('empty.tar.'+suffix)).write_bytes(compress(bytes(10240)))
    (out/('invalid-inner.tar.'+suffix)).write_bytes(compress(bytes([t.getvalue()[0] ^ 0x80]) + t.getvalue()[1:]))
