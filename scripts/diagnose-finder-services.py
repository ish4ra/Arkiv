#!/usr/bin/env python3
"""Development/CI-only Services database diagnostic. Never called by Arkiv itself.

The system pbs tool is an implementation detail, not an app runtime dependency.
Raw system output stays in local build logs; only fixed diagnostics are printed.
"""
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
pbs = Path('/System/Library/CoreServices/pbs')
logs = Path('.build/ci-logs')
logs.mkdir(parents=True, exist_ok=True)
if not pbs.is_file():
    raise SystemExit('System Services diagnostic unavailable: pbs is missing on this runner.')


def run(label, args):
    try:
        result = subprocess.run([str(pbs), *args], capture_output=True, text=True, errors='replace', timeout=45)
    except subprocess.TimeoutExpired:
        raise SystemExit('System Services diagnostic timed out: ' + label)
    (logs / ('services-' + label + '.log')).write_text(result.stdout + result.stderr)
    print('pbs ' + label + ' exit code: ' + str(result.returncode))
    if result.returncode:
        raise SystemExit('System Services diagnostic failed: ' + label)
    return result.stdout + result.stderr


def normalized(output):
    return output.replace('\\U2026', '…').replace('\\u2026', '…')


titles = [s['NSMenuItem']['default'] for s in info['NSServices']]
parsed = normalized(run('read-bundle', ['-read_bundle', str(app)]))
before = normalized(run('dump-before', ['-dump']))
print('::notice title=Arkiv Services diagnostic::Before indexing: ' +
      str(sum(title in before for title in titles)) + '/4 titles; read_bundle output: ' +
      str(sum(title in parsed for title in titles)) + '/4 titles.')

# A CI build directory is not an automatically indexed installation location.
# Register the actual built bundle, then ask Services to refresh its database.
# This is a test fixture operation only, never an application startup hook.
register = Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
result = subprocess.run([str(register), '-f', str(app)], capture_output=True, text=True, errors='replace', timeout=45)
(logs / 'services-launchservices.log').write_text(result.stdout + result.stderr)
if result.returncode:
    raise SystemExit('Launch Services registration failed for the built app.')
run('refresh', [])
dump = normalized(run('dump', ['-dump']))
found = sum(title in dump for title in titles)
print('::notice title=Arkiv Services diagnostic::After indexing: ' + str(found) + '/4 direct titles; bundle path present: ' + str(str(app) in dump) + '.')
if found != 4:
    print('::error title=Arkiv Services registration::System Services dump is missing one or more Arkiv actions.')
    raise SystemExit(1)
print('::notice title=Arkiv Services registration::System Services tooling accepted the bundle and lists all four direct Arkiv actions.')
