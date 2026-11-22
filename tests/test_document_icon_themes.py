"""Regression tests for the optional document-icon theme pipeline and packs.

Always: configuration, inventory, limits and constants shared with the Swift
code, and publication safety (no overlap with Sparkle's releases or feed).
With ARKIV_THEME_PACKS=<dist> (CI, after build.py): every pack's container,
manifest, checksums and decoded pixels.
"""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
THEMES = ROOT / 'design/document-icon-themes'
CONFIG = json.loads((THEMES / 'themes.json').read_text())
INVENTORY = json.loads((THEMES / 'inventory.json').read_text())
PACKS = os.environ.get('ARKIV_THEME_PACKS')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


icons = load('verify_document_icons', ROOT / 'scripts/verify-document-icons.py')
REPS = [f'icon_{pt}x{pt}{"@2x" if s == 2 else ""}.png' for pt in (16, 32, 128, 256, 512) for s in (1, 2)]
SUPERSEDED = ['folio-tar-three-windows', 'folio-xs-glyph-unit-60', 'folio-dark-zip-pale-tape', 'strata-tar-trefoil-windows',
              'strata-xz-octahedron-v0', 'strata-zst-floating-streaks', 'seal-zip-pale-ladder', 'seal-rar-ring',
              'seal-layout-v0', 'seal-layout-v0.5-large-glyph', 'production-zip-loose-teeth']


def swift_int(source, name):
    match = re.search(rf'static let {name} = (\d+)(?: << (\d+))?', source)
    return int(match.group(1)) << int(match.group(2) or 0)


