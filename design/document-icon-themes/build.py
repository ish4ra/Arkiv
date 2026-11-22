#!/usr/bin/env python3
"""Builds Arkiv's optional document-icon theme packs from the renders of render.mjs.

Design-time / CI only; nothing here runs in or ships with Arkiv.app.

  python3 design/document-icon-themes/build.py --work <dir> --out <dist>          # build and compare with inventory.json
  python3 design/document-icon-themes/build.py --work <dir> --out <dist> --write  # an approved theme change: rewrite inventory.json

Needs the hash-locked optimizer in design/document-icons/requirements-optimize.txt.

For every representation of every theme it:
  * takes the file the archived generator produced (or, for the shipped
    default and the restored candidate, the preserved PNG itself);
  * decodes it with the repository's standard-library decoder and requires the
    decoded RGBA pixels to equal the archived pixel manifest
    (archive v2 reference/v1-pixels.sha256, a v2 theme's PIXELS.sha256, or
    main's Resources/DocumentIcons/PIXELS.sha256). Artwork the archives
    define but never rendered at every size (superseded variants, unregistered
    artwork) is checked by render.mjs against the archived script output and
    preserved previews; here its unaffected control renders must equal the
    parent's manifest, and its affected icons must differ from the parent;
  * recompresses it with the pinned lossless optimizer used for the bundled
    icons and requires identical decoded pixels;
  * stores byte-identical representations once per pack (the manifest still
    lists all ten representations of every icon).

Packs are ZIP files using the Store method, with fixed timestamps, permissions
and entry order, so the same renders always give the same bytes. The pack's
SHA-256, its size and the preview pack's SHA-256 go into the catalogue payload,
which is signed separately (scripts/document-icon-theme-catalog.swift).
"""
import argparse
import hashlib
import importlib.util
import json
from multiprocessing import Pool
import os
from pathlib import Path
import sys
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CONFIG = json.loads((HERE / 'themes.json').read_text())
REPS = [(pt, scale) for pt in (16, 32, 128, 256, 512) for scale in (1, 2)]
RELEASE_BASE = 'https://github.com/ish4ra/Arkiv/releases/download/'
PACK_SCHEMA = 1
CATALOG_SCHEMA = 1
# Hard limits, mirrored by Sources/ArkivThemes/ThemeLimits.swift and tested.
LIMITS = {'packBytes': 16 << 20, 'installedBytes': 16 << 20, 'previewBytes': 2 << 20, 'fileBytes': 2 << 20, 'files': 256,
          'manifestBytes': 256 << 10, 'catalogBytes': 1 << 20, 'themes': 128}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


icons = load('verify_document_icons', REPO / 'scripts/verify-document-icons.py')
optimizer = load('optimize_document_icons', REPO / 'design/document-icons/optimize.py')


def rep_name(pt, scale):
    return f'icon_{pt}x{pt}{"@2x" if scale == 2 else ""}.png'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def manifest(path):
    return icons.read_manifest(path)


class Source:
    """One representation: the file to pack and how its pixels are authorised."""
    def __init__(self, path, authority, digest=None):
        self.path, self.authority, self.digest = Path(path), authority, digest


def v1_file(work, direction, name, pt, scale):
    art = CONFIG['artwork'][name]
    vid = art['format'] + ('-alias' if art.get('alias') else '')
    rel = f'png/{direction}/{vid}/{vid}-{pt}{"pt@2x" if scale == 2 else ""}.png'
    return work / 'v1' / rel, rel


