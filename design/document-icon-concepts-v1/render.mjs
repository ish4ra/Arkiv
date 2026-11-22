// Renders every direction × format × size to transparent PNGs and writes the
// editable SVG sources. Usage:
//   node render.mjs                      # everything
//   node render.mjs --dirs folio --only zip,7z --sizes 512 --sheet scratch.png
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FORMATS } from './lib/formats.mjs';
import { tier } from './lib/core.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const DIRECTIONS = {
  folio: (await import('./directions/folio.mjs')).default,
  strata: (await import('./directions/strata.mjs')).default,
  seal: (await import('./directions/seal.mjs')).default,
  'folio-dark': (await import('./directions/folio-dark.mjs')).default,
  'seal-dark': (await import('./directions/seal-dark.mjs')).default,
  'seal-dark-wine': (await import('./directions/seal-dark.mjs')).makeSealDark('wine'),
  'seal-dark-noir': (await import('./directions/seal-dark.mjs')).makeSealDark('noir'),
  current: (await import('./directions/current.mjs')).default,
};
export const SIZES = [16, 32, 64, 128, 256, 512, 1024];

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
};

// Rendering must not depend on the host's fonts: the SVG font stack starts with
// 'SF Pro Display' (present on macOS), so the vendored Inter Display weights
// are bound to every family name in that stack. Output is then identical on any
// machine with the pinned Chromium (see ARCHIVE.md / package.json).
const FONT_FILES = { 600: 'InterDisplay-SemiBold.otf', 700: 'InterDisplay-Bold.otf', 800: 'InterDisplay-ExtraBold.otf' };
const FAMILIES = ['SF Pro Display', 'SF Pro Rounded', 'Inter Display', 'Inter', 'Helvetica Neue'];
export async function pinFonts(page, out) {
  const faces = FAMILIES.flatMap((family) => Object.entries(FONT_FILES).map(([w, file]) =>
    `@font-face{font-family:'${family}';font-weight:${w};src:url('file://${path.join(here, 'fonts', file)}') format('opentype')}`)).join('');
  const host = path.join(out, '.render-host.html');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(host, `<!doctype html><html><head><style>${faces} html,body{margin:0;background:transparent}</style></head><body></body></html>`);
  await page.goto(`file://${host}`);
  await page.evaluate(async (fams) => { await Promise.all(fams.flatMap((f) => ['600', '700', '800'].map((w) => document.fonts.load(`${w} 40px '${f}'`)))); }, FAMILIES);
}

export async function renderAll({ dirs, only, sizes, out, sheet }) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await pinFonts(page, out);
  const svgOut = path.join(out, 'svg'), pngOut = path.join(out, 'png');
  const sheetItems = [];
  for (const dir of dirs) {
    const draw = DIRECTIONS[dir];
    for (const fmt of FORMATS.filter((x) => !only || only.includes(x.id))) {
      const variants = fmt.alias ? [{ ...fmt }, { ...fmt, label: fmt.alias, id: `${fmt.id}-alias`, aliasOf: fmt.id }] : [fmt];
      for (const v of variants) {
        const savedTiers = new Set();
        // 1× previews at every size, plus Retina @2x pairs that keep the
        // point-size artwork (16 pt @2x = 16 pt design rendered at 32 px).
        const jobs = [
          ...sizes.map((px) => ({ pt: px, px, name: `${v.id}-${px}.png` })),
          ...sizes.filter((pt) => [16, 32, 128, 256, 512].includes(pt)).map((pt) => ({ pt, px: pt * 2, name: `${v.id}-${pt}pt@2x.png` })),
        ];
        for (const { pt, px, name } of jobs) {
          const svg = draw(v, px, pt);
          const t = tier(pt);
          if (!savedTiers.has(t)) {
            savedTiers.add(t);
            const dst = path.join(svgOut, dir, `${v.id}-${t}.svg`);
            fs.mkdirSync(path.dirname(dst), { recursive: true });
            fs.writeFileSync(dst, svg.replace(/ width="\d+" height="\d+">/, ' width="1024" height="1024">'));
          }
          await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
          await page.evaluate((markup) => { document.body.innerHTML = markup; }, svg);
          await page.evaluate(() => document.fonts.ready);
          const dst = path.join(pngOut, dir, v.id, name);
          fs.mkdirSync(path.dirname(dst), { recursive: true });
          await page.locator('svg').screenshot({ path: dst, omitBackground: true });
          if (sheet && px === pt) sheetItems.push({ dir, id: v.id, px, file: dst });
        }
      }
    }
  }
  if (sheet) {
    const rows = {};
    for (const it of sheetItems) (rows[`${it.dir}/${it.id}`] ??= []).push(it);
    const html = `<html><body style="margin:0;padding:24px;background:${arg('bg', '#ececec')};font:12px Inter;display:flex;flex-wrap:wrap;gap:24px;align-items:flex-end;width:${arg('width', 1600)}px">${
      Object.entries(rows).map(([k, list]) => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px">${list.map((x) => `<img src="file://${x.file}" width="${x.px}" height="${x.px}">`).join('')}<span>${k}</span></div>`).join('')
    }</body></html>`;
    fs.writeFileSync(path.join(out, 'sheet.html'), html);
    const p2 = await browser.newPage({ viewport: { width: Number(arg('width', 1600)) + 48, height: 400 }, deviceScaleFactor: 1 });
    await p2.goto(`file://${path.join(out, 'sheet.html')}`);
    await p2.screenshot({ path: sheet, fullPage: true });
  }
  await browser.close();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dirs = arg('dirs', Object.keys(DIRECTIONS).join(',')).split(',');
  const only = arg('only', null)?.split(',');
  const sizes = arg('sizes', SIZES.join(',')).split(',').map(Number);
  const out = path.resolve(arg('out', path.join(here, 'out')));
  await renderAll({ dirs, only, sizes, out, sheet: arg('sheet', null) });
}
