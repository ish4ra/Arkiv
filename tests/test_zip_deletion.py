"""Raw byte preservation and fail-closed deletion transactions."""
from test_zip_addition import LIB
import ctypes as C
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

LIB.arkiv_zip_prepare_delete.argtypes = [C.c_void_p, C.POINTER(C.c_ubyte), C.c_size_t, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]

class DeletionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.path = self.root / 'original.zip'
        self.stage = self.root / 'stage'
        self.stage.mkdir(mode=0o700)
        with zipfile.ZipFile(self.path, 'w') as z:
            for name in ['remove', '資料/é.txt', 'last']:
                e = zipfile.ZipInfo(name)
                e.extra = struct.pack('<HHBI', 0x5455, 5, 1, 1234567890)
                e.comment = b'comment\x00\xff'
                e.external_attr = 0o100640 << 16
                e.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(e, name.encode() * 100)
            z.comment = b'archive\x00\xff'
        self.before = self.path.read_bytes()
        self.error = C.create_string_buffer(256)
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        self.assertTrue(self.t)
    def tearDown(self):
        LIB.arkiv_zip_end(self.t)
        self.tmp.cleanup()
    def prepare(self, mask=(0,1,1), token=None, callback=None):
        return LIB.arkiv_zip_prepare_delete(self.t, (C.c_ubyte * len(mask))(*mask), len(mask), os.fsencode(self.stage), token, callback, None, self.error, 256)
    def commit(self, token=None):
        return LIB.arkiv_zip_commit(self.t, token, self.error, 256)
    def test_raw_local_and_central_records_metadata_and_comments(self):
        self.assertEqual(self.prepare(), 0, self.error.value)
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertEqual(self.commit(), 0)
        after = self.path.read_bytes()
        with zipfile.ZipFile(io.BytesIO(self.before)) as old, zipfile.ZipFile(self.path) as new:
            self.assertIsNone(new.testzip())
            new.extractall(self.root / "extracted")
            self.assertEqual((self.root / "extracted/資料/é.txt").read_bytes(), "資料/é.txt".encode() * 100)
            self.assertEqual(new.namelist(), ['資料/é.txt', 'last'])
            self.assertEqual(new.comment, old.comment)
            for i, entry in enumerate(new.infolist()):
                original = old.getinfo(entry.filename)
                original_end = old.infolist()[i+2].header_offset if i == 0 else old.start_dir
                new_end = new.infolist()[1].header_offset if i == 0 else new.start_dir
                self.assertEqual(self.before[original.header_offset:original_end], after[entry.header_offset:new_end])
            def central(data, start):
                records = []
                while data[start:start+4] == b'PK\x01\x02':
                    n,e,c = struct.unpack_from('<HHH', data, start+28)
                    record = bytearray(data[start:start+46+n+e+c]); record[42:46] = b'\0'*4
                    records.append(record); start += len(record)
                return records
            self.assertEqual(central(self.before, old.start_dir)[1:], central(after, new.start_dir))
    def test_subtree_splice_preserves_retained_raw_metadata(self):
        addition = self.root / "addition.zip"
        with zipfile.ZipFile(addition, "w") as z:
            z.writestr("new/empty/", b"")
            z.writestr("new/file", b"replacement")
        LIB.arkiv_zip_prepare_subtree.argtypes = [C.c_void_p, C.c_char_p, C.POINTER(C.c_ubyte), C.c_size_t, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]
        self.assertEqual(LIB.arkiv_zip_prepare_subtree(self.t, os.fsencode(addition), (C.c_ubyte*3)(0,1,1), 3, os.fsencode(self.stage), None, None, None, self.error, 256), 0, self.error.value)
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertEqual(self.commit(), 0)
        after = self.path.read_bytes()
        with zipfile.ZipFile(io.BytesIO(self.before)) as old, zipfile.ZipFile(self.path) as new:
            self.assertIsNone(new.testzip())
            self.assertEqual(new.comment, old.comment)
            self.assertEqual(self.before[old.infolist()[1].header_offset:old.start_dir], after[:new.getinfo("new/empty/").header_offset])
            for name in ["資料/é.txt", "last"]:
                a,b = old.getinfo(name),new.getinfo(name)
                for field in ["CRC", "compress_size", "file_size", "comment", "extra", "external_attr", "date_time", "compress_type"]:
                    self.assertEqual(getattr(a,field),getattr(b,field))
                self.assertEqual(old.read(name),new.read(name))
            self.assertEqual(new.read("new/file"),b"replacement")
            self.assertNotIn("remove",new.namelist())

    def reopen(self, data):
        LIB.arkiv_zip_end(self.t)
        self.path.write_bytes(data)
        self.before = data
        self.t = LIB.arkiv_zip_begin(os.fsencode(self.path), self.error, 256)
        return self.t
    def test_legacy_encoded_name_is_preserved_without_utf8_reencoding(self):
        data = self.before.replace(b'remove', b'caf\x82xx')
        self.assertTrue(self.reopen(data))
        result = self.prepare((1,0,1))
        # Some libarchive/locale combinations reject this legacy encoding during
        # full verification. Fail closed, while still proving raw rewrite fidelity.
        if result:
            self.assertEqual(result, 1)
            self.assertEqual(self.commit(), 1)
            self.assertEqual(self.path.read_bytes(), data)
            output = self.stage / 'replacement.zip'
        else:
            self.assertEqual(self.commit(), 0)
            output = self.path
        with zipfile.ZipFile(output) as z:
            self.assertEqual(z.namelist(), ['caféxx', 'last'])
            self.assertEqual(z.read('caféxx'), b'remove' * 100)
            self.assertFalse(z.infolist()[0].flag_bits & 0x800)
    def test_central_order_disagreement_is_readonly(self):
        data = self.before
        start = data.index(b'PK\x01\x02')
        n,e,c = struct.unpack_from('<HHH', data, start+28)
        end = start+46+n+e+c
        n,e,c = struct.unpack_from('<HHH', data, end+28)
        second = end+46+n+e+c
        self.assertFalse(self.reopen(data[:start]+data[end:second]+data[start:end]+data[second:]))
    def test_data_descriptors_remain_byte_identical(self):
        class Unseekable(io.BytesIO):
            def seekable(self): return False
            def seek(self, *args): raise OSError('unseekable')
        stream = Unseekable()
        with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('remove', b'remove')
            z.writestr('keep', b'payload' * 100)
        data = stream.getvalue()
        self.assertTrue(self.reopen(data))
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            local = data[z.infolist()[1].header_offset:z.start_dir]
        self.assertEqual(self.prepare((0,1)), 0, self.error.value)
        self.assertEqual(self.commit(), 0)
        self.assertTrue(self.path.read_bytes().startswith(local))
        with zipfile.ZipFile(self.path) as z: self.assertIsNone(z.testzip())
    def test_delete_all_and_count_or_mask_mismatch(self):
        self.assertEqual(self.prepare((0,)), 1)
        self.assertEqual(self.path.read_bytes(), self.before)
    def test_delete_all_valid_empty_zip(self):
        self.assertEqual(self.prepare((0,0,0)), 0, self.error.value)
        self.assertEqual(self.commit(), 0)
        with zipfile.ZipFile(self.path) as z:
            self.assertEqual(z.namelist(), [])
            self.assertEqual(z.comment, b'archive\x00\xff')
    def test_cancel_during_copy_and_before_commit(self):
        token = LIB.arkiv_cancel_new()
        callback = C.CFUNCTYPE(None,C.c_void_p,C.c_uint64,C.c_uint64)(lambda *_: LIB.arkiv_cancel_set(token))
        try:
            self.assertEqual(self.prepare(token=token, callback=callback), 2)
            self.assertEqual(self.commit(token), 2)
            self.assertEqual(self.path.read_bytes(), self.before)
        finally: LIB.arkiv_cancel_free(token)
    def test_changed_source_never_replaced(self):
        self.assertEqual(self.prepare(), 0)
        self.path.write_bytes(b'changed')
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.path.read_bytes(), b'changed')
    def test_changed_replacement_never_commits(self):
        self.assertEqual(self.prepare(), 0)
        (self.stage / 'replacement.zip').write_bytes(b'changed')
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.path.read_bytes(), self.before)
    def test_corrupt_retained_payload_never_commits(self):
        broken = bytearray(self.before)
        with zipfile.ZipFile(self.path) as z: off = z.infolist()[1].header_offset
        n,e = struct.unpack_from('<HH', broken, off+26)
        broken[off+30+n+e] ^= 0xff
        self.path.write_bytes(broken)
        self.assertEqual(self.prepare(), 1)
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.path.read_bytes(), broken)

if __name__ == '__main__': unittest.main()
