// Rebuilds every superseded intermediate design variant from the exploration
// session (2026-11-22) that is not itself a file in archive v1.
//
//   node iterations/render-iterations.mjs --v1 <path>/design/document-icon-concepts-v1 [--out out/iterations]
//
// Each variant is recorded as exact source text substitutions against the
// final code it was replaced by: the archived v1 direction files, or the
// build 26501 production source in themes/seal-dark-refined-26501. Every
// substitution must match exactly once, so a variant can only be rebuilt
// from the precise code it came from. The substitution text below is the
// code as it was originally written in the session.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const tooling = path.join(root, 'tooling');
const arg = (n) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : null; };
const v1 = arg('v1');
if (!v1 || !fs.existsSync(path.join(v1, 'directions'))) {
  console.error('Usage: node iterations/render-iterations.mjs --v1 <path>/design/document-icon-concepts-v1 [--out dir]');
  process.exit(2);
}
const out = path.resolve(arg('out') ?? path.join(root, 'out', 'iterations'));
const { chromium } = createRequire(path.join(tooling, 'package.json'))('playwright');
const { outlineText } = await import(pathToFileURL(path.join(tooling, 'outline.mjs')).href);

export const VARIANTS = [
  {
    id: 'folio-tar-three-windows', base: 'v1:directions/folio.mjs', direction: 'folio', formats: ['tar', 'tgz', 'tbz2'],
    note: 'A · Folio tape reel with three kidney-shaped windows (replaced by five round windows: read as a radiation trefoil).',
    subs: [[
      "    const windows = polygon(5, 0, 0, 128).map(([x, y]) => `<circle cx=\"${f(x)}\" cy=\"${f(y)}\" r=\"44\" fill=\"black\"/>`).join('');\n",
      "    const windows = [0, 120, 240].map((a) => {\n      const a0 = ((a - 30 - 90) * Math.PI) / 180, a1 = ((a + 30 - 90) * Math.PI) / 180, R = 122;\n      return `<path d=\"M${f(R * Math.cos(a0))},${f(R * Math.sin(a0))} A${R},${R} 0 0 1 ${f(R * Math.cos(a1))},${f(R * Math.sin(a1))}\" stroke=\"black\" stroke-width=\"78\" stroke-linecap=\"round\" fill=\"none\"/>`;\n    }).join('');\n",
    ]],
  },
  {
    id: 'folio-xs-glyph-unit-60', base: 'v1:directions/folio.mjs', direction: 'folio', formats: ['zip', '7z', 'tar', 'xz'], sizes: [[16, 16], [32, 16], [128, 16]],
    note: 'A · Folio first 16 pt layout: mini glyph at unit 60, centre y 540 (later 54 / 548 for margin).',
    subs: [['} else o += placeMini(fmt.motif, ink, cx, 548, 54);', '} else o += placeMini(fmt.motif, ink, cx, 540, 60);']],
  },
  {
    id: 'folio-dark-zip-pale-tape', base: 'v1:directions/folio-dark.mjs', direction: 'folio-dark', formats: ['zip', 'zip-split'],
    note: 'A · Folio Dark first ZIP: Folio\'s pale paper tape wash unchanged on graphite (read khaki; replaced by a warm translucent amber tape).',
    subs: [['const GLYPHS = {\n  ...FOLIO,\n  zip(s, h) {', 'const GLYPHS = {\n  ...FOLIO,\n  zipAmberTapeOverride(s, h) {']],
  },
  {
    id: 'strata-tar-trefoil-windows', base: 'v1:directions/strata.mjs', direction: 'strata', formats: ['tar', 'tgz', 'tbz2', 'txz', 'tzst'],
    note: 'B · Strata reel with three sector windows (read as a radiation trefoil; replaced by five round windows).',
    subs: [[
      '    const windows = polygon(5, 0, 0, 112, -45).map(([x, y]) => ({ p: circle(34, 28, x, y).map(([u, v]) => [u, v, 96.5]), c: tape.dark, k: 0.7 }));\n',
      '    const windows = [0, 120, 240].map((deg) => {\n      const pts3 = [];\n      for (let i = 0; i <= 10; i++) { const ang = ((deg - 32 + (64 * i) / 10) * Math.PI) / 180; pts3.push([150 * Math.cos(ang), 150 * Math.sin(ang), 96.5]); }\n      for (let i = 10; i >= 0; i--) { const ang = ((deg - 26 + (52 * i) / 10) * Math.PI) / 180; pts3.push([72 * Math.cos(ang), 72 * Math.sin(ang), 96.5]); }\n      return { p: pts3, c: tape.dark, k: 0.7 };\n    });\n',
    ]],
  },
  {
    id: 'strata-xz-octahedron-v0', base: 'v1:directions/strata.mjs', direction: 'strata', formats: ['xz', 'txz'],
    note: 'B · Strata first XZ crystal: axis-aligned octahedron in base/dark (replaced by a rotated, lighter cut-gem octahedron).',
    region: ['  xz(h) {', '  zst(h) {'],
    replacement: '  xz(h) {\n    const H = 215, A = 140, top = [0, 0, 2 * H], bot = [0, 0, 0];\n    const eq = [[A, 0, H], [0, A, H], [-A, 0, H], [0, -A, H]];\n    const faces = [];\n    for (let i = 0; i < 4; i++) {\n      const a = eq[i], b = eq[(i + 1) % 4];\n      faces.push({ p: [a, b, top], c: h.base });\n      faces.push({ p: [b, a, bot], c: h.dark });\n    }\n    return [faces];\n  },\n',
  },
  {
    id: 'strata-zst-floating-streaks', base: 'v1:directions/strata.mjs', direction: 'strata', formats: ['zst', 'tzst'],
    note: 'B · Strata first ZSTD: short streak blocks floating above-left of the Z (replaced by longer, thinner streaks behind it).',
    subs: [[
      'const streaks = [[-300, 278, 120], [-330, 160, 150], [-300, 30, 100]].map(([x, z, w]) => box(x, 30, z, x + w, 46, z + 18, h.light));',
      'const streaks = [[-260, 290, 70], [-290, 180, 100], [-262, 70, 60]].map(([x, z, w]) => box(x, -14, z, x + w, 14, z + 22, h.light));',
    ]],
  },
  {
    id: 'seal-zip-pale-ladder', base: 'v1:directions/seal.mjs', direction: 'seal', formats: ['zip', 'zip-split'],
    note: 'C · Seal first ZIP: pale ribbon tapes with wavy teeth (replaced by darker tapes and tighter ribbon teeth).',
    region: ['  zip(s, h) {', "  '7z'(s, h) {"],
    replacement: '  zip(s, h) {\n    const g = ribbonGrad(s, h);\n    let o = `<g filter="${soft(s)}">`;\n    o += `<path d="M-128,-215 V215 M128,-215 V215" stroke="${mix(h.light, \'#ffffff\', 0.15)}" stroke-width="40" stroke-linecap="round"/>`;\n    for (let i = 0; i < 9; i++) {\n      const y = -188 + i * 47, left = i % 2 === 0;\n      o += `<path d="M${left ? -128 : 128},${y} C${left ? -60 : 60},${y - 14} ${left ? -10 : 10},${y + 14} ${left ? 46 : -46},${y}" stroke="${g}" stroke-width="32" stroke-linecap="round" fill="none"/>`;\n    }\n    return o + `</g>`;\n  },\n',
  },
  {
    id: 'seal-rar-ring', base: 'v1:directions/seal.mjs', direction: 'seal', formats: ['rar', 'rar-parts'],
    note: 'C · Seal first RAR: three ribbons drawn through a plum ring collar (read as a megaphone; replaced by pressed slanted ribbon layers).',
    region: ['  rar(s, h) {', '  tar(s, h) {'],
    replacement: '  rar(s, h) {\n    const g = ribbonGrad(s, h, -150, 150);\n    const ring = s.lin([[0, mix(BRAND.plumHi, \'#ffffff\', 0.12)], [1, BRAND.plumLo]], 0, -150, 0, 150);\n    const back = `<path d="M-96,-136 A52,136 0 0 0 -96,136" stroke="${mix(BRAND.plumLo, \'#000000\', 0.1)}" stroke-width="40" fill="none" stroke-linecap="round"/>`;\n    const front = `<path d="M-96,-136 A52,136 0 0 1 -96,136" stroke="${ring}" stroke-width="44" fill="none" stroke-linecap="round"/>`;\n    let rib = \'\';\n    [[-150, -46, -40], [-6, 0, 0], [150, 46, 40]].forEach(([yOut, yIn, yIn2]) => {\n      rib += `<path d="M-200,${yIn2} C-150,${yIn2} -110,${yIn} -60,${yIn} C40,${yIn} 90,${yOut} 196,${yOut + 10}" stroke="${g}" stroke-width="54" stroke-linecap="round" fill="none"/>`;\n    });\n    return `<g filter="${soft(s)}">${back}${rib}${front}</g>`;\n  },\n',
  },
  {
    id: 'seal-layout-v0', base: 'v1:directions/seal.mjs', direction: 'seal', formats: ['zip', '7z', 'rar', 'tar', 'tgz', '7z-split'],
    note: 'C · Seal first layout: glyph at scale 0.84 centred at y 430, label baseline 864 (moved down and resized to clear the fold).',
    subs: [
      ['art += `<g transform="translate(${cx - 8},476) scale(0.86)">', 'art += `<g transform="translate(${cx},430) scale(0.84)">'],
      ['art += `<g transform="translate(${cx - 8},410) scale(0.66)">', 'art += `<g transform="translate(${cx},380) scale(0.68)">'],
      ['art += `<g transform="translate(${cx - 50},420) scale(0.66)">', 'art += `<g transform="translate(${cx - 40},380) scale(0.72)">'],
      ['<text x="${cx}" y="${isSplit ? 872 : 872}"', '<text x="${cx}" y="${isSplit ? 872 : 864}"'],
    ],
  },
  {
    id: 'seal-layout-v0.5-large-glyph', base: 'v1:directions/seal.mjs', direction: 'seal', formats: ['zip', 'rar', '7z', 'rar-parts'],
    note: 'C · Seal second layout: glyph at scale 0.94 centred at y 432 (overlapped the page fold; superseded the same day).',
    subs: [
      ['art += `<g transform="translate(${cx - 8},476) scale(0.86)">', 'art += `<g transform="translate(${cx},432) scale(0.94)">'],
      ['art += `<g transform="translate(${cx - 8},410) scale(0.66)">', 'art += `<g transform="translate(${cx},385) scale(0.76)">'],
    ],
  },
  {
    id: 'production-zip-loose-teeth', base: 'themes/seal-dark-refined-26501/seal-dark.mjs', direction: 'production', formats: ['zip'],
    note: 'Production refinement, first pass: 11 looser zipper teeth (tightened into the 13-tooth meshing chain shipped in build 26501).',
    subs: [[
      "    // Meshing chain: alternate teeth from each tape, overlapping at the centre.\n    for (let i = 0; i < 13; i++) {\n      const y = -214 + i * 19, left = i % 2 === 0;\n      o += `<g transform=\"translate(0,${y})\"><rect x=\"${left ? -64 : -12}\" y=\"-9.5\" width=\"76\" height=\"19\" rx=\"9\" fill=\"${tooth}\" stroke=\"${mix(h.base, h.dark, 0.3)}\" stroke-opacity=\"0.45\" stroke-width=\"2\"/></g>`;\n    }",
      "    for (let i = 0; i < 11; i++) {\n      const y = -212 + i * 22, left = i % 2 === 0;\n      o += `<g transform=\"translate(0,${y})\"><rect x=\"${left ? -66 : -16}\" y=\"-8\" width=\"82\" height=\"16\" rx=\"8\" fill=\"${tooth}\"/></g>`;\n    }",
    ]],
  },
];

