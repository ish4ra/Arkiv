#!/usr/bin/env python3
"""Informational size report for the bundled document icons (macOS CI).

Compares the committed iconsets and the packaged app with a baseline
Resources/DocumentIcons tree (normally main's) in the same run, so runner and
toolchain differences cancel out. The baseline app is a scratch copy of the
built app with only the 11 document ICNS files replaced by iconutil output
from the baseline iconsets; everything else is byte-identical. That copy is
measured, zipped and imaged exactly like the shipped artifacts, then deleted.
It is never signed, verified or shipped. Nothing here changes build outputs.

  measure-document-icons.py --baseline DIR --app build/Arkiv.app --zip build/Arkiv-arm64.zip
"""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location('icons', ROOT / 'scripts/verify-document-icons.py')
icons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(icons)


def png_total(root):
    return sum((Path(root) / f'Arkiv-{name}.iconset' / icons.rep_name(pt, s)).stat().st_size
               for name in icons.ICONS for pt, s in icons.REPRESENTATIONS)


def tree_bytes(path):
    """Apparent size: regular file bytes plus symlink lengths, without following links."""
    total = 0
    for directory, _, files in os.walk(path):
        for name in files:
            total += os.lstat(os.path.join(directory, name)).st_size
    return total


def allocated_bytes(path):
    return int(subprocess.check_output(['du', '-sk', str(path)], text=True).split()[0]) * 1024


def build_icns(iconsets, output):
    output.mkdir(parents=True, exist_ok=True)
    for name in icons.ICONS:
        subprocess.run(['iconutil', '-c', 'icns', str(Path(iconsets) / f'Arkiv-{name}.iconset'),
                        '-o', str(output / f'Arkiv-{name}.icns')], check=True)
    return {name: (output / f'Arkiv-{name}.icns').stat().st_size for name in icons.ICONS}


def make_zip(app, output):
    # Same command as the workflow's update archive (Sparkle payload).
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(output)], check=True)
    return output.stat().st_size


def make_dmg(app, work):
    # Same steps as scripts/build-dmg.sh (UDRW, then UDZO).
    source = work / 'source'
    source.mkdir()
    subprocess.run(['ditto', str(app), str(source / 'Arkiv.app')], check=True)
    (source / 'Applications').symlink_to('/Applications')
    raw, image = work / 'raw.dmg', work / 'Arkiv.dmg'
    subprocess.run(['hdiutil', 'create', '-quiet', '-volname', 'Arkiv', '-srcfolder', str(source),
                    '-fs', 'HFS+', '-format', 'UDRW', str(raw)], check=True)
    subprocess.run(['hdiutil', 'convert', '-quiet', str(raw), '-format', 'UDZO', '-o', str(image)], check=True)
    return image.stat().st_size


def dmg_or_none(app, work):
    try:
        return make_dmg(app, work)
    except (subprocess.CalledProcessError, OSError) as error:
        print(f'::warning title=Arkiv size report::DMG measurement unavailable ({error})')
        return None


def mb(value):
    return '—' if value is None else f'{value / 1e6:.2f} MB'


def delta(before, after):
    if before is None or after is None:
        return '—'
    change = after - before
    percent = f' ({change / before * 100:+.1f}%)' if before else ''
    return f'{change / 1e6:+.2f} MB{percent}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path, required=True, help='baseline Resources/DocumentIcons tree')
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--zip', type=Path, required=True, help='the update archive built from --app')
    parser.add_argument('--label', default='main')
    args = parser.parse_args()
    app = args.app.resolve()
    resources = app / 'Contents/Resources'
    after_icns = {name: (resources / f'Arkiv-{name}.icns').stat().st_size for name in icons.ICONS}
    rows = []
    (ROOT / 'build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='arkiv-size-report-', dir=ROOT / 'build') as tmp:
        work = Path(tmp)
        before_icns = build_icns(args.baseline, work / 'icns')
        baseline_app = work / 'baseline' / 'Arkiv.app'
        subprocess.run(['ditto', str(app), str(baseline_app)], check=True)
        for name in icons.ICONS:
            shutil.copyfile(work / 'icns' / f'Arkiv-{name}.icns', baseline_app / f'Contents/Resources/Arkiv-{name}.icns')
        rows.append(('Document icon PNGs (110)', png_total(args.baseline), png_total(icons.SOURCES)))
        rows.append(('Document icon ICNS (11)', sum(before_icns.values()), sum(after_icns.values())))
        rows.append(('App bundle (apparent)', tree_bytes(baseline_app), tree_bytes(app)))
        rows.append(('App bundle (allocated, du)', allocated_bytes(baseline_app), allocated_bytes(app)))
        rows.append(('Update archive ZIP (ditto)', make_zip(baseline_app, work / 'baseline.zip'), args.zip.stat().st_size))
        (work / 'dmg-before').mkdir()
        (work / 'dmg-after').mkdir()
        rows.append(('DMG (UDZO)', dmg_or_none(baseline_app, work / 'dmg-before'), dmg_or_none(app, work / 'dmg-after')))
    lines = [f'### Document icon size report ({args.label} → this build)', '',
             f'| Measure | {args.label} | This build | Change |', '| --- | ---: | ---: | ---: |']
    lines += [f'| {label} | {mb(before)} | {mb(after)} | {delta(before, after)} |' for label, before, after in rows]
    lines += ['', '| ICNS | ' + args.label + ' bytes | This build bytes |', '| --- | ---: | ---: |']
    lines += [f'| Arkiv-{name}.icns | {before_icns[name]:,} | {after_icns[name]:,} |' for name in icons.ICONS]
    lines += ['', 'Exact byte counts: ' + '; '.join(f'{label}: {before if before is not None else "—"} → {after if after is not None else "—"}'
                                                    for label, before, after in rows)]
    report = '\n'.join(lines) + '\n'
    print(report)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as handle:
            handle.write(report)


if __name__ == '__main__':
    main()