class ConfigurationTests(unittest.TestCase):
    def test_archives_are_pinned_to_the_preserved_commits(self):
        self.assertEqual(CONFIG['archives']['v1']['commit'], '7e9b736b123274e28a64727d0e6fde22ca11daf7')
        self.assertEqual(CONFIG['archives']['v2']['commit'], '8a1b92ae31f5ba4e649022f0cb38ccd9e24647a6')

    def test_inventory_covers_every_archived_design(self):
        sources = [t['source'] for t in CONFIG['themes']]
        directions = {s['direction'] for s in sources if s['type'] == 'v1-family'}
        self.assertEqual(directions, {'folio', 'folio-dark', 'strata', 'seal', 'seal-dark', 'seal-dark-wine', 'seal-dark-noir', 'current'},
                         'Every v1 family and the pre-redesign icons (ARCHIVE.md rows 1-8)')
        self.assertEqual([s['theme'] for s in sources if s['type'] == 'v2-theme'], ['seal-dark-restored-readability'], 'Row 10')
        self.assertEqual([s['variant'] for s in sources if s['type'] == 'iteration'], SUPERSEDED, 'Rows 11-21')
        self.assertEqual(CONFIG['default']['id'], 'seal-dark', 'Row 9 is the bundled default, not a download')
        ids = [t['id'] for t in CONFIG['themes']]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertNotIn('seal-dark', ids)
        for theme in CONFIG['themes']:
            self.assertRegex(theme['id'], r'^[a-z0-9]+(-[a-z0-9]+)*$')
            self.assertGreaterEqual(theme['version'], 1)
            if theme['kind'] == 'variation':
                self.assertIn(theme['variantOf'], ids + ['seal-dark'])
                self.assertEqual(theme['variantOf'], theme['source']['parent'])

    def test_inventory_lock_matches_configuration_and_limits(self):
        build = load('build_theme_packs', THEMES / 'build.py')
        self.assertEqual([t['id'] for t in INVENTORY['themes']], [t['id'] for t in CONFIG['themes']])
        for theme in INVENTORY['themes']:
            self.assertLessEqual(theme['packBytes'], build.LIMITS['packBytes'], theme['id'])
            self.assertLessEqual(theme['installedBytes'], build.LIMITS['installedBytes'], theme['id'])
            self.assertLessEqual(theme['storedFiles'] + 1, build.LIMITS['files'], theme['id'])
            self.assertRegex(theme['packSHA256'], r'^[0-9a-f]{64}$')
            if theme['id'] == 'classic':
                self.assertEqual(theme['coverage'], '4/11 icons, 0/8 extras')
            else:
                self.assertEqual(theme['coverage'], '11/11 icons, 8/8 extras', theme['id'])
                self.assertEqual(theme['representations'], 190)
        swift = (ROOT / 'Sources/ArkivThemes/ThemeModels.swift').read_text()
        for key, name in [('packBytes', 'packBytes'), ('previewBytes', 'previewBytes'), ('fileBytes', 'fileBytes'), ('files', 'files'),
                          ('manifestBytes', 'manifestBytes'), ('catalogBytes', 'catalogBytes'), ('themes', 'themes'), ('installedBytes', 'installedBytes')]:
            self.assertEqual(swift_int(swift, name), build.LIMITS[key], name)

    def test_rendering_toolchain_is_pinned(self):
        render = (THEMES / 'render.mjs').read_text()
        fetch = (THEMES / 'fetch-headless-shell.sh').read_text()
        self.assertIn("export const BROWSER = 'Google Chrome for Testing 157.0.8103.78';", render)
        self.assertIn("'--font-render-hinting=none', '--disable-lcd-text', '--force-color-profile=srgb'", render)
        self.assertIn('version=157.0.8103.78', fetch)
        self.assertRegex(fetch, r'sha256=[0-9a-f]{64}')
        self.assertIn('sha256sum -c', fetch)

    def test_inventory_page_is_generated_from_the_lock(self):
        build = load('build_theme_packs', THEMES / 'build.py')
        self.assertEqual((ROOT / 'docs/document-icon-theme-inventory.md').read_text(), build.inventory_markdown(INVENTORY))

    def test_signing_context_and_ids_match_the_app(self):
        verifier = (ROOT / 'Sources/ArkivThemes/CatalogVerifier.swift').read_text()
        tool = (ROOT / 'scripts/document-icon-theme-catalog.swift').read_text()
        context = 'Data("Arkiv document icon theme catalogue v1\\n".utf8)'
        self.assertIn(context, verifier)
        self.assertIn(context, tool)
        self.assertIn('public static let bundled = "seal-dark"', verifier)
        self.assertIn('assetPrefix: "https://github.com/ish4ra/Arkiv/releases/download/"', verifier)
        self.assertIn('SPARKLE_PRIVATE_ED_KEY', tool, 'The signing tool refuses Sparkle keys')

    def test_optional_artwork_is_never_bundled(self):
        for script in ['scripts/build-app.sh', 'scripts/package-document-icons.py', 'scripts/verify-app.sh']:
            text = (ROOT / script).read_text()
            self.assertNotIn('document-icon-themes', text, script)
            self.assertNotIn('arkivtheme', text, script)
        bundled = sorted(p.name for p in (ROOT / 'Resources/DocumentIcons').iterdir() if p.is_dir())
        self.assertEqual(len(bundled), 11)

    def test_no_launch_time_theme_work(self):
        main = (ROOT / 'Sources/ArkivApp/main.swift').read_text()
        self.assertNotIn('DocumentIconThemeManager', main)
        self.assertNotIn('refreshCatalog', main)
        settings = (ROOT / 'Sources/ArkivApp/SettingsWindowController.swift').read_text()
        self.assertIn('appearance.view = NSView()', settings, 'The theme pane is a placeholder until the tab is shown')
        self.assertIn('let pane = DocumentIconThemePane(manager: makeThemeManager())', settings)


