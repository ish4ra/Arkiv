"""WinZip-produced corpus, independently generated fixtures and adversarial ZIP32 layouts."""
import ctypes as C, os, unittest
from pathlib import Path
import test_integrity
FIX=Path(__file__).parent/'fixtures/zip-aes'
class ZIPAESTests(unittest.TestCase):
    def test_independent_aes_store_deflate_and_passwords(self):
        t=test_integrity.IntegrityTests();t.setUp()
        try:
            for name in ['winzip_aes128','winzip_aes256','winzip_aes256_stored']:
                t.path.write_bytes((FIX/(name+'.zip')).read_bytes())
                self.assertEqual(t.check()[0],4,name)
                self.assertEqual(t.check(b'wrong')[0],5,name)
                self.assertEqual(t.check(b'password')[0],0,name)
        finally:t.tearDown()

# Fixtures produced with pyzipper 0.3.6 / pycryptodomex 3.23.0:
# AESZipFile(..., compression=0 or 8, encryption=WZ_AES), setpassword(b'fixture password'),
# setencryption(WZ_AES, nbits=128/192/256, force_wz_aes_version=1/2); write
# folder/資料 🐘.txt = b'authenticated content\n'*2000, empty.txt = b'', then
# setpassword(None), setencryption(None); plain.txt=b'plain content', empty-folder/=b''.
import hashlib, hmac, json, struct, tarfile, tempfile, zipfile
LIB=test_integrity.LIB
LIB.arkiv_unlock_zip_aes.argtypes=[C.c_char_p,C.c_char_p,C.c_char_p,test_integrity.Limits,C.c_void_p,test_integrity.PROGRESS,C.c_void_p]
class AESHostileTests(unittest.TestCase):
    def setUp(self):
        self.t=test_integrity.IntegrityTests();self.t.setUp();self.path=self.t.path
        self.out=self.path.parent/'plain.tar'
    def tearDown(self):self.t.tearDown()
    def unlock(self,password=b'fixture password',limit=10000000,callback=None):
        return LIB.arkiv_unlock_zip_aes(bytes(self.path),bytes(self.out),password,test_integrity.Limits(1000,limit),self.t.token,test_integrity.PROGRESS(callback or (lambda *args:None)),None)
    def load(self,name='pyzipper-ae2-256-0.zip'):self.path.write_bytes((FIX/name).read_bytes())
    def test_all_independent_variants_mixed_empty_and_metadata(self):
        manifest=json.loads((FIX/'provenance.json').read_text())
        for name in manifest:
            self.assertEqual(hashlib.sha256((FIX/name).read_bytes()).hexdigest(),manifest[name]['sha256'])
            if not name.startswith('pyzipper'):continue
            self.load(name);self.assertEqual(self.unlock(),0,name)
            with tarfile.open(self.out) as t:
                self.assertEqual(t.extractfile('folder/資料 🐘.txt').read(),b'authenticated content\n'*2000)
                self.assertEqual(t.extractfile('empty.txt').read(),b'')
                self.assertEqual(t.extractfile('plain.txt').read(),b'plain content')
                self.assertTrue(t.getmember('empty-folder').isdir())
            self.out.unlink()
    def test_authentication_tags_including_empty_file(self):
        for filename in ['folder/資料 🐘.txt','empty.txt']:
            self.load()
            with zipfile.ZipFile(self.path) as z:info=z.getinfo(filename)
            raw=bytearray(self.path.read_bytes());off=info.header_offset;data=off+30+struct.unpack_from('<H',raw,off+26)[0]+struct.unpack_from('<H',raw,off+28)[0]
            raw[data+info.compress_size-1]^=1;self.path.write_bytes(raw)
            self.assertEqual(self.unlock(),12,filename);self.assertFalse(self.out.exists())
    def test_macos_metadata_named_files_are_authenticated_not_hidden(self):
        import pyzipper
        with pyzipper.AESZipFile(self.path,'w',encryption=pyzipper.WZ_AES) as z:
            z.setpassword(b'fixture password')
            z.writestr('file.txt',b'data');z.writestr('__MACOSX/._file.txt',b'ordinary named file')
        self.assertEqual(self.unlock(),0)
        with tarfile.open(self.out) as t:
            self.assertEqual(t.extractfile('__MACOSX/._file.txt').read(),b'ordinary named file')
        self.out.unlink()
        with zipfile.ZipFile(self.path) as z: info=z.getinfo('__MACOSX/._file.txt')
        raw=bytearray(self.path.read_bytes());off=info.header_offset
        start=off+30+struct.unpack_from('<H',raw,off+26)[0]+struct.unpack_from('<H',raw,off+28)[0]
        raw[start+info.compress_size-1]^=1;self.path.write_bytes(raw)
        self.assertEqual(self.unlock(),12);self.assertFalse(self.out.exists())
    def test_encrypted_directories_and_special_entries_never_bypass_authentication(self):
        self.load('encrypted-directory.zip')
        original=self.path.read_bytes()
        with zipfile.ZipFile(self.path) as z: info=z.getinfo('empty/')
        central=original.index(b'PK\x01\x02',original.index(b'PK\x01\x02')+4)
        data=info.header_offset+30+len(info.filename)+len(info.extra)
        # Independent pyzipper fixture; reject both authentic and damaged tags,
        # before any password request. Exercise each directory representation and
        # Unix special type, even if the other metadata calls it a regular file.
        for representation in ['slash','unix','dos','symlink','fifo','device','socket']:
            raw=bytearray(original)
            struct.pack_into('<I',raw,central+38,0o100600<<16)
            if representation != 'slash':
                raw[info.header_offset+30+5]=ord('x');raw[central+46+5]=ord('x')
            types={'unix':0o040700,'symlink':0o120700,'fifo':0o010600,'device':0o020600,'socket':0o140600}
            if representation in types: struct.pack_into('<I',raw,central+38,types[representation]<<16)
            if representation == 'dos': struct.pack_into('<I',raw,central+38,0x10)
            for tampered in [False,True]:
                candidate=bytearray(raw)
                if tampered: candidate[data+info.compress_size-1]^=1
                self.path.write_bytes(candidate)
                for password in [None,b'wrong',b'fixture password']:
                    with self.subTest(representation=representation,tampered=tampered,passwordProvided=password is not None):
                        self.assertEqual(self.unlock(password),8);self.assertFalse(self.out.exists())
                        self.assertEqual(self.t.check(password)[0],8)
    def test_password_cancel_limit_and_stale_source_cleanup(self):
        self.load();self.assertEqual(self.unlock(None),4);self.assertFalse(self.out.exists())
        self.assertEqual(self.unlock(b'wrong'),5);self.assertFalse(self.out.exists())
        self.assertNotEqual(self.unlock(limit=32),0);self.assertFalse(self.out.exists())
        self.assertNotEqual(self.unlock(callback=lambda *args:self.path.write_bytes(self.path.read_bytes()+b'x')),0);self.assertFalse(self.out.exists())
        self.load();self.assertEqual(self.unlock(callback=lambda *args:LIB.arkiv_cancel_set(self.t.token)),2);self.assertFalse(self.out.exists())
    def test_malformed_extra_headers_method_crc_and_truncation(self):
        self.load();original=self.path.read_bytes();central=original.index(b'PK\x01\x02');aes=original.index(b'\x01\x99\x07\x00')
        cases=[]
        for index in [aes+4,aes+6,aes+8,aes+9,central+8,central+10,central+16]:
            raw=bytearray(original);raw[index]^=0x40;cases.append(raw)
        cases += [original[:-1],original[:-22],original[:central],original[:len(original)//2]]
        for raw in cases:
            self.path.write_bytes(raw);self.assertNotEqual(self.unlock(),0);self.assertFalse(self.out.exists())
    def test_duplicate_paths_traversal_and_overlapping_records_reject(self):
        import pyzipper
        with pyzipper.AESZipFile(self.path,'w',encryption=pyzipper.WZ_AES) as z:
            z.setpassword(b'fixture password');z.writestr('a.txt',b'first');z.writestr('b.txt',b'second')
        raw=self.path.read_bytes()
        self.path.write_bytes(raw.replace(b'b.txt',b'a.txt'))
        self.assertNotEqual(self.unlock(),0);self.assertFalse(self.out.exists())
        self.path.write_bytes(raw.replace(b'a.txt',b'../xx'))
        self.assertNotEqual(self.unlock(),0);self.assertFalse(self.out.exists());self.assertFalse((self.path.parent.parent/'xx').exists())
        broken=bytearray(raw);first=raw.index(b'PK\x01\x02');second=raw.index(b'PK\x01\x02',first+4)
        struct.pack_into('<I',broken,second+42,0);self.path.write_bytes(broken)
        self.assertNotEqual(self.unlock(),0);self.assertFalse(self.out.exists())
    def test_unsupported_encrypted_layout_cannot_use_plain_listing_or_selection(self):
        import test_engine
        self.load();raw=self.path.read_bytes();end=len(raw)-22
        fields=struct.unpack_from('<4s4H2IH',raw,end)
        count,size,offset=fields[4:7]
        zip64=raw[:end]+struct.pack('<4sQ2H2I4Q',b'PK\x06\x06',44,45,45,0,0,count,count,size,offset)
        zip64+=struct.pack('<4sIQI',b'PK\x06\x07',0,end,1)+struct.pack('<4s4H2IH',b'PK\x05\x06',0,0,65535,65535,0xffffffff,0xffffffff,0)
        for candidate in [zip64,b'X'*100+raw,raw]:
            t=test_engine.EngineTests();t.setUp()
            try:
                t.archive.write_bytes(candidate)
                self.assertNotEqual(t.listing()[0],0)
                self.assertNotEqual(t.extract([2])[0],0)
                self.assertEqual(list(t.out.iterdir()),[])
            finally:t.tearDown()
    def test_authenticated_invalid_deflate_and_ae1_crc(self):
        self.load('pyzipper-ae2-256-8.zip');raw=bytearray(self.path.read_bytes())
        with zipfile.ZipFile(self.path) as z:info=z.infolist()[0]
        data=30+struct.unpack_from('<H',raw,26)[0]+struct.unpack_from('<H',raw,28)[0]
        key=hashlib.pbkdf2_hmac('sha1',b'fixture password',raw[data:data+16],1000,66)
        start=data+18;end=data+info.compress_size-10;raw[start]^=0xff
        raw[end:end+10]=hmac.new(key[32:64],raw[start:end],'sha1').digest()[:10]
        self.path.write_bytes(raw);self.assertNotEqual(self.unlock(),0);self.assertFalse(self.out.exists())
        self.load('pyzipper-ae1-256-0.zip');raw=bytearray(self.path.read_bytes());central=raw.index(b'PK\x01\x02')
        raw[14]^=1;raw[central+16]^=1;self.path.write_bytes(raw)
        self.assertEqual(self.unlock(),7);self.assertFalse(self.out.exists())

class AESCreationTests(unittest.TestCase):
    def test_creation_is_aes256_and_independent_reader_accepts(self):
        import pyzipper
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();source=root/'資料.txt';source.write_bytes(b'new encrypted payload'*5000)
            destination=root/'out';destination.mkdir();(destination/'.stage').mkdir(mode=0o700)
            args=[C.POINTER(C.c_char_p),C.c_size_t,C.c_char_p,C.c_char_p,C.c_char_p,C.c_char_p,C.c_size_t,C.c_int,test_integrity.Limits,C.c_void_p,test_integrity.PROGRESS,C.c_void_p,C.c_char_p,C.c_size_t,C.c_int,C.c_char_p,C.c_int,C.c_int]
            LIB.arkiv_create_archive_preset.argtypes=args
            for method in [0,1]:
                inputs=(C.c_char_p*1)(bytes(source));published=C.create_string_buffer(512);error=C.create_string_buffer(256)
                code=LIB.arkiv_create_archive_preset(inputs,1,bytes(destination),b'.stage',b'aes.zip',published,512,method,test_integrity.Limits(1000,10000000),None,test_integrity.PROGRESS(lambda *a:None),None,error,256,0,b'fixture password',0,0 if method==0 else 6)
                self.assertEqual(code,0,error.value)
                with pyzipper.AESZipFile(destination/published.value.decode()) as z:
                    e=z.infolist()[0];self.assertTrue(e.flag_bits&1);self.assertEqual(e.wz_aes_strength,3)
                    self.assertEqual(z.read(e.filename,pwd=b'fixture password'),source.read_bytes())
                self.assertEqual(list((destination/'.stage').iterdir()),[])

if __name__=='__main__':unittest.main()
