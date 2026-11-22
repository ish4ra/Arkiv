"""CI reliability regressions: pipefail-safe matching and bounded PlugInKit retries.

Runs on any OS with bash. The shell tests feed synthetic `otool -L` output to
the exact helper that scripts/verify-app.sh sources.
"""
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'scripts/verification-helpers.sh'
SYSTEM = ''.join(f'\t/usr/lib/{name} (compatibility version 1.0.0, current version 1.2.12)\n'
                 for name in ('libz.1.dylib', 'libbz2.1.0.dylib', 'liblzma.5.dylib'))
# Far larger than any pipe buffer, so an early-exiting grep reliably meets a
# producer that is still writing.
FILLER = ''.join(f'\t/System/Library/Frameworks/Filler{i}.framework/Versions/A/Filler{i} (compatibility version 1.0.0)\n'
                 for i in range(12000))
# Pipe operators into an early-exiting reader. A pipeline into such a reader is
# only safe without pipefail, so these patterns are banned in pipefail scripts.
EARLY_EXIT = re.compile(r'\|\s*(grep\b[^|\n]*\s-[A-Za-z]*[qm]|head\b|sed\s+-n\s+[^|\n]*q)')


def bash(script, stdin=''):
    return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + script], input=stdin,
                          capture_output=True, text=True, cwd=ROOT, timeout=60)


def check_libraries(libraries):
    return bash('fail() { echo "FAIL: $1" >&2; exit 1; }\n'
                f'source "{HELPERS}"\n'
                'libraries=$(cat)\n'
                'verify_slice_libraries arm64 "$libraries"\n'
                'echo verified\n', libraries)


class PipefailMatchingTests(unittest.TestCase):
    def test_old_pattern_reproduces_false_failure(self):
        # Control: the replaced `printf | grep -Fq` reports a present library as missing.
        result = bash('libraries=$(cat)\n'
                      "printf '%s\\n' \"$libraries\" | grep -Fq $'\\t/usr/lib/libz.1.dylib (' || exit 7\n",
                      SYSTEM + FILLER)
        self.assertEqual(result.returncode, 7, 'Expected the SIGPIPE false failure the fix removes')

    def test_old_pattern_reproduces_silent_pass(self):
        # Control: inside `if`, the same race hides a forbidden host library.
        result = bash('libraries=$(cat)\n'
                      "if printf '%s\\n' \"$libraries\" | grep -Eq '/usr/local/|/opt/|libzstd'; then exit 7; fi\n",
                      '\t/usr/local/lib/libzstd.1.dylib (compatibility version 1.0.0)\n' + SYSTEM + FILLER)
        self.assertEqual(result.returncode, 0, 'Expected the SIGPIPE silent pass the fix removes')

    def test_present_system_decoders_pass_with_large_output(self):
        for libraries in (SYSTEM, SYSTEM + FILLER, FILLER + SYSTEM):
            result = check_libraries(libraries)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('verified', result.stdout)

    def test_each_missing_system_decoder_fails(self):
        for name in ('libz.1.dylib', 'libbz2.1.0.dylib', 'liblzma.5.dylib'):
            libraries = ''.join(line + '\n' for line in SYSTEM.splitlines() if name not in line)
            result = check_libraries(libraries + FILLER)
            self.assertEqual(result.returncode, 1)
            self.assertIn(f'Missing system decoder {name} in arm64 slice.', result.stderr)

    def test_decoder_must_be_the_system_path(self):
        result = check_libraries(SYSTEM.replace('\t/usr/lib/libz.1.dylib', '\t@rpath/libz.1.dylib') + FILLER)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Missing system decoder libz.1.dylib', result.stderr)

    def test_forbidden_host_libraries_fail_wherever_they_appear(self):
        for bad in ('\t/usr/local/lib/liblzma.5.dylib (compatibility version 8.0.0)\n',
                    '\t/opt/homebrew/opt/xz/lib/liblzma.5.dylib (compatibility version 8.0.0)\n',
                    '\t@rpath/libzstd.1.dylib (compatibility version 1.0.0)\n'):
            for libraries in (bad + SYSTEM + FILLER, SYSTEM + FILLER + bad):
                result = check_libraries(libraries)
                self.assertEqual(result.returncode, 1, bad)
                self.assertIn('depends on a non-system host library', result.stderr)

    def test_matching_errors_fail_closed(self):
        result = bash(f'source "{HELPERS}"\nif text_contains E "text" "("; then exit 0; else exit 0; fi\n')
        self.assertGreaterEqual(result.returncode, 2, 'A grep error must not read as "no match"')
        result = bash(f'source "{HELPERS}"\ntext_contains X "text" "t"\n')
        self.assertEqual(result.returncode, 2)

    def test_fixed_matching_is_literal(self):
        result = bash(f'source "{HELPERS}"\n'
                      'text_contains F "@rpath/libArkivSeven.dylib" "@rpath/libArkivSeven.dylib"\n'
                      '! text_contains F "@rpath/libArkivSevenXdylib" "@rpath/libArkivSeven.dylib"\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_verify_app_uses_safe_helpers_for_every_dependency_check(self):
        text = (ROOT / 'scripts/verify-app.sh').read_text()
        self.assertIn('source scripts/verification-helpers.sh', text)
        self.assertIn('verify_slice_libraries "$arch" "$libraries"', text)
        self.assertIn("text_contains F \"$links\" '@rpath/libArkivSeven.dylib' || fail", text)
        self.assertIn('libraries=$(otool -arch "$arch" -L "$binary")', text)
        self.assertIn('links=$(otool -L "$binary")', text)

    def test_no_early_exit_pipelines_under_pipefail(self):
        sources = sorted([*ROOT.glob('scripts/*.sh'), *ROOT.glob('branding/*.sh')])
        self.assertIn(ROOT / 'scripts/verify-app.sh', sources)
        audited = 0
        for path in sources:
            text = path.read_text()
            if 'pipefail' not in text:
                continue
            audited += 1
            for number, line in enumerate(text.splitlines(), 1):
                if not line.lstrip().startswith('#'):
                    self.assertIsNone(EARLY_EXIT.search(line), f'{path.name}:{number}: {line.strip()}')
        self.assertGreaterEqual(audited, 8)
        # GitHub's default macOS `run:` shell is `bash -eo pipefail`.
        for number, line in enumerate((ROOT / '.github/workflows/macos.yml').read_text().splitlines(), 1):
            self.assertIsNone(EARLY_EXIT.search(line), f'macos.yml:{number}: {line.strip()}')

    def test_audit_pattern_catches_known_vulnerable_forms(self):
        for line in ["printf '%s\\n' \"$x\" | grep -Fq foo || fail", 'otool -L "$b" | grep -q bar',
                     'if cmd | grep -Eq baz; then', 'cmd | head -1', "cmd | sed -n '1p;1q'", 'cmd | grep -m1 x']:
            self.assertIsNotNone(EARLY_EXIT.search(line), line)
        for line in ['text_contains F "$links" foo', 'cmd | sed s/a/b/', 'grep -Fq foo <<< "$x"']:
            self.assertIsNone(EARLY_EXIT.search(line), line)


spec = importlib.util.spec_from_file_location('finder_diagnostic', ROOT / 'scripts/diagnose-finder-extension.py')
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)
EXTENSION = Path('/build/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex')
LISTING = f'+    {diagnostic.IDENTIFIER}(26501)\n\t    Path = {EXTENSION}\n'


