#!/usr/bin/env python3
"""CI/developer-only PlugInKit discovery check; never enables an extension.

`pluginkit -a` hands the bundle to the pkd daemon, which indexes it
asynchronously, so an immediate `pluginkit -m` can miss a correct
registration. Registration and discovery are therefore retried a bounded
number of times with a short backoff (about 30 s at most). The check itself
is unchanged: it passes only when discovery lists this identifier at this
exact packaged path, and it fails after the last attempt otherwise.
"""
from pathlib import Path
import subprocess
import sys
import time

IDENTIFIER = 'xyz.isharalakshan.arkiv.finder-sync'
PLUGINKIT = '/usr/bin/pluginkit'
# Seconds to wait before each retry; len(BACKOFF) + 1 attempts in total.
BACKOFF = (1, 2, 3, 5, 8, 10)


def run_pluginkit(args):
    try:
        result = subprocess.run([PLUGINKIT, *args], capture_output=True, text=True, timeout=45)
    except subprocess.TimeoutExpired as error:
        return 124, f'timed out after {error.timeout} s\n'
    return result.returncode, result.stdout + result.stderr


def discovered(output, extension):
    return IDENTIFIER in output and str(extension) in output


def attempt(label, args, accept, run, sleep, log):
    """Run one PlugInKit command until `accept(status, output)`; return the attempt count."""
    for number in range(1, len(BACKOFF) + 2):
        status, output = run(args)
        log.append(f'== {label} attempt {number}: exit {status}\n{output}')
        if accept(status, output):
            return number
        if number <= len(BACKOFF):
            sleep(BACKOFF[number - 1])
    return None


def check(extension, run=run_pluginkit, sleep=time.sleep):
    """Return (message, logs) on success; raise SystemExit on failure."""
    logs = {'register': [], 'discover': []}
    if attempt('register', ['-a', str(extension)], lambda status, _: status == 0, run, sleep, logs['register']) is None:
        raise SystemExit('PlugInKit register failed on every attempt; see local diagnostic log', logs)
    tries = attempt('discover', ['-m', '-A', '-D', '-v', '-v', '-i', IDENTIFIER],
                    lambda status, output: status == 0 and discovered(output, extension), run, sleep, logs['discover'])
    if tries is None:
        raise SystemExit('PlugInKit did not discover this packaged Finder extension path', logs)
    suffix = '' if tries == 1 else f' after {tries} attempts'
    return f'PlugInKit discovered the packaged Finder Sync identifier{suffix}. Enablement remains a user action.', logs


def main(argv):
    extension = Path(argv[1]).resolve() / 'Contents/PlugIns/ArkivFinderSync.appex'
    directory = Path('.build/ci-logs')
    directory.mkdir(parents=True, exist_ok=True)

    def write(logs):
        for label, entries in logs.items():
            (directory / f'finder-plugin-{label}.log').write_text('\n'.join(entries))

    try:
        message, logs = check(extension)
    except SystemExit as failure:
        write(failure.args[1])
        raise SystemExit(failure.args[0])
    write(logs)
    print('::notice title=Arkiv Finder registration::' + message)


if __name__ == '__main__':
    main(sys.argv)