function patched(variant) {
  const [kind, rel] = variant.base.startsWith('v1:') ? ['v1', variant.base.slice(3)] : ['v2', variant.base];
  let src = fs.readFileSync(kind === 'v1' ? path.join(v1, rel) : path.join(root, rel), 'utf8');
  for (const [now, then] of variant.subs ?? []) {
    if (src.split(now).length !== 2) throw new Error(`${variant.id}: anchor not found exactly once in ${variant.base}`);
    src = src.replace(now, () => then);
  }
  if (variant.region) {
    const a = src.indexOf(variant.region[0]), b = src.indexOf(variant.region[1]);
    if (a < 0 || b < a || src.indexOf(variant.region[0], a + 1) >= 0) throw new Error(`${variant.id}: region not unique in ${variant.base}`);
    src = src.slice(0, a) + variant.replacement + src.slice(b);
  }
  // Stage beside the libraries the original file imported.
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), `arkiv-iter-${variant.id}-`));
  fs.cpSync(path.join(tooling, 'lib'), path.join(stage, 'lib'), { recursive: true });
  if (kind === 'v1') {
    fs.mkdirSync(path.join(stage, 'directions'));
    for (const dep of fs.readdirSync(path.join(v1, 'directions'))) fs.copyFileSync(path.join(v1, 'directions', dep), path.join(stage, 'directions', dep));
    fs.writeFileSync(path.join(stage, rel), src);
    return { stage, file: path.join(stage, rel) };
  }
  fs.writeFileSync(path.join(stage, 'seal-dark.mjs'), src);
  return { stage, file: path.join(stage, 'seal-dark.mjs') };
}

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
await page.setContent('<!doctype html><html><body style="margin:0;background:transparent"></body></html>');
const index = [];
for (const variant of VARIANTS) {
  const { stage, file } = patched(variant);
  const draw = (await import(pathToFileURL(file).href)).default;
  const { FORMATS } = await import(pathToFileURL(path.join(stage, 'lib/formats.mjs')).href);
  const dir = path.join(out, variant.id);
  fs.mkdirSync(dir, { recursive: true });
  for (const id of variant.formats) {
    const fmt = FORMATS.find((x) => x.id === id);
    for (const [px, pt] of variant.sizes ?? [[512, 512], [64, 32], [32, 16]]) {
      await page.setViewportSize({ width: Math.max(px, 16), height: Math.max(px, 16) });
      await page.evaluate((m) => { document.body.innerHTML = m; }, outlineText(draw(fmt, px, pt)));
      await page.locator('svg').screenshot({ path: path.join(dir, `${id}-${pt}pt-${px}px.png`), omitBackground: true });
    }
  }
  index.push(`${variant.id}: ${variant.note}`);
  fs.rmSync(stage, { recursive: true, force: true });
}
await browser.close();
fs.writeFileSync(path.join(out, 'INDEX.txt'), index.join('\n') + '\n');
console.log(`${VARIANTS.length} superseded variants rebuilt into ${out}`);
