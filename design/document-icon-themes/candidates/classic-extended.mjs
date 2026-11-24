// CANDIDATE, NOT APPROVED: an extended Classic theme for the formats the
// pre-redesign icons never covered. Design-time only; nothing here is in any
// pack or in Arkiv.app.
//
//   node design/document-icon-themes/candidates/classic-extended.mjs --v1 <archive v1 dir> --out <dir>
//
// The archived Classic reproduction (archive v1 directions/current.mjs) draws
// one template: the cream paper, its fold, the Arkiv mark and a plum label in
// Inter Display SemiBold. It had labels only for ZIP, 7z, TAR and RAR, sized
// for three characters. This candidate changes only two things, as exact
// substitutions of that archived file:
//   1. labels for every other supported format (and the split 7z volume);
//   2. a label size scaled down for labels wider than three characters, so
//      they stay inside the paper (the original sizes are unchanged for
//      three-character labels).
// The four original icons are rendered through the same staged source and
// must still equal the archived pixel references, which proves nothing else
// changed. The board marks archived and candidate artwork separately.
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const arg = (n) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : null; };
const V1 = path.resolve(arg('v1') ?? '');
const out = path.resolve(arg('out') ?? 'classic-extended');
if (!fs.existsSync(path.join(V1, 'directions/current.mjs'))) { console.error('Usage: --v1 <archive v1 dir> --out <dir>'); process.exit(2); }
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

const ORIGINAL = { zip: 'ZIP', '7z': '7z', tar: 'TAR', rar: 'RAR' };
const ADDED = { gz: 'GZIP', bz2: 'BZIP2', xz: 'XZ', zst: 'ZSTD', 'tgz-alias': 'TGZ', 'tbz2-alias': 'TBZ2', 'txz-alias': 'TXZ',
  tgz: 'TAR.GZ', tbz2: 'TAR.BZ2', txz: 'TAR.XZ', tzst: 'TAR.ZST', 'tzst-alias': 'TZST', '7z-split': '7z.001' };
const SUBS = [
  ["const SHIPPING = { zip: 'ZIP', '7z': '7z', tar: 'TAR', rar: 'RAR' };",
   `const SHIPPING = ${JSON.stringify({ ...ORIGINAL, ...ADDED })};`],
  ['  const size = px <= 64 ? 224 : 148;',
   "  const wide = [...label].reduce((w, c) => w + (c === '.' ? 0.4 : 1), 0);\n  const size = Math.round((px <= 64 ? 224 : 148) * Math.min(1, 3.4 / wide));"],
];

// Keep the archive's layout: current.mjs reads ../../../branding from directions/.
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arkiv-classic-candidate-'));
const stage = path.join(root, 'design/document-icon-concepts-v1');
fs.cpSync(V1, stage, { recursive: true, filter: (p) => !p.endsWith('node_modules') && !p.endsWith(`${path.sep}out`) });
fs.mkdirSync(path.join(root, 'branding'), { recursive: true });
fs.copyFileSync(path.join(V1, '../../branding/Arkiv-Mark-Transparent-512.png'), path.join(root, 'branding/Arkiv-Mark-Transparent-512.png'));
let source = fs.readFileSync(path.join(stage, 'directions/current.mjs'), 'utf8');
for (const [now, then] of SUBS) {
  if (source.split(now).length !== 2) throw new Error('anchor not found exactly once: ' + now);
  source = source.replace(now, () => then);
}
fs.writeFileSync(path.join(stage, 'directions/current.mjs'), source);
fs.symlinkSync(path.join(repo, 'design/document-icons/node_modules'), path.join(stage, 'node_modules'));

