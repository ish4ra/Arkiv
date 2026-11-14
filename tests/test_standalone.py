"""Independent codec interoperability and fail-closed stream boundary tests."""
import bz2, gzip, lzma, ctypes as C, os, tempfile, unittest
from pathlib import Path
LIB=C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
LIB.arkiv_decompress_stream.argtypes=[C.c_char_p,C.c_char_p,C.c_uint64,C.c_void_p]
LIB.arkiv_cancel_new.restype=C.c_void_p
LIB.arkiv_cancel_set.argtypes=[C.c_void_p]
LIB.arkiv_cancel_free.argtypes=[C.c_void_p]
class Limits(C.Structure):
    _fields_=[('max_entries',C.c_uint64),('max_bytes',C.c_uint64)]
LIB.arkiv_create_stream.argtypes=[C.c_char_p,C.c_char_p,C.c_char_p,C.c_char_p,C.c_char_p,C.c_size_t,C.c_int,Limits,C.c_void_p,C.c_void_p,C.c_void_p,C.c_char_p,C.c_size_t]
PROGRESS=C.CFUNCTYPE(None,C.c_void_p,C.c_uint64,C.c_uint64)
class StandaloneTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve()
        self.source=self.root/'source';self.dest=self.root/'output';self.dest.mkdir();(self.dest/'.stage').mkdir(mode=0o700)
        self.token=LIB.arkiv_cancel_new()
    def tearDown(self): LIB.arkiv_cancel_free(self.token);self.temp.cleanup()
    def decode(self,payload,limit=4*1024*1024):
        self.source.write_bytes(payload);out=self.root/'decoded'
        if out.exists():out.unlink()
        result=LIB.arkiv_decompress_stream(bytes(self.source),bytes(out),limit,self.token)
        if result:self.assertFalse(out.exists())
        return result,out
    def create(self,kind,callback=None):
        error=C.create_string_buffer(256)
        ext=['gz','bz2','xz'][kind-1]
        return LIB.arkiv_create_stream(bytes(self.source),bytes(self.dest),b'.stage',('result.'+ext).encode(),C.create_string_buffer(512),512,kind,Limits(100000,20*1024**3),self.token,callback,None,error,256)
    def test_complete_stream_validation_and_limits(self):
        raw=bytes(range(256))*2048
        for compress in (gzip.compress,bz2.compress,lzma.compress):
            data=compress(raw)
            for content in (b'',b'hello',raw):
                code,path=self.decode(compress(content));self.assertEqual(code,0);self.assertEqual(path.read_bytes(),content)
            broken=bytearray(data);broken[-8]^=0x80
            for bad in (data[:-4],data+b'x',data+data,bytes(broken),b'broken'):
                self.assertNotEqual(self.decode(bad)[0],0)
            self.assertEqual(self.decode(data,len(raw)-1)[0],8)
        self.assertNotEqual(self.decode(lzma.compress(raw)+bytes(4))[0],0)
        self.assertEqual(self.decode(lzma.compress(raw,check=lzma.CHECK_NONE))[0],8)
        self.assertEqual(self.decode(lzma.compress(raw,filters=[{'id':lzma.FILTER_LZMA2,'dict_size':128*1024*1024}]))[0],8)
        LIB.arkiv_cancel_set(self.token);self.assertEqual(self.decode(gzip.compress(raw))[0],2)
    def test_creation_independent_decoders_and_no_overwrite(self):
        for kind,decode in enumerate((gzip.decompress,bz2.decompress,lzma.decompress),1):
            for raw in (b'',b'hello',bytes(range(256))*4096):
                for p in self.dest.iterdir():
                    if p.is_file():p.unlink()
                self.source.write_bytes(raw)
                self.assertEqual(self.create(kind),0)
                output=next(p for p in self.dest.iterdir() if p.is_file());packed=output.read_bytes()
                self.assertEqual(decode(packed),raw)
                self.assertEqual(self.create(kind),0);self.assertEqual(output.read_bytes(),packed)
                self.assertEqual(len([p for p in self.dest.iterdir() if p.is_file()]),2)
                self.assertEqual(list((self.dest/'.stage').iterdir()),[])
    def test_cancel_source_changes_and_unsafe_sources_clean_up(self):
        for kind in (1,2,3):
            self.source.write_bytes(bytes(range(256))*4096)
            @PROGRESS
            def change(_,entries,size):
                if size:os.utime(self.source,(1700000000,1700000000))
            self.assertNotEqual(self.create(kind,change),0)
            self.assertEqual(list((self.dest/'.stage').iterdir()),[])
        self.source.unlink();self.source.symlink_to('/etc/hosts')
        self.assertNotEqual(self.create(1),0)
        self.source.unlink();self.source.mkdir();self.assertNotEqual(self.create(1),0)
        self.source.rmdir();os.mkfifo(self.source);self.assertNotEqual(self.create(1),0)
        self.source.unlink();self.source.write_bytes(bytes(1000000))
        @PROGRESS
        def cancel(_,entries,size):LIB.arkiv_cancel_set(self.token)
        self.assertEqual(self.create(1,cancel),2)
        self.assertEqual([p.name for p in self.dest.iterdir()],['.stage'])
if __name__=='__main__':unittest.main()
