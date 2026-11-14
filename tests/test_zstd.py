"""Pinned decoder policy against independently generated Zstandard fixtures."""
import ctypes as C, os, struct, unittest, hashlib, json, random, subprocess
from pathlib import Path
from test_standalone import StandaloneTests, LIB, PROGRESS, Limits
from test_tar_creation import TARCreationTests
FIXTURES=Path(__file__).parent/'fixtures'
RAW=('database content é 🐘\n'*10000).encode()
LIB.arkiv_decompress_stream_inspect.argtypes=[C.c_char_p,C.c_char_p,C.c_uint64,C.c_void_p,C.c_void_p,C.c_void_p,C.POINTER(C.c_int)]
class ZstandardTests(StandaloneTests):
    # Inherit source/no-follow/cleanup regressions; creation is always ZSTD here.
    def create(self,kind=4,callback=None):
        error=C.create_string_buffer(256)
        return LIB.arkiv_create_stream(bytes(self.source),bytes(self.dest),b'.stage',b'result.zst',C.create_string_buffer(512),512,4,Limits(100000,20*1024**3),self.token,callback,None,error,256)
    def test_pinned_backend_source_and_license(self):
        root=Path(__file__).resolve().parents[1]
        for path,digest in json.loads((root/"Sources/CZstd/checksums.json").read_text()).items():
            self.assertEqual(hashlib.sha256((root/path).read_bytes()).hexdigest(),digest,path)
    def test_no_accidental_host_zstd_headers(self):
        root=Path(__file__).resolve().parents[1]
        for source in ['Sources/CZstd/zstd.c','Sources/CArkiv/ArkivCompressedTAR.c']:
            deps=subprocess.check_output(['cc','-M','-I',str(root/'Sources/CZstd/include'),'-I',str(root/'Sources/CArkiv/include'),'-I',str(root/'Sources/CArkiv/vendor/xz'),str(root/source)],text=True)
            for dependency in deps.split():
                if dependency.endswith(('/zstd.h','/zstd_errors.h')):
                    self.assertEqual(Path(dependency).resolve().parent,root/'Sources/CZstd/include')
    def test_creation_independent_decoders_and_no_overwrite(self):
        for raw in (b'',b'hello',bytes(range(256))*4096,random.Random(42).randbytes(300000)):
            for p in self.dest.iterdir():
                if p.is_file():p.unlink()
            self.source.write_bytes(raw)
            self.assertEqual(self.create(),0)
            packed=(self.dest/'result.zst').read_bytes()
            self.assertTrue(packed[4]&4,'creation must enable the content checksum')
            result,out=self.decode(packed);self.assertEqual(result,0);self.assertEqual(out.read_bytes(),raw)
            self.source.write_bytes(raw);self.assertEqual(self.create(),0)
            self.assertEqual((self.dest/'result.zst').read_bytes(),packed)
            self.assertTrue((self.dest/'result (2).zst').exists())
            self.assertEqual(list((self.dest/'.stage').iterdir()),[])
    def test_frame_policy_and_checksum_evidence(self):
        for name,raw,checksum in [('standalone.sql',RAW,1),('standalone-empty',b'',1),('zstd-no-checksum',RAW,0),('zstd-unknown-size',RAW,1)]:
            self.source.write_bytes((FIXTURES/(name+'.zst')).read_bytes());out=self.root/'out';evidence=C.c_int(-1)
            self.assertEqual(LIB.arkiv_decompress_stream_inspect(bytes(self.source),bytes(out),len(raw),self.token,None,None,C.byref(evidence)),0)
            self.assertEqual(evidence.value,checksum);self.assertEqual(out.read_bytes(),raw);out.unlink()
        data=(FIXTURES/'standalone.sql.zst').read_bytes()
        bad=bytearray(data);bad[-1]^=1
        for payload in (data[:-1],data[:7],bytes(bad),data+b'junk',data+data,struct.pack('<II',0x184D2A50,0),struct.pack('<II',0x184D2A50,3)+b'abc'+data):
            self.assertNotEqual(self.decode(payload)[0],0)
        for name in ['zstd-large-window.zst','zstd-dictionary.zst']:
            self.assertEqual(self.decode((FIXTURES/name).read_bytes())[0],8)
        self.assertEqual(self.decode(data,len(RAW)-1)[0],8)
        self.assertEqual(self.decode(data,21*1024**3)[0],8)
        unknown=(FIXTURES/'zstd-unknown-size.zst').read_bytes()
        self.assertEqual(self.decode(unknown,len(RAW)-1)[0],8)
        boundary=bytearray(unknown);boundary[5]=0x80 # exactly 64 MiB, within policy
        self.assertEqual(self.decode(bytes(boundary))[0],0)
        LIB.arkiv_cancel_set(self.token);self.assertEqual(self.decode(data)[0],2)
    def test_decode_midstream_cancel_and_source_revalidation(self):
        data=(FIXTURES/'standalone.sql.zst').read_bytes()
        for cancel in [False,True]:
            self.source.write_bytes(data);out=self.root/'out'
            @PROGRESS
            def callback(_,count,size):
                if cancel:LIB.arkiv_cancel_set(self.token)
                else:os.utime(self.source,(1700000000,1700000000))
            result=LIB.arkiv_decompress_stream_inspect(bytes(self.source),bytes(out),len(RAW),self.token,callback,None,None)
            self.assertEqual(result,2 if cancel else 6);self.assertFalse(out.exists())
class ZstdTARCreationTests(TARCreationTests):
    def create(self,codec=4,suffix='.tar.zst',limits=None,callback=None,token=None,source=None):
        return super().create(4,'.tar.zst',limits,callback,token,source)
    def test_variants_independent_checksums_pax_metadata_and_collision(self):
        # Existing TAR assertions below use stdlib compression dispatch, so run
        # equivalent checks after the bounded decoder provides the actual TAR.
        import tarfile
        self.assertEqual(self.create(),0)
        output=self.output/'result.tar.zst';tar=self.root/'verified.tar'
        self.assertEqual(LIB.arkiv_decompress_stream(bytes(output),bytes(tar),20*1024**3,None),0)
        with tarfile.open(tar) as archive:
            self.assertEqual(archive.extractfile(self.source.name+'/'+self.file.name).read(),self.data)
            self.assertTrue(archive.getmember(self.source.name+'/empty').isdir())
            self.assertEqual(archive.getmember(self.source.name+'/'+self.file.name).mode,0o751)
# Avoid running imported base classes twice under unittest discovery.
del StandaloneTests, TARCreationTests
if __name__=='__main__':unittest.main()
