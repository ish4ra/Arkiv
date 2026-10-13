"""Rename uses the shared verified ZIP transaction and preserves compressed records."""
from test_zip_addition import LIB
import ctypes as C
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

LIB.arkiv_zip_prepare_rename.argtypes = [C.c_void_p, C.POINTER(C.c_char_p), C.POINTER(C.c_char_p), C.c_size_t, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]

class RenameTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.path = self.root / 'original.zip'
        self.stage = self.root / 'stage'
        self.stage.mkdir(mode=0o700)
        self.error = C.create_string_buffer(256)
        self.t = None
    def tearDown(self):
        if self.t: LIB.arkiv_zip_end(self.t)
        self.tmp.cleanup()
    def fixture(self, comment=b'comment', method=zipfile.ZIP_DEFLATED):
        with zipfile.ZipFile(self.path, 'w') as z:
            for name in ['old', 'keep']:
                entry = zipfile.ZipInfo(name, (2020, 1, 2, 3, 4, 6))
                entry.compress_type = method
                entry.comment = comment
                entry.extra = struct.pack('<HHBI', 0x5455, 5, 1, 1234567890)
                entry.external_attr = 0o100640 << 16
                z.writestr(entry, b'payload' * 100)
            z.comment = b'archive\x00\xff'
        self.before = self.path.read_bytes()
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
    def prepare(self, new=b'new-long-name', old=b'old', token=None):
        return LIB.arkiv_zip_prepare_rename(self.t, (C.c_char_p*2)(old, b'keep'), (C.c_char_p*2)(new, None), 2, os.fsencode(self.stage), token, None, None, self.error, 256)
    def commit(self, token=None):
        return LIB.arkiv_zip_commit(self.t, token, self.error, 256)
    @staticmethod
    def payload(raw, info):
        off = info.header_offset
        n, e = struct.unpack_from('<HH', raw, off+26)
        return raw[off+30+n+e:off+30+n+e+info.compress_size]
    def check_preservation(self, method):
        self.fixture(comment=b'comment\x00\xff', method=method)
        with zipfile.ZipFile(self.path) as z: old = z.infolist()
        self.assertEqual(self.prepare(), 0, self.error.value)
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertEqual(self.commit(), 0, self.error.value)
        after = self.path.read_bytes()
        with zipfile.ZipFile(self.path) as z:
            self.assertEqual(z.namelist(), ['new-long-name', 'keep'])
            self.assertIsNone(z.testzip())
            z.extractall(self.root/'extracted')
            self.assertEqual(z.comment, b'archive\x00\xff')
            for a, b in zip(old, z.infolist()):
                self.assertEqual(self.payload(self.before, a), self.payload(after, b))
                for attribute in ['CRC', 'date_time', 'compress_type', 'compress_size', 'file_size', 'extra', 'comment', 'external_attr', 'internal_attr', 'flag_bits']:
                    self.assertEqual(getattr(a, attribute), getattr(b, attribute), attribute)
                n = struct.unpack_from('<H', after, b.header_offset+26)[0]
                self.assertEqual(after[b.header_offset+30:b.header_offset+30+n].decode(), b.filename)
            a,b=old[1],z.infolist()[1]
            self.assertEqual(self.before[a.header_offset:a.header_offset+30+len(a.filename)+len(a.extra)+a.compress_size], after[b.header_offset:b.header_offset+30+len(b.filename)+len(b.extra)+b.compress_size])
        self.assertEqual((self.root/'extracted/new-long-name').read_bytes(), b'payload'*100)
    def test_store_payload_metadata_local_central_extract(self): self.check_preservation(zipfile.ZIP_STORED)
    def test_deflate_payload_metadata_local_central_extract(self): self.check_preservation(zipfile.ZIP_DEFLATED)
    def test_unicode_sets_matching_utf8_flags(self):
        self.fixture()
        self.assertEqual(self.prepare('資料 🐘'.encode()), 0, self.error.value)
        self.assertEqual(self.commit(), 0)
        with zipfile.ZipFile(self.path) as z:
            self.assertEqual(z.namelist(), ['資料 🐘', 'keep'])
            self.assertTrue(z.infolist()[0].flag_bits & 0x800)
            self.assertIsNone(z.testzip())
    def test_unicode_does_not_reinterpret_legacy_comment(self):
        self.fixture(comment=b'legacy\xff')
        self.assertNotEqual(self.prepare('資料'.encode()), 0)
        self.assertNotEqual(self.commit(), 0)
        self.assertEqual(self.path.read_bytes(), self.before)
    def test_wrong_expected_name_rejected(self):
        self.fixture()
        self.assertNotEqual(self.prepare(old=b'bad'), 0)
        self.assertNotEqual(self.commit(), 0)
        self.assertEqual(self.path.read_bytes(), self.before)
    def test_legacy_non_ascii_name_fails_closed(self):
        self.fixture()
        LIB.arkiv_zip_end(self.t)
        self.t = None
        self.path.write_bytes(self.before.replace(b'old', b'\x82ld'))
        self.before = self.path.read_bytes()
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
        self.assertNotEqual(self.prepare(old=b'\x82ld'), 0)
        self.assertEqual(self.path.read_bytes(), self.before)
    def test_corrupt_unaffected_payload_cannot_commit(self):
        self.fixture(method=zipfile.ZIP_STORED)
        LIB.arkiv_zip_end(self.t)
        self.t = None
        with zipfile.ZipFile(self.path) as z: info = z.infolist()[1]
        raw = bytearray(self.before)
        n,e = struct.unpack_from('<HH', raw, info.header_offset+26)
        raw[info.header_offset+30+n+e] ^= 1
        self.path.write_bytes(raw)
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
        self.assertNotEqual(self.prepare(), 0)
        self.assertNotEqual(self.commit(), 0)
        self.assertEqual(self.path.read_bytes(), raw)
    def test_cancel_and_stale_commit_preserve_original(self):
        self.fixture()
        self.assertEqual(self.prepare(), 0)
        token = LIB.arkiv_cancel_new()
        try:
            LIB.arkiv_cancel_set(token)
            self.assertEqual(self.commit(token), 2)
            self.assertEqual(self.path.read_bytes(), self.before)
        finally: LIB.arkiv_cancel_free(token)
        self.path.write_bytes(b'another writer')
        self.assertNotEqual(self.commit(), 0)
        self.assertEqual(self.path.read_bytes(), b'another writer')

if __name__ == '__main__': unittest.main()