class PublicationSafetyTests(unittest.TestCase):
    publisher = load('publish_themes', ROOT / 'scripts/publish-document-icon-themes.py')

    def envelope(self, version, themes):
        payload = json.dumps({'schema': 1, 'catalogVersion': version, 'defaultTheme': 'seal-dark', 'themes': themes}).encode()
        return json.dumps({'schema': 1, 'keyID': '0' * 16, 'payload': base64.b64encode(payload).decode(), 'signature': ''}).encode()

    def test_release_namespace_is_independent_of_sparkle(self):
        source = (ROOT / 'scripts/publish-document-icon-themes.py').read_text()
        self.assertIn("'--prerelease', '--latest=false'", source)
        self.assertNotIn('--clobber', source)
        self.assertNotIn('appcast.xml', source)
        self.assertNotIn('update_channel', source)
        self.assertEqual(self.publisher.TAG_PREFIX, 'document-icon-themes-v')
        self.assertEqual(self.publisher.BRANCH, 'document-icon-themes')
        self.assertNotIn(self.publisher.BRANCH, self.publisher.FORBIDDEN_REFS)
        channel = (ROOT / 'scripts/update_channel.py').read_text()
        self.assertIn("releases/download/dev-{version}/Arkiv-universal.zip", channel, 'Sparkle only follows dev-<build> releases')
        self.assertNotIn('document-icon-themes', channel)

    def test_plan_rejects_rollback_and_foreign_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            dist = Path(directory)
            (dist / 'a-1.arkivtheme').write_bytes(b'pack')
            (dist / 'a-1.preview.arkivtheme').write_bytes(b'prev')
            def asset(tag, name, data):
                return {'url': f'https://github.com/ish4ra/Arkiv/releases/download/{tag}/{name}', 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            good = [{'pack': asset('document-icon-themes-v2', 'a-1.arkivtheme', b'pack'), 'preview': asset('document-icon-themes-v2', 'a-1.preview.arkivtheme', b'prev')}]
            tag, assets = self.publisher.plan(dist, self.envelope(2, good), self.envelope(1, []))
            self.assertEqual(tag, 'document-icon-themes-v2')
            self.assertEqual(len(assets), 2)
            with self.assertRaises(SystemExit):
                self.publisher.plan(dist, self.envelope(2, good), self.envelope(2, []))
            for tag in ['dev-30001', 'development-updates', 'updates']:
                bad = [{'pack': asset(tag, 'a-1.arkivtheme', b'pack'), 'preview': good[0]['preview']}]
                with self.assertRaises(SystemExit):
                    self.publisher.plan(dist, self.envelope(3, bad), None)
            tampered = [{'pack': asset('document-icon-themes-v2', 'a-1.arkivtheme', b'other'), 'preview': good[0]['preview']}]
            with self.assertRaises(SystemExit):
                self.publisher.plan(dist, self.envelope(2, tampered), None)


@unittest.skipUnless(PACKS, 'set ARKIV_THEME_PACKS to the output of build.py')
class PackTests(unittest.TestCase):
    def test_every_pack_matches_inventory_and_its_manifest(self):
        dist = Path(PACKS)
        payload_bytes = (dist / 'catalog-payload.json').read_bytes()
        self.assertEqual(hashlib.sha256(payload_bytes).hexdigest(), INVENTORY['catalogPayloadSHA256'])
        payload = json.loads(payload_bytes)
        self.assertEqual([t['id'] for t in payload['themes']], [t['id'] for t in INVENTORY['themes']])
        for theme, locked in zip(payload['themes'], INVENTORY['themes']):
            data = (dist / theme['pack']['url'].rsplit('/', 1)[1]).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), locked['packSHA256'], theme['id'])
            with zipfile.ZipFile(dist / theme['pack']['url'].rsplit('/', 1)[1]) as pack:
                infos = pack.infolist()
                self.assertEqual(infos[0].filename, 'theme.json')
                names = [i.filename for i in infos]
                self.assertEqual(len(names), len(set(n.lower() for n in names)))
                for info in infos:
                    self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertEqual(info.external_attr >> 16, 0o100444)
                    self.assertFalse(info.filename.startswith('/') or '..' in info.filename.split('/'))
                manifest = json.loads(pack.read('theme.json'))
                self.assertEqual((manifest['id'], manifest['version']), (theme['id'], theme['version']))
                self.assertEqual(sorted(manifest['icons']), sorted(theme['coverage']))
                self.assertEqual(sorted(f['path'] for f in manifest['files']) + ['theme.json'], sorted(names))
                files = {f['path']: f for f in manifest['files']}
                for name, reps in {**manifest['icons'], **manifest['extras']}.items():
                    self.assertEqual(sorted(reps), sorted(REPS), name)
                for path, f in files.items():
                    blob = pack.read(path)
                    self.assertEqual(hashlib.sha256(blob).hexdigest(), f['sha256'])
                    self.assertEqual({kind for kind, _ in icons.png_chunks(blob)} - {b'IHDR', b'IDAT', b'IEND'}, set(), path)
                    width, height, rgba = icons.decode_png(blob, path)
                    self.assertEqual((width, height), (f['width'], f['height']))
                    self.assertEqual(icons.pixel_digest(width, height, rgba), f['pixels'], f'{theme["id"]} {path}')
                self.assertEqual(hashlib.sha256(''.join(f'{f["pixels"]}  {f["path"]}\n' for f in manifest['files']).encode()).hexdigest(),
                                 locked['pixels'])
            preview = dist / theme['preview']['url'].rsplit('/', 1)[1]
            self.assertEqual(hashlib.sha256(preview.read_bytes()).hexdigest(), theme['preview']['sha256'])


if __name__ == '__main__':
    unittest.main()
