// Renders every optional document-icon theme from the preserved archives.
//
//   node design/document-icon-themes/render.mjs --work <scratch dir>
//
// Design-time / CI only. Uses the pinned Playwright 1.63.0 (its Chrome Headless Shell) and
// opentype.js 1.3.4 from design/document-icons/package-lock.json; run
// `npm ci` there first. Nothing here is built into or required by Arkiv.app.
//
// Steps, all from the archive commits pinned in themes.json (never a branch tip):
//   1. Extract both archives with `git archive` into <work>/archives.
//   2. Run the archived generators unmodified:
//        v1 render.mjs                       -> <work>/v1        (every v1 family, 1,824 PNGs)
//        v2 iterations/render-iterations.mjs -> <work>/iterations (superseded variants, previews)
//        v2 reproduce.mjs seal-dark-restored-readability (175 files must not differ)
//   3. Render what the archives define but never rendered at every macOS
//      representation:
//        * each superseded variant's formats, with its exact archived source
//          substitutions, through its parent family's own pipeline
//          (v1: vendored fonts bound to the SVG text; production: outlined labels);
//        * the unregistered artwork (TAR.* labels, TZST, volumes) of the two
//          v2 Seal Dark themes, through the production pipeline.
//   4. Self-checks that need a browser:
//        * every variant re-rendered with outlined labels at the archived
//          script's sizes is byte-identical to render-iterations.mjs output, so
//          the substitutions applied here are exactly the archived ones;
//        * the extras' 512 px renders are byte-identical to the preserved
//          512 px previews.
// build.py then verifies every pixel against the archived manifests,
// optimizes losslessly, and writes packs and the catalogue.
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const config = JSON.parse(fs.readFileSync(path.join(here, 'themes.json'), 'utf8'));
const arg = (n) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : null; };
const work = path.resolve(arg('work') ?? fail('Usage: node render.mjs --work <scratch dir>'));
function fail(message) { console.error(message); process.exit(2); }
const run = (cmd, args, opts = {}) => {
  const r = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  if (r.status !== 0) fail(`${cmd} ${args.join(' ')} failed (${r.status})`);
};
const sha = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const REPS = [16, 32, 128, 256, 512].flatMap((pt) => [[pt, 1], [pt, 2]]);
const repName = (pt, scale) => `icon_${pt}x${pt}${scale === 2 ? '@2x' : ''}.png`;

// 1. Archives at their pinned commits.
const nodeModules = path.join(repo, 'design/document-icons/node_modules');
if (!fs.existsSync(path.join(nodeModules, 'playwright'))) fail('Run `npm ci` in design/document-icons first.');
fs.rmSync(work, { recursive: true, force: true });
const archives = path.join(work, 'archives');
fs.mkdirSync(archives, { recursive: true });
for (const [key, a] of Object.entries(config.archives)) {
  const ok = spawnSync('git', ['-C', repo, 'cat-file', '-e', `${a.commit}^{commit}`]);
  if (ok.status !== 0) fail(`Archive ${key} commit ${a.commit} is missing: git fetch origin ${a.commit}`);
  const paths = key === 'v1' ? [a.path, 'branding/Arkiv-Mark-Transparent-512.png'] : [a.path];
  const tar = spawnSync('git', ['-C', repo, 'archive', a.commit, ...paths], { maxBuffer: 1 << 30 });
  if (tar.status !== 0) fail(`git archive ${a.commit} failed`);
  run('tar', ['-x', '-C', archives], { input: tar.stdout, stdio: ['pipe', 'inherit', 'inherit'] });
}
const V1 = path.join(archives, config.archives.v1.path);
const V2 = path.join(archives, config.archives.v2.path);
// The archived toolchains pin the same Playwright as design/document-icons.
const lockVersion = (file, name) => JSON.parse(fs.readFileSync(file, 'utf8')).packages[`node_modules/${name}`];
for (const lock of [path.join(V1, 'package-lock.json'), path.join(V2, 'tooling/package-lock.json')]) {
  for (const name of ['playwright', 'playwright-core', ...(lock.includes('tooling') ? ['opentype.js'] : [])]) {
    const want = lockVersion(lock, name), have = lockVersion(path.join(repo, 'design/document-icons/package-lock.json'), name);
    if (!want || want.integrity !== have?.integrity) fail(`${lock}: ${name} differs from design/document-icons/package-lock.json`);
  }
}
fs.symlinkSync(nodeModules, path.join(V1, 'node_modules'));
fs.symlinkSync(nodeModules, path.join(V2, 'tooling/node_modules'));

