import bz2, gzip, lzma, io, tarfile, ctypes as C, unittest
import test_engine
import os
import unicodedata
from pathlib import Path
LIB = test_engine.LIB
LIB.arkiv_decompress_tar.argtypes=[C.c_char_p,C.c_char_p,C.c_uint64,C.c_void_p]
METADATA = C.CFUNCTYPE(None, C.c_void_p, C.c_char_p, C.c_int64, C.c_double, C.c_char_p, C.c_int, C.c_int64, C.c_int64, C.c_int64)
LIB.arkiv_entry_metadata.argtypes = [C.c_char_p, METADATA, C.c_void_p]
class CompressedTARTests(unittest.TestCase):
    setUp = test_engine.EngineTests.setUp
    tearDown = test_engine.EngineTests.tearDown
    def test_stored_permissions_through_private_spool(self):
        fixtures = Path(__file__).parent / 'fixtures'
        for codec in ['gz', 'bz2', 'xz']:
            with self.subTest(codec=codec):
                out = self.base.resolve() / ('spool-' + codec + '.tar')
                self.assertEqual(LIB.arkiv_decompress_tar(bytes(fixtures / ('compressed.tar.' + codec)), bytes(out), 100000, self.token), 0)
                # Independent fixture evidence, not permissions of the spool on disk.
                with tarfile.open(out) as archive:
                    expected = {unicodedata.normalize('NFC', e.name.rstrip('/')): e.mode for e in archive}
                modes = {}
                @METADATA
                def metadata(_, name, packed, time, method, encrypted, crc, mode, attrs):
                    # macOS libarchive emits decomposed UTF-8; Swift paths compare
                    # canonical Unicode equivalents. Compare the same way here.
                    modes[unicodedata.normalize('NFC', name.decode('utf8').rstrip('/'))] = mode
                result = LIB.arkiv_entry_metadata(bytes(out), metadata, None)
                # Diagnose strict ancestor opening independently; never print paths.
                fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
                path_error = 0
                try:
                    for part in out.parts[1:]:
                        next_fd = os.open(part, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                        os.close(fd); fd = next_fd
                except OSError as error:
                    path_error = error.errno
                finally:
                    os.close(fd)
                self.assertEqual(path_error, 0)
                self.assertEqual(result, 0)
                self.assertEqual(set(modes), set(expected))
                for name, mode in expected.items():
                    self.assertEqual(modes[name] & 0o7777, mode)

    def test_codecs_validation_limits_and_cleanup(self):
        raw=io.BytesIO()
        with tarfile.open(fileobj=raw,mode='w',format=tarfile.USTAR_FORMAT) as t:
            for name,body in [('folder/hello.txt',b'hello'),('empty',b'')]:
                e=tarfile.TarInfo(name);e.size=len(body);e.mode=0o755;t.addfile(e,io.BytesIO(body))
        plain=raw.getvalue()
        for compress in [gzip.compress,bz2.compress,lzma.compress]:
            expanded=plain+bytes(2*1024*1024)
            self.archive.write_bytes(compress(expanded))
            expanded_out=self.base/'expanded'
            self.assertEqual(LIB.arkiv_decompress_tar(bytes(self.archive),bytes(expanded_out),len(expanded),self.token),0)
            self.assertEqual(expanded_out.read_bytes(),expanded)
            expanded_out.unlink()
            data=compress(plain)
            for payload,limit,success in [(data,len(plain),True),(data,512,False),(data[:-5],len(plain),False),(data+b'x',len(plain),False),(compress(b'not tar'),100000,False)]:
                self.archive.write_bytes(payload);out=self.base/'spool.tar'
                code=LIB.arkiv_decompress_tar(bytes(self.archive),bytes(out),limit,self.token)
                self.assertEqual(code==0,success)
                if success:self.assertEqual(out.read_bytes(),plain);out.unlink()
                else:self.assertFalse(out.exists())
            broken=bytearray(data);broken[len(broken)//2]^=0xff
            self.archive.write_bytes(broken)
            self.assertNotEqual(LIB.arkiv_decompress_tar(bytes(self.archive),bytes(self.base/'bad'),100000,self.token),0)
        self.archive.write_bytes(lzma.compress(bytes(10240), filters=[{'id':lzma.FILTER_LZMA2,'dict_size':128*1024*1024}]))
        self.assertEqual(LIB.arkiv_decompress_tar(bytes(self.archive),bytes(self.base/'memory'),100000,self.token),8)
        self.assertFalse((self.base/'memory').exists())
        LIB.arkiv_cancel_set(self.token)
        self.assertEqual(LIB.arkiv_decompress_tar(bytes(self.archive),bytes(self.base/'cancelled'),100000,self.token),2)

if __name__=='__main__': unittest.main()