def build_sources(work):
    v1_pixels = manifest(work / 'archives' / CONFIG['archives']['v2']['path'] / 'reference/v1-pixels.sha256')
    v2 = work / 'archives' / CONFIG['archives']['v2']['path']
    restored = v2 / 'themes/seal-dark-restored-readability'
    restored_pixels, restored_sums = manifest(restored / 'PIXELS.sha256'), manifest(restored / 'SHA256SUMS')
    main_root = REPO / 'Resources/DocumentIcons'
    main_pixels, main_sums = manifest(main_root / 'PIXELS.sha256'), manifest(main_root / 'SHA256SUMS')
    report = json.loads((work / 'render-report.json').read_text())

    def v1_family(direction, names):
        out = {}
        for name in names:
            for pt, scale in REPS:
                path, rel = v1_file(work, direction, name, pt, scale)
                out[(name, rep_name(pt, scale))] = Source(path, f'archive v1 render {rel} = reference/v1-pixels.sha256', v1_pixels[rel])
        return out

    def extras(theme):
        return {(name, rep_name(pt, scale)): Source(work / 'extras' / theme / name / rep_name(pt, scale),
                f'v2 themes/{theme}/seal-dark.mjs render (512 px byte-identical to the preserved preview)')
                for name in CONFIG['extras'] for pt, scale in REPS}

    def iconset(root, pixels, sums, label):
        out = {}
        for name in CONFIG['icons']:
            for pt, scale in REPS:
                rel = f'Arkiv-{name}.iconset/{rep_name(pt, scale)}'
                path = root / rel
                assert sha256(path.read_bytes()) == sums[rel], f'{label}: {rel} differs from SHA256SUMS'
                out[(name, rep_name(pt, scale))] = Source(path, f'{label} {rel} = PIXELS.sha256', pixels[rel])
        return out

    sources = {'seal-dark': {**iconset(main_root, main_pixels, main_sums, 'main Resources/DocumentIcons'),
                             **extras('seal-dark-refined-26501')}}
    checks = []
    for theme in CONFIG['themes']:
        src = theme['source']
        if src['type'] == 'v1-family':
            names = src.get('icons') or CONFIG['icons'] + CONFIG['extras']
            sources[theme['id']] = v1_family(src['direction'], names)
        elif src['type'] == 'v2-theme':
            assert src['theme'] == 'seal-dark-restored-readability'
            sources[theme['id']] = {**iconset(restored / 'iconsets', restored_pixels, restored_sums,
                                              'archive v2 themes/seal-dark-restored-readability/iconsets'),
                                    **extras('seal-dark-restored-readability')}
    for theme in CONFIG['themes']:
        src = theme['source']
        if src['type'] != 'iteration':
            continue
        rendered = report['variants'][src['variant']]
        parent = sources[src['parent']]
        combined = dict(parent)
        for name in rendered['names']:
            for rep in rendered['reps']:
                combined[(name, rep)] = Source(work / 'variants' / src['variant'] / name / rep,
                    f'archive v2 iterations/render-iterations.mjs `{src["variant"]}` substitutions, '
                    f'{rendered["pipeline"]} pipeline (byte-identical to the archived script at its sizes)')
        control = rendered['control']
        for pt, scale in REPS:
            rep = rep_name(pt, scale)
            base = work / 'variants' / src['variant']
            checks.append(('control', theme['id'], base / '_control' / control / rep, parent[(control, rep)]))
            checks.append(('shared', theme['id'], base / '_patched-control' / control / rep, parent[(control, rep)]))
        checks.append(('differs', theme['id'], {name: [(combined[(name, r)], parent[(name, r)]) for r in rendered['reps']]
                                                for name in rendered['names']}))
        sources[theme['id']] = combined
    return sources, checks


def decode_digest(path):
    width, height, rgba = icons.read_png(path)
    return width, height, icons.pixel_digest(width, height, rgba)


def optimize_one(data):
    ox = optimizer.oxipng_module()
    output = optimizer.optimize_bytes(data, ox)
    width, height, rgba = icons.decode_png(output)
    return sha256(data), output, icons.pixel_digest(width, height, rgba)


def zip_bytes(entries):
    """Deterministic Store-method ZIP: fixed time, mode 0444, given order."""
    import io
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_STORED) as archive:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type, info.create_system = zipfile.ZIP_STORED, 3
            info.external_attr = 0o100444 << 16
            archive.writestr(info, data)
    return buffer.getvalue()


def mb(n):
    return f'{n / 1e6:.2f} MB'


