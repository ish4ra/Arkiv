"""Replacement preserves original names/metadata and unrelated raw records."""
import test_zip_rename as rename
LIB = rename.LIB
import ctypes as C
import os
import zipfile
import unittest

LIB.arkiv_zip_prepare_replace.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_size_t, C.c_char_p, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]

class ReplacementTests(unittest.TestCase):
    setUp = rename.RenameTests.setUp
    tearDown = rename.RenameTests.tearDown
    fixture = rename.RenameTests.fixture
    commit = rename.RenameTests.commit
    def prepare_replacement(self, payload, method=zipfile.ZIP_DEFLATED, name=b'old', ordinal=0, count=2, token=None):
        content = self.root / 'content.zip'
        with zipfile.ZipFile(content, 'w', compression=method) as z:
            entry = zipfile.ZipInfo('different.txt')
            entry.compress_type = method
            entry.external_attr = 0o100600 << 16
            z.writestr(entry, payload)
        return LIB.arkiv_zip_prepare_replace(self.t, os.fsencode(content), ordinal, count, name, os.fsencode(self.stage), token, None, None, self.error, 256)
    def test_content_sizes_methods_and_metadata(self):
        for method in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]:
            for payload in [b'', b'x', b'large replacement'*10000]:
                with self.subTest(method=method, size=len(payload)):
                    if self.t: LIB.arkiv_zip_end(self.t); self.t=None
                    (self.stage/'replacement.zip').unlink(missing_ok=True)
                    self.fixture(comment=b'legacy\x00\xff', method=method)
                    with zipfile.ZipFile(self.path) as z: old=z.infolist(); central=z.start_dir
                    self.assertEqual(self.prepare_replacement(payload, method), 0, self.error.value)
                    self.assertEqual(self.path.read_bytes(), self.before)
                    self.assertEqual(self.commit(), 0, self.error.value)
                    after=self.path.read_bytes()
                    with zipfile.ZipFile(self.path) as z:
                        self.assertEqual(z.namelist(), ['old','keep'])
                        self.assertEqual(z.read('old'), payload)
                        self.assertEqual(z.read('keep'), b'payload'*100)
                        self.assertIsNone(z.testzip())
                        self.assertEqual(z.comment,b'archive\x00\xff')
                        for a,b in zip(old,z.infolist()):
                            for attr in ['filename','date_time','compress_type','extra','comment','external_attr','internal_attr']:
                                self.assertEqual(getattr(a,attr),getattr(b,attr),attr)
                        self.assertEqual(self.before[old[1].header_offset:central], after[z.infolist()[1].header_offset:z.start_dir])
                        z.extractall(self.root/'extracted')
                    self.assertEqual((self.root/'extracted/old').read_bytes(),payload)
    def test_unicode_original_name_and_rejected_opaque_extra(self):
        name = 'folder/資料 🐘.txt'
        with zipfile.ZipFile(self.path, 'w') as z:
            entry = zipfile.ZipInfo(name)
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(entry, b'old')
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
        self.assertEqual(self.prepare_replacement(b'new', name=name.encode(), count=1), 0, self.error.value)
        self.assertEqual(self.commit(), 0)
        with zipfile.ZipFile(self.path) as z:
            self.assertEqual(z.namelist(), [name])
            self.assertEqual(z.read(name), b'new')
        LIB.arkiv_zip_end(self.t); self.t = None
        with zipfile.ZipFile(self.path, 'w') as z:
            entry.extra = b'\x34\x12\x00\x00'
            z.writestr(entry, b'old')
        self.assertFalse(LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256))
    def test_corrupt_unrelated_entry_fails_verification(self):
        self.fixture(method=zipfile.ZIP_STORED)
        LIB.arkiv_zip_end(self.t); self.t = None
        import struct
        with zipfile.ZipFile(self.path) as z: item = z.infolist()[1]
        raw = bytearray(self.before)
        n,e = struct.unpack_from('<HH', raw, item.header_offset+26)
        raw[item.header_offset+30+n+e] ^= 1
        self.path.write_bytes(raw)
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
        self.assertNotEqual(self.prepare_replacement(b'new', method=zipfile.ZIP_STORED), 0)
        self.assertNotEqual(self.commit(), 0)
        self.assertEqual(self.path.read_bytes(), raw)
    def test_replace_wrong_name_method_and_ordinal_fail_closed(self):
        self.fixture()
        self.assertNotEqual(self.prepare_replacement(b'x', name=b'wrong'),0)
        self.assertNotEqual(self.prepare_replacement(b'x', ordinal=2),0)
        self.assertNotEqual(self.prepare_replacement(b'x', count=1),0)
        self.assertNotEqual(self.prepare_replacement(b'x', method=zipfile.ZIP_STORED),0)
        self.assertNotEqual(self.commit(),0)
        self.assertEqual(self.path.read_bytes(),self.before)
    def test_replace_cancel_stale(self):
        self.fixture()
        self.assertEqual(self.prepare_replacement(b'new'),0,self.error.value)
        token=LIB.arkiv_cancel_new()
        try:
            LIB.arkiv_cancel_set(token)
            self.assertEqual(self.commit(token),2)
            self.assertEqual(self.path.read_bytes(),self.before)
        finally: LIB.arkiv_cancel_free(token)
        self.path.write_bytes(b'concurrent writer')
        self.assertNotEqual(self.commit(),0)
        self.assertEqual(self.path.read_bytes(),b'concurrent writer')

if __name__ == '__main__': unittest.main()
