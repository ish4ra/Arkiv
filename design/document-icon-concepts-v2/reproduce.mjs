// Re-renders a preserved Seal Dark theme and checks it byte-for-byte.
//
//   node reproduce.mjs seal-dark-refined-26501
//   node reproduce.mjs seal-dark-restored-readability [--keep <dir>]
//
// For each theme it regenerates all 11 shipped iconsets (10 representations
// each) and compares them with themes/<theme>/SHA256SUMS. When the theme folder
// also holds svg/ or previews/unregistered/, those are regenerated and compared
// too. Theme sources are kept byte-identical to where they came from, so they
// are staged next to the shared tooling in a temporary directory before import.
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const tooling = path.join(here, 'tooling');
const { chromium } = createRequire(path.join(tooling, 'package.json'))('playwright');
const theme = process.argv[2];
const themeDir = path.join(here, 'themes', theme ?? '');
if (!theme || !fs.existsSync(path.join(themeDir, 'seal-dark.mjs'))) {
  console.error(`Usage: node reproduce.mjs <${fs.readdirSync(path.join(here, 'themes')).join('|')}> [--keep <dir>]`);
  process.exit(2);
}
const keepAt = process.argv.indexOf('--keep');

// Same tables as design/document-icons/generate.mjs at main 84320df.
const { ICONS } = await import(pathToFileURL(path.join(tooling, 'generate-config.mjs')).href);
const UNREGISTERED = [['TAR.GZ', 'tgz'], ['TAR.BZ2', 'tbz2'], ['TAR.XZ', 'txz'],
  ['TAR.ZST', 'tzst'], ['TZST', 'tzst', 'TZST'], ['7z-volume', '7z-split'], ['RAR-volume-future', 'rar-parts'], ['ZIP-volume-future', 'zip-split']];
const REPS = [16, 32, 128, 256, 512].flatMap((pt) => [[pt, 1], [pt, 2]]);
const repName = (pt, scale) => `icon_${pt}x${pt}${scale === 2 ? '@2x' : ''}.png`;

const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'arkiv-theme-'));
fs.cpSync(path.join(tooling, 'lib'), path.join(stage, 'lib'), { recursive: true });
fs.copyFileSync(path.join(themeDir, 'seal-dark.mjs'), path.join(stage, 'seal-dark.mjs'));
const draw = (await import(pathToFileURL(path.join(stage, 'seal-dark.mjs')).href)).default;
const { FORMATS } = await import(pathToFileURL(path.join(stage, 'lib/formats.mjs')).href);
const { outlineText } = await import(pathToFileURL(path.join(tooling, 'outline.mjs')).href);
const fmtFor = (id, label) => { const f = FORMATS.find((x) => x.id === id); return label ? { ...f, label } : f; };
const svgFor = (id, px, pt, label) => outlineText(draw(fmtFor(id, label), px, pt));
const hash = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

const out = keepAt > 0 ? path.resolve(process.argv[keepAt + 1]) : path.join(stage, 'out');
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
await page.setContent('<!doctype html><html><body style="margin:0;background:transparent"></body></html>');
const shot = async (markup, px, file) => {
  await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
  await page.evaluate((m) => { document.body.innerHTML = m; }, markup);
  await page.locator('svg').screenshot({ path: file, omitBackground: true });
};

let checked = 0; const bad = [];
const want = new Map(fs.readFileSync(path.join(themeDir, 'SHA256SUMS'), 'utf8').trim().split('\n').map((l) => [l.slice(66), l.slice(0, 64)]));
for (const [name, v] of Object.entries(ICONS)) {
  const dir = path.join(out, 'iconsets', `Arkiv-${name}.iconset`);
  fs.mkdirSync(dir, { recursive: true });
  for (const [pt, scale] of REPS) {
    const file = path.join(dir, repName(pt, scale));
    await shot(svgFor(v.format, pt * scale, pt, v.label), pt * scale, file);
    checked++;
    if (hash(file) !== want.get(`Arkiv-${name}.iconset/${repName(pt, scale)}`)) bad.push(path.relative(out, file));
  }
}
if (want.size !== checked) bad.push(`SHA256SUMS lists ${want.size} files, rendered ${checked}`);

const items = [...Object.entries(ICONS).map(([n, v]) => [n, v.format, v.label]), ...UNREGISTERED];
if (fs.existsSync(path.join(themeDir, 'svg'))) {
  for (const [name, id, label] of items) {
    for (const [pt, tierName] of [[16, 'xs'], [32, 's'], [512, 'l']]) {
      const svg = svgFor(id, 1024, pt, label).replace(/ width="\d+" height="\d+">/, ' width="1024" height="1024">');
      checked++;
      if (svg !== fs.readFileSync(path.join(themeDir, 'svg', `${name}-${tierName}.svg`), 'utf8')) bad.push(`svg/${name}-${tierName}.svg`);
    }
  }
}
const prevDir = path.join(themeDir, 'previews', 'unregistered');
if (fs.existsSync(prevDir)) {
  fs.mkdirSync(path.join(out, 'unregistered'), { recursive: true });
  for (const [name, id, label] of UNREGISTERED) {
    const file = path.join(out, 'unregistered', `${name}-512.png`);
    await shot(svgFor(id, 512, 512, label), 512, file);
    checked++;
    if (hash(file) !== hash(path.join(prevDir, `${name}-512.png`))) bad.push(`previews/unregistered/${name}-512.png`);
  }
}
await browser.close();
if (keepAt < 0) fs.rmSync(stage, { recursive: true, force: true });
console.log(`${theme}: ${checked} files regenerated, ${bad.length} differ`);
if (bad.length) { console.log(bad.slice(0, 20).join('\n')); process.exit(1); }
