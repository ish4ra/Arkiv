"""Independent stdlib decoding and TAR reader evidence for the in-process creator."""
import bz2
import ctypes as C
import gzip
import io
import lzma
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
import unicodedata

lib = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
class Limits(C.Structure):
    _fields_ = [('max_entries', C.c_uint64), ('max_bytes', C.c_uint64)]
lib.arkiv_create_tar.argtypes = [C.POINTER(C.c_char_p), C.c_size_t, C.c_char_p, C.c_char_p, C.c_char_p, C.c_char_p, C.c_size_t, C.c_int, Limits, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]
lib.arkiv_cancel_new.restype = C.c_void_p
lib.arkiv_cancel_set.argtypes = [C.c_void_p]
lib.arkiv_cancel_free.argtypes = [C.c_void_p]
PROGRESS = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64, C.c_uint64)
FORMATS = [(0, '.tar'), (1, '.tar.gz'), (1, '.tgz'), (2, '.tar.bz2'), (2, '.tbz2'), (3, '.tar.xz'), (3, '.txz')]

class TARCreationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / '資料 🐈'
        self.source.mkdir()
        (self.source / 'empty').mkdir()
        self.file = self.source / ('long-' + 'a' * 110 + '.txt')
        self.data = bytes(range(256)) * 1000
        self.file.write_bytes(self.data)
        os.chmod(self.file, 0o751)
        os.utime(self.file, (1700000000, 1700000000))
        (self.source / 'zero').touch()
        self.output = self.root / 'output'
        self.output.mkdir()
        (self.output / '.stage').mkdir(mode=0o700)
    def tearDown(self): self.temp.cleanup()
    def create(self, codec=0, suffix='.tar', limits=None, callback=None, token=None, source=None):
        paths = (C.c_char_p * 1)(os.fsencode(source or self.source))
        error = C.create_string_buffer(256)
        result = lib.arkiv_create_tar(paths, 1, os.fsencode(self.output), b'.stage', ('result' + suffix).encode(), C.create_string_buffer(512), 512, codec, limits or Limits(100000, 20 * 1024**3), token, callback, None, error, 256)
        return result
    def clean_stage(self): self.assertEqual(list((self.output / '.stage').iterdir()), [])
    def test_variants_independent_checksums_pax_metadata_and_collision(self):
        for codec, suffix in FORMATS:
            with self.subTest(suffix=suffix):
                self.assertEqual(self.create(codec, suffix), 0)
                path = self.output / ('result' + suffix)
                packed = path.read_bytes()
                raw = [lambda b: b, gzip.decompress, bz2.decompress, lzma.decompress][codec](packed)
                self.assertEqual(len(raw) % 512, 0)
                self.assertEqual(raw[-1024:], bytes(1024))
                with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
                    members = {unicodedata.normalize('NFC', m.name): m for m in archive}
                    name = '資料 🐈/' + self.file.name
                    member = members[name]
                    self.assertEqual(archive.extractfile(member).read(), self.data)
                    self.assertEqual(member.mode, 0o751)
                    self.assertEqual(member.mtime, 1700000000)
                    self.assertTrue(members['資料 🐈/empty'].isdir())
                    self.assertEqual(members['資料 🐈/zero'].size, 0)
                self.assertEqual(self.create(codec, suffix), 0)
                self.assertEqual(path.read_bytes(), packed)
                self.assertTrue((self.output / ('result (2)' + suffix)).exists())
                self.clean_stage()
    def test_unsafe_sources_limits_and_cleanup(self):
        for codec, suffix in FORMATS:
            self.assertNotEqual(self.create(codec, suffix, limits=Limits(2, 20 * 1024**3)), 0)
            self.assertNotEqual(self.create(codec, suffix, limits=Limits(100, 1024)), 0)
            link = self.source / 'link'
            link.symlink_to(self.file)
            self.assertNotEqual(self.create(codec, suffix), 0)
            link.unlink()
            os.mkfifo(self.source / 'pipe')
            self.assertNotEqual(self.create(codec, suffix), 0)
            (self.source / 'pipe').unlink()
            self.clean_stage()
        alias = self.root / 'alias'; alias.symlink_to(self.source, target_is_directory=True)
        self.assertNotEqual(self.create(source=alias), 0)
        self.assertEqual([p.name for p in self.output.iterdir()], ['.stage'])
    def test_cancellation_and_changed_source_are_atomic(self):
        for codec, suffix in FORMATS:
            token = lib.arkiv_cancel_new()
            try:
                @PROGRESS
                def cancel(_, entries, size): lib.arkiv_cancel_set(token)
                self.assertEqual(self.create(codec, suffix, callback=cancel, token=token), 2)
            finally: lib.arkiv_cancel_free(token)
            @PROGRESS
            def change(_, entries, size):
                if size: os.utime(self.file, (1700000001, 1700000001))
            self.assertNotEqual(self.create(codec, suffix, callback=change), 0)
            os.utime(self.file, (1700000000, 1700000000))
            self.clean_stage()
        self.assertEqual([p.name for p in self.output.iterdir()], ['.stage'])

if __name__ == '__main__': unittest.main()
