"""Real archive fixtures; no compressor mocks. Run via scripts/test-engine.sh."""
import ctypes as C
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

LIB = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
class Limits(C.Structure):
    _fields_ = [('entries', C.c_uint64), ('bytes', C.c_uint64)]
ENTRY = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_int64, C.c_char_p, C.c_int64, C.c_int)
PROGRESS = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64, C.c_uint64)
LIB.arkiv_list.argtypes = [C.c_char_p, Limits, C.c_void_p, ENTRY, C.c_void_p, C.c_char_p, C.c_size_t]
LIB.arkiv_extract.argtypes = [C.c_char_p, C.c_char_p, C.POINTER(C.c_int64), C.c_size_t, Limits, C.c_void_p, PROGRESS, C.c_void_p, C.c_char_p, C.c_size_t]
LIB.arkiv_cancel_new.restype = C.c_void_p
LIB.arkiv_cancel_set.argtypes = [C.c_void_p]
LIB.arkiv_cancel_free.argtypes = [C.c_void_p]

class EngineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.archive = self.base / 'input'
        self.out = self.base / 'out'
        self.out.mkdir(mode=0o700)
        self.token = LIB.arkiv_cancel_new()
        self.limits = Limits(10000, 8 * 1024 * 1024)
    def tearDown(self):
        LIB.arkiv_cancel_free(self.token)
        self.tmp.cleanup()
    def zip(self, entries):
        with zipfile.ZipFile(self.archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            for name, data in entries:
                z.writestr(name, data)
    def listing(self):
        rows = []
        @ENTRY
        def entry(_, index, name, size, kind):
            rows.append((index, name.decode('utf-8'), size, kind)); return 0
        error = C.create_string_buffer(256)
        result = LIB.arkiv_list(bytes(self.archive), self.limits, self.token, entry, None, error, 256)
        return result, rows, error.value
    def extract(self, ids=None, progress=None):
        error = C.create_string_buffer(256)
        array = (C.c_int64 * len(ids))(*ids) if ids is not None else None
        @PROGRESS
        def callback(_, files, size):
            if progress: progress(files, size)
        result = LIB.arkiv_extract(bytes(self.archive), bytes(self.out), array, len(ids or []), self.limits, self.token, callback, None, error, 256)
        return result, error.value
    def test_zip_unicode_nested_and_selective(self):
        self.zip([('folder/hello 🦊.txt', b'hello'), ('other.txt', b'other')])
        result, rows, _ = self.listing()
        self.assertEqual(result, 0); self.assertEqual(len(rows), 2)
        self.assertEqual(self.extract([0])[0], 0)
        self.assertEqual((self.out / 'folder/hello 🦊.txt').read_bytes(), b'hello')
        self.assertFalse((self.out / 'other.txt').exists())
    def test_tar(self):
        with tarfile.open(self.archive, 'w') as t:
            e = tarfile.TarInfo('a/b.txt'); e.size = 4; t.addfile(e, io.BytesIO(b'data'))
        self.assertEqual(self.extract()[0], 0)
        self.assertEqual((self.out / 'a/b.txt').read_bytes(), b'data')
    def test_empty_zip(self):
        self.zip([])
        self.assertEqual(self.listing()[0], 0)
        self.assertEqual(self.extract()[0], 0)
    def test_traversal_absolute_and_windows_paths(self):
        for name in ['../escape', '/escape', 'a/../../escape', 'C:/escape', 'a\\..\\..\\escape', './file', 'a//file']:
            with self.subTest(name=name):
                self.zip([(name, b'bad')])
                self.assertNotEqual(self.extract()[0], 0)
                self.assertFalse((self.base / 'escape').exists())
    def test_symlink_and_hardlink_rejected(self):
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE]:
            with self.subTest(kind=kind):
                with tarfile.open(self.archive, 'w') as t:
                    e = tarfile.TarInfo('link'); e.type = kind; e.linkname = '../escape'; t.addfile(e)
                self.assertNotEqual(self.extract()[0], 0)
    def test_preexisting_symlink_parent(self):
        (self.out / 'redirect').symlink_to(self.base, target_is_directory=True)
        self.zip([('redirect/escape', b'bad')])
        self.assertNotEqual(self.extract()[0], 0)
        self.assertFalse((self.base / 'escape').exists())
    def test_preexisting_file_never_overwritten(self):
        (self.out / 'file').write_bytes(b'original')
        self.zip([('file', b'replacement')])
        self.assertNotEqual(self.extract()[0], 0)
        self.assertEqual((self.out / 'file').read_bytes(), b'original')
    def test_duplicate_names_fail(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            self.zip([('file', b'one'), ('file', b'two')])
        self.assertNotEqual(self.extract()[0], 0)
        self.assertEqual((self.out / 'file').read_bytes(), b'one')
    def test_limits(self):
        self.zip([('large', b'a' * 100000)])
        self.limits = Limits(10, 10)
        self.assertNotEqual(self.extract()[0], 0)
        self.limits = Limits(1, 1000000)
        self.zip([('one', b'1'), ('two', b'2')])
        self.assertNotEqual(self.listing()[0], 0)
    def test_cancel_before_start(self):
        self.zip([('file', b'data')])
        LIB.arkiv_cancel_set(self.token)
        self.assertEqual(self.extract()[0], 2)
        self.assertEqual(self.listing()[0], 2)
        self.assertEqual(list(self.out.iterdir()), [])
    def test_cancel_from_final_listing_callback(self):
        self.zip([('file', b'data')])
        @ENTRY
        def callback(*args):
            LIB.arkiv_cancel_set(self.token)
            return 0
        error = C.create_string_buffer(256)
        result = LIB.arkiv_list(bytes(self.archive), self.limits, self.token, callback, None, error, 256)
        self.assertEqual(result, 2)
    def test_cancel_while_streaming(self):
        self.zip([('large', b'a' * 1000000)])
        self.assertEqual(self.extract(progress=lambda f, b: LIB.arkiv_cancel_set(self.token))[0], 2)
    def test_corrupt_archive(self):
        self.archive.write_bytes(b'not an archive')
        self.assertNotEqual(self.listing()[0], 0)
        self.assertNotEqual(self.extract()[0], 0)
    def test_crc_failure(self):
        with zipfile.ZipFile(self.archive, 'w', compression=zipfile.ZIP_STORED) as z:
            z.writestr('file', b'unique payload')
        data = self.archive.read_bytes().replace(b'unique payload', b'broken payload')
        self.archive.write_bytes(data)
        self.assertNotEqual(self.extract()[0], 0)
    def test_directory_and_file_collision(self):
        self.zip([('folder/', b''), ('folder', b'bad')])
        self.assertNotEqual(self.extract()[0], 0)
    def test_missing_selection(self):
        self.zip([('file', b'data')])
        self.assertNotEqual(self.extract([999])[0], 0)
    def test_7z_fixture(self):
        self.archive.write_bytes((Path(__file__).parent / 'fixtures/basic.7z').read_bytes())
        self.assertEqual(self.listing()[0], 0)
        self.assertEqual(self.extract()[0], 0)
        self.assertEqual((self.out / 'folder/hello.txt').read_bytes(), b'hello from Arkiv\n' * 100)
    def test_rar5_stored_fixture(self):
        self.archive.write_bytes((Path(__file__).parent / 'fixtures/rar5-stored.rar').read_bytes())
        self.assertEqual(self.listing()[0], 0)
        self.assertEqual(self.extract()[0], 0)
        self.assertEqual((self.out / 'helloworld.txt').read_bytes(), b'hello libarchive test suite!\n')
    def test_long_name(self):
        name = 'x' * 200
        self.zip([(name, b'ok')])
        self.assertEqual(self.extract()[0], 0)
        self.assertEqual((self.out / name).read_bytes(), b'ok')

if __name__ == '__main__': unittest.main()