// The exact rendering toolchain. The archived references were rendered by
// Chrome for Testing 157.0.8103.78's headless shell launched with these
// switches. Without the switches, labels drawn from fonts (archive v1)
// rasterize differently; with Playwright 1.63.0's own 153.0.8010.12, 18
// Strata 512 px renders differ. So the version is checked, and every
// browser below, including those the unmodified archived scripts start, is
// launched through a wrapper that adds the switches, found through
// PLAYWRIGHT_BROWSERS_PATH. fetch-headless-shell.sh installs the pinned build.
export const SWITCHES = ['--font-render-hinting=none', '--disable-lcd-text', '--force-color-profile=srgb'];
export const BROWSER = 'Google Chrome for Testing 157.0.8103.78';
const registry = process.env.PLAYWRIGHT_BROWSERS_PATH || path.join(os.homedir(), '.cache/ms-playwright');
const shell = JSON.parse(fs.readFileSync(path.join(nodeModules, 'playwright-core/browsers.json'), 'utf8'))
  .browsers.find((b) => b.name === 'chromium-headless-shell');
const shellDir = `chromium_headless_shell-${shell.revision}`;
const original = path.resolve(process.env.ARKIV_THEME_HEADLESS_SHELL || path.join(registry, shellDir, 'chrome-headless-shell-linux64'));
if (process.platform !== 'linux' || !fs.existsSync(path.join(original, 'chrome-headless-shell'))) {
  fail('Theme renders need the pinned headless shell on Linux: design/document-icon-themes/fetch-headless-shell.sh <dir>, then ARKIV_THEME_HEADLESS_SHELL=<dir>/chrome-headless-shell-linux64');
}
const version = spawnSync(path.join(original, 'chrome-headless-shell'), ['--version'], { encoding: 'utf8' }).stdout.trim();
if (version !== BROWSER) fail(`${version || 'Unknown browser'} found; the archived renders need ${BROWSER} (fetch-headless-shell.sh)`);
const browsers = path.join(work, 'browsers');
const wrapped = path.join(browsers, shellDir, 'chrome-headless-shell-linux64');
fs.mkdirSync(wrapped, { recursive: true });
for (const marker of ['INSTALLATION_COMPLETE', 'DEPENDENCIES_VALIDATED']) fs.writeFileSync(path.join(browsers, shellDir, marker), '');
for (const name of fs.readdirSync(original)) {
  if (name !== 'chrome-headless-shell') fs.symlinkSync(path.join(original, name), path.join(wrapped, name));
}
fs.writeFileSync(path.join(wrapped, 'chrome-headless-shell'),
  `#!/bin/sh\nexec '${path.join(original, 'chrome-headless-shell')}' ${SWITCHES.join(' ')} "$@"\n`, { mode: 0o755 });
process.env.PLAYWRIGHT_BROWSERS_PATH = browsers;
console.log(`Rendering with ${version} and ${SWITCHES.join(' ')}`);

// 2. Archived generators, unmodified.
run(process.execPath, ['render.mjs', '--out', path.join(work, 'v1')], { cwd: V1 });
run(process.execPath, ['iterations/render-iterations.mjs', '--v1', V1, '--out', path.join(work, 'iterations')], { cwd: V2 });
run(process.execPath, ['reproduce.mjs', 'seal-dark-restored-readability'], { cwd: V2 });

// 3. Renders through each parent's own pipeline.
const { chromium } = createRequire(path.join(nodeModules, 'playwright/package.json'))('playwright');
const { outlineText } = await import(pathToFileURL(path.join(V2, 'tooling/outline.mjs')).href);
const { pinFonts } = await import(pathToFileURL(path.join(V1, 'render.mjs')).href);
const browser = await chromium.launch();

// The variant table is read from the archived script, never retyped here.
const iterSource = fs.readFileSync(path.join(V2, 'iterations/render-iterations.mjs'), 'utf8');
const start = iterSource.indexOf('export const VARIANTS = ['), end = iterSource.indexOf('\n];\n', start);
if (start < 0 || end < 0) fail('render-iterations.mjs: VARIANTS table not found');
const VARIANTS = (await import('data:text/javascript;base64,' + Buffer.from(
  iterSource.slice(start, end + 3).replace('export const VARIANTS =', 'export default')).toString('base64'))).default;

