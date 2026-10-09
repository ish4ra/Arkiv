"""Direct ZIP backend checks; run after scripts/test-engine.sh builds the library."""
import ctypes as C
import os
import pathlib
import tempfile
import unittest
import zipfile

lib = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
class Limits(C.Structure):
    _fields_ = [('max_entries', C.c_uint64), ('max_bytes', C.c_uint64)]
lib.arkiv_create_zip.argtypes = [C.POINTER(C.c_char_p), C.c_size_t, C.c_char_p, C.c_char_p, C.c_char_p, C.c_char_p, C.c_size_t, C.c_int, Limits, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]

class CreationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.source = self.root / '資料 🐈'
        self.source.mkdir()
        (self.source / 'empty').mkdir()
        (self.source / 'data space.txt').write_bytes(bytes(range(256)) * 1000)
        self.destination = self.root / 'output'
        self.destination.mkdir()
        (self.destination / '.stage').mkdir(mode=0o700)
    def tearDown(self):
        self.temp.cleanup()
    def create(self, source=None, compression=1, limits=None, destination=None):
        sources = (C.c_char_p * 1)(os.fsencode(source or self.source))
        error = C.create_string_buffer(256)
        return lib.arkiv_create_zip(sources, 1, os.fsencode(destination or self.destination), b'.stage', b'result.zip', C.create_string_buffer(512), 512, compression, limits or Limits(100000, 20 * 1024**3), None, None, None, error, len(error))
    def test_compression_unicode_crc_and_no_overwrite(self):
        for method in (0, 1):
            self.assertEqual(self.create(compression=method), 0)
            archive = self.destination / 'result.zip'
            with zipfile.ZipFile(archive) as z:
                self.assertIsNone(z.testzip())
                self.assertIn('資料 🐈/empty/', z.namelist())
                name = '資料 🐈/data space.txt'
                self.assertEqual(z.read(name), (self.source / 'data space.txt').read_bytes())
                self.assertEqual(z.getinfo(name).compress_type, zipfile.ZIP_STORED if method == 0 else zipfile.ZIP_DEFLATED)
                self.assertTrue(z.getinfo(name).flag_bits & 0x800)
            previous = archive.read_bytes()
            self.assertEqual(self.create(), 0)
            self.assertEqual(archive.read_bytes(), previous)
            self.assertEqual(list((self.destination / '.stage').iterdir()), [])
            archive.unlink()
            (self.destination / "result (2).zip").unlink()
    def test_limits_and_symlink_ancestors(self):
        self.assertEqual(self.create(limits=Limits(1, 100)), 1)
        alias = self.root / 'alias'
        alias.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.create(source=alias / self.source.name), 1)
        self.assertEqual(self.create(destination=alias / self.destination.name), 1)
        (self.source / 'link').symlink_to(self.source / 'data space.txt')
        self.assertEqual(self.create(), 1)
        self.assertFalse((self.destination / 'result.zip').exists())
        self.assertEqual(list((self.destination / '.stage').iterdir()), [])
    def test_fifo_and_self_inclusion(self):
        os.mkfifo(self.source / 'pipe')
        self.assertEqual(self.create(), 1)
        (self.source / 'pipe').unlink()
        (self.source / '.stage').mkdir()
        self.assertEqual(self.create(destination=self.source), 1)
        self.assertFalse((self.source / 'result.zip').exists())

if __name__ == '__main__':
    unittest.main()
