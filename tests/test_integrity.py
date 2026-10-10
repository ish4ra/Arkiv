"""Integrity is full data decoding, never an extraction/publication operation."""
import ctypes as C
import io
import os
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
import zipfile

LIB = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
class Limits(C.Structure):
    _fields_ = [('entries', C.c_uint64), ('bytes', C.c_uint64)]
PROGRESS = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64, C.c_uint64)
LIB.arkiv_test.argtypes = [C.c_char_p, C.c_char_p, Limits, C.c_void_p, PROGRESS, C.c_void_p, C.c_char_p, C.c_size_t]
LIB.arkiv_cancel_new.restype = C.c_void_p
LIB.arkiv_cancel_set.argtypes = [C.c_void_p]
LIB.arkiv_cancel_free.argtypes = [C.c_void_p]

class IntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name).resolve() / 'archive'
        self.token = LIB.arkiv_cancel_new()
    def tearDown(self):
        LIB.arkiv_cancel_free(self.token)
        self.tmp.cleanup()
    def check(self, password=None, cancel=False, limits=None):
        before = self.path.read_bytes()
        seen = []
        @PROGRESS
        def progress(_, files, size):
            seen.append((files,size))
            if cancel: LIB.arkiv_cancel_set(self.token)
        error = C.create_string_buffer(256)
        code = LIB.arkiv_test(os.fsencode(self.path), password, limits or Limits(1000, 10000000), self.token, progress, None, error, len(error))
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])
        return code, seen
    def zip(self, payload=b'payload'*100, compression=zipfile.ZIP_STORED):
        with zipfile.ZipFile(self.path, 'w', compression=compression) as z:
            z.writestr('folder/file.txt',payload)
    def test_valid_zip_store_deflate_and_empty(self):
        for compression in [zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED]:
            self.zip(compression=compression)
            result,progress=self.check();self.assertEqual(result,0);self.assertTrue(progress)
        with zipfile.ZipFile(self.path,'w'):pass
        self.assertEqual(self.check()[0],0)
    def test_crc_mismatch_actual_payload(self):
        self.zip()
        raw=bytearray(self.path.read_bytes());offset=30+struct.unpack_from('<H',raw,26)[0]+struct.unpack_from('<H',raw,28)[0]
        raw[offset]^=1;self.path.write_bytes(raw)
        self.assertEqual(self.check()[0],7)
    def test_missing_central_directory_or_end_record(self):
        self.zip();raw=self.path.read_bytes()
        for cut in [raw.index(b'PK\x01\x02'),len(raw)-22,len(raw)-1]:
            self.path.write_bytes(raw[:cut]);self.assertNotEqual(self.check()[0],0)
    def test_bad_central_directory(self):
        self.zip();raw=bytearray(self.path.read_bytes());central=raw.index(b'PK\x01\x02')
        raw[central]=0;self.path.write_bytes(raw);self.assertNotEqual(self.check()[0],0)
    def test_payload_cannot_be_hidden_by_empty_directory(self):
        self.zip();raw=self.path.read_bytes();offset=raw.index(b'PK\x01\x02')
        end=struct.pack('<4s4H2IH',b'PK\x05\x06',0,0,0,0,0,offset,0)
        self.path.write_bytes(raw[:offset]+end)
        self.assertEqual(self.check()[0],6)
    def test_zip64_directory_and_count_mismatch(self):
        self.zip();raw=self.path.read_bytes();end=len(raw)-22
        fields=struct.unpack_from('<4s4H2IH',raw,end)
        count, directory_size, offset=fields[4:7]
        record=struct.pack('<4sQ2H2I4Q',b'PK\x06\x06',44,45,45,0,0,count,count,directory_size,offset)
        locator=struct.pack('<4sIQI',b'PK\x06\x07',0,end,1)
        eocd=struct.pack('<4s4H2IH',b'PK\x05\x06',0,0,65535,65535,0xffffffff,0xffffffff,0)
        self.path.write_bytes(raw[:end]+record+locator+eocd);self.assertEqual(self.check()[0],0)
        broken=bytearray(raw);struct.pack_into('<HH',broken,end+8,count+1,count+1)
        self.path.write_bytes(broken);self.assertEqual(self.check()[0],6)
    def test_zip_comment_and_hostile_directory_bounds(self):
        self.zip();raw=self.path.read_bytes();end=len(raw)-22
        commented=bytearray(raw);struct.pack_into('<H',commented,end+20,4);commented+=b'test'
        self.path.write_bytes(commented);self.assertEqual(self.check()[0],0)
        broken=bytearray(raw);struct.pack_into('<I',broken,end+16,0xfffffff0)
        self.path.write_bytes(broken);self.assertEqual(self.check()[0],6)
    def test_cancel_during_data_read(self):
        self.zip(b'a'*500000)
        self.assertEqual(self.check(cancel=True)[0],2)
    def test_byte_limit(self):
        self.zip(b'a'*500000)
        self.assertNotEqual(self.check(limits=Limits(100,100))[0],0)
    def test_tar_warns_even_if_payload_modified_but_truncation_fails(self):
        with tarfile.open(self.path,'w') as t:
            e=tarfile.TarInfo('file');e.size=1000;t.addfile(e,io.BytesIO(b'a'*1000))
        raw=bytearray(self.path.read_bytes());self.assertEqual(self.check()[0],9)
        raw[512]^=1;self.path.write_bytes(raw);self.assertEqual(self.check()[0],9)
        self.path.write_bytes(raw[:600]);self.assertNotIn(self.check()[0],[0,9])
    def test_seven_corruption_and_streaming_cancel(self):
        raw=(Path(__file__).parent/'fixtures'/'created-plain.7z').read_bytes()
        self.path.write_bytes(raw[:-8]);self.assertNotEqual(self.check()[0],0)
        self.path.write_bytes(raw);self.assertEqual(self.check(cancel=True)[0],2)
    def test_seven_honors_caller_limits(self):
        self.path.write_bytes((Path(__file__).parent/'fixtures'/'created-plain.7z').read_bytes())
        self.assertNotEqual(self.check(limits=Limits(0,0))[0],0)
    def test_seven_encrypted_password_and_plain(self):
        fixtures=Path(__file__).parent/'fixtures'
        self.path.write_bytes((fixtures/'created-plain.7z').read_bytes());self.assertEqual(self.check()[0],0)
        self.path.write_bytes((fixtures/'created-aes-headers.7z').read_bytes());self.assertEqual(self.check()[0],4)
        self.assertEqual(self.check(b'wrong')[0],5)
        self.assertEqual(self.check(b'fixture password')[0],0)

if __name__=='__main__':unittest.main()
