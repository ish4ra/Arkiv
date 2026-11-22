// Builds the review boards (HTML → PNG with Chromium). Run after render.mjs.
//   node boards.mjs
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FORMATS } from './lib/formats.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(here, 'out');
const BOARDS = path.join(OUT, 'boards');
fs.mkdirSync(BOARDS, { recursive: true });

const img = (dir, id, px, css = px) => `<img src="file://${OUT}/png/${dir}/${id}/${id}-${px}.png" width="${css}" height="${css}" alt="">`;
// Best raster for a CSS size at 2× density.
const at2x = (dir, id, css) => (css === 16 || css === 32)
  ? `<img src="file://${OUT}/png/${dir}/${id}/${id}-${css}pt@2x.png" width="${css}" height="${css}" alt="">`
  : img(dir, id, [64, 128, 256, 512, 1024].find((p) => p >= css * 2) ?? 1024, css);

const DIRS = {
  folio: { name: 'A · Folio', tag: 'Native paper + format illustration', text: 'Apple-native white paper with a folded corner. Each format carries its own refined illustration and hue: a zipper, a heptagonal rosette, pressed slabs, a tape reel, a bellows press, sorted blocks, a quartz crystal and a speed Z. Calm in Finder and closest to the system document language.' },
  'folio-dark': { name: 'A · Folio Dark', tag: 'Graphite sheet + the Folio illustrations', text: 'The Folio illustrations on a satin graphite document: cool top sheen, a light-catching rim that separates it from dark backgrounds, a dark hairline that keeps it crisp on light ones, and the format hue rising softly from the bottom edge. Same artwork and colours as Folio, re-lit for a dark material rather than inverted.' },
  strata: { name: 'B · Strata', tag: 'Tinted glass card + dimensional porcelain object', text: 'A tinted glass document card holding a dimensional porcelain archive object with real facet lighting. Hue fills the whole card, so formats separate instantly, even at 16 px and in dark mode. The objects (a zipped parcel, a layered heptagonal prism, a slab stack, a reel, a bellows, a block staircase, a crystal, an extruded Z) give each format its own silhouette.' },
  seal: { name: 'C · Seal', tag: 'Arkiv-native spine + folded-ribbon glyphs', text: 'Warm ivory paper bound by a plum spine with the jade pressure stud, taken from the Tension Seal palette and materials but never reusing the mark. Format glyphs are drawn as folded ribbons: interlocking teeth, a seven-petal rosette, pressed layers, a wound spiral, a pleated press, sorted bands, a crystal and a Z fold. Every file reads as Arkiv first, format second.' },
  'seal-dark': { name: 'C · Seal Dark', tag: 'Lacquered aubergine + brass seam + jade stud', text: 'A lacquered aubergine document bound by a near-black spine. A champagne-brass seam marks the binding, and the jade pressure stud sits in a brass bezel with a faint jade halo. Folded-ribbon glyphs are re-tuned for a dark ground, with lighter ribbon bodies, lit top edges and a low-key halo in the format hue, so colour stays clean rather than muddy. Ivory labels. Unmistakably Arkiv, in its dark-first setting.' },
};
const ORDER = ['folio', 'folio-dark', 'strata', 'seal', 'seal-dark'];
const BASE = ['zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz', 'zst'];
const TARS = ['tgz', 'tgz-alias', 'tbz2', 'tbz2-alias', 'txz', 'txz-alias', 'tzst', 'tzst-alias'];
const ALL = [...BASE, ...TARS, '7z-split'];

