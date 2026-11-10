import bz2, gzip, lzma, io, tarfile, ctypes as C, unittest
import test_engine
LIB = test_engine.LIB
LIB.arkiv_decompress_tar.argtypes=[C.c_char_p,C.c_char_p,C.c_uint64,C.c_void_p]
class CompressedTARTests(unittest.TestCase):
    setUp = test_engine.EngineTests.setUp
    tearDown = test_engine.EngineTests.tearDown
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
