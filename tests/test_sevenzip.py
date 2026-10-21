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

    def test_encryption_policy_and_password_validation(self):
        self.assertTrue(hasattr(lib, 'arkiv_seven_policy'), 'policy inspection API missing')
        probe = lib.arkiv_seven_policy
        probe.argtypes = [C.c_int, C.c_char_p, C.POINTER(C.c_uint32), C.c_void_p, C.c_void_p]
        for headers in (False, True):
            data = self.encode(b'policy secret', headers)
            for password, expected in [(None, 4), (b'wrong', 5), (b'policy secret', 0)]:
                with self.subTest(headers=headers, password_case=expected), tempfile.TemporaryFile() as f:
                    f.write(data); f.flush()
                    flags = C.c_uint32()
                    self.assertEqual(probe(f.fileno(), password, C.byref(flags), None, None), expected)
                    if expected == 0:
                        self.assertEqual(flags.value, 1 | (2 if headers else 0) | 8 | 16)
                    self.assertEqual(f.seek(0), 0)
                    self.assertEqual(f.read(), data)
        with tempfile.TemporaryFile() as f:
            f.write(stored('plain')); f.flush()
            flags = C.c_uint32()
            self.assertEqual(probe(f.fileno(), None, C.byref(flags), None, None), 0)
            self.assertEqual(flags.value, 8 | 16)

    def test_policy_rejects_mixed_and_unsupported_layouts(self):
        probe = lib.arkiv_seven_policy
        probe.argtypes = [C.c_int, C.c_char_p, C.POINTER(C.c_uint32), C.c_void_p, C.c_void_p]
        # Independent metadata fixture: one Copy stream and one AES stream.
        # No CRC is present, so arbitrary AES plaintext may decode successfully.
        # Mixed encryption must remain ineligible regardless of decoding success.
        mixed = stored_many([('plain', 0x20, b'plain'), ('encrypted', 0x20, bytes(16))])
        offset, length, _ = struct.unpack_from('<QQI', mixed, 12)
        header = mixed[32 + offset:]
        folders = b'\x07\x0b\x02\x00' + b'\x01\x01\x00' * 2
        aes = b'\x01\x24\x06\xf1\x07\x01\x12\x53\x0f' + bytes(16)
        header = header.replace(folders, b'\x07\x0b\x02\x00\x01\x01\x00' + aes)
        start = struct.pack('<QQI', offset, len(header), zlib.crc32(header))
        mixed = mixed[:8] + struct.pack('<I', zlib.crc32(start)) + start + mixed[32:32 + offset] + header
        with tempfile.TemporaryFile() as f:
            f.write(mixed); f.flush(); flags = C.c_uint32()
            self.assertEqual(probe(f.fileno(), b'secret', C.byref(flags), None, None), 0)
            self.assertEqual(flags.value & 5, 5)
            self.assertEqual(flags.value & 8, 0)
            delete = lib.arkiv_seven_delete_encrypted
            delete.argtypes = [C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_ubyte), C.c_uint64, C.c_int, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
            with tempfile.TemporaryFile() as output:
                names = (C.c_char_p * 2)(b'plain', b'encrypted')
                mask = (C.c_ubyte * 2)(1, 0)
                self.assertNotEqual(delete(f.fileno(), names, mask, 2, output.fileno(), b'secret', None, None, None, None), 0)
                self.assertEqual(output.seek(0, 2), 0)
            f.seek(0); self.assertEqual(f.read(), mixed)
        for data in [stored('link', (0o120777 << 16) | 0x8000, b'target'), stored('ok') + b'trailer']:
            with tempfile.TemporaryFile() as f:
                f.write(data); f.flush(); flags = C.c_uint32()
                self.assertEqual(probe(f.fileno(), None, C.byref(flags), None, None), 0)
                self.assertEqual(flags.value & 8, 0)

    def test_encrypted_delete_preserves_ciphertext_and_header_policy(self):
        self.assertTrue(hasattr(lib, 'arkiv_seven_delete_encrypted'))
        fn = lib.arkiv_seven_delete_encrypted
        fn.argtypes = [C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_ubyte), C.c_uint64,
                       C.c_int, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        def packed(data):
            # EncodedHeader's PackInfo PackPos is the end of file-data streams.
            offset = struct.unpack_from('<Q', data, 12)[0]
            header = data[32 + offset:]
            if header[:2] == b'\x17\x06':
                first = header[2]; value = 0; mask = 0x80; pos = 3
                for i in range(8):
                    if not first & mask:
                        value |= (first & (mask - 1)) << (8 * i); break
                    value |= header[pos] << (8 * i); pos += 1; mask >>= 1
                offset = value
            return data[32:32 + offset]
        for headers in [False, True]:
            before = self.encode(b'delete secret', headers)
            for password, expected in [(b'wrong', 5), (b'delete secret', 0)]:
                with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as output:
                    source.write(before); source.flush()
                    names = (C.c_char_p * 3)('資料 🐈/hello.txt'.encode(), b'empty/', b'zero')
                    mask = (C.c_ubyte * 3)(1, 0, 0)
                    result = fn(source.fileno(), names, mask, 3, output.fileno(), password, None, None, None, None)
                    self.assertEqual(result, expected)
                    output.seek(0); after = output.read()
                    if result == 0:
                        self.assertEqual(packed(before), packed(after), 'retained ciphertext must be copied in full')
                        status, tar = self.decode(after, b'delete secret')
                        self.assertEqual(status, 0)
                        with tarfile.open(fileobj=io.BytesIO(tar)) as t:
                            self.assertEqual(t.getnames(), ['資料 🐈/hello.txt'])
                            self.assertEqual(t.extractfile(t.getmembers()[0]).read(), b'content' * 10000)
                        flags = C.c_uint32()
                        self.assertEqual(lib.arkiv_seven_policy(output.fileno(), password, C.byref(flags), None, None), 0)
                        self.assertEqual(bool(flags.value & 2), headers)
                    else:
                        self.assertEqual(after, b'')
                    source.seek(0); self.assertEqual(source.read(), before)

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


