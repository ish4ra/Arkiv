// Archived for provenance: the exact script that produced
// themes/seal-dark-restored-readability/boards/approved-vs-26501-vs-restored-*.webp
// on 2026-11-22. Its input paths (D, SP) point at that session's working
// directories: `approved` was archive v1 extracted from the branch, and
// `shipped` was main 84320df's Resources/DocumentIcons. Adjust them before
// re-running.
// Three-way review board: approved concept | shipped (main) | corrected.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const D = '/home/user/Arkiv/design/document-icons/';
const SP = path.dirname(new URL(import.meta.url).pathname);
const { chromium } = createRequire(D + 'x.js')('playwright');
const { outlineText } = await import(D + 'outline.mjs');
const { FORMATS } = await import(D + 'lib/formats.mjs');
const approved = (await import(pathToFileURL(SP + '/approved/design/document-icon-concepts-v1/directions/seal-dark.mjs').href)).default;
const corrected = (await import(D + 'seal-dark.mjs')).default;
const ICONS = [['ZIP', 'zip'], ['7z', '7z'], ['RAR', 'rar'], ['TAR', 'tar'], ['GZIP', 'gz'], ['BZIP2', 'bz2'], ['XZ', 'xz'], ['ZSTD', 'zst'], ['TGZ', 'tgz', 'TGZ'], ['TBZ2', 'tbz2', 'TBZ2'], ['TXZ', 'txz', 'TXZ']];
const EXTRA = [['7Z volume (Quick Look, not registered)', '7z-split'], ['TAR.GZ label (not registered)', 'tgz'], ['TZST (not registered)', 'tzst', 'TZST']];
const fmt = (id, label) => { const f = FORMATS.find((x) => x.id === id); return label ? { ...f, label } : f; };
const svg = (fn, id, label, px, pt) => 'data:image/svg+xml;base64,' + Buffer.from(outlineText(fn(fmt(id, label), px, pt))).toString('base64');
const png = (p) => 'data:image/png;base64,' + fs.readFileSync(p).toString('base64');
const img = (src, css) => `<img src="${src}" width="${css}" height="${css}">`;
const sha = (p) => fs.readFileSync(p).toString('base64');
const col = (big, s32x2, s16x2, s32, s16) => `<td><div style="display:flex;gap:10px;align-items:flex-end">${img(big, 150)}<div style="display:flex;flex-direction:column;gap:6px;align-items:center">${img(s32x2, 32)}${img(s16x2, 16)}<div style="height:4px"></div>${img(s32, 32)}${img(s16, 16)}</div></div></td>`;
const rowsFor = () => ICONS.map(([name, id, label]) => {
  const ship = (f) => `${SP}/shipped/Arkiv-${name}.iconset/${f}`, cor = (f) => `/home/user/Arkiv/Resources/DocumentIcons/Arkiv-${name}.iconset/${f}`;
  const files = ['icon_512x512.png', 'icon_32x32@2x.png', 'icon_16x16@2x.png', 'icon_32x32.png', 'icon_16x16.png'];
  const bigSame = sha(ship(files[0])) === sha(cor(files[0])), smallSame = files.slice(1).every((f) => sha(ship(f)) === sha(cor(f)));
  const status = bigSame && smallSame ? '<span class="pill same">Unchanged: already matched approved</span>' : `<span class="pill fix">Restored${bigSame ? '' : ' · large artwork'}${smallSame ? '' : ' · 16/32 pt'}</span>`;
  return `<tr><td class="lab"><b>${name}</b><br>${status}</td>${col(svg(approved, id, label, 300, 512), svg(approved, id, label, 64, 32), svg(approved, id, label, 32, 16), svg(approved, id, label, 32, 32), svg(approved, id, label, 16, 16))}${col(png(ship(files[0])), png(ship(files[1])), png(ship(files[2])), png(ship(files[3])), png(ship(files[4])))}${col(png(cor(files[0])), png(cor(files[1])), png(cor(files[2])), png(cor(files[3])), png(cor(files[4])))}</tr>`;
}).join('');
const extra = () => EXTRA.map(([name, id, label]) => `<tr><td class="lab"><b>${name}</b><br><span class="pill same">Artwork preserved</span></td>${col(svg(approved, id, label, 300, 512), svg(approved, id, label, 64, 32), svg(approved, id, label, 32, 16), svg(approved, id, label, 32, 32), svg(approved, id, label, 16, 16))}<td class="lab" style="text-align:center">not shipped</td>${col(svg(corrected, id, label, 300, 512), svg(corrected, id, label, 64, 32), svg(corrected, id, label, 32, 16), svg(corrected, id, label, 32, 32), svg(corrected, id, label, 16, 16))}</tr>`).join('');
for (const dark of [false, true]) {
  const bg = dark ? '#1E1D20' : '#FFFFFF', fg = dark ? '#ECE8EC' : '#1D1A1C';
  const html = `<!doctype html><html><head><style>body{margin:0;background:#F1EFEC;font-family:Inter}.b{padding:40px 48px;width:1560px}h1{font:700 32px 'Inter Display',Inter;margin:0 0 6px}.sub{color:#6b6468;font-size:15px;margin:0 0 20px;line-height:1.45}
  table{border-collapse:collapse;background:${bg};color:${fg};border-radius:16px;overflow:hidden}td,th{padding:12px 22px;vertical-align:middle}th{font:600 14px Inter;text-align:left;opacity:.75;padding-top:18px}tr+tr td{border-top:1px solid ${dark ? '#2e2c30' : '#eee'}}
  .lab{font-size:13px;width:200px;line-height:1.6}.pill{font:600 10.5px Inter;letter-spacing:.06em;text-transform:uppercase;padding:3px 8px;border-radius:99px;white-space:nowrap}.same{background:${dark ? '#26332d' : '#DDF1E7'};color:${dark ? '#9fdcbe' : '#1c5a45'}}.fix{background:${dark ? '#3a2f1c' : '#FFE9C7'};color:${dark ? '#f3c983' : '#8a4c00'}}</style></head><body><div class="b">
  <h1>Seal Dark document icons · approved vs current vs corrected · ${dark ? 'dark' : 'light'} background</h1>
  <div class="sub"><b>Approved</b>: archived concept source, archive/document-icon-concepts-v1. <b>Current</b>: the PNGs shipped on main (84320df, Sparkle build 26501). <b>Corrected</b>: this branch's regenerated iconsets. Each cell: 512 pt artwork at 150 pt, then 32 pt and 16 pt at 2× (top) and 1× (bottom).</div>
  <table><tr><th></th><th>Approved concept</th><th>Current production</th><th>Corrected</th></tr>${rowsFor()}${extra()}</table></div></body></html>`;
  const b = await chromium.launch(); const p = await b.newPage({ deviceScaleFactor: 2, viewport: { width: 1660, height: 900 } });
  await p.setContent(html); await p.waitForTimeout(500);
  await p.screenshot({ path: `${SP}/seal-dark-correction-${dark ? 'dark' : 'light'}.png`, fullPage: true }); await b.close();
}
