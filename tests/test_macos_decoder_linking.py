"""Exercise the real package link settings against a conflicting host liblzma."""
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SYSTEM_LIBRARIES = ('libz.1.dylib', 'libbz2.1.0.dylib', 'liblzma.5.dylib')


@unittest.skipUnless(platform.system() == 'Darwin', 'Requires the real macOS SDK/linker')
class DecoderLinkingTests(unittest.TestCase):
    def test_both_slices_ignore_host_library_and_use_system_decoders(self):
        print('::notice title=Arkiv decoder link regression::Resolving SDK', flush=True)
        sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        print('::notice title=Arkiv decoder link regression::Reading package link settings', flush=True)
        manifest = subprocess.run(['swift', 'package', 'dump-package'], cwd=ROOT, capture_output=True, text=True)
        if manifest.returncode:
            for phrase in ['cannot be used within an App Sandbox', 'Operation not permitted', 'Invalid manifest', 'SDK must provide', 'Select an installed macOS SDK']:
                if phrase.lower() in manifest.stderr.lower():
                    print('::error title=Arkiv decoder manifest diagnostic::' + phrase, flush=True)
        manifest.check_returncode()
        package = json.loads(manifest.stdout)
        target = next(t for t in package['targets'] if t['name'] == 'CArkiv')
        flags = []
        for setting in target['settings']:
            if setting['tool'] != 'linker':
                continue
            kind = setting['kind']
            if 'unsafeFlags' in kind:
                flags += kind['unsafeFlags']['_0']
            elif 'linkedLibrary' in kind and kind['linkedLibrary']['_0'] in ('z', 'bz2', 'lzma'):
                flags += ['-l' + kind['linkedLibrary']['_0']]
        print('::notice title=Arkiv decoder link regression::Package link settings parsed', flush=True)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # A host-only library earlier on -L must never shadow the SDK.
            decoy = root / 'decoy.c'
            decoy.write_text('void arkiv_decoy(void) {}\n')
            print('::notice title=Arkiv decoder link regression::Building conflicting host library', flush=True)
            subprocess.run(['xcrun', 'clang', '-isysroot', sdk, '-arch', 'x86_64',
                            '-dynamiclib', str(decoy), '-o', str(root / 'liblzma.dylib'),
                            '-Wl,-install_name,/usr/local/lib/liblzma.dylib'], check=True)
            probe = root / 'probe.c'
            probe.write_text('''#include <zlib.h>
#include "bzlib.h"
#include "xz/lzma.h"
int main(void) {
    if (!zlibVersion() || !BZ2_bzlibVersion()) return 1;
    lzma_stream stream = LZMA_STREAM_INIT;
    if (lzma_stream_decoder(&stream, 64ULL * 1024 * 1024, 0) != LZMA_OK) return 2;
    lzma_ret result = lzma_code(&stream, LZMA_FINISH);
    lzma_end(&stream);
    if (result != LZMA_OK && result != LZMA_BUF_ERROR) return 3;
    unsigned char buffer[4096];
    z_stream z = {0};
    if (deflateInit2(&z, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY) != Z_OK) return 4;
    z.next_out = buffer; z.avail_out = sizeof(buffer);
    if (deflate(&z, Z_FINISH) != Z_STREAM_END) return 5;
    deflateEnd(&z);
    bz_stream bz = {0};
    if (BZ2_bzCompressInit(&bz, 9, 0, 30) != BZ_OK) return 6;
    bz.next_out = (char *)buffer; bz.avail_out = sizeof(buffer);
    if (BZ2_bzCompress(&bz, BZ_FINISH) != BZ_STREAM_END) return 7;
    BZ2_bzCompressEnd(&bz);
    lzma_stream encoder = LZMA_STREAM_INIT;
    if (lzma_easy_encoder_memusage(6) > (128ULL << 20) || lzma_easy_decoder_memusage(6) > (64ULL << 20)) return 8;
    if (lzma_easy_encoder(&encoder, 6, LZMA_CHECK_CRC64) != LZMA_OK) return 9;
    encoder.next_out = buffer; encoder.avail_out = sizeof(buffer);
    if (lzma_code(&encoder, LZMA_FINISH) != LZMA_STREAM_END) return 10;
    lzma_end(&encoder);
    return 0;
}
''')
            for arch in ('arm64', 'x86_64'):
                with self.subTest(architecture=arch):
                    print('::notice title=Arkiv decoder link regression::Linking ' + arch, flush=True)
                    binary = root / arch
                    # Package flags use Swift driver's -Xlinker spelling, also
                    # accepted by clang. No extra SDK -L directory masks a bug.
                    subprocess.run(['xcrun', 'clang', '-isysroot', sdk, '-arch', arch,
                                    '-mmacosx-version-min=13.0', '-L' + str(root),
                                    '-I', str(ROOT / 'Sources/CArkiv/vendor'),
                                    '-I', str(ROOT / 'Sources/CArkiv/vendor/xz'),
                                    str(probe), *flags, '-o', str(binary)], check=True)
                    subprocess.run(['lipo', str(binary), '-verify_arch', arch], check=True)
                    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
                    dependencies = [line.strip().split(' (')[0] for line in linked.splitlines()[1:]]
                    for name in SYSTEM_LIBRARIES:
                        self.assertIn('/usr/lib/' + name, dependencies)
                    self.assertFalse(any('/usr/local/' in p or '/opt/' in p for p in dependencies))
                    print('::notice title=Arkiv decoder link regression::Verified system dependencies for ' + arch, flush=True)
                    if arch == platform.machine():
                        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
