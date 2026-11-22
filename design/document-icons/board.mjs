// Production review board for the Seal Dark document icons.
//   node board.mjs out.png [--concept <archive>/design/document-icon-concepts-v1/directions/seal-dark.mjs]
// With --concept, each icon is shown next to the approved concept it refines.
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { FORMATS } from './lib/formats.mjs';
import draw from './seal-dark.mjs';
import { outlineText } from './outline.mjs';
import { ICONS } from './generate-config.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');
const out = process.argv[2];
const ci = process.argv.indexOf('--concept');
const concept = ci > 0 ? (await import(pathToFileURL(path.resolve(process.argv[ci + 1])).href)).default : null;
const uri = (svg) => 'data:image/svg+xml;base64,' + Buffer.from(svg).toString('base64');
const fmt = (id, label) => { const f = FORMATS.find((x) => x.id === id); return label ? { ...f, label } : f; };
const img = (fn, id, label, px, pt, css) => `<img src="${uri(outlineText(fn(fmt(id, label), px, pt)))}" width="${css}" height="${css}">`;
const cap = (t, sub = '') => `<div style="font:600 12px Inter;margin-top:6px;text-align:center">${t}<div style="font-weight:400;opacity:.65">${sub}</div></div>`;

const registered = Object.entries(ICONS).map(([name, v]) => [name, v.format, v.label, v.ext]);
const unregistered = [['TAR.GZ', 'tgz', null, '.tar.gz → GZIP icon'], ['TAR.BZ2', 'tbz2', null, '.tar.bz2 → BZIP2'], ['TAR.XZ', 'txz', null, '.tar.xz → XZ'],
  ['TAR.ZST', 'tzst', null, '.tar.zst/.tzst → ZSTD'], ['7Z volume', '7z-split', null, '.7z.001 (Quick Look task)'], ['RAR volume', 'rar-parts', null, 'future concept'], ['ZIP volume', 'zip-split', null, 'future concept']];

const panel = (dark) => {
  const fg = dark ? '#ECE8EC' : '#1D1A1C', bg = dark ? '#1E1D20' : '#FFFFFF';
  let h = `<div style="background:${bg};color:${fg};border-radius:18px;padding:26px 28px;margin-bottom:22px">`;
  h += `<div style="font:600 13px Inter;opacity:.6;margin-bottom:12px">${dark ? 'DARK' : 'LIGHT'} BACKGROUND · registered document types (shipped in Arkiv.app)</div><div style="display:flex;gap:18px;flex-wrap:wrap">`;
  for (const [name, id, label, ext] of registered) {
    h += `<div style="display:flex;flex-direction:column;align-items:center">`;
    if (concept) h += `<div style="display:flex;gap:4px;align-items:flex-end">${img(concept, id, label, 192, 512, 84)}${img(draw, id, label, 288, 512, 140)}</div>`;
    else h += img(draw, id, label, 288, 512, 140);
    h += cap(name, ext) + `<div style="display:flex;gap:8px;align-items:flex-end;margin-top:8px">${img(draw, id, label, 64, 32, 32)}${img(draw, id, label, 32, 16, 16)}${img(draw, id, label, 32, 32, 32)}${img(draw, id, label, 16, 16, 16)}</div></div>`;
  }
  h += `</div><div style="font:600 13px Inter;opacity:.6;margin:22px 0 12px">Artwork kept for a future Quick Look thumbnail extension (not registered; Finder types these by their last extension)</div><div style="display:flex;gap:18px">`;
  for (const [name, id, label, note] of unregistered) h += `<div style="display:flex;flex-direction:column;align-items:center">${img(draw, id, label, 224, 512, 112)}${cap(name, note)}</div>`;
  return h + '</div></div>';
};
const html = `<!doctype html><html><body style="margin:0;background:#F1EFEC;font-family:Inter"><div style="padding:44px 52px;width:1900px">
<div style="font:700 36px 'Inter Display',Inter">Arkiv document icons · C · Seal Dark (production)</div>
<div style="font:16px Inter;color:#6b6468;margin:8px 0 26px;max-width:1500px">${concept ? 'Each pair shows the approved concept (small) beside the production icon. ' : ''}Below each icon: 32 pt and 16 pt at 2× (Retina), then 32 pt and 16 pt at 1× (true pixels), all dedicated small-size artwork.</div>
${panel(false)}${panel(true)}</div></body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 2004, height: 900 } });
await page.setContent(html);
await page.waitForTimeout(400);
await page.screenshot({ path: out, fullPage: true });
await browser.close();
