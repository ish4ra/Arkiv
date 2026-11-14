"""Developer-only fixture generation using an independent installed libzstd.
Not used by Arkiv, its build, or CI. Pass an explicit library path if necessary.
"""
import ctypes as C, ctypes.util, gzip, sys
from pathlib import Path
lib=C.CDLL(sys.argv[1] if len(sys.argv)>1 else ctypes.util.find_library('zstd'))
lib.ZSTD_versionString.restype=C.c_char_p
lib.ZSTD_createCCtx.restype=C.c_void_p
lib.ZSTD_CCtx_setParameter.argtypes=[C.c_void_p,C.c_int,C.c_int]
lib.ZSTD_compressBound.argtypes=[C.c_size_t];lib.ZSTD_compressBound.restype=C.c_size_t
lib.ZSTD_compress2.argtypes=[C.c_void_p,C.c_void_p,C.c_size_t,C.c_void_p,C.c_size_t];lib.ZSTD_compress2.restype=C.c_size_t
lib.ZSTD_freeCCtx.argtypes=[C.c_void_p]
lib.ZSTD_isError.argtypes=[C.c_size_t]
def compress(data,checksum=1,size=1):
    ctx=lib.ZSTD_createCCtx()
    try:
        for k,v in [(100,3),(201,checksum),(200,size)]:assert not lib.ZSTD_isError(lib.ZSTD_CCtx_setParameter(ctx,k,v))
        out=C.create_string_buffer(lib.ZSTD_compressBound(len(data)))
        n=lib.ZSTD_compress2(ctx,out,len(out),data,len(data));assert not lib.ZSTD_isError(n)
        return out.raw[:n]
    finally:lib.ZSTD_freeCCtx(ctx)
if __name__=='__main__':
    root=Path(__file__).parent/'fixtures'
    for name in ['standalone.sql','standalone-empty','compressed.tar','empty.tar','invalid-inner.tar']:
        raw=gzip.decompress((root/(name+'.gz')).read_bytes())
        (root/(name+'.zst')).write_bytes(compress(raw))
    raw=gzip.decompress((root/'standalone.sql.gz').read_bytes())
    for name,checksum,size in [('no-checksum',0,1),('unknown-size',1,0)]:
        (root/('zstd-'+name+'.zst')).write_bytes(compress(raw,checksum,size))
    unknown=bytearray(compress(raw,1,0));assert not unknown[4]&32
    unknown[5]=0x88 # Window_Log 27: 128 MiB, rejected before decoder allocation
    (root/'zstd-large-window.zst').write_bytes(unknown)
    dictionary=bytearray(compress(raw,1,0));dictionary[4]|=1;dictionary[6:6]=b'\x01'
    (root/'zstd-dictionary.zst').write_bytes(dictionary)
    print('Independent fixture producer: libzstd',lib.ZSTD_versionString().decode())
