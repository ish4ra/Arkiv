"""Independent upstream RAR payloads; header mutation never implements an encoder."""
import ctypes as C, hashlib, json, os, struct, unittest, zlib
from pathlib import Path
import test_engine
from test_engine import LIB, Limits, PROGRESS
FIX=Path(__file__).parent/'fixtures/rar'
LIB.arkiv_test.argtypes=[C.c_char_p,C.c_char_p,Limits,C.c_void_p,PROGRESS,C.c_void_p,C.c_char_p,C.c_size_t]
class RARTests(unittest.TestCase):
    def setUp(self): self.t=test_engine.EngineTests();self.t.setUp();self.t.base=self.t.base.resolve();self.t.archive=self.t.base/'input';self.t.out=self.t.base/'out'
    def tearDown(self): self.t.tearDown()
    def load(self,name): self.t.archive.write_bytes((FIX/(name+'.rar')).read_bytes())
    def check(self,callback=None):
        return LIB.arkiv_test(bytes(self.t.archive),None,self.t.limits,self.t.token,PROGRESS(callback or (lambda *a:None)),None,C.create_string_buffer(256),256)
    def test_fixture_provenance(self):
        for name,info in json.loads((FIX/'provenance.json').read_text()).items():self.assertEqual(hashlib.sha256((FIX/name).read_bytes()).hexdigest(),info['sha256'])
    def test_rar4_store_normal_best_hierarchy_and_full_payload(self):
        for name in ['rar4-stored','rar4-normal','rar4-best','rar4-unicode']:
            with self.subTest(name=name):
                self.load(name);status,rows,_=self.t.listing();self.assertEqual(status,0);self.assertEqual(self.check(),0)
                self.assertEqual(self.t.extract()[0],0)
                if name!='rar4-unicode':
                    self.assertEqual((self.t.out/'testdir/test.txt').read_bytes(),b'test text document\r\n')
                    self.assertTrue((self.t.out/'testemptydir').is_dir())
                    if name!='rar4-stored':
                        data=(self.t.out/'LibarchiveAddingTest.html').read_bytes();self.assertEqual(len(data),20111)
                        self.assertEqual(data,(self.t.out/'testdir/LibarchiveAddingTest.html').read_bytes())
                        self.assertTrue(data.endswith(b'<P STYLE="margin-bottom: 0in"><BR>\n</P>\n</BODY>\n</HTML>'))
                else:self.assertEqual((self.t.out/'表だよ/漢字長いファイル名long-filename-in-漢字.txt').read_bytes(),b'kanji')
                import shutil
                shutil.rmtree(self.t.out);self.t.out.mkdir()
    def test_rar4_large_multiblock_payload_and_limit(self):
        self.load('rar4-large');self.t.limits=Limits(100,32<<20)
        self.assertEqual(self.check(),0);self.assertEqual(self.t.extract()[0],0)
        payload=(self.t.out/'multi_lzss_blocks_test.txt').read_bytes()
        self.assertEqual(len(payload),20131111)
        self.assertTrue(payload.endswith(b'-bottom: 0in"><BR>\n</P>\n</BODY>\n</HTML>'))
        self.t.limits=Limits(100,8<<20);self.assertNotEqual(self.check(),0)
    def test_rar5_full_and_selected_polynomial_bytes(self):
        for name,magic,size in [('rar5-compressed',0,1200),('rar5-multiple',1,4096)]:
            self.load(name);status,rows,_=self.t.listing();self.assertEqual(status,0);self.assertEqual(self.check(),0)
            ids=[0] if magic==0 else [0,2]
            self.assertEqual(self.t.extract(ids)[0],0)
            for i in ids:
                expected=b''.join(struct.pack('<I',max(0,k*k-3*k+1+magic+i)) for k in range(1,size//4+1))
                self.assertEqual((self.t.out/rows[i][1]).read_bytes(),expected)
            self.assertEqual(len(list(self.t.out.iterdir())),len(ids))
            for p in self.t.out.iterdir():p.unlink()
    def test_rar5_unicode_links_and_checksums(self):
        self.load('rar5-unicode');self.assertEqual(self.t.listing()[0],0);self.assertEqual(self.check(),0)
        self.assertEqual(self.t.extract()[0],0)
        self.assertEqual((self.t.out/'👋🌎.txt').read_bytes(),(self.t.out/'Ⓗⓐⓡⓓ Ⓛⓘⓝⓚ.txt').read_bytes())
        self.assertEqual(os.readlink(self.t.out/'𝒮𝓎𝓂𝒷𝑜𝓁𝒾𝒸 𝐿𝒾𝓃𝓀.txt'),'👋🌎.txt')
    def test_encrypted_solid_and_multipart_fail_before_output(self):
        for name,code in [('rar4-encrypted-data',8),('rar4-encrypted-header',8),('rar5-solid',8),('rar4-volume',10),('rar5-volume',10)]:
            self.load(name);self.assertNotEqual(self.t.listing()[0],0);self.assertEqual(self.check(),code)
            self.assertNotEqual(self.t.extract()[0],0);self.assertEqual(list(self.t.out.iterdir()),[])
    def test_corrupt_header_payload_truncation_and_limits(self):
        for name in ['rar4-stored','rar5-compressed']:
            self.load(name);raw=self.t.archive.read_bytes()
            for n in [7,8,20,len(raw)-1,len(raw)//2]:
                self.t.archive.write_bytes(raw[:n]);self.assertNotEqual(self.check(),0)
            changed=bytearray(raw);changed[12]^=0x40;self.t.archive.write_bytes(changed);self.assertNotEqual(self.check(),0)
            self.t.archive.write_bytes(raw);self.t.limits=Limits(100,1);self.assertNotEqual(self.check(),0)
            self.t.limits=Limits(10000,8<<20)
        self.load('rar4-stored');raw=bytearray(self.t.archive.read_bytes());i=raw.index(b'test text document');raw[i]^=1;self.t.archive.write_bytes(raw)
        self.assertEqual(self.check(),7);self.assertNotEqual(self.t.extract()[0],0)
    def test_hostile_path_and_unsupported_method_headers(self):
        self.load('rar4-stored');raw=self.t.archive.read_bytes();offset=7
        while raw[offset+2]!=0x74:offset+=struct.unpack_from('<H',raw,offset+5)[0]
        length=struct.unpack_from('<H',raw,offset+5)[0]
        for unsafe in [b'../x.txt',b'/bad.txt',b'C:/x.txt']:
            changed=bytearray(raw);changed[offset+32:offset+40]=unsafe
            struct.pack_into('<H',changed,offset,zlib.crc32(changed[offset+2:offset+length])&65535)
            self.t.archive.write_bytes(changed);self.assertNotEqual(self.t.listing()[0],0);self.assertNotEqual(self.check(),0);self.assertNotEqual(self.t.extract()[0],0)
        changed=bytearray(raw);changed[offset+25]=0x36;struct.pack_into('<H',changed,offset,zlib.crc32(changed[offset+2:offset+length])&65535)
        self.t.archive.write_bytes(changed);self.assertEqual(self.check(),8);self.assertEqual(list(self.t.out.iterdir()),[])
    def test_rar5_absent_crc_is_warning_and_header_encryption_rejects(self):
        def vint(data,p):
            value=0;shift=0
            while True:
                b=data[p];p+=1;value|=(b&127)<<shift
                if not b&128:return value,p
                shift+=7
        self.load('rar5-compressed');raw=self.t.archive.read_bytes();offset=8
        while True:
            size,p=vint(raw,offset+4);end=p+size;kind,p=vint(raw,p);flags,p=vint(raw,p)
            extra=0;data=0
            if flags&1:extra,p=vint(raw,p)
            if flags&2:data,p=vint(raw,p)
            if kind==2:break
            offset=end+data
        fileflags=p;ff,p=vint(raw,p);_,p=vint(raw,p);_,p=vint(raw,p)
        if ff&2:p+=4
        self.assertTrue(ff&4);self.assertLess(size,128)
        h=bytearray(raw[offset:end]);h[fileflags-offset]&=~4
        del h[p-offset:p-offset+4];h[4]-=4;struct.pack_into('<I',h,0,zlib.crc32(h[4:]))
        self.t.archive.write_bytes(raw[:offset]+h+raw[end:]);self.assertEqual(self.check(),11)
        self.assertEqual(self.t.extract()[0],0)
        # RAR5 type 4 is an encryption header; no ciphertext or password guessing.
        crypt=bytes([4,0,0]);header=bytes([len(crypt)])+crypt
        self.t.archive.write_bytes(raw[:8]+struct.pack('<I',zlib.crc32(header))+header)
        self.assertEqual(self.check(),8)
    def test_sfx_cannot_bypass_envelope_admission(self):
        for name in ['rar4-stored','rar5-compressed']:
            self.load(name);raw=self.t.archive.read_bytes()
            self.t.archive.write_bytes(b'MZ'+b'\0'*(65536-2)+raw)
            self.assertNotEqual(self.t.listing()[0],0)
            self.assertNotEqual(self.check(),0)
            self.assertNotEqual(self.t.extract()[0],0)
            self.assertEqual(list(self.t.out.iterdir()),[])
    def test_cancellation_during_full_decode(self):
        self.load('rar5-multiple');before=self.t.archive.read_bytes()
        self.assertEqual(self.check(lambda *args:LIB.arkiv_cancel_set(self.t.token)),2)
        self.assertEqual(self.t.archive.read_bytes(),before);self.assertEqual(list(self.t.out.iterdir()),[])
if __name__=='__main__':unittest.main()
