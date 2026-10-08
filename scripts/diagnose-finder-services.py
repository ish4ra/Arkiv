#!/usr/bin/env python3
"""Development/CI-only bundle parseability check using macOS Services tooling.

Never called by Arkiv. A CI build directory is not an installed application, so
reading the global Services cache is informational, not a Finder discovery test.
Raw system output stays in local logs; only fixed diagnostics are printed.
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


def run(label, args, required=True):
    try:
        result = subprocess.run([str(pbs), *args], capture_output=True, text=True, errors='replace', timeout=45)
    except subprocess.TimeoutExpired:
        if required:
            raise SystemExit('System Services bundle parsing timed out.')
        print('::notice title=Arkiv Services cache::Global cache diagnostic timed out; bundle parsing is checked separately.')
        return ''
    output = result.stdout + result.stderr
    (logs / ('services-' + label + '.log')).write_text(output)
    print('pbs ' + label + ' exit code: ' + str(result.returncode))
    if result.returncode:
        if required:
            raise SystemExit('System Services bundle parsing failed.')
        print('::notice title=Arkiv Services cache::Global cache diagnostic unavailable; bundle parsing is checked separately.')
        return ''
    return output.replace('\\U2026', '…').replace('\\u2026', '…')


# -read_bundle is the explicit bundle parser. It reports Services even when the
# bundle is outside Applications and absent from the current user's global cache.
parsed = run('read-bundle', ['-read_bundle', str(app)])
titles = [s['NSMenuItem']['default'] for s in info['NSServices']]
found = sum(title in parsed for title in titles)
if len(titles) != 4 or found != 4:
    print('::error title=Arkiv Services registration::System bundle parser did not report all four direct Arkiv service titles.')
    raise SystemExit(1)
print('::notice title=Arkiv Services registration::pbs read_bundle parsed all four direct Arkiv actions from the built app.')

# Do not register or launch an app, reset caches, or equate this dump with Finder
# visibility. That requires a real installation and an interactive user session.
dump = run('dump', ['-dump'], required=False)
count = sum(title in dump for title in titles)
print('::notice title=Arkiv Services cache::Informational global cache snapshot: ' + str(count) + '/4 titles. This is not the bundle parseability result.')
