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
        sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        package = json.loads(subprocess.check_output(['swift', 'package', 'dump-package'], cwd=ROOT))
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
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # A host-only library earlier on -L must never shadow the SDK.
            decoy = root / 'decoy.c'
            decoy.write_text('void arkiv_decoy(void) {}\n')
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
    return result == LZMA_OK || result == LZMA_BUF_ERROR ? 0 : 3;
}
''')
            for arch in ('arm64', 'x86_64'):
                with self.subTest(architecture=arch):
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
                    if arch == platform.machine():
                        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
