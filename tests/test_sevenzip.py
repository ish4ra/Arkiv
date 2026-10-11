"""In-process 7z/AES boundary tests. Passwords are passed only in memory."""
import ctypes as C
import io
import stat
import tarfile
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


def stored_many(entries):
    """Independent 7z Copy fixture with one unpack stream per file."""
    count = number(len(entries))
    payload = b''.join(data for name, mode, data in entries)
    paths = b''.join(name.encode('utf-16le') + b'\0\0' for name, mode, data in entries)
    sizes = b''.join(number(len(data)) for name, mode, data in entries)
    attrs = b''.join(struct.pack('<I', mode) for name, mode, data in entries)
    header = (b'\x01\x04\x06\x00' + count + b'\x09' + sizes + b'\x00'
              + b'\x07\x0b' + count + b'\x00' + b'\x01\x01\x00' * len(entries)
              + b'\x0c' + sizes + b'\x00\x08\x00\x00'
              + b'\x05' + count + b'\x11' + number(len(paths) + 1) + b'\x00' + paths
              + b'\x15' + number(len(attrs) + 2) + b'\x01\x00' + attrs + b'\x00\x00')
    start = struct.pack('<QQI', len(payload), len(header), zlib.crc32(header))
    return b"7z\xbc\xaf\x27\x1c\x00\x04" + struct.pack('<I', zlib.crc32(start)) + start + payload + header


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

    def test_reparse_attributes_rejected(self):
        for attr in [0x400]:
            self.assertEqual(self.decode(stored('unsafe', attr))[0], 1)

    def test_posix_symlink_targets_and_executable_modes(self):
        for target in [b'other', b'../outside', b'/absolute']:
            result, decoded = self.decode(stored('link', (0o120777 << 16) | 0x8000, target))
            self.assertEqual(result, 0)
            with tarfile.open(fileobj=io.BytesIO(decoded)) as z:
                self.assertTrue(z.getmember('link').issym())
                self.assertEqual(z.getmember('link').linkname.encode(), target)
        result, decoded = self.decode(stored('run', (0o107777 << 16) | 0x8000, b'executable'))
        self.assertEqual(result, 0)
        with tarfile.open(fileobj=io.BytesIO(decoded)) as z:
            self.assertEqual(z.getmember('run').mode, 0o755)
        for target in [b'', b'a\0b', b'x' * 4097]:
            self.assertNotEqual(self.decode(stored('bad', (0o120777 << 16) | 0x8000, target))[0], 0)

    def test_special_types_survive_private_spool(self):
        for mode, kind in [(0o010600, tarfile.FIFOTYPE), (0o020600, tarfile.CHRTYPE), (0o060600, tarfile.BLKTYPE)]:
            result, decoded = self.decode(stored('special', (mode << 16) | 0x8000, b'discard payload'))
            self.assertEqual(result, 0)
            with tarfile.open(fileobj=io.BytesIO(decoded)) as t:
                self.assertEqual(t.getmember('special').type, kind)
                self.assertEqual(t.getmember('special').size, 0)

    def test_special_and_normal_entry_share_spool(self):
        result, decoded = self.decode(stored_many([('fifo', (0o010600 << 16) | 0x8000, b'ignored'), ('ok', (0o100755 << 16) | 0x8000, b'payload')]))
        self.assertEqual(result, 0)
        with tarfile.open(fileobj=io.BytesIO(decoded)) as t:
            self.assertTrue(t.getmember('fifo').isfifo())
            self.assertEqual(t.extractfile('ok').read(), b'payload')
            self.assertEqual(t.getmember('ok').mode, 0o755)

    def test_socket_marker_warns_and_normal_file_extracts(self):
        result, decoded = self.decode(stored_many([('socket', (0o140600 << 16) | 0x8000, b'ignored'), ('ok', (0o100755 << 16) | 0x8000, b'payload')]))
        self.assertEqual(result, 0)
        with tarfile.open(fileobj=io.BytesIO(decoded)) as t:
            self.assertTrue(t.getmember('socket').isfifo())
        # Exercise the actual private-spool consumer: the marker must never become
        # an on-disk FIFO, and its warning must not prevent ordinary extraction.
        seven = pathlib.Path(os.environ['ARKIV_SEVEN_LIBRARY'])
        engine = C.CDLL(str(seven.parent.parent / 'engine-tests' / seven.name.replace('libArkivSeven', 'libarkiv')))
        class Limits(C.Structure):
            _fields_ = [('entries', C.c_uint64), ('bytes', C.c_uint64)]
        progress_type = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64, C.c_uint64)
        warning_type = C.CFUNCTYPE(None, C.c_void_p, C.c_char_p, C.c_char_p)
        engine.arkiv_extract_with_warnings.argtypes = [C.c_char_p, C.c_char_p, C.c_void_p, C.c_size_t, Limits, C.c_void_p, progress_type, warning_type, C.c_void_p, C.c_char_p, C.c_size_t]
        warnings = []
        with tempfile.TemporaryDirectory() as base:
            root = pathlib.Path(base); archive = root / 'spool.tar'; archive.write_bytes(decoded)
            out = root / 'out'; out.mkdir(); error = C.create_string_buffer(256)
            result = engine.arkiv_extract_with_warnings(bytes(archive), bytes(out), None, 0, Limits(100, 100000), None, progress_type(lambda *args: None), warning_type(lambda _, name, message: warnings.append((name, message))), None, error, len(error))
            self.assertEqual(result, 0, error.value)
            self.assertEqual(len(warnings), 1)
            self.assertEqual(warnings[0][0], b'socket')
            self.assertIn(b'Unsupported special', warnings[0][1])
            self.assertFalse((out / 'socket').exists())
            self.assertEqual((out / 'ok').read_bytes(), b'payload')

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
                with tarfile.open(fileobj=f) as z:
                    self.assertEqual(z.extractfile('資料 🐈/hello.txt').read(), b'content' * 10000)
                    self.assertEqual(z.extractfile('zero').read(), b'')
                    self.assertTrue(z.getmember('empty').isdir())

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