class FakePluginKit:
    def __init__(self, register, discover):
        self.responses = {'-a': list(register), '-m': list(discover)}
        self.calls, self.sleeps = [], []

    def run(self, args):
        self.calls.append(args[0])
        queue = self.responses[args[0]]
        return queue.pop(0) if len(queue) > 1 else queue[0]

    def sleep(self, seconds):
        self.sleeps.append(seconds)


class PlugInKitRetryTests(unittest.TestCase):
    def check(self, fake):
        return diagnostic.check(EXTENSION, run=fake.run, sleep=fake.sleep)

    def test_immediate_discovery_needs_no_retry(self):
        fake = FakePluginKit([(0, '')], [(0, LISTING)])
        message, logs = self.check(fake)
        self.assertEqual(fake.calls, ['-a', '-m'])
        self.assertEqual(fake.sleeps, [])
        self.assertNotIn('attempts', message)
        self.assertIn('discover attempt 1: exit 0', logs['discover'][0])

    def test_late_indexing_is_retried_and_reported(self):
        fake = FakePluginKit([(0, '')], [(0, ''), (0, '(no matches)\n'), (0, LISTING)])
        message, logs = self.check(fake)
        self.assertEqual(fake.calls, ['-a', '-m', '-m', '-m'])
        self.assertEqual(fake.sleeps, [1, 2])
        self.assertIn('after 3 attempts', message)
        self.assertEqual(len(logs['discover']), 3)

    def test_transient_register_failure_is_retried(self):
        fake = FakePluginKit([(1, 'pkd busy'), (0, '')], [(0, LISTING)])
        self.check(fake)
        self.assertEqual(fake.calls, ['-a', '-a', '-m'])

    def test_retries_are_bounded_and_still_fail(self):
        fake = FakePluginKit([(0, '')], [(0, '')])
        with self.assertRaises(SystemExit) as failure:
            self.check(fake)
        self.assertIn('did not discover', failure.exception.args[0])
        self.assertEqual(fake.calls.count('-m'), len(diagnostic.BACKOFF) + 1)
        self.assertEqual(fake.sleeps, list(diagnostic.BACKOFF))
        self.assertLessEqual(sum(diagnostic.BACKOFF), 30)

    def test_register_failure_on_every_attempt_fails(self):
        fake = FakePluginKit([(1, 'denied')], [(0, LISTING)])
        with self.assertRaises(SystemExit) as failure:
            self.check(fake)
        self.assertIn('register failed', failure.exception.args[0])
        self.assertNotIn('-m', fake.calls)

    def test_other_copy_or_failed_listing_never_satisfies_discovery(self):
        other = LISTING.replace(str(EXTENSION), '/Applications/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex')
        for response in [(0, other), (1, LISTING), (0, f'Path = {EXTENSION}\n')]:
            with self.assertRaises(SystemExit):
                self.check(FakePluginKit([(0, '')], [response]))


if __name__ == '__main__':
    unittest.main()
