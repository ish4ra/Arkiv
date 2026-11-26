#!/usr/bin/env python3
"""Publishes signed document-icon theme packs. Maintainer-approved runs only.

Run by the manual `publish` job of .github/workflows/document-icon-themes.yml
(protected `document-icon-themes` environment). It is independent of Sparkle:

* Packs and previews go to the GitHub release `document-icon-themes-v<N>`.
  It is built as a **draft**, which is invisible to the public and never
  "Latest", and is published as a prerelease with --latest=false only once
  every asset has been uploaded and verified. The tag namespace never
  overlaps the app's `dev-<build>` releases, `development-updates`, or the
  `updates` appcast branch, so Sparkle cannot see it.
* The signed catalogue goes to the single-file `document-icon-themes` branch
  (plumbing commit, normal push: a concurrent publication is rejected, and
  history is never rewritten). It is pushed **last**, after every asset the
  catalogue references, in any release, has downloaded back byte-identical
  from its public URL. A failure at any step therefore never exposes an
  incomplete catalogue, and rerunning the job resumes safely:
    - a draft release with missing or wrong assets is completed or repaired;
    - a published release is accepted only if it is already complete and
      identical (published releases are immutable; never rewritten);
    - a catalogue push that failed is simply retried;
    - a draft GitHub has created but does not list yet is looked up again
      with a bounded, doubling wait. It is never created twice in one run,
      two releases with the theme tag stop publication, and if the draft
      never appears the run stops with instructions instead of crashing.
* The catalogue version must increase, and a theme version that was already
  published must keep exactly the same pack and preview.

  python3 scripts/publish-document-icon-themes.py <dist dir> <signed catalog.json>
"""
import base64
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
RELEASE_BASE = f'https://github.com/{REPO}/releases/download/'
RAW = f'https://raw.githubusercontent.com/{REPO}/{BRANCH}/catalog.json'
VERIFY = ['swift', 'scripts/document-icon-theme-catalog.swift', 'verify']
FORBIDDEN_REFS = {'updates', 'development-updates'}
SUPPORTED_SCHEMA = 1
# GitHub can take a moment to list a draft it has just created (run 45578558002,
# attempt 1: the lookup right after `gh release create` returned nothing). The
# lookup is retried with a doubling wait: 2 + 4 + 8 + 16 + 32 s, about a minute.
DISCOVERY_ATTEMPTS = 6
DISCOVERY_WAIT = 2


class PublicationError(SystemExit):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def payload_of(envelope):
    return json.loads(base64.b64decode(json.loads(envelope)['payload']))


def assets_of(payload):
    """(tag, name, size, sha256) for every pack and preview the catalogue references."""
    out = []
    for theme in payload['themes']:
        for asset in (theme['pack'], theme['preview']):
            url = asset['url']
            if not url.startswith(RELEASE_BASE) or url.count('/') != RELEASE_BASE.count('/') + 1:
                raise PublicationError(f'Unexpected asset URL {url}')
            tag, name = url[len(RELEASE_BASE):].split('/')
            if tag.startswith('dev-') or tag in FORBIDDEN_REFS or not tag.startswith(TAG_PREFIX):
                raise PublicationError(f'Asset {name} is not in the theme release namespace')
            out.append((tag, name, asset['size'], asset['sha256']))
    return out


def plan(dist, envelope, published):
    """Pure checks: returns (tag, {name: path} of this release's assets, every referenced asset)."""
    payload = payload_of(envelope)
    if payload.get('schema') != SUPPORTED_SCHEMA:
        raise PublicationError('Unsupported catalogue schema')
    version = payload['catalogVersion']
    tag = f'{TAG_PREFIX}{version}'
    if published is not None:
        old = payload_of(published)
        if version <= old['catalogVersion']:
            raise PublicationError('Refusing: catalogue version is not newer than the published one')
        # Published theme versions are immutable.
        previous = {(t['id'], t['version']): t for t in old['themes']}
        for theme in payload['themes']:
            before = previous.get((theme['id'], theme['version']))
            if before and (before['pack'] != theme['pack'] or before['preview'] != theme['preview']):
                raise PublicationError(f"Theme {theme['id']} v{theme['version']} changed after publication; bump its version")
    referenced = assets_of(payload)
    names = [name for _, name, _, _ in referenced]
    if len(names) != len(set(names)):
        raise PublicationError('Two assets share a name')
    own = {}
    for asset_tag, name, size, digest in referenced:
        if asset_tag == tag:
            data = (dist / name).read_bytes()
            if len(data) != size or sha256(data) != digest:
                raise PublicationError(f'{name} does not match the signed catalogue')
            own[name] = dist / name
        elif published is None or int(asset_tag[len(TAG_PREFIX):]) >= version:
            raise PublicationError(f'{name} refers to release {asset_tag}, which this run cannot have published')
    return tag, own, referenced


