// Converts every <text> element in an icon SVG into outlined <path> glyphs
// using the vendored Inter Display fonts (OFL-1.1, fonts/OFL.txt). The
// committed artwork then has no font dependency at all: rendering is a pure
// function of the SVG and the pinned Chromium.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const opentype = createRequire(import.meta.url)('opentype.js');
const here = path.dirname(fileURLToPath(import.meta.url));
const FILES = { 600: 'InterDisplay-SemiBold.otf', 700: 'InterDisplay-Bold.otf', 800: 'InterDisplay-ExtraBold.otf' };
const fonts = {};
const font = (weight) => {
  const w = FILES[weight] ? weight : 700;
  if (!fonts[w]) {
    const buf = fs.readFileSync(path.join(here, 'fonts', FILES[w]));
    fonts[w] = opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  }
  return fonts[w];
};
const attrs = (s) => Object.fromEntries([...s.matchAll(/([\w:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
const unescape = (t) => t.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

export function outlineText(svg) {
  return svg.replace(/<text ([^>]*)>([\s\S]*?)<\/text>/g, (_, rawAttrs, body) => {
    const a = attrs(rawAttrs);
    const size = Number(a['font-size']), spacing = Number(a['letter-spacing'] || 0);
    const fnt = font(Number(a['font-weight'] || 700));
    const runs = body.includes('<tspan')
      ? [...body.matchAll(/<tspan fill="([^"]*)">([^<]*)<\/tspan>/g)].map((m) => ({ fill: m[1], text: unescape(m[2]) }))
      : [{ fill: a.fill, text: unescape(body) }];
    // Advance like the browser: glyph advance + kerning + letter-spacing after every glyph.
    const scale = size / fnt.unitsPerEm;
    let x = 0, prev = null;
    const placed = runs.map((run) => {
      const glyphs = [];
      for (const ch of run.text) {
        const g = fnt.charToGlyph(ch);
        if (prev) x += fnt.getKerningValue(prev, g) * scale;
        glyphs.push({ g, x });
        x += g.advanceWidth * scale + spacing;
        prev = g;
      }
      return { ...run, glyphs };
    });
    const width = x;
    const anchor = a['text-anchor'] || 'start';
    const x0 = Number(a.x) - (anchor === 'middle' ? width / 2 : anchor === 'end' ? width : 0);
    const y = Number(a.y);
    const paths = placed.map((run) => {
      const d = run.glyphs.map(({ g, x: gx }) => g.getPath(x0 + gx, y, size).toPathData(2)).join('');
      return d ? `<path d="${d}" fill="${run.fill || a.fill || '#000000'}"/>` : '';
    }).join('');
    const extra = ['opacity', 'filter'].filter((k) => a[k]).map((k) => ` ${k}="${a[k]}"`).join('');
    return `<g data-label="${runs.map((r) => r.text).join('')}"${extra}>${paths}</g>`;
  });
}
