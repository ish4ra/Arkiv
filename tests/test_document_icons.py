import copy
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import re
import shutil
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location('icons', 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)
spec = importlib.util.spec_from_file_location('packager', 'scripts/package-document-icons.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)

# SHA-256 of Resources/DocumentIcons/PIXELS.sha256: the decoded pixels of build
# 26501's refined Seal Dark icons, byte-identical to the manifest preserved on
# archive/document-icon-concepts-v2 (themes/seal-dark-refined-26501). Changing
# it means changing the artwork, which needs an approved design change.
PIXELS_26501 = '53e7df26242c7e331dc07cd6b26b1eaa126ebc60c8ef34f8b56fb6ad7cafbf57'
# SHA-256 of Resources/DocumentIconsInApp/PIXELS.sha256: the decoded pixels of
# the refined Seal Dark compound-suffix and split-7z artwork, rendered by the
# archived 26501 generator (512 px renders byte-identical to the preserved
# previews). Change only together with an approved artwork change.
PIXELS_INAPP = '64601047f7204e4911c29c7b5553bd92b1251486bb7cb62f59dc8a056bc451f1'


def encode_png(width, height, rgba, level=9, extra=()):
    """Minimal stdlib PNG encoder (filter 0) for synthetic lossless re-encodes."""
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    stride = width * 4
    raw = b''.join(b'\0' + rgba[y * stride:(y + 1) * stride] for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + b''.join(chunk(kind, body) for kind, body in extra)
            + chunk(b'IDAT', zlib.compress(raw, level)) + chunk(b'IEND', b''))


def resum(root):
    """Rewrite SHA256SUMS so only the pixel and layout checks can reject a change."""
    lines = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}' for p in root.glob('*.iconset/*.png')]
    (root / 'SHA256SUMS').write_text('\n'.join(sorted(lines, key=lambda line: line[66:])) + '\n')


class DocumentIconTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads(Path('Resources/Info.plist').read_bytes())

    # Registrations -----------------------------------------------------------
    def test_supported_viewer_alternate_registrations(self):
        icons.verify_metadata(self.info)

    def test_every_supported_format_has_its_own_icon(self):
        declared = {d['LSItemContentTypes'][0]: d['CFBundleTypeIconFile'] for d in self.info['CFBundleDocumentTypes']}
        self.assertEqual(set(declared), set(icons.ICONS.values()))
        self.assertEqual(len(set(declared.values())), len(icons.ICONS), 'No two document types share artwork')

    def test_registration_never_claims_default_handler(self):
        for uti in icons.ICONS.values():
            for field, value in [('LSHandlerRank', 'Owner'), ('LSHandlerRank', 'Default'), ('CFBundleTypeRole', 'Editor')]:
                changed = copy.deepcopy(self.info)
                next(d for d in changed['CFBundleDocumentTypes'] if d['LSItemContentTypes'] == [uti])[field] = value
                with self.assertRaises(AssertionError):
                    icons.verify_metadata(changed)

    def test_stream_registration_keeps_existing_default_handlers(self):
        for uti in icons.STREAM_FORMATS:
            changed = copy.deepcopy(self.info)
            next(d for d in changed['CFBundleDocumentTypes'] if d['LSItemContentTypes'] == [uti])['LSHandlerRank'] = 'Owner'
            with self.assertRaises(AssertionError):
                icons.verify_metadata(changed)

    def test_bad_icon_reference_rejected(self):
        changed = copy.deepcopy(self.info)
        changed['CFBundleDocumentTypes'][0]['CFBundleTypeIconFile'] = 'Missing.icns'
        with self.assertRaises(AssertionError):
            icons.verify_metadata(changed)

    def test_alias_mappings(self):
        imported = {d['UTTypeIdentifier']: d['UTTypeTagSpecification']['public.filename-extension']
                    for d in self.info['UTImportedTypeDeclarations']}
        extensions = [e for values in imported.values() for e in values]
        # .tgz: attached to the macOS-declared type; never redeclared by Arkiv.
        self.assertIn('org.gnu.gnu-zip-tar-archive', icons.ICONS.values())
        self.assertNotIn('org.gnu.gnu-zip-tar-archive', imported)
        self.assertNotIn('tgz', extensions)
        # .tbz2/.tbz and .txz: macOS-declared types, likewise never redeclared.
        for uti in ['public.tar-bzip2-archive', 'org.tukaani.tar-xz-archive']:
            self.assertIn(uti, icons.ICONS.values())
            self.assertNotIn(uti, imported)
        self.assertEqual(set(icons.SYSTEM_DECLARED), {'org.gnu.gnu-zip-tar-archive', 'public.tar-bzip2-archive', 'org.tukaani.tar-xz-archive'})
        # .tzst stays on the existing Zstandard type so current associations do not move.
        self.assertEqual(imported['org.zstandard.zstd'], ['zst', 'tzst'])
        # No alias or double suffix is declared by Arkiv itself.
        for ext in ['tbz2', 'tbz', 'txz', 'tar.gz', 'tar.bz2', 'tar.xz', 'tar.zst']:
            self.assertNotIn(ext, extensions)
        changed = copy.deepcopy(self.info)
        changed['UTImportedTypeDeclarations'].append({'UTTypeIdentifier': 'org.gnu.gnu-zip-tar-archive', 'UTTypeConformsTo': ['public.archive'],
                                                      'UTTypeTagSpecification': {'public.filename-extension': ['tgz']}})
        with self.assertRaises(AssertionError):
            icons.verify_metadata(changed)

    def test_no_generic_numeric_extension_registration(self):
        icons.verify_no_generic_extensions(self.info)
        text = Path('Resources/Info.plist').read_text()
        for ext in ['001', '002', '003', 'z01', 'r00', 'part1']:
            self.assertNotIn(f'<string>{ext}</string>', text)
        for ext in ['001', 'z01', 'r00', 'part1']:
            changed = copy.deepcopy(self.info)
            changed['UTImportedTypeDeclarations'][0]['UTTypeTagSpecification']['public.filename-extension'].append(ext)
            with self.assertRaises(AssertionError):
                icons.verify_no_generic_extensions(changed)

    # Icon sources --------------------------------------------------------------
    def test_iconset_sizes_transparency_and_checksums(self):
        icons.verify_sources()

    def test_tampered_or_missing_representation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'DocumentIcons'
            shutil.copytree(icons.SOURCES, root)
            target = root / 'Arkiv-ZIP.iconset/icon_16x16.png'
            target.write_bytes(target.read_bytes() + b'\0')
            with self.assertRaises(AssertionError):
                icons.verify_sources(root, decode_limit=0)
            shutil.copytree(icons.SOURCES, root, dirs_exist_ok=True)
            (root / 'Arkiv-ZIP.iconset/icon_512x512@2x.png').unlink()
            with self.assertRaises(AssertionError):
                icons.verify_sources(root, decode_limit=0)

    def test_pixels_are_build_26501(self):
        manifest = icons.SOURCES / 'PIXELS.sha256'
        self.assertEqual(hashlib.sha256(manifest.read_bytes()).hexdigest(), PIXELS_26501)
        self.assertEqual(set(icons.read_manifest(manifest)), set(icons.read_manifest(icons.SOURCES / 'SHA256SUMS')))

    def test_inapp_extras_are_pinned_and_verified(self):
        self.assertEqual(hashlib.sha256((icons.INAPP / 'PIXELS.sha256').read_bytes()).hexdigest(), PIXELS_INAPP)
        self.assertEqual(icons.verify_inapp(), 24)
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / 'DocumentIconsInApp'
            shutil.copytree(icons.INAPP, copy)
            target = copy / 'Arkiv-TAR.XZ/icon_16x16.png'
            data = bytearray(target.read_bytes()); data[-20] ^= 1
            target.write_bytes(bytes(data))
            with self.assertRaises(AssertionError):
                icons.verify_inapp(copy)

    def test_lossless_reencode_passes_but_any_pixel_change_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'DocumentIcons'
            shutil.copytree(icons.SOURCES, root)
            target = root / 'Arkiv-ZIP.iconset/icon_32x32.png'
            width, height, rgba = icons.read_png(target)
            # A different encoder (filter 0, zlib level 1) with identical pixels is accepted.
            target.write_bytes(encode_png(width, height, rgba, level=1))
            resum(root)
            icons.verify_sources(root)
            # One channel of one pixel, even a fully transparent one, is rejected.
            for index in (0, len(rgba) // 2 + 1):
                changed = bytearray(rgba)
                changed[index] ^= 1
                target.write_bytes(encode_png(width, height, bytes(changed)))
                resum(root)
                with self.assertRaisesRegex(AssertionError, 'Pixels differ'):
                    icons.verify_sources(root)

    def test_png_metadata_chunks_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'DocumentIcons'
            shutil.copytree(icons.SOURCES, root)
            target = root / 'Arkiv-7z.iconset/icon_16x16.png'
            width, height, rgba = icons.read_png(target)
            for extra in [(b'gAMA', struct.pack('>I', 45455)), (b'iCCP', b'x\0\0'), (b'tEXt', b'k\0v')]:
                target.write_bytes(encode_png(width, height, rgba, extra=[extra]))
                resum(root)
                with self.assertRaisesRegex(AssertionError, 'chunks'):
                    icons.verify_sources(root, decode_limit=0)

    def test_pixel_manifest_must_cover_every_representation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'DocumentIcons'
            shutil.copytree(icons.SOURCES, root)
            manifest = root / 'PIXELS.sha256'
            manifest.write_text(''.join(manifest.read_text().splitlines(keepends=True)[1:]))
            with self.assertRaises(AssertionError):
                icons.verify_sources(root, decode_limit=0)

    def test_icns_png_elements_checked_against_pixels(self):
        iconset = icons.SOURCES / 'Arkiv-TAR.iconset'
        types = {'ic07': 'icon_128x128.png', 'ic13': 'icon_128x128@2x.png', 'ic11': 'icon_16x16@2x.png'}
        def icns(elements):
            body = b''.join(kind.encode() + struct.pack('>I', len(data) + 8) + data for kind, data in elements)
            return b'icns' + struct.pack('>I', len(body) + 8) + body
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Arkiv-TAR.icns'
            elements = [(kind, (iconset / name).read_bytes()) for kind, name in types.items()]
            path.write_bytes(icns(elements + [('is32', b'\0' * 12)]))
            self.assertEqual(icons.verify_icns(path, iconset), (['ic07', 'ic13', 'ic11', 'is32'], 3, 3))
            width, height, rgba = icons.read_png(iconset / 'icon_128x128.png')
            path.write_bytes(icns([('ic07', encode_png(width, height, rgba))]))
            self.assertEqual(icons.verify_icns(path, iconset), (['ic07'], 1, 0), 'Re-encoded but pixel-identical')
            path.write_bytes(icns([('ic07', (iconset / 'icon_256x256.png').read_bytes())]))
            with self.assertRaises(AssertionError):
                icons.verify_icns(path, iconset)
            path.write_bytes(icns(elements)[:-3])
            with self.assertRaises(AssertionError):
                icons.verify_icns(path, iconset)

    # Packaging ------------------------------------------------------------------
    def iconutil_like(self, name, extra=((b'sRGB', b'\0'), (b'pHYs', struct.pack('>IIB', 5669, 5669, 1)))):
        """A PNG shaped like an iconutil re-encode: same pixels, ancillary chunks, weak Deflate."""
        width, height, rgba = icons.read_png(icons.SOURCES / 'Arkiv-ZIP.iconset' / name)
        return encode_png(width, height, rgba, level=1, extra=extra)

    def icns(self, elements):
        body = b''.join(kind.encode() + struct.pack('>I', len(data) + 8) + data for kind, data in elements)
        return b'icns' + struct.pack('>I', len(body) + 8) + body

    def test_packaging_swaps_only_verified_idat_data(self):
        iconset = icons.SOURCES / 'Arkiv-ZIP.iconset'
        pixels = icons.read_manifest(icons.SOURCES / 'PIXELS.sha256')
        argb = b'\0\0\0\0ARGB' + bytes(range(64))
        info = b'bplist00' + bytes(20)
        plain = self.icns([('ic12', self.iconutil_like('icon_32x32@2x.png')), ('ic04', argb),
                           ('ic07', self.iconutil_like('icon_128x128.png')), ('info', info)])
        packaged, report = packager.splice_icns(plain, iconset, pixels)
        self.assertLess(len(packaged), len(plain))
        self.assertEqual([r[0] for r in report], ['ic12', 'ic07'])
        before, after = dict(icons.icns_elements_bytes(plain)), dict(icons.icns_elements_bytes(packaged))
        self.assertEqual(list(before), list(after), 'Element types and order are iconutil\'s')
        self.assertEqual(after['ic04'], argb)
        self.assertEqual(after['info'], info)
        for kind, name in [('ic12', 'icon_32x32@2x.png'), ('ic07', 'icon_128x128.png')]:
            theirs, ours = list(icons.png_chunks(before[kind])), list(icons.png_chunks(after[kind]))
            self.assertEqual([c for c in theirs if c[0] != b'IDAT'], [c for c in ours if c[0] != b'IDAT'],
                             'IHDR, colour metadata and other chunks are preserved exactly')
            committed = [body for k, body in icons.png_chunks((iconset / name).read_bytes()) if k == b'IDAT']
            self.assertEqual([body for k, body in ours if k == b'IDAT'], committed)
            self.assertEqual(icons.decode_png(after[kind]), icons.decode_png(before[kind]))
        self.assertEqual(packager.splice_icns(plain, iconset, pixels), (packaged, report), 'Deterministic')
        # Packaged-app verification rebuilds without decoding; for a valid build
        # it must reproduce exactly the bytes the fully checked build wrote.
        self.assertEqual(packager.splice_icns(plain, iconset, pixels, verify_pixels=False), (packaged, report))
        self.assertEqual(icons.verify_icns_bytes(packaged, iconset), (['ic12', 'ic04', 'ic07', 'info'], 2, 2))

    def test_packaging_keeps_iconutil_element_when_unsafe(self):
        iconset = icons.SOURCES / 'Arkiv-ZIP.iconset'
        pixels = icons.read_manifest(icons.SOURCES / 'PIXELS.sha256')
        width, height, rgba = icons.read_png(iconset / 'icon_128x128.png')
        changed = bytearray(rgba)
        changed[len(changed) // 2] ^= 1
        cases = {
            'different pixels': encode_png(width, height, bytes(changed), level=1),
            'wrong representation': self.iconutil_like('icon_256x256.png'),
            'already smaller': (iconset / 'icon_128x128.png').read_bytes(),
        }
        for label, payload in cases.items():
            plain = self.icns([('ic07', payload)])
            packaged, _ = packager.splice_icns(plain, iconset, pixels)
            self.assertEqual(packaged, plain, label)
        # If the checked build kept iconutil's element because pixels differed,
        # the decode-free rebuild differs from it, so verification fails closed.
        plain = self.icns([('ic07', cases['different pixels'])])
        self.assertNotEqual(packager.splice_icns(plain, iconset, pixels, verify_pixels=False)[0],
                            packager.splice_icns(plain, iconset, pixels)[0])
        wrong_manifest = dict(pixels, **{'Arkiv-ZIP.iconset/icon_128x128.png': '0' * 64})
        plain = self.icns([('ic07', self.iconutil_like('icon_128x128.png'))])
        self.assertEqual(packager.splice_icns(plain, iconset, wrong_manifest)[0], plain)

    def test_optimizer_is_pinned_lossless_and_deterministic(self):
        source = Path('design/document-icons/optimize.py').read_text()
        for setting in ['optimize_alpha=False', 'bit_depth_reduction=False', 'color_type_reduction=False',
                        'palette_reduction=False', 'grayscale_reduction=False', 'interlace=None',
                        'strip=oxipng.StripChunks.none()', 'timeout=None', "OXIPNG_VERSION = '9.1.1'"]:
            self.assertIn(setting, source)
        requirements = Path('design/document-icons/requirements-optimize.txt').read_text()
        self.assertIn('pyoxipng==9.1.1', requirements)
        self.assertEqual(requirements.count('--hash=sha256:'), 3)
        generator = Path('design/document-icons/generate.mjs').read_text()
        self.assertIn("optimize('--reproduce', tmp)", generator)
        self.assertIn("optimize('--record-pixels', RES)", generator)
        for path in ['Package.swift', 'Package.resolved', 'scripts/build-app.sh']:
            self.assertNotIn('oxipng', Path(path).read_text(), 'Optimization is design-time only')

    def test_png_decoder_detects_opaque_corners(self):
        width, height, rgba = icons.read_png(icons.SOURCES / 'Arkiv-7z.iconset/icon_32x32.png')
        self.assertEqual((width, height), (32, 32))
        self.assertEqual(rgba[3], 0)
        self.assertEqual(rgba[((16 * 32) + 16) * 4 + 3], 255)

    def test_generator_table_matches_verification(self):
        config = Path('design/document-icons/generate-config.mjs').read_text()
        names = set(re.findall(r"^\s+'?([\w.]+)'?: \{ format:", config, re.M))
        self.assertEqual(names, set(icons.ICONS))
        for path in ['design/document-icons/generate.mjs', 'design/document-icons/seal-dark.mjs',
                     'design/document-icons/outline.mjs', 'design/document-icons/fonts/OFL.txt',
                     'design/document-icons/package-lock.json']:
            self.assertTrue(Path(path).is_file(), path)

    # Branding and packaging ----------------------------------------------------
    def test_original_artwork_preserved(self):
        icons.verify_branding()
        pins = Path('branding/app-icon-preservation.json').read_text()
        self.assertIn('scripts/render-icon.swift', pins)

    def test_build_and_packaged_verification_hooks(self):
        build = Path('scripts/build-app.sh').read_text()
        self.assertIn('shasum -a 256 -c SHA256SUMS', build)
        self.assertIn('python3 scripts/package-document-icons.py Resources/DocumentIcons "$app/Contents/Resources"', build)
        self.assertIn("['iconutil', '-c', 'icns', str(iconset)", Path('scripts/package-document-icons.py').read_text())
        self.assertIn('not the deterministic iconutil-based packaging', Path('scripts/verify-document-icons.py').read_text())
        self.assertIn('swift scripts/render-icon.swift', build, 'App icon still comes from its original renderer')
        self.assertNotIn('render-document-icons.swift', build)
        for tool in ['node ', 'npm ', 'npx ', 'playwright']:
            self.assertNotIn(tool, build, 'Icon generation is design-time only')
        self.assertIn('verify-document-icons.py', Path('scripts/verify-app.sh').read_text())
        self.assertTrue(Path('scripts/diagnose-document-types.swift').is_file())

    def test_design_sources_stay_out_of_runtime(self):
        package = Path('Package.swift').read_text()
        self.assertNotIn('design/', package)
        self.assertNotIn('DocumentIcons', package)
        ignored = Path('design/document-icons/.gitignore').read_text()
        self.assertIn('node_modules/', ignored)
        self.assertIn('out/', ignored)


if __name__ == '__main__':
    unittest.main()