class GitHub:
    """The few release operations publication needs, through the gh CLI."""
    def __init__(self, repo=REPO):
        self.repo = repo

    def _api(self, *args, data=None):
        return subprocess.run(['gh', 'api', *args], check=True, capture_output=True, input=data).stdout

    def release(self, tag):
        """{'id', 'draft', 'prerelease', 'assets': {name: {'id', 'size', 'sha256'}}} or None (drafts included).

        Drafts have no tag yet, so GitHub allows several with one tag name.
        Publication never works on an ambiguous release: two matches stop it."""
        page, matches = 1, []
        while True:
            items = json.loads(self._api(f'repos/{self.repo}/releases?per_page=100&page={page}'))
            matches += [release for release in items if release['tag_name'] == tag]
            if len(items) < 100:
                break
            page += 1
        if len(matches) > 1:
            raise PublicationError(f'{len(matches)} releases are named {tag} (ids {sorted(r["id"] for r in matches)}). '
                                   'Delete the extra draft by hand, then rerun; nothing was changed.')
        if not matches:
            return None
        release = matches[0]
        return {'id': release['id'], 'draft': release['draft'], 'prerelease': release['prerelease'],
                'assets': {a['name']: {'id': a['id'], 'size': a['size'],
                                       'sha256': (a.get('digest') or '').removeprefix('sha256:')}
                           for a in release['assets']}}

    def create_draft(self, tag, target, title, notes):
        subprocess.run(['gh', 'release', 'create', tag, '--repo', self.repo, '--draft', '--prerelease',
                        '--target', target, '--title', title, '--notes', notes], check=True)

    def upload(self, tag, path):
        subprocess.run(['gh', 'release', 'upload', tag, str(path), '--repo', self.repo], check=True)  # never overwrites: replacements are deleted first, in our own draft only

    def delete_asset(self, asset_id):
        self._api('-X', 'DELETE', f'repos/{self.repo}/releases/assets/{asset_id}')

    def publish(self, tag):
        subprocess.run(['gh', 'release', 'edit', tag, '--repo', self.repo, '--draft=false', '--prerelease', '--latest=false'], check=True)

    def download(self, url):
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read()


def discover_release(github, tag, attempts=DISCOVERY_ATTEMPTS, wait=DISCOVERY_WAIT):
    """Look the release up until GitHub lists it: bounded, with a doubling wait. None if it never appears."""
    delay = wait
    for attempt in range(1, attempts + 1):
        release = github.release(tag)
        if release is not None:
            if attempt > 1:
                print(f'Release {tag} listed after {attempt} lookups', file=sys.stderr)
            return release
        if attempt < attempts:
            print(f'Release {tag} is not listed by GitHub yet (lookup {attempt}/{attempts}); retrying in {delay} s', file=sys.stderr)
            time.sleep(delay)
            delay *= 2
    return None


def require_release(github, tag, stage, attempts=DISCOVERY_ATTEMPTS, wait=DISCOVERY_WAIT):
    """The release, or a clear stop. Never creates anything, so a rerun cannot duplicate a draft."""
    release = discover_release(github, tag, attempts, wait)
    if release is None:
        total = sum(wait * 2 ** i for i in range(attempts - 1))
        raise PublicationError(f'Release {tag} could not be found {stage} after {attempts} lookups over about {total} s. '
                               'No further draft was created and the catalogue was not published. Rerun the publish job '
                               'once GitHub lists the draft: it resumes the existing draft.')
    return release


def complete_release(github, tag, own, title, notes, target):
    """Create or resume the draft until it holds exactly `own`, verified by digest; then publish it."""
    release = github.release(tag)
    if release is None:
        github.create_draft(tag, target, title, notes)
        # Created exactly once per run; from here the draft is only looked up.
        release = require_release(github, tag, 'after creating its draft')
    if not release['draft']:
        # Published: immutable. Accept only a complete, identical release.
        problems = sorted(set(own) ^ set(release['assets']))
        problems += [n for n, p in own.items() if n in release['assets'] and
                     (release['assets'][n]['size'] != p.stat().st_size or release['assets'][n]['sha256'] != sha256(p.read_bytes()))]
        if problems:
            raise PublicationError(f'Published release {tag} differs from this catalogue ({problems[:5]}); '
                                   'it cannot be changed: publish a new catalogue version instead')
        if not release['prerelease']:
            raise PublicationError(f'Release {tag} is not a prerelease')
        return 'already published'
    for name, asset in release['assets'].items():
        path = own.get(name)
        if path is None or asset['size'] != path.stat().st_size or asset['sha256'] != sha256(path.read_bytes()):
            github.delete_asset(asset['id'])  # interrupted or unexpected upload in our own draft
    present = require_release(github, tag, 'after checking its draft assets')['assets']
    for name, path in sorted(own.items()):
        if name not in present:
            github.upload(tag, path)
    final = require_release(github, tag, 'after uploading its assets')
    for name, path in own.items():
        asset = final['assets'].get(name)
        if not asset or asset['size'] != path.stat().st_size or asset['sha256'] != sha256(path.read_bytes()):
            raise PublicationError(f'{name} did not upload intact; the release stays a draft. Rerun to resume.')
    if set(final['assets']) != set(own):
        raise PublicationError(f'Release {tag} holds unexpected assets; the release stays a draft')
    github.publish(tag)
    return 'published'


