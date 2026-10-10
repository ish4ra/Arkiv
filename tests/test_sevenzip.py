"""In-process 7z/AES boundary tests. Passwords are passed only in memory."""
import ctypes as C
import os
import pathlib
import struct
import tempfile
import unittest
import zipfile
import zlib

lib = C.CDLL(os.environ['ARKIV_SEVEN_LIBRARY'])
lib.arkiv_seven_encode.argtypes = [C.c_int, C.c_int, C.c_char_p, C.c_int, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
lib.arkiv_seven_decode.argtypes = [C.c_int, C.c_int, C.c_char_p, C.c_void_p, C.c_void_p]


def number(n):
    if n < 128:
        return bytes([n])
    return b'\xff' + struct.pack('<Q', n)


def stored(name, attributes=0x20, data=b'payload'):
    """A minimal independent 7z Copy archive; no bundled codec is used to produce it."""
    path = name.encode('utf-16le') + b'\0\0'
    header = (b'\x01\x04\x06\x00\x01\x09' + number(len(data)) + b'\x00'
              b'\x07\x0b\x01\x00\x01\x01\x00\x0c' + number(len(data)) + b'\x00\x08\x00\x00'
              b'\x05\x01\x11' + number(len(path) + 1) + b'\x00' + path +
              b'\x15\x06\x01\x00' + struct.pack('<I', attributes) + b'\x00\x00')
    start = struct.pack('<QQI', len(data), len(header), zlib.crc32(header))
    return b"7z\xbc\xaf\x27\x1c\x00\x04" + struct.pack('<I', zlib.crc32(start)) + start + data + header


class SevenZipTests(unittest.TestCase):
    def decode(self, data, password=None, cancel=None):
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as output:
            source.write(data); source.flush()
            result = lib.arkiv_seven_decode(source.fileno(), output.fileno(), password, cancel, None)
            output.seek(0)
            return result, output.read()

    def encode(self, password=None, headers=True, progress=None):
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as output:
            with zipfile.ZipFile(source, 'w') as z:
                z.writestr('資料 🐈/hello.txt', b'content' * 10000)
                z.writestr('empty/', b'')
                z.writestr('zero', b'')
            source.seek(0)
            result = lib.arkiv_seven_encode(source.fileno(), output.fileno(), password, headers, None, None, progress, None)
            self.assertEqual(result, 0)
            output.seek(0)
            return output.read()

    def test_independent_copy_fixture_and_hostile_paths(self):
        self.assertEqual(self.decode(stored('safe.txt'))[0], 0)
        for name in ['../escape', '/absolute', 'C:\\evil', 'a/../b', 'a//b', 'a:b', 'a\nb', '/'.join(['x'] * 257)]:
            with self.subTest(name=name):
                self.assertEqual(self.decode(stored(name))[0], 1)

    def test_symlink_device_and_reparse_attributes_rejected(self):
        for attr in [(0o120777 << 16) | 0x8000, (0o020600 << 16) | 0x8000, 0x400]:
            self.assertEqual(self.decode(stored('unsafe', attr))[0], 1)

    def test_aes_header_content_wrong_password_and_retry(self):
        for headers in [False, True]:
            archive = self.encode(b'fixture password', headers)
            self.assertNotIn(b'contentcontent', archive)
            self.assertEqual(self.decode(archive)[0], 4)
            self.assertEqual(self.decode(archive, b'wrong')[0], 5)
            result, decoded = self.decode(archive, b'fixture password')
            self.assertEqual(result, 0)
            with tempfile.TemporaryFile() as f:
                f.write(decoded); f.seek(0)
                with zipfile.ZipFile(f) as z:
                    self.assertEqual(z.read('資料 🐈/hello.txt'), b'content' * 10000)
                    self.assertEqual(z.read('zero'), b'')
                    self.assertIsNone(z.testzip())

    def test_cancelled_and_corrupt(self):
        callback = C.CFUNCTYPE(C.c_int, C.c_void_p)(lambda _: 1)
        self.assertEqual(self.decode(self.encode(), cancel=callback)[0], 2)
        self.assertEqual(self.decode(b'7z\xbc\xaf\x27\x1c')[0], 1)
        archive = bytearray(self.encode())
        archive[-1] ^= 0x80
        self.assertEqual(self.decode(bytes(archive))[0], 1)

    def test_checked_in_fixtures(self):
        folder = pathlib.Path(__file__).parent / 'fixtures'
        for name, password in [('created-plain.7z', None), ('created-aes-headers.7z', b'fixture password')]:
            self.assertEqual(self.decode((folder / name).read_bytes(), password)[0], 0)


if __name__ == '__main__':
    unittest.main()