def inventory_markdown(inventory):
    """docs/document-icon-theme-inventory.md, generated from inventory.json only."""
    names = {t['id']: t['name'] for t in inventory['themes']}
    names['seal-dark'] = inventory['default']['name']
    lines = ['# Document icon theme inventory', '',
             '<!-- Generated by `python3 design/document-icon-themes/build.py --markdown` from inventory.json. Do not edit. -->', '',
             'Every optional theme Arkiv can download, built only from the preserved archives at',
             f"`{inventory['archives']['v1']['commit'][:7]}` (v1) and `{inventory['archives']['v2']['commit'][:7]}` (v2).",
             f"The bundled default, **{inventory['default']['name']}** ({inventory['default']['family']}), is not a download: it ships in Arkiv.app.", '',
             'Sizes are bytes as published. *Raw* is the archived renders before lossless optimisation;',
             '*installed* is what the theme occupies on disk; every pack also has a small preview pack (11 × 128 px).', '',
             '| Theme | Family | Kind | Source | Coverage | Raw | Download | Installed | Preview |',
             '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |']
    for t in inventory['themes']:
        src = t['source']
        if src['type'] == 'v1-family':
            source = f"v1 `{src['file']}` (`{src['direction']}`)"
        elif src['type'] == 'v2-theme':
            source = f"v2 `themes/{src['theme']}/`"
        else:
            source = f"v2 `iterations/` `{src['variant']}` on {names.get(src['parent'], src['parent'])}"
        kind = t['kind'] + (f" of {names.get(t['variantOf'], t['variantOf'])}" if t.get('variantOf') else '')
        coverage = t['coverage']
        if 'variation' in t:
            coverage += '; changes ' + ', '.join(t['variation']['changes'])
        lines.append(f"| {t['name']} (`{t['id']}` v{t['version']}) | {t['familyName']} | {kind} | {source} | {coverage} | "
                     f"{mb(t['rawBytes'])} | {mb(t['packBytes'])} | {mb(t['installedBytes'])} | {t['previewBytes'] / 1e3:.0f} kB |")
    total = sum(t['packBytes'] for t in inventory['themes'])
    lines += ['', f"**{len(inventory['themes'])} packs, {mb(total)} in total.** "
              'A user downloads only the themes they choose.', '',
              'Notes:',
              '* Every pack has all ten macOS representations of each covered icon (190 for full themes). Byte-identical',
              '  representations (128 pt @2x = 256 pt, 256 pt @2x = 512 pt) are stored once and mapped by the manifest.',
              '* *Extras* are the unregistered artwork kept for a future Quick Look thumbnail provider: TAR.GZ, TAR.BZ2,',
              '  TAR.XZ, TAR.ZST, TZST, the 7z volume and the future RAR and ZIP volume concepts. Arkiv does not use them today.',
              '* Variations use their parent family for every format the archive does not record for them. *Changes* lists',
              '  the formats whose pixels actually differ from the parent.',
              '* Classic is the pre-redesign icons, preserved only as v1 `directions/current.mjs` (a comparison reproduction).',
              '  They existed for ZIP, 7z, TAR and RAR; other formats keep the system\'s generic icon, as they did then.',
              '']
    return '\n'.join(lines)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--work', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--markdown', action='store_true', help='regenerate docs/document-icon-theme-inventory.md from inventory.json')
    parser.add_argument('--release-tag', default='document-icon-themes-v1')
    parser.add_argument('--catalog-version', type=int, default=1)
    parser.add_argument('--write', action='store_true', help='rewrite inventory.json (approved theme change)')
    parser.add_argument('--jobs', type=int, default=os.cpu_count() or 2)
    parser.add_argument('--cache', type=Path, help='reuse optimizer output between local builds (never used in CI)')
    args = parser.parse_args(argv)
    if args.markdown:
        (REPO / 'docs/document-icon-theme-inventory.md').write_text(inventory_markdown(json.loads((HERE / 'inventory.json').read_text())))
        return
    optimizer.oxipng_module()  # fail early on a wrong optimizer version
    work, out = args.work.resolve(), args.out.resolve()
    sources, checks = build_sources(work)

    every = {s.path for theme in sources.values() for s in theme.values()}
    every |= {c[2] for c in checks if c[0] in ('control', 'shared')}
    with Pool(args.jobs) as pool:
        decoded = dict(zip(sorted(every), pool.map(decode_digest, sorted(every), chunksize=4)))
    failures = []
    for theme_id, theme in sources.items():
        for (name, rep), src in theme.items():
            width, height, digest = decoded[src.path]
            pt = int(rep.split('_')[1].split('x')[0]); px = pt * (2 if '@2x' in rep else 1)
            if (width, height) != (px, px):
                failures.append(f'{theme_id} {name}/{rep}: {width}x{height}, expected {px}x{px}')
            if src.digest is not None and digest != src.digest:
                failures.append(f'{theme_id} {name}/{rep}: pixels differ from {src.authority}')
    changed, shared = {}, {}
    for check in checks:
        if check[0] == 'control':
            _, theme_id, path, parent = check
            if decoded[path][2] != decoded[parent.path][2]:
                failures.append(f'{theme_id}: unpatched control render {path.name} differs from the parent\'s archived pixels')
        elif check[0] == 'shared':
            _, theme_id, path, parent = check
            if decoded[path][2] != decoded[parent.path][2]:
                shared[theme_id] = True
        else:
            _, theme_id, by_name = check
            changed[theme_id] = [name for name, pairs in by_name.items()
                                 if any(decoded[a.path][2] != decoded[b.path][2] for a, b in pairs)]
            if not changed[theme_id]:
                failures.append(f'{theme_id}: the variant changed nothing relative to its parent')
    if failures:
        raise SystemExit('Provenance check failed:\n  ' + '\n  '.join(failures[:40]))
    verified = sum(len(t) for t in sources.values())
    print(f'Verified {verified} representations across {len(sources)} themes against archived pixel manifests')

    raw = {}
    for path in sorted(every):
        raw.setdefault(sha256(path.read_bytes()), path)
    # Optional cache of optimizer output, keyed by input SHA-256. Every cached
    # result is decoded again and must match the input's pixels.
    cache = args.cache.resolve() if args.cache else None
    optimized, todo = {}, []
    for key in sorted(raw):
        hit = cache / f'{key}.png' if cache else None
        if hit and hit.exists():
            data = hit.read_bytes()
            width, height, rgba = icons.decode_png(data)
            if icons.pixel_digest(width, height, rgba) == decoded[raw[key]][2]:
                optimized[key] = (data, decoded[raw[key]][2]); continue
        todo.append(key)
    with Pool(args.jobs) as pool:
        results = pool.map(optimize_one, [raw[k].read_bytes() for k in todo], chunksize=1)
    for key, data, digest in results:
        optimized[key] = (data, digest)
        if cache:
            cache.mkdir(parents=True, exist_ok=True)
            (cache / f'{key}.png').write_bytes(data)

    out.mkdir(parents=True, exist_ok=True)
    inventory = {'schema': 1, 'releaseTag': args.release_tag, 'catalogVersion': args.catalog_version,
                 'archives': CONFIG['archives'], 'default': CONFIG['default'], 'themes': []}
    catalog_themes = []
    for theme in CONFIG['themes']:
        theme_sources = sources[theme['id']]
        names = sorted({name for name, _ in theme_sources}, key=lambda n: (CONFIG['icons'] + CONFIG['extras']).index(n))
        stored, files, mapping, raw_bytes = {}, [], {'icons': {}, 'extras': {}}, 0
        for name in names:
            group = 'icons' if name in CONFIG['icons'] else 'extras'
            folder = ('' if group == 'icons' else 'extras/') + f'Arkiv-{name}.iconset/'
            mapping[group][name] = {}
            for pt, scale in REPS:
                rep = rep_name(pt, scale)
                src = theme_sources[(name, rep)]
                data = src.path.read_bytes()
                raw_bytes += len(data)
                packed, digest = optimized[sha256(data)]
                assert digest == decoded[src.path][2], f'{theme["id"]} {name}/{rep}: optimizer changed pixels'
                key = sha256(packed)
                if key not in stored:
                    stored[key] = folder + rep
                    files.append({'path': folder + rep, 'size': len(packed), 'sha256': key, 'width': pt * scale,
                                  'height': pt * scale, 'pixels': digest, 'data': packed})
                mapping[group][name][rep] = stored[key]
        pack_manifest = {'schema': PACK_SCHEMA, 'id': theme['id'], 'version': theme['version'], 'name': theme['name'],
                         'icons': mapping['icons'], 'extras': mapping['extras'],
                         'files': [{k: f[k] for k in ('path', 'size', 'sha256', 'width', 'height', 'pixels')} for f in files],
                         'licence': CONFIG['licence']}
        manifest_bytes = (json.dumps(pack_manifest, indent=1, sort_keys=True, ensure_ascii=False) + '\n').encode()
        pack = zip_bytes([('theme.json', manifest_bytes)] + [(f['path'], f['data']) for f in files])
        previews = [(f'Arkiv-{name}.png', theme_sources[(name, 'icon_128x128.png')]) for name in CONFIG['icons'] if name in mapping['icons']]
        preview_entries = [(n, optimized[sha256(s.path.read_bytes())][0]) for n, s in previews]
        preview = zip_bytes(preview_entries)
        installed = len(manifest_bytes) + sum(f['size'] for f in files)
        assert len(pack) <= LIMITS['packBytes'] and len(preview) <= LIMITS['previewBytes'], theme['id']
        assert installed <= LIMITS['installedBytes'], theme['id']
        assert len(files) + 1 <= LIMITS['files'] and len(manifest_bytes) <= LIMITS['manifestBytes'], theme['id']
        assert all(f['size'] <= LIMITS['fileBytes'] for f in files), theme['id']
        pack_name, preview_name = f'{theme["id"]}-{theme["version"]}.arkivtheme', f'{theme["id"]}-{theme["version"]}.preview.arkivtheme'
        (out / pack_name).write_bytes(pack)
        (out / preview_name).write_bytes(preview)
        url = RELEASE_BASE + args.release_tag + '/'
        provenance = theme['source'] | {'archive': CONFIG['archives']['v1' if theme['source']['type'] == 'v1-family' else 'v2']['branch']}
        if theme['source']['type'] == 'iteration':
            provenance['archives'] = [CONFIG['archives']['v2']['commit']] + ([] if theme['source']['parent'] == 'seal-dark' else [CONFIG['archives']['v1']['commit']])
        else:
            provenance['commit'] = CONFIG['archives']['v1' if theme['source']['type'] == 'v1-family' else 'v2']['commit']
        entry = {
            'id': theme['id'], 'version': theme['version'], 'name': theme['name'], 'family': theme['family'],
            'familyName': theme['familyName'], 'kind': theme['kind'], 'summary': theme['summary'],
            'variantOf': theme.get('variantOf'), 'coverage': list(mapping['icons']), 'extras': list(mapping['extras']),
            'minimumAppBuild': 0, 'licence': CONFIG['licence'], 'provenance': provenance,
            'pack': {'url': url + pack_name, 'size': len(pack), 'sha256': sha256(pack), 'installedSize': installed, 'files': len(files) + 1},
            'preview': {'url': url + preview_name, 'size': len(preview), 'sha256': sha256(preview),
                        'files': [{'name': n, 'size': len(d), 'sha256': sha256(d), 'width': 128, 'height': 128} for n, d in preview_entries]},
        }
        catalog_themes.append(entry)
        inventory['themes'].append({
            'id': theme['id'], 'version': theme['version'], 'name': theme['name'], 'familyName': theme['familyName'],
            'kind': theme['kind'], 'variantOf': theme.get('variantOf'), 'source': provenance,
            'coverage': f'{len(mapping["icons"])}/{len(CONFIG["icons"])} icons, {len(mapping["extras"])}/{len(CONFIG["extras"])} extras',
            'representations': sum(len(v) for g in mapping.values() for v in g.values()), 'storedFiles': len(files),
            'rawBytes': raw_bytes, 'packBytes': len(pack), 'installedBytes': installed,
            'packSHA256': sha256(pack), 'previewBytes': len(preview), 'previewSHA256': sha256(preview),
            'pixels': sha256(''.join(f'{f["pixels"]}  {f["path"]}\n' for f in files).encode()),
        })
        if theme['id'] in changed:
            inventory['themes'][-1]['variation'] = {
                'changes': changed[theme['id']],
                'sourceAlsoChangesUnrecordedFormats': shared.get(theme['id'], False)}
            entry['variation'] = {'changes': changed[theme['id']]}
    payload = {'schema': CATALOG_SCHEMA, 'catalogVersion': args.catalog_version, 'defaultTheme': CONFIG['default']['id'],
               'limits': LIMITS, 'themes': catalog_themes}
    payload_bytes = (json.dumps(payload, indent=1, sort_keys=True, ensure_ascii=False) + '\n').encode()
    assert len(payload_bytes) <= LIMITS['catalogBytes'] and len(catalog_themes) <= LIMITS['themes']
    (out / 'catalog-payload.json').write_bytes(payload_bytes)
    inventory['catalogPayloadSHA256'] = sha256(payload_bytes)
    text = json.dumps(inventory, indent=1, sort_keys=True, ensure_ascii=False) + '\n'
    lock = HERE / 'inventory.json'
    (out / 'inventory.json').write_text(text)
    if args.write:
        lock.write_text(text)
        (REPO / 'docs/document-icon-theme-inventory.md').write_text(inventory_markdown(inventory))
        print(f'Wrote {lock.relative_to(REPO)} and docs/document-icon-theme-inventory.md')
    elif not lock.exists() or lock.read_text() != text:
        raise SystemExit('Built packs differ from design/document-icon-themes/inventory.json; '
                         'the build is not reproducible or the themes changed (re-run with --write for an approved change)')
    total = sum(t['packBytes'] for t in inventory['themes'])
    print(f'Built {len(catalog_themes)} theme packs ({total:,} bytes) into {out}; '
          f'catalogue payload {len(payload_bytes):,} bytes, sha256 {inventory["catalogPayloadSHA256"]}')


if __name__ == '__main__':
    main(sys.argv[1:])
