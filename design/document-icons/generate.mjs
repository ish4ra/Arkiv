// Generates Arkiv's production document-icon iconsets (C · Seal Dark).
//
//   node generate.mjs           # approved artwork change only: render, record PIXELS.sha256,
//                               # optimize losslessly, write SHA256SUMS, SVGs and previews
//   node generate.mjs --check   # render into a temp dir, then optimize.py --reproduce: the renders
//                               # must match PIXELS.sha256 and optimize to the committed bytes
//
// Design-time only (Node 22 + Playwright 1.63.0 / Chromium 157, plus the pinned
// optimizer in requirements-optimize.txt). The app build never runs this:
// scripts/build-app.sh packages the committed PNGs with Apple's iconutil, so
// packaging is deterministic and adds no dependency.
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FORMATS } from './lib/formats.mjs';
import draw from './seal-dark.mjs';
import { outlineText } from './outline.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const RES = path.join(repo, 'Resources/DocumentIcons');

import { ICONS } from './generate-config.mjs';
// Artwork kept for a future Quick Look thumbnail extension; never packaged.
const UNREGISTERED = [['TAR.GZ', 'tgz'], ['TAR.BZ2', 'tbz2'], ['TAR.XZ', 'txz'],
  ['TAR.ZST', 'tzst'], ['TZST', 'tzst', 'TZST'], ['7z-volume', '7z-split'], ['RAR-volume-future', 'rar-parts'], ['ZIP-volume-future', 'zip-split']];
const REPS = [16, 32, 128, 256, 512].flatMap((pt) => [[pt, 1], [pt, 2]]);
const repName = (pt, scale) => `icon_${pt}x${pt}${scale === 2 ? '@2x' : ''}.png`;

const fmtFor = (id, label) => { const f = FORMATS.find((x) => x.id === id); return label ? { ...f, label } : f; };
export const svgFor = (id, px, pt, label) => outlineText(draw(fmtFor(id, label), px, pt));

async function renderSet(page, items, dir) {
  const written = [];
  for (const [name, id, label] of items) {
    const out = path.join(dir, `Arkiv-${name}.iconset`);
    fs.mkdirSync(out, { recursive: true });
    for (const [pt, scale] of REPS) {
      const px = pt * scale;
      await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
      await page.evaluate((markup) => { document.body.innerHTML = markup; }, svgFor(id, px, pt, label));
      const file = path.join(out, repName(pt, scale));
      await page.locator('svg').screenshot({ path: file, omitBackground: true });
      written.push(file);
    }
  }
  return written;
}
// Lossless recompression and pixel bookkeeping live in optimize.py (pinned oxipng).
const optimize = (...args) => {
  const result = spawnSync(process.env.PYTHON || 'python3', [path.join(here, 'optimize.py'), ...args], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status ?? 1);
};

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
await page.setContent('<!doctype html><html><body style="margin:0;background:transparent"></body></html>');
const items = Object.entries(ICONS).map(([name, v]) => [name, v.format, v.label]);

if (process.argv.includes('--check')) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'arkiv-doc-icons-'));
  await renderSet(page, items, tmp);
  await browser.close();
  try { optimize('--reproduce', tmp); } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  console.log(`Regenerated ${items.length} iconsets match PIXELS.sha256 and SHA256SUMS byte-for-byte`);
  process.exit(0);
}

for (const [name] of items) fs.rmSync(path.join(RES, `Arkiv-${name}.iconset`), { recursive: true, force: true });
const files = await renderSet(page, items, RES);
optimize('--record-pixels', RES);

// Editable outlined SVG sources for every shipped icon and size tier.
const SVG = path.join(here, 'svg');
fs.rmSync(SVG, { recursive: true, force: true });
for (const [name, id, label] of [...items, ...UNREGISTERED]) {
  for (const [pt, tierName] of [[16, 'xs'], [32, 's'], [512, 'l']]) {
    fs.mkdirSync(SVG, { recursive: true });
    fs.writeFileSync(path.join(SVG, `${name}-${tierName}.svg`), svgFor(id, 1024, pt, label).replace(/ width="\d+" height="\d+">/, ' width="1024" height="1024">'));
  }
}
// Transparent previews of unregistered artwork (multipart and TAR.* labels).
const PREV = path.join(here, 'previews');
fs.mkdirSync(path.join(PREV, 'unregistered'), { recursive: true });
for (const [name, id, label] of UNREGISTERED) {
  await page.setViewportSize({ width: 512, height: 512 });
  await page.evaluate((markup) => { document.body.innerHTML = markup; }, svgFor(id, 512, 512, label));
  await page.locator('svg').screenshot({ path: path.join(PREV, 'unregistered', `${name}-512.png`), omitBackground: true });
}
await browser.close();
console.log(`Wrote ${items.length} iconsets (${files.length} PNGs) to ${path.relative(repo, RES)}`);