// Same staging as render-iterations.mjs `patched()`: exact-once substitutions.
function patched(variant) {
  const [kind, rel] = variant.base.startsWith('v1:') ? ['v1', variant.base.slice(3)] : ['v2', variant.base];
  let src = fs.readFileSync(kind === 'v1' ? path.join(V1, rel) : path.join(V2, rel), 'utf8');
  for (const [now, then] of variant.subs ?? []) {
    if (src.split(now).length !== 2) fail(`${variant.id}: anchor not found exactly once`);
    src = src.replace(now, () => then);
  }
  if (variant.region) {
    const a = src.indexOf(variant.region[0]), b = src.indexOf(variant.region[1]);
    if (a < 0 || b < a || src.indexOf(variant.region[0], a + 1) >= 0) fail(`${variant.id}: region not unique`);
    src = src.slice(0, a) + variant.replacement + src.slice(b);
  }
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), `arkiv-theme-${variant.id}-`));
  fs.cpSync(path.join(V2, 'tooling/lib'), path.join(stage, 'lib'), { recursive: true });
  if (kind === 'v1') {
    fs.mkdirSync(path.join(stage, 'directions'));
    for (const dep of fs.readdirSync(path.join(V1, 'directions'))) fs.copyFileSync(path.join(V1, 'directions', dep), path.join(stage, 'directions', dep));
    fs.writeFileSync(path.join(stage, rel), src);
    return { kind, stage, file: path.join(stage, rel) };
  }
  fs.writeFileSync(path.join(stage, 'seal-dark.mjs'), src);
  return { kind, stage, file: path.join(stage, 'seal-dark.mjs') };
}

// v1 pipeline: identical page setup and per-image sequence to v1 render.mjs.
async function v1Page() {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await pinFonts(page, path.join(work, 'font-host'));
  return async (svg, px, file) => {
    await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
    await page.evaluate((markup) => { document.body.innerHTML = markup; }, svg);
    await page.evaluate(() => document.fonts.ready);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await page.locator('svg').screenshot({ path: file, omitBackground: true });
  };
}
// Production pipeline: identical to design/document-icons/generate.mjs and v2 reproduce.mjs.
async function outlinePage() {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await page.setContent('<!doctype html><html><body style="margin:0;background:transparent"></body></html>');
  return async (svg, px, file) => {
    await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
    await page.evaluate((m) => { document.body.innerHTML = m; }, outlineText(svg));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await page.locator('svg').screenshot({ path: file, omitBackground: true });
  };
}
const shootV1 = await v1Page();
const shootOutline = await outlinePage();

// Artwork naming in each pipeline. v1 renders aliases as `${id}-alias` with the
// alias label; production passes the alias label on the unchanged format.
function variantsOf(FORMATS, name, pipeline) {
  const art = config.artwork[name];
  const fmt = FORMATS.find((x) => x.id === art.format);
  if (!fmt) fail(`No format ${art.format}`);
  if (!art.alias) return { ...fmt };
  return pipeline === 'v1' ? { ...fmt, label: fmt.alias, id: `${fmt.id}-alias`, aliasOf: fmt.id } : { ...fmt, label: fmt.alias };
}
const allNames = [...config.icons, ...config.extras];
const report = { browser: version, switches: SWITCHES, variants: {}, extras: {} };