const CSS = `
*{box-sizing:border-box} body{margin:0;font-family:Inter,'SF Pro Text',sans-serif;color:#1d1a1c;background:#F4F2EF;-webkit-font-smoothing:antialiased}
.board{padding:56px 64px;width:var(--w,1680px)} h1{font:700 40px/1.1 'Inter Display',Inter;margin:0 0 6px;letter-spacing:-.01em}
h2{font:650 22px 'Inter Display',Inter;margin:36px 0 14px} .sub{color:#6b6468;font-size:17px;margin:0 0 24px;max-width:1100px;line-height:1.45}
.grid{display:flex;flex-wrap:wrap;gap:26px 22px;align-items:flex-end} .cell{display:flex;flex-direction:column;align-items:center;gap:8px}
.cap{font-size:12.5px;color:#6b6468;text-align:center;line-height:1.3} .cap b{color:#1d1a1c;font-weight:600}
.pill{display:inline-block;font:600 11px Inter;letter-spacing:.08em;text-transform:uppercase;padding:4px 9px;border-radius:99px;background:#E9E4DE;color:#5a4b52}
.future{background:#FFE9C7;color:#8a4c00} .ok{background:#DDF1E7;color:#1c5a45}
.dark{background:#1C1B1D;color:#ECE9EC} .dark .cap{color:#9a949a} .dark .cap b{color:#eee}
.card{background:#fff;border-radius:18px;padding:28px;box-shadow:0 1px 0 rgba(0,0,0,.04),0 8px 30px rgba(0,0,0,.05)}
.row{display:flex;gap:28px;align-items:flex-start}
table{border-collapse:collapse} td,th{padding:10px 14px;text-align:center} th{font:600 13px Inter;color:#6b6468}
`;

async function shoot(browser, name, html, { width = 1680, scale = 2 } = {}) {
  const file = path.join(BOARDS, `${name}.html`);
  fs.writeFileSync(file, `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body>${html}</body></html>`);
  const page = await browser.newPage({ viewport: { width, height: 800 }, deviceScaleFactor: scale });
  await page.goto(`file://${file}`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(BOARDS, `${name}.png`), fullPage: true });
  await page.close();
}

const label = (id) => {
  if (id.endsWith('-alias')) { const f = FORMATS.find((x) => x.id === id.replace('-alias', '')); return `<b>${f.alias}</b><br>${f.ext[1]}`; }
  const f = FORMATS.find((x) => x.id === id);
  return `<b>${f.kind === 'split' ? `${f.label} volume` : f.label}</b><br>${f.ext.join(' ')}`;
};

const browser = await chromium.launch();

// 1–3. Design-system proposals
for (const [dir, meta] of Object.entries(DIRS)) {
  const html = `<div class="board"><span class="pill">Design system proposal</span><h1 style="margin-top:12px">${meta.name}</h1><p class="sub"><b>${meta.tag}.</b> ${meta.text}</p>
  <div class="row"><div class="card" style="display:flex;gap:28px;align-items:flex-end">${['zip', '7z', 'tar'].map((id) => `<div class="cell">${at2x(dir, id, 300)}<div class="cap">${label(id)}</div></div>`).join('')}</div>
  <div class="card dark" style="display:flex;gap:28px;align-items:flex-end;background:#1C1B1D">${['rar', 'zst'].map((id) => `<div class="cell">${at2x(dir, id, 220)}<div class="cap">${label(id)}</div></div>`).join('')}</div></div>
  <h2>Supported single formats</h2><div class="grid">${BASE.map((id) => `<div class="cell">${at2x(dir, id, 150)}<div class="cap">${label(id)}</div></div>`).join('')}</div>
  <h2>Compressed TAR and aliases <span class="cap">(an alias shares its family's artwork and only the label changes)</span></h2><div class="grid">${TARS.map((id) => `<div class="cell">${at2x(dir, id, 150)}<div class="cap">${label(id)}</div></div>`).join('')}</div>
  <h2>Split volumes</h2><div class="grid">${['7z-split', 'rar-parts', 'zip-split'].map((id) => `<div class="cell">${at2x(dir, id, 150)}<div class="cap">${label(id)}<br>${FORMATS.find((x) => x.id === id).status === 'future' ? '<span class="pill future">Future concept · not supported</span>' : '<span class="pill ok">Supported</span>'}</div></div>`).join('')}</div>
  <h2>Dedicated small artwork (32 pt and 16 pt, Retina)</h2><div class="grid">${ALL.slice(0, 16).filter((x) => !x.endsWith('alias')).concat('7z-split').map((id) => `<div class="cell" style="gap:6px">${at2x(dir, id, 32)}${at2x(dir, id, 16)}</div>`).join('')}</div>
  </div>`;
  await shoot(browser, `01-proposal-${dir}`, html);
}