const { chromium } = createRequire(path.join(repo, 'design/document-icons/node_modules/playwright/package.json'))('playwright');
const { pinFonts } = await import(pathToFileURL(path.join(stage, 'render.mjs')).href);
const draw = (await import(pathToFileURL(path.join(stage, 'directions/current.mjs')).href)).default;
const { FORMATS } = await import(pathToFileURL(path.join(stage, 'lib/formats.mjs')).href);
const variant = (id) => {
  const base = FORMATS.find((f) => f.id === id.replace(/-alias$/, ''));
  return id.endsWith('-alias') ? { ...base, label: base.alias, id, aliasOf: base.id } : { ...base };
};

fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
await pinFonts(page, path.join(out, '.fonts'));
const files = {};
for (const id of [...Object.keys(ORIGINAL), ...Object.keys(ADDED)]) {
  for (const [px, pt, name] of [[256, 128, `${id}-128pt@2x.png`], [128, 128, `${id}-128.png`], [64, 32, `${id}-32pt@2x.png`], [32, 32, `${id}-32.png`], [32, 16, `${id}-16pt@2x.png`], [16, 16, `${id}-16.png`]]) {
    await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
    await page.evaluate((m) => { document.body.innerHTML = m; }, draw(variant(id), px, pt));
    await page.evaluate(() => document.fonts.ready);
    const file = path.join(out, 'png', name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await page.locator('svg').screenshot({ path: file, omitBackground: true });
    files[name] = file;
  }
}

// Board: archived originals and candidates, light and dark, 128 / 32 / 16 pt (2x).
const cell = (id, label, kind) => `<figure><div class="row">${['128pt@2x', '32pt@2x', '16pt@2x'].map((s, i) =>
  `<img src="file://${files[`${id}-${s}.png`]}" width="${[128, 32, 16][i]}" height="${[128, 32, 16][i]}">`).join('')}</div><figcaption>${label}<br><b>${kind}</b></figcaption></figure>`;
const section = (bg, fg, title) => `<section style="background:${bg};color:${fg}"><h2>${title}</h2>
  <h3>Archived (archive v1 directions/current.mjs, unchanged)</h3><div class="grid">${Object.entries(ORIGINAL).map(([id, l]) => cell(id, l, 'archived')).join('')}</div>
  <h3>Candidate: new labels for the same template (needs approval)</h3><div class="grid">${Object.entries(ADDED).map(([id, l]) => cell(id, l, 'CANDIDATE')).join('')}</div></section>`;
const html = `<!doctype html><html><head><style>
  body{margin:0;font:13px -apple-system,Helvetica,Arial,sans-serif;width:1500px}
  section{padding:24px 28px} h2{margin:0 0 6px} h3{margin:16px 0 8px;font-size:13px;opacity:.8}
  .grid{display:flex;flex-wrap:wrap;gap:22px} figure{margin:0;text-align:center} .row{display:flex;align-items:flex-end;gap:10px}
  figcaption{margin-top:6px;font-size:12px} b{font-size:10px;letter-spacing:.06em}
</style></head><body>
<section style="background:#fff3cd;color:#5c4400"><b>CANDIDATE ARTWORK, NOT APPROVED.</b> Extended Classic: the archived pre-redesign template with labels for formats it never covered. The four archived icons are re-rendered from the staged source and are pixel-identical to the archive references.</section>
${section('#ececec', '#222', 'Light background')}${section('#1e1e1e', '#ddd', 'Dark background')}</body></html>`;
fs.writeFileSync(path.join(out, 'board.html'), html);
const board = await browser.newPage({ viewport: { width: 1500, height: 900 }, deviceScaleFactor: 1 });
await board.goto(`file://${path.join(out, 'board.html')}`);
await board.screenshot({ path: path.join(out, 'classic-extended-board.png'), fullPage: true });
await browser.close();
const hash = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
fs.writeFileSync(path.join(out, 'SHA256SUMS'), Object.keys(files).sort().map((n) => `${hash(files[n])}  png/${n}`).join('\n') + '\n');
fs.rmSync(root, { recursive: true, force: true });
fs.rmSync(path.join(out, '.fonts'), { recursive: true, force: true });
console.log(`Candidate renders and board written to ${out}`);
