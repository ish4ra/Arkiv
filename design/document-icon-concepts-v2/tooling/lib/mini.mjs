// Dedicated small-size glyphs, drawn on a 16-unit pixel grid (1 unit = 1 px at
// 16 px, 2 px at 32 px). Geometry snaps to whole/half units so 16 px Finder
// list icons stay crisp instead of being a blurred downscale.
//
// `ink`: { fill, light, dark } colors for this context (paper vs. colored card).
import { f, polygon, pts } from './core.mjs';

const r = (x, y, w, h, c, rx = 0) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${c}"/>`;

export const MINI = {
  zip(ink) {
    let o = '';
    for (let i = 0; i < 6; i++) o += r(i % 2 ? 8 : 6, 2 + i, 2, 1, i % 2 ? ink.dark : ink.fill);
    o += r(6, 8, 4, 2, ink.dark, 0.5) + r(7.25, 9.5, 1.5, 3, ink.fill, 0.6);
    return o;
  },
  '7z'(ink) {
    const p = polygon(7, 8, 8.4, 4.1);
    const q = polygon(7, 8, 8.4, 1.9);
    return `<polygon points="${pts(p)}" fill="${ink.fill}" stroke="${ink.dark}" stroke-width="0.7" stroke-linejoin="round"/><polygon points="${pts(q)}" fill="${ink.light}"/>`;
  },
  rar(ink) {
    // three offset slabs, each a parallelogram with a darker lower edge
    let o = '';
    [[4.5, 4], [4, 7], [3.5, 10]].forEach(([x, y], i) => {
      o += `<polygon points="${pts([[x + 1.2, y], [x + 8.2, y], [x + 7, y + 2], [x, y + 2]])}" fill="${i === 1 ? ink.dark : ink.fill}"/>`;
    });
    return o;
  },
  tar(ink) {
    return `<rect x="8" y="10.4" width="6" height="1.6" fill="${ink.light}"/>` +
      `<circle cx="7.5" cy="7.6" r="3.4" fill="none" stroke="${ink.fill}" stroke-width="2"/>` +
      `<circle cx="7.5" cy="7.6" r="1" fill="${ink.dark}"/>`;
  },
  gz(ink) {
    return r(3.5, 3.5, 9, 1.5, ink.dark, 0.5) + r(3.5, 11.5, 9, 1.5, ink.dark, 0.5) +
      `<polyline points="5,6 11,7.25 5,8.5 11,9.75 5,11" fill="none" stroke="${ink.fill}" stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round"/>`;
  },
  bz2(ink) {
    let o = '';
    [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2]].forEach(([c, row], i) => {
      o += r(3.5 + c * 3, 10.5 - row * 3, 2.5, 2.5, i < 3 ? ink.dark : i < 5 ? ink.fill : ink.light, 0.4);
    });
    return o;
  },
  xz(ink) {
    const L = [[8, 2.5], [5, 6], [5, 11], [8, 13.5]];
    const R = [[8, 2.5], [11, 6], [11, 11], [8, 13.5]];
    return `<polygon points="${pts(L)}" fill="${ink.fill}"/><polygon points="${pts(R)}" fill="${ink.dark}"/>` +
      `<polygon points="${pts([[8, 2.5], [5, 6], [8, 6.8], [11, 6]])}" fill="${ink.light}"/>`;
  },
  zst(ink) {
    return `<polyline points="5.5,4.5 11.5,4.5 5.5,11.5 11.5,11.5" fill="none" stroke="${ink.fill}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>` +
      r(2.5, 7.25, 2.5, 1.2, ink.light, 0.6);
  },
};

// Place a mini glyph: grid (0..16) → canvas, centered at (cx, cy) canvas units.
export function placeMini(motif, ink, cx, cy, unit = 64) {
  return `<g transform="translate(${f(cx - 8 * unit)},${f(cy - 8 * unit)}) scale(${unit})">${MINI[motif](ink)}</g>`;
}