// 4. Large comparison boards on light and dark backgrounds: rows = formats, columns = families (+ current)
for (const dark of [false, true]) {
  const rows = ALL.filter((x) => !x.endsWith('alias')).concat(['rar-parts', 'zip-split']);
  const html = `<div class="board ${dark ? 'dark' : ''}" style="--w:1640px;${dark ? 'background:#1C1B1E' : ''}"><h1>Format comparison · ${dark ? 'dark' : 'light'} background</h1><p class="sub">Every supported format across all five families, with the current shipping icon where one exists. Shown at 150 pt (2× rasters). Future concepts are marked.</p>
  <table><tr><th></th><th>Current</th>${ORDER.map((d) => `<th>${DIRS[d].name}</th>`).join('')}</tr>
  ${rows.map((id) => `<tr><td class="cap" style="text-align:left;width:190px">${label(id)}${FORMATS.find((x) => x.id === id).status === 'future' ? '<br><span class="pill future">Future concept</span>' : ''}</td><td>${['zip', '7z', 'tar', 'rar'].includes(id) ? at2x('current', id, 110) : '<span class="cap">No icon today</span>'}</td>${ORDER.map((d) => `<td>${at2x(d, id, 150)}</td>`).join('')}</tr>`).join('')}</table></div>`;
  await shoot(browser, `02-format-comparison-${dark ? 'dark' : 'light'}`, html, { width: 1640 });
}

// 5. Actual size: rendered at 1× (true pixels) and 2× (Retina)
for (const scale of [1, 2]) {
  const sizes = [16, 32, 64, 128];
  const ids = [...BASE, 'tgz', '7z-split'];
  const block = (dark) => `<div class="card ${dark ? 'dark' : ''}" style="${dark ? 'background:#1E1E20' : ''};margin-bottom:20px">${['current', ...ORDER].map((dir) => `<div style="display:flex;align-items:flex-end;gap:14px;margin:0 0 18px"><div class="cap" style="width:130px;text-align:left"><b>${dir === 'current' ? 'Current' : DIRS[dir].name}</b></div>${sizes.map((sz) => `<div style="display:flex;gap:6px;align-items:flex-end;margin-right:18px">${ids.map((id) => (dir === 'current' && !['zip', '7z', 'tar', 'rar'].includes(id)) ? `<span style="display:inline-block;width:${sz}px"></span>` : (scale === 1 ? img(dir, id, sz, sz) : sz <= 32 ? at2x(dir, id, sz) : img(dir, id, sz * 2, sz))).join('')}</div>`).join('')}</div>`).join('')}</div>`;
  const html = `<div class="board" style="--w:3000px;padding:32px"><h1 style="font-size:28px">Actual size · ${scale}× ${scale === 1 ? '(non-Retina, true pixels)' : '(Retina)'}</h1><p class="sub" style="font-size:14px">16 / 32 / 64 / 128 pt. Formats left to right: ZIP 7Z RAR TAR GZIP BZIP2 XZ ZSTD TAR.GZ 7Z-volume. 16 and 32 use dedicated artwork, not downscaled.</p>${block(false)}${block(true)}</div>`;
  await shoot(browser, `03-actual-size-${scale}x`, html, { width: 3000, scale });
}