def verify_public(github, referenced, attempts=12, wait=5):
    """Every asset the catalogue references must download back byte-identical."""
    for tag, name, size, digest in referenced:
        for attempt in range(attempts):
            try:
                data = github.download(f'{RELEASE_BASE}{tag}/{name}')
                if len(data) == size and sha256(data) == digest:
                    break
            except OSError:
                pass
            time.sleep(wait)
        else:
            raise PublicationError(f'{name} is not publicly available byte-identical; the catalogue was not published')


class CatalogueBranch:
    """Single-file branch, like the `updates` feed branch: plumbing commits, normal push."""
    def __init__(self, cwd='.'):
        self.cwd = cwd

    def git(self, *args, data=None):
        env = dict(os.environ, GIT_AUTHOR_NAME='Arkiv Theme Publisher', GIT_AUTHOR_EMAIL='themes@users.noreply.github.com',
                   GIT_COMMITTER_NAME='Arkiv Theme Publisher', GIT_COMMITTER_EMAIL='themes@users.noreply.github.com')
        return subprocess.check_output(['git', *args], input=data, env=env, cwd=self.cwd)

    def read(self):
        if not self.git('ls-remote', '--heads', 'origin', f'refs/heads/{BRANCH}').strip():
            return None, None
        self.git('fetch', '--no-tags', 'origin', f'refs/heads/{BRANCH}')
        parent = self.git('rev-parse', 'FETCH_HEAD').decode().strip()
        entries = self.git('ls-tree', parent).decode().splitlines()
        if len(entries) != 1 or not entries[0].startswith('100644 blob ') or not entries[0].endswith('\tcatalog.json'):
            raise PublicationError('Refusing unrelated theme branch contents')
        return parent, self.git('show', parent + ':catalog.json')

    def advance(self, envelope, parent):
        blob = self.git('hash-object', '-w', '--stdin', data=envelope).decode().strip()
        tree = self.git('mktree', data=f'100644 blob {blob}\tcatalog.json\n'.encode()).decode().strip()
        commit = self.git('commit-tree', tree, *(['-p', parent] if parent else []),
                          data=b'Publish signed document icon theme catalogue\n').decode().strip()
        self.git('push', 'origin', f'{commit}:refs/heads/{BRANCH}')  # rejected if another run advanced it


def publish(dist, envelope, github, branch, verify_signature, target):
    parent, published = branch.read()
    if published is not None:
        verify_signature(published)
    tag, own, referenced = plan(dist, envelope, published)
    state = complete_release(github, tag, own, f'Arkiv document icon themes {tag[len(TAG_PREFIX):]}',
                             'Optional document icon theme packs. The signed catalogue is on the document-icon-themes branch. '
                             'Not an Arkiv application release; Arkiv updates continue through Sparkle.', target)
    verify_public(github, referenced)
    branch.advance(envelope, parent)
    return tag, state


def main(dist, signed):
    envelope = signed.read_bytes()
    subprocess.run(VERIFY + [str(signed), str(dist / 'catalog-payload.json')], check=True)

    def verify_signature(data):
        old = dist / 'published-catalog.json'
        old.write_bytes(data)
        subprocess.run(VERIFY + [str(old)], check=True)

    tag, state = publish(dist, envelope, GitHub(), CatalogueBranch(), verify_signature, os.environ['GITHUB_SHA'])
    for attempt in range(12):
        try:
            with urllib.request.urlopen(f'{RAW}?v={attempt}', timeout=30) as response:
                if response.read() == envelope:
                    print(f'Published {tag} ({state}) and the signed catalogue')
                    return
        except OSError:
            pass
        time.sleep(5)
    raise PublicationError('Catalogue pushed but not yet served; check the branch before retrying')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