# inserted before __main__ in test_sevenzip.py

def copy_or_lzma2(data=b'old payload' * 1000, method='Copy', solid=False, opaque=False):
    """Independent CRC-bearing archive with known packed-stream boundaries."""
    import lzma
    packed = data if method == 'Copy' else lzma.compress(data, format=lzma.FORMAT_RAW,
                    filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 20}])
    coder = b'\x01\x00' if method == 'Copy' else b'\x21\x21\x01\x10'
    names = ('old.txt\0second.txt\0' if solid else 'old.txt\0').encode('utf-16le')
    substreams = b'\x08\x0d\x02\x09' + number(len(data) // 2) + b'\x00' if solid else b'\x08\x00'
    header = (b'\x01' + (b'\x02\x01\x03abc\x00' if opaque else b'')
              + b'\x04\x06\x00\x01\x09' + number(len(packed)) + b'\x00'
              + b'\x07\x0b\x01\x00\x01' + coder + b'\x0c' + number(len(data))
              + b'\x0a\x01' + struct.pack('<I', zlib.crc32(data)) + b'\x00'
              + substreams + b'\x00\x05' + number(2 if solid else 1)
              + b'\x11' + number(len(names) + 1) + b'\x00' + names
              + b'\x15' + number(2 + (8 if solid else 4)) + b'\x01\x00'
              + struct.pack('<I', (stat.S_IFREG | 0o755) << 16 | 0x8020) * (2 if solid else 1)
              + b'\x00\x00')
    start = struct.pack('<QQI', len(packed), len(header), zlib.crc32(header))
    return b"7z\xbc\xaf\x27\x1c\x00\x04" + struct.pack('<I', zlib.crc32(start)) + start + packed + header, packed


class SevenZipAppendTests(unittest.TestCase):
    decode = SevenZipTests.decode
    encode = SevenZipTests.encode
    # These methods use independent Copy/LZMA2 fixtures, not encode/decode agreement.
    def probe(self, data):
        lib.arkiv_seven_probe_append.argtypes = [C.c_int]
        with tempfile.TemporaryFile() as source:
            source.write(data); source.flush()
            return lib.arkiv_seven_probe_append(source.fileno())

    def append(self, data, cancel=None):
        lib.arkiv_seven_append.argtypes = [C.c_int, C.c_int, C.c_int, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as additions, tempfile.TemporaryFile() as output:
            source.write(data); source.flush()
            with zipfile.ZipFile(additions, 'w') as z:
                z.writestr('資料/new.txt', b'new bytes')
                z.writestr('empty/', b'')
                z.writestr('zero', b'')
            additions.seek(0)
            result = lib.arkiv_seven_append(source.fileno(), additions.fileno(), output.fileno(), cancel, None, None, None)
            output.seek(0)
            return result, output.read()

    def test_independent_copy_lzma2_streams_and_attributes_preserved(self):
        for method in ['Copy', 'LZMA2']:
            with self.subTest(method=method):
                before, packed = copy_or_lzma2(method=method)
                self.assertEqual(self.decode(before)[0], 0)
                self.assertEqual(self.probe(before), 0)
                result, after = self.append(before)
                self.assertEqual(result, 0)
                self.assertEqual(after[32:32 + len(packed)], packed, 'all old packed bytes must be copied verbatim')
                result, tar = self.decode(after)
                self.assertEqual(result, 0)
                with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
                    self.assertEqual(archive.extractfile('old.txt').read(), b'old payload' * 1000)
                    self.assertEqual(archive.getmember('old.txt').mode & 0o777, 0o755)
                    self.assertEqual(archive.extractfile('資料/new.txt').read(), b'new bytes')
                    self.assertEqual(archive.extractfile('zero').read(), b'')
                    self.assertTrue(archive.getmember('empty').isdir())
                self.assertEqual(self.probe(after), 0)

    def test_read_only_solid_encrypted_opaque_trailing_and_special(self):
        solid, _ = copy_or_lzma2(solid=True)
        opaque, _ = copy_or_lzma2(opaque=True)
        self.assertEqual(self.decode(solid)[0], 0)
        self.assertEqual(self.decode(opaque)[0], 0)
        plain, _ = copy_or_lzma2()
        for data in [solid, opaque, self.encode(b'secret', False), self.encode(b'secret', True),
                     plain + b'trailing data', b'prefix' + plain, plain[:len(plain)//2],
                     stored('link', (stat.S_IFLNK | 0o777) << 16 | 0x8020, b'target'),
                     stored('reparse', 0x400)]:
            self.assertNotEqual(self.probe(data), 0)
            self.assertNotEqual(self.append(data)[0], 0)

    def replace(self, data, names, target, contents=b'new', directory=False, cancel=None):
        lib.arkiv_seven_replace.argtypes = [C.c_int, C.c_int, C.POINTER(C.c_char_p), C.c_uint64, C.c_uint64, C.c_int, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        paths = (C.c_char_p * len(names))(*(name.encode('utf-8') for name in names))
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as content, tempfile.TemporaryFile() as output:
            source.write(data); source.flush()
            with zipfile.ZipFile(content, 'w') as z:
                z.writestr('ignored/' if directory else 'ignored.bin', contents)
            content.seek(0)
            result = lib.arkiv_seven_replace(source.fileno(), content.fileno(), paths, len(names), target, output.fileno(), cancel, None, None, None)
            output.seek(0)
            return result, output.read()

    def test_replace_preserves_path_metadata_and_unrelated_packed_stream(self):
        keep = b'unrelated packed bytes' * 100
        mode = (stat.S_IFREG | 0o755) << 16 | 0x8020
        data = stored_many([('keep', 0x20, keep), ('資料/猫.txt', mode, b'old payload')])
        for contents in [b'x', b'larger' * 10000, b'']:
            result, after = self.replace(data, ['資料/猫.txt', 'keep'], 0, contents)
            self.assertEqual(result, 0)
            self.assertEqual(after[32:32 + len(keep)], keep)
            result, tar = self.decode(after)
            self.assertEqual(result, 0)
            with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
                self.assertEqual(archive.extractfile('資料/猫.txt').read(), contents)
                self.assertEqual(archive.getmember('資料/猫.txt').mode & 0o777, 0o755)
                self.assertEqual(archive.extractfile('keep').read(), keep)
                self.assertNotIn('ignored.bin', archive.getnames())

    def test_replace_rejects_ambiguous_plan_folder_solid_and_cancel(self):
        data, _ = copy_or_lzma2()
        self.assertNotEqual(self.replace(data, ['missing'], 0)[0], 0)
        self.assertNotEqual(self.replace(data, ['old.txt'], 1)[0], 0)
        self.assertNotEqual(self.replace(data, ['old.txt'], 0, directory=True)[0], 0)
        solid, _ = copy_or_lzma2(solid=True)
        self.assertNotEqual(self.replace(solid, ['old.txt', 'second.txt'], 0)[0], 0)
        cancel = C.CFUNCTYPE(C.c_int, C.c_void_p)(lambda _: 1)
        self.assertEqual(self.replace(data, ['old.txt'], 0, cancel=cancel)[0], 2)

    def delete(self, data, names, keep):
        lib.arkiv_seven_delete.argtypes = [C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_ubyte), C.c_uint64, C.c_int, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        paths = (C.c_char_p * len(names))(*(name.encode('utf-8') for name in names))
        mask = (C.c_ubyte * len(keep))(*keep)
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as output:
            source.write(data); source.flush()
            result = lib.arkiv_seven_delete(source.fileno(), paths, mask, len(keep), output.fileno(), None, None, None, None)
            output.seek(0)
            return result, output.read()

    def test_delete_retains_packed_bytes_and_maps_names_not_ordinals(self):
        data = stored_many([('keep', 0x20, b'kept bytes' * 100), ('remove', 0x20, b'removed')])
        result, after = self.delete(data, ['remove', 'keep'], [0, 1])
        self.assertEqual(result, 0)
        self.assertEqual(after[32:32 + 1000], b'kept bytes' * 100)
        result, tar = self.decode(after)
        self.assertEqual(result, 0)
        with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
            self.assertEqual(archive.getnames(), ['keep'])
            self.assertEqual(archive.extractfile('keep').read(), b'kept bytes' * 100)
        self.assertNotEqual(self.delete(data, ['keep', 'unknown'], [1, 0])[0], 0)
        self.assertNotEqual(self.delete(data, ['keep', 'keep'], [1, 0])[0], 0)

    def test_delete_to_empty_and_keep_lzma2_without_recompression(self):
        before, packed = copy_or_lzma2(method='LZMA2')
        result, after = self.delete(before, ['old.txt'], [1])
        self.assertEqual(result, 0)
        self.assertEqual(after[32:32 + len(packed)], packed)
        result, empty = self.delete(before, ['old.txt'], [0])
        self.assertEqual(result, 0)
        self.assertEqual(self.probe(empty), 0)
        self.assertEqual(self.decode(empty)[0], 0)

    def test_append_cancellation(self):
        cancel = C.CFUNCTYPE(C.c_int, C.c_void_p)(lambda _: 1)
        self.assertEqual(self.append(copy_or_lzma2()[0], cancel)[0], 2)


@unittest.skipUnless(os.environ.get('ARKIV_TEST_LIBRARY'), 'C transaction library required')
class SevenZipTransactionTests(unittest.TestCase):
    def setUp(self):
        self.api = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
        for name in ['arkiv_seven_begin', 'arkiv_zip_begin']:
            getattr(self.api, name).argtypes = [C.c_char_p, C.c_char_p, C.c_size_t]
            getattr(self.api, name).restype = C.c_void_p
        self.api.arkiv_zip_end.argtypes = [C.c_void_p]
        self.api.arkiv_seven_prepare.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]
        self.api.arkiv_zip_prepare.argtypes = self.api.arkiv_seven_prepare.argtypes
        self.api.arkiv_zip_commit.argtypes = [C.c_void_p, C.c_void_p, C.c_char_p, C.c_size_t]
        self.api.arkiv_cancel_new.restype = C.c_void_p
        self.api.arkiv_cancel_set.argtypes = [C.c_void_p]
        self.api.arkiv_cancel_free.argtypes = [C.c_void_p]
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name).resolve()
        self.original = self.root / 'original.7z'
        self.before, self.packed = copy_or_lzma2(method='LZMA2')
        self.original.write_bytes(self.before)
        self.original.chmod(0o640)
        self.stage = self.root / 'stage'; self.stage.mkdir(mode=0o700)
        self.additions = self.root / 'additions.zip'
        with zipfile.ZipFile(self.additions, 'w') as z: z.writestr('new', b'new content')
        self.error = C.create_string_buffer(256)
        self.transaction = self.api.arkiv_seven_begin(os.fsencode(self.original), self.error, 256)
        self.assertTrue(self.transaction, self.error.value)

    def tearDown(self):
        self.api.arkiv_zip_end(self.transaction)
        self.tmp.cleanup()

    def prepare(self, token=None, callback=None):
        return self.api.arkiv_seven_prepare(self.transaction, os.fsencode(self.additions), os.fsencode(self.stage), token, callback, None, self.error, 256)

    def commit(self, token=None):
        return self.api.arkiv_zip_commit(self.transaction, token, self.error, 256)

    def test_verify_then_atomic_publication_preserves_original_mode(self):
        self.assertEqual(self.prepare(), 0, self.error.value)
        self.assertEqual(self.original.read_bytes(), self.before)
        self.assertEqual(self.commit(), 0, self.error.value)
        self.assertEqual(self.original.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.original.read_bytes()[32:32+len(self.packed)], self.packed)
        self.assertFalse((self.stage / 'replacement.zip').exists())

    def test_cancel_during_prepare_keeps_original(self):
        token = self.api.arkiv_cancel_new()
        callback = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64, C.c_uint64)(lambda *_: self.api.arkiv_cancel_set(token))
        try:
            self.assertEqual(self.prepare(token, callback), 2)
            self.assertNotEqual(self.commit(), 0)
            self.assertEqual(self.original.read_bytes(), self.before)
        finally: self.api.arkiv_cancel_free(token)

    def test_cancel_before_commit_keeps_original(self):
        self.assertEqual(self.prepare(), 0)
        token = self.api.arkiv_cancel_new()
        try:
            self.api.arkiv_cancel_set(token)
            self.assertEqual(self.commit(token), 2)
            self.assertEqual(self.original.read_bytes(), self.before)
        finally: self.api.arkiv_cancel_free(token)

    def test_changed_source_refuses_publication(self):
        self.assertEqual(self.prepare(), 0)
        self.original.write_bytes(b'externally changed')
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.original.read_bytes(), b'externally changed')

    def test_changed_replacement_refuses_publication(self):
        self.assertEqual(self.prepare(), 0)
        (self.stage / 'replacement.zip').write_bytes(b'changed replacement')
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.original.read_bytes(), self.before)

    def test_corrupt_original_fails_full_verification(self):
        broken = bytearray(self.before); broken[40] ^= 0x80
        self.assertNotEqual(SevenZipTests().decode(bytes(broken))[0], 0, "fixture must corrupt decoded content")
        self.original.write_bytes(broken)
        self.assertEqual(self.prepare(), 1)
        self.assertEqual(self.commit(), 1)
        self.assertEqual(self.original.read_bytes(), broken)

    def test_zip_prepare_rejects_seven_transaction(self):
        self.assertEqual(self.api.arkiv_zip_prepare(self.transaction, os.fsencode(self.additions), os.fsencode(self.stage), None, None, None, self.error, 256), 1)
        self.assertEqual(self.original.read_bytes(), self.before)


if __name__ == '__main__':
    unittest.main()