// 6. Finder-style mockups (light + dark) for every direction
const FILES = [
  ['Project Assets.zip', 'zip', '18.4 MB'], ['Photos 2026.7z', '7z', '1.2 GB'], ['Legacy Docs.rar', 'rar', '240 MB'], ['Backup.tar', 'tar', '3.1 GB'],
  ['server-logs.gz', 'gz', '84 MB'], ['dataset.bz2', 'bz2', '412 MB'], ['kernel.xz', 'xz', '96 MB'], ['build-cache.zst', 'zst', '702 MB'],
  ['website.tar.gz', 'tgz', '58 MB'], ['sources.tgz', 'tgz-alias', '12 MB'], ['toolchain.tar.xz', 'txz', '188 MB'], ['snapshot.tar.zst', 'tzst', '2.4 GB'],
  ['Footage.7z.001', '7z-split', '1 GB'], ['Footage.7z.002', '7z-split', '1 GB'], ['Footage.7z.003', '7z-split', '312 MB'], ['release.tar.bz2', 'tbz2', '64 MB'],
];
const kind = (id) => { const f = FORMATS.find((x) => x.id === id.replace('-alias', '')); return f.kind === 'split' ? '7-Zip volume' : `${f.label} archive`; };
for (const dir of ORDER) {
  for (const dark of [false, true]) {
    const c = dark
      ? { win: '#1E1E1E', side: '#2A282B', bar: '#2C2A2D', text: '#E6E3E6', dim: '#8F8A90', sel: '#0A5BD6', line: '#3A373B', row: '#242225' }
      : { win: '#FFFFFF', side: '#EEECEF', bar: '#F6F5F7', text: '#1F1D1F', dim: '#86808A', sel: '#0A64E8', line: '#E2DFE3', row: '#F6F5F7' };
    const icons = FILES.map(([n, id], i) => `<div style="width:118px;display:flex;flex-direction:column;align-items:center;gap:6px;padding:8px 0">
      <div style="padding:4px;border-radius:8px;${i === 1 ? `background:${dark ? 'rgba(255,255,255,.12)' : 'rgba(0,0,0,.07)'}` : ''}">${at2x(dir, id, 64)}</div>
      <div style="font-size:12px;text-align:center;line-height:1.25;padding:1px 5px;border-radius:4px;${i === 1 ? `background:${c.sel};color:#fff` : ''}">${n}</div></div>`).join('');
    const list = FILES.map(([n, id, sz], i) => `<div style="display:flex;align-items:center;height:24px;padding:0 14px;font-size:12.5px;${i % 2 ? `background:${c.row}` : ''}${i === 4 ? `;background:${c.sel};color:#fff` : ''}">
      <div style="width:300px;display:flex;align-items:center;gap:7px">${at2x(dir, id, 16)}${n}</div><div style="width:190px;opacity:.75">Today at ${9 + (i % 9)}:${String(10 + i * 3).slice(-2)}</div><div style="width:90px;opacity:.75;text-align:right">${sz}</div><div style="padding-left:28px;opacity:.75">${kind(id)}</div></div>`).join('');
    const sidebar = `<div style="width:190px;background:${c.side};padding:44px 12px;font-size:13px;color:${c.text}"><div style="color:${c.dim};font-size:11px;font-weight:600;margin:0 0 6px 8px">Favourites</div>${['Recents', 'Applications', 'Desktop', 'Documents', 'Downloads'].map((x, i) => `<div style="padding:5px 8px;border-radius:6px;${i === 4 ? `background:${dark ? 'rgba(255,255,255,.1)' : 'rgba(0,0,0,.08)'}` : ''}">${x}</div>`).join('')}</div>`;
    const win = (body, title) => `<div style="border-radius:12px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,${dark ? 0.6 : 0.22}),0 0 0 1px rgba(0,0,0,.12);display:flex;background:${c.win};color:${c.text};margin-bottom:34px">${sidebar}
      <div style="flex:1"><div style="height:52px;background:${c.bar};border-bottom:1px solid ${c.line};display:flex;align-items:center;padding:0 18px;gap:8px;font-weight:600;font-size:14px">
      <span style="width:12px;height:12px;border-radius:6px;background:#FF5F57;position:relative;left:-196px"></span><span style="width:12px;height:12px;border-radius:6px;background:#FEBC2E;position:relative;left:-196px"></span><span style="width:12px;height:12px;border-radius:6px;background:#28C840;position:relative;left:-196px"></span><span style="margin-left:-160px">${title}</span></div>${body}</div></div>`;
    const html = `<div class="board ${dark ? 'dark' : ''}" style="--w:1500px;background:${dark ? 'linear-gradient(160deg,#2b2433,#141318)' : 'linear-gradient(160deg,#dfe6ef,#f3efe9)'}">
      <h1>${DIRS[dir].name} · Finder ${dark ? 'dark' : 'light'}</h1><p class="sub" style="color:${c.dim}">Icon view at 64 pt and list view at 16 pt (2× rasters). Mockup only. See the notes on .tar.* and .7z.001 Finder limits.</p>
      ${win(`<div style="display:flex;flex-wrap:wrap;padding:18px 22px;gap:4px 8px">${icons}</div>`, 'Downloads')}
      ${win(`<div style="display:flex;height:28px;align-items:center;padding:0 14px;font-size:11.5px;color:${c.dim};border-bottom:1px solid ${c.line}"><div style="width:300px">Name</div><div style="width:190px">Date Modified</div><div style="width:90px;text-align:right">Size</div><div style="padding-left:28px">Kind</div></div>${list}`, 'Downloads')}</div>`;
    await shoot(browser, `04-finder-${dir}-on-${dark ? "dark" : "light"}`, html, { width: 1500 });
  }
}

// 7. Current vs proposed
{
  const ids = ['zip', '7z', 'tar', 'rar', 'gz', 'zst'];
  const html = `<div class="board" style="--w:1640px"><h1>Current vs proposed</h1><p class="sub">Today all four shipping icons share one template: the same paper, the same Tension Seal mark and a plum label, with only the text changing. GZIP, BZIP2, XZ, ZSTD and compressed TAR have no Arkiv icon at all. Current icons are reproduced from <code>scripts/render-document-icons.swift</code> geometry; the app icon is untouched.</p>
  <table><tr><th></th>${ids.map((id) => `<th>${label(id)}</th>`).join('')}</tr>
  ${['current', ...ORDER].map((dir) => `<tr><td class="cap" style="text-align:left"><b>${dir === 'current' ? 'Current' : DIRS[dir].name}</b></td>${ids.map((id) => `<td>${dir === 'current' && !['zip', '7z', 'tar', 'rar'].includes(id) ? '<span class="cap">no Arkiv icon</span>' : at2x(dir, id, 170)}<div style="display:flex;gap:8px;justify-content:center;align-items:flex-end;margin-top:6px">${dir === 'current' && !['zip', '7z', 'tar', 'rar'].includes(id) ? '' : at2x(dir, id, 32) + at2x(dir, id, 16)}</div></td>`).join('')}</tr>`).join('')}</table></div>`;
  await shoot(browser, '05-current-vs-proposed', html, { width: 1640 });
}

// 8. Multipart concepts
{
  const html = `<div class="board" style="--w:1760px"><h1>Split-volume concepts</h1><p class="sub">A volume icon says "this file is one piece of a larger set": stacked sheets behind the document, the format's own artwork, and a segment strip with the first segment filled. Numbers are never drawn into the artwork, because one icon serves every part.</p>
  <table><tr><th></th>${ORDER.map((d) => `<th>${DIRS[d].name}</th>`).join('')}<th>16 / 32 pt</th></tr>
  ${[['7z-split', 'ok', 'Supported today: name.7z.001 … .128 (read, test, create)'], ['rar-parts', 'future', 'Future concept only: name.part1.rar, .r00 (multipart RAR is rejected today)'], ['zip-split', 'future', 'Future concept only: name.z01 / name.zip.001 (split ZIP is not supported today)']]
    .map(([id, st, note]) => `<tr><td style="text-align:left;width:250px"><span class="pill ${st}">${st === 'ok' ? 'Supported' : 'Future concept'}</span><div class="cap" style="text-align:left;margin-top:8px">${label(id)}<br>${note}</div></td>${ORDER.map((d) => `<td>${at2x(d, id, 200)}</td>`).join('')}<td><div style="display:flex;flex-direction:column;gap:10px">${ORDER.map((d) => `<div style="display:flex;gap:8px;align-items:flex-end">${at2x(d, id, 32)}${at2x(d, id, 16)}</div>`).join('')}</div></td></tr>`).join('')}</table>
  <h2>What Finder can actually show</h2><div class="card" style="font-size:14.5px;line-height:1.55;max-width:1400px">
  Finder chooses an icon from a file's <b>type identifier</b>, and that comes from the <b>last</b> extension only. <code>Footage.7z.001</code> is typed as <code>.001</code>, which is generic and shared with other applications. Arkiv must not declare or claim it, so a document-type icon can never target split 7z volumes safely. The workable route is a <b>Quick Look thumbnail extension</b> that inspects the name pattern and the 7z signature and returns a volume thumbnail only for real 7z sets, so unrelated <code>.001</code> files keep their normal icon. That needs a real-Mac prototype; see <code>README.md</code> for the full analysis.</div></div>`;
  await shoot(browser, '06-multipart', html, { width: 1760 });
}

// 0. Overview: all five families, every base format, light and dark panels
{
  const panel = (dark) => `<div class="card ${dark ? 'dark' : ''}" style="${dark ? 'background:#1E1D20;' : ''}margin-bottom:24px">${ORDER.map((d) => `<div style="display:flex;align-items:center;gap:18px;margin:6px 0 18px"><div class="cap" style="width:150px;text-align:left;font-size:14px"><b>${DIRS[d].name}</b></div>${[...BASE, 'tgz', '7z-split'].map((id) => at2x(d, id, 118)).join('')}</div>`).join('')}</div>`;
  const html = `<div class="board" style="--w:1640px"><h1>Five families</h1><p class="sub">A · Folio, A · Folio Dark, B · Strata, C · Seal and C · Seal Dark, side by side on light and dark backgrounds. ZIP · 7Z · RAR · TAR · GZIP · BZIP2 · XZ · ZSTD · TAR.GZ · 7Z volume at 118 pt.</p>${panel(false)}${panel(true)}</div>`;
  await shoot(browser, '00-overview-five-families', html, { width: 1640 });
}

// 7. Original vs dark, A and C
{
  const ids = [...BASE, 'tgz', 'tbz2', 'txz', 'tzst', '7z-split'];
  const pair = (a, b) => `<h2>${DIRS[a].name} → ${DIRS[b].name}</h2>
    <div class="row" style="margin-bottom:18px">${[false, true].map((dark) => `<div class="card ${dark ? 'dark' : ''}" style="flex:1;${dark ? 'background:#1E1D20' : ''}"><div class="cap" style="text-align:left;margin-bottom:12px"><b>${dark ? 'Dark' : 'Light'} background</b></div><div style="display:flex;gap:20px;align-items:flex-end">${['zip', '7z', 'rar'].map((id) => `<div style="display:flex;gap:8px;align-items:flex-end">${at2x(a, id, 128)}${at2x(b, id, 128)}</div>`).join('')}</div></div>`).join('')}</div>
    ${[false, true].map((dark) => `<div class="card ${dark ? 'dark' : ''}" style="margin-bottom:14px;${dark ? 'background:#1E1D20' : ''}">${[a, b].map((d) => `<div style="display:flex;align-items:center;gap:10px;margin:4px 0 10px"><div class="cap" style="width:130px;text-align:left"><b>${DIRS[d].name}</b></div>${ids.map((id) => at2x(d, id, 96)).join('')}<div style="width:18px"></div>${['zip', '7z', 'tar', 'gz'].map((id) => at2x(d, id, 32) + at2x(d, id, 16)).join('')}</div>`).join('')}</div>`).join('')}`;
  const html = `<div class="board" style="--w:1900px"><h1>Original vs dark</h1><p class="sub">Each dark family keeps its format artwork, hue and silhouette. The material changes, and the artwork is re-lit for it rather than inverted. Both dark families are checked on light Finder backgrounds as well as dark, since Arkiv cannot assume the system appearance.</p>${pair('folio', 'folio-dark')}${pair('seal', 'seal-dark')}</div>`;
  await shoot(browser, '07-original-vs-dark', html, { width: 1900 });
}

// 8. Seal Dark surface study
{
  const S = [['seal-dark', 'Aubergine', 'selected: plum-leaning and closest to the brand clasp'], ['seal-dark-wine', 'Wine', 'warmer, red-leaning; RAR claret loses separation'], ['seal-dark-noir', 'Noir', 'near-black page with the original plum spine: most neutral, least distinctive']];
  const ids = ['zip', '7z', 'rar', 'tar', 'gz', 'zst', 'tgz', '7z-split'];
  const html = `<div class="board" style="--w:1640px"><h1>C · Seal Dark: surface study</h1><p class="sub">Three lacquer surfaces were tried under the same glyphs, brass seam and jade stud. Aubergine is used for the Seal Dark family; Wine and Noir are kept for comparison.</p>
  ${[false, true].map((dark) => `<div class="card ${dark ? 'dark' : ''}" style="margin-bottom:20px;${dark ? 'background:#1E1D20' : ''}">${S.map(([d, n, why]) => `<div style="display:flex;align-items:center;gap:14px;margin:6px 0 16px"><div class="cap" style="width:190px;text-align:left"><b>${n}</b><br>${why}</div>${ids.map((id) => at2x(d, id, 140)).join('')}<div style="display:flex;flex-direction:column;gap:6px;margin-left:8px">${at2x(d, '7z', 32)}${at2x(d, '7z', 16)}</div></div>`).join('')}</div>`).join('')}</div>`;
  await shoot(browser, '08-seal-dark-surfaces', html, { width: 1640 });
}

await browser.close();
console.log('boards written to', BOARDS);
