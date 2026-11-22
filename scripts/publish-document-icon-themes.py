#!/usr/bin/env python3
"""Publishes signed document-icon theme packs. Maintainer-approved runs only.

Run by the manual `publish` job of .github/workflows/document-icon-themes.yml
(protected `document-icon-themes` environment). It is independent of Sparkle:

* Packs and previews go to a new GitHub release `document-icon-themes-v<N>`,
  created as a prerelease that is never marked Latest. The tag namespace never
  overlaps the app's `dev-<build>` releases, `development-updates`, or the
  `updates` appcast branch, so app update selection cannot see it.
* The signed catalogue goes to the single-file `document-icon-themes` branch
  (like the `updates` feed branch: plumbing commits, normal push, no force).
* Nothing is published unless the catalogue signature verifies with the
  dedicated theme key, its version is newer than the published one, and every
  uploaded asset downloads back byte-identical.

  python3 scripts/publish-document-icon-themes.py <dist dir> <signed catalog.json>
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

REPO = 'ish4ra/Arkiv'
BRANCH = 'document-icon-themes'
TAG_PREFIX = 'document-icon-themes-v'
RAW = f'https://raw.githubusercontent.com/{REPO}/{BRANCH}/catalog.json'
VERIFY = ['swift', 'scripts/document-icon-theme-catalog.swift', 'verify']
FORBIDDEN_REFS = {'updates', 'development-updates'}


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def git(*args, data=None):
    env = dict(os.environ, GIT_AUTHOR_NAME='Arkiv Theme Publisher', GIT_AUTHOR_EMAIL='themes@users.noreply.github.com',
               GIT_COMMITTER_NAME='Arkiv Theme Publisher', GIT_COMMITTER_EMAIL='themes@users.noreply.github.com')
    return subprocess.check_output(['git', *args], input=data, env=env)


def payload_of(envelope):
    import base64
    return json.loads(base64.b64decode(json.loads(envelope)['payload']))


def plan(dist, envelope, published):
    """Pure checks, unit-tested: returns (tag, assets)."""
    payload = payload_of(envelope)
    version = payload['catalogVersion']
    if published is not None and version <= payload_of(published)['catalogVersion']:
        raise SystemExit('Refusing: catalogue version is not newer than the published one')
    tag = f'{TAG_PREFIX}{version}'
    assets = []
    for theme in payload['themes']:
        for asset in (theme['pack'], theme['preview']):
            url = asset['url']
            if not url.startswith(f'https://github.com/{REPO}/releases/download/'):
                raise SystemExit(f'Unexpected asset URL {url}')
            asset_tag, name = url.rsplit('/', 2)[-2:]
            if asset_tag.startswith('dev-') or asset_tag in FORBIDDEN_REFS or not asset_tag.startswith(TAG_PREFIX):
                raise SystemExit(f'Asset {name} is not in the theme release namespace')
            path = dist / name
            data = path.read_bytes()
            if len(data) != asset['size'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
                raise SystemExit(f'{name} does not match the signed catalogue')
            if asset_tag == tag:
                assets.append(path)
    return tag, assets


def read_branch():
    if not git('ls-remote', '--heads', 'origin', f'refs/heads/{BRANCH}').strip():
        return None, None
    git('fetch', '--no-tags', 'origin', f'refs/heads/{BRANCH}')
    parent = git('rev-parse', 'FETCH_HEAD').decode().strip()
    entries = git('ls-tree', parent).decode().splitlines()
    if len(entries) != 1 or not entries[0].startswith('100644 blob ') or not entries[0].endswith('\tcatalog.json'):
        raise SystemExit('Refusing unrelated theme branch contents')
    return parent, git('show', parent + ':catalog.json')


def main(dist, signed):
    envelope = signed.read_bytes()
    run(VERIFY + [str(signed), str(dist / 'catalog-payload.json')])
    parent, published = read_branch()
    if published is not None:
        old = dist / 'published-catalog.json'
        old.write_bytes(published)
        run(VERIFY + [str(old)])
    tag, assets = plan(dist, envelope, published)
    exists = subprocess.run(['gh', 'release', 'view', tag, '--repo', REPO], capture_output=True)
    if exists.returncode == 0:
        raise SystemExit(f'Release {tag} already exists; theme releases are immutable')
    run(['gh', 'release', 'create', tag, *map(str, assets), '--repo', REPO, '--target', os.environ['GITHUB_SHA'],
         '--prerelease', '--latest=false', '--title', f'Arkiv document icon themes {tag[len(TAG_PREFIX):]}',
         '--notes', 'Optional document icon theme packs. Signed catalogue on the document-icon-themes branch. '
                    'Not an Arkiv application release; Arkiv updates continue through Sparkle.'])
    for path in assets:
        url = f'https://github.com/{REPO}/releases/download/{tag}/{path.name}'
        for attempt in range(12):
            try:
                with urllib.request.urlopen(url, timeout=60) as response:
                    if hashlib.sha256(response.read()).digest() == hashlib.sha256(path.read_bytes()).digest():
                        break
            except OSError:
                pass
            time.sleep(5)
        else:
            raise SystemExit(f'{path.name} did not download back byte-identical; catalogue not published')
    blob = git('hash-object', '-w', '--stdin', data=envelope).decode().strip()
    tree = git('mktree', data=f'100644 blob {blob}\tcatalog.json\n'.encode()).decode().strip()
    commit = git('commit-tree', tree, *(['-p', parent] if parent else []), data=b'Publish signed document icon theme catalogue\n').decode().strip()
    git('push', 'origin', f'{commit}:refs/heads/{BRANCH}')
    for attempt in range(12):
        try:
            with urllib.request.urlopen(f'{RAW}?v={attempt}', timeout=30) as response:
                if response.read() == envelope:
                    print(f'Published {tag}: {len(assets)} assets and the signed catalogue')
                    return
        except OSError:
            pass
        time.sleep(5)
    raise SystemExit('Catalogue pushed but not yet served; check the branch before retrying')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