for (const theme of config.themes.filter((t) => t.source.type === 'iteration')) {
  const variant = VARIANTS.find((v) => v.id === theme.source.variant);
  if (!variant) fail(`${theme.id}: variant ${theme.source.variant} is not in the archive`);
  const { kind, stage, file } = patched(variant);
  const draw = (await import(pathToFileURL(file).href)).default;
  const { FORMATS } = await import(pathToFileURL(path.join(stage, 'lib/formats.mjs')).href);
  const pipeline = kind === 'v1' ? 'v1' : 'production';
  const shoot = pipeline === 'v1' ? shootV1 : shootOutline;
  // Fidelity: the archived script's own sizes, through its own outline pipeline.
  let fidelity = 0;
  for (const id of variant.formats) {
    const fmt = FORMATS.find((x) => x.id === id);
    for (const [px, pt] of variant.sizes ?? [[512, 512], [64, 32], [32, 16]]) {
      const mine = path.join(work, 'fidelity', variant.id, `${id}-${pt}pt-${px}px.png`);
      await shootOutline(draw(fmt, px, pt), px, mine);
      if (sha(mine) !== sha(path.join(work, 'iterations', variant.id, `${id}-${pt}pt-${px}px.png`))) {
        fail(`${variant.id}: ${id} ${pt}pt/${px}px differs from render-iterations.mjs output`);
      }
      fidelity++;
    }
  }
  // Every artwork name drawn from an affected format id gets the variant, at
  // the point sizes the variant changed (all sizes unless it declares some).
  const pts = variant.sizes ? new Set(variant.sizes.map(([, pt]) => pt)) : null;
  const names = allNames.filter((n) => variant.formats.includes(config.artwork[n].format));
  const reps = REPS.filter(([pt]) => !pts || pts.has(pt));
  for (const name of names) {
    for (const [pt, scale] of reps) {
      await shoot(draw(variantsOf(FORMATS, name, pipeline), pt * scale, pt), pt * scale,
        path.join(work, 'variants', variant.id, name, repName(pt, scale)));
    }
  }
  // Controls on an icon the archive does not record for this variant:
  //  * `_control`: the unpatched parent source, staged and rendered exactly like
  //    the variant, must equal the parent's archived pixels (build.py checks);
  //  * `_patched-control`: the patched source. Layout variants change code that
  //    every format shares, but the archive records their artwork only for the
  //    listed formats, so only those formats use it. build.py reports this.
  const control = config.icons.find((n) => !variant.formats.includes(config.artwork[n].format));
  const parentStage = patched({ ...variant, id: `${variant.id}-parent`, subs: [], region: undefined });
  const parentDraw = (await import(pathToFileURL(parentStage.file).href)).default;
  for (const [pt, scale] of REPS) {
    await shoot(parentDraw(variantsOf(FORMATS, control, pipeline), pt * scale, pt), pt * scale,
      path.join(work, 'variants', variant.id, '_control', control, repName(pt, scale)));
    await shoot(draw(variantsOf(FORMATS, control, pipeline), pt * scale, pt), pt * scale,
      path.join(work, 'variants', variant.id, '_patched-control', control, repName(pt, scale)));
  }
  report.variants[variant.id] = { pipeline, formats: variant.formats, names, reps: reps.map(([pt, s]) => repName(pt, s)), control, fidelity };
  fs.rmSync(stage, { recursive: true, force: true });
  fs.rmSync(parentStage.stage, { recursive: true, force: true });
}

// Unregistered artwork of the two v2 Seal Dark themes, all representations.
const EXTRA_SOURCES = {
  'seal-dark-restored-readability': { src: path.join(V2, 'themes/seal-dark-restored-readability/seal-dark.mjs'), previews: path.join(V2, 'themes/seal-dark-restored-readability/previews/unregistered') },
  'seal-dark-refined-26501': { src: path.join(V2, 'themes/seal-dark-refined-26501/seal-dark.mjs'), previews: path.join(repo, 'design/document-icons/previews/unregistered') },
};
for (const [theme, { src, previews }] of Object.entries(EXTRA_SOURCES)) {
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), `arkiv-theme-${theme}-`));
  fs.cpSync(path.join(V2, 'tooling/lib'), path.join(stage, 'lib'), { recursive: true });
  fs.copyFileSync(src, path.join(stage, 'seal-dark.mjs'));
  const draw = (await import(pathToFileURL(path.join(stage, 'seal-dark.mjs')).href)).default;
  const { FORMATS } = await import(pathToFileURL(path.join(stage, 'lib/formats.mjs')).href);
  let matched = 0;
  for (const name of config.extras) {
    for (const [pt, scale] of REPS) {
      const out = path.join(work, 'extras', theme, name, repName(pt, scale));
      await shootOutline(draw(variantsOf(FORMATS, name, 'production'), pt * scale, pt), pt * scale, out);
      if (pt === 512 && scale === 1) {
        if (sha(out) !== sha(path.join(previews, `${name}-512.png`))) fail(`${theme}: ${name} 512 px differs from the preserved preview`);
        matched++;
      }
    }
  }
  report.extras[theme] = { names: config.extras, previewsMatched: matched };
  fs.rmSync(stage, { recursive: true, force: true });
}
await browser.close();
fs.writeFileSync(path.join(work, 'render-report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`Rendered ${Object.keys(report.variants).length} variants and ${Object.keys(report.extras).length} extra sets into ${work}`);
