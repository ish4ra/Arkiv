#!/usr/bin/env python3
"""CI/developer-only PlugInKit discovery check; never enables an extension."""
from pathlib import Path
import subprocess
import sys

extension = Path(sys.argv[1]).resolve() / 'Contents/PlugIns/ArkivFinderSync.appex'
identifier = 'xyz.isharalakshan.arkiv.finder-sync'
logs = Path('.build/ci-logs')
logs.mkdir(parents=True, exist_ok=True)
for label, args in [('register', ['-a', str(extension)]),
                    ('discover', ['-m', '-A', '-D', '-i', identifier])]:
    result = subprocess.run(['/usr/bin/pluginkit', *args], capture_output=True,
                            text=True, timeout=45)
    output = result.stdout + result.stderr
    (logs / ('finder-plugin-' + label + '.log')).write_text(output)
    if result.returncode:
        raise SystemExit('PlugInKit ' + label + ' failed; see local diagnostic log')
    if label == 'discover' and identifier not in output:
        raise SystemExit('PlugInKit did not discover the packaged Finder extension')
print('::notice title=Arkiv Finder registration::PlugInKit discovered the packaged Finder Sync identifier. Enablement remains a user action.')
