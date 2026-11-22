// Direction A · Dark — "Folio Dark": the Folio illustrations on a graphite
// document. Not an inversion: the sheet is a satin graphite material with a
// cool top sheen, a light-catching rim (so it separates from dark Finder
// backgrounds) and a dark hairline (so it stays crisp on light ones). Each
// format's hue rises from the bottom of the sheet as a restrained wash, and a
// soft halo lifts the illustration off the surface.
import { Svg, FONT, tier, pagePath, flapPath, f, mix, labelSize } from '../lib/core.mjs';
import { HUE } from '../lib/formats.mjs';
import { placeMini } from '../lib/mini.mjs';
import { GLYPHS as FOLIO } from './folio.mjs';

const PAGE = { L: 176, T: 72, R: 848, B: 952, r: 40, F: 200 };
const GR = { hi: '#3D3E45', mid: '#2C2D33', lo: '#1D1E22', flapHi: '#66676F', flapLo: '#3B3C42' };

const bright = (h, k = 0.12) => mix(h.light, '#ffffff', k);

// Folio's illustrations, reused as-is except the ZIP tape: its pale paper wash
// turns khaki on graphite, so the dark sheet gets a warm translucent amber tape.
const GLYPHS = {
  ...FOLIO,
  zip(s, h) {
    const tape = s.lin([[0, h.base, 0.34], [0.7, h.base, 0.16], [1, h.base, 0.06]], 0, -400, 0, 90);
    return FOLIO.zip(s, h).replace(/^<path d="M-118,-420 [^"]*" fill="[^"]*"\/>/, `<path d="M-118,-420 H118 V40 L60,96 H-60 L-118,40 Z" fill="${tape}"/><path d="M-118,-420 V40 M118,-420 V40" stroke="${h.light}" stroke-opacity="0.28" stroke-width="3"/>`);
  },
};

function sheet(s, P, h, { glyphY = 440, back = 0 } = {}) {
  const d = pagePath(P), clip = s.clip(d);
  const top = back ? mix(GR.hi, '#000000', 0.12 * back) : GR.hi, bot = back ? mix(GR.lo, '#000000', 0.1 * back) : GR.lo;
  let o = `<g filter="${s.shadow([[0, 12, 26, '#000000', 0.34], [0, 1.5, 2.5, '#000000', 0.42]])}"><path d="${d}" fill="${s.lin([[0, top], [0.55, back ? bot : GR.mid], [1, bot]], 0, P.T, 0, P.B)}"/></g>`;
  if (back) return { o: o + rim(s, P, d, clip, 0.6), clip, d };
  const cx = (P.L + P.R) / 2;
  o += `<g clip-path="${clip}">`;
  o += `<path d="${d}" fill="${s.lin([[0, '#ffffff', 0.07], [0.35, '#ffffff', 0], [1, '#ffffff', 0]], P.L, P.T, P.R * 0.8, P.B * 0.7)}"/>`;
  o += `<ellipse cx="${cx}" cy="${P.B + 40}" rx="520" ry="330" fill="${s.rad([[0, h.base, 0.30], [0.6, h.base, 0.08], [1, h.base, 0]], cx, P.B + 40, 520)}"/>`;
  o += `<circle cx="${cx}" cy="${glyphY}" r="300" fill="${s.rad([[0, h.light, 0.20], [0.55, h.base, 0.07], [1, h.base, 0]], cx, glyphY, 300)}"/>`;
  o += `</g>`;
  return { o, clip, d };
}
function rim(s, P, d, clip, k = 1) {
  return `<path d="${d}" fill="none" stroke="${s.lin([[0, '#ffffff', 0.34 * k], [0.25, '#ffffff', 0.12 * k], [1, '#ffffff', 0.07 * k]], 0, P.T, 0, P.B)}" stroke-width="6" clip-path="${clip}"/>` +
    `<path d="${d}" fill="none" stroke="#000000" stroke-opacity="0.55" stroke-width="2.5"/>`;
}
function fold(s, P, clip) {
  const fl = flapPath(P);
  return `<g clip-path="${clip}"><path d="${fl}" transform="translate(-8,12)" fill="#000000" opacity="0.5" filter="${s.blur(10)}"/>` +
    `<path d="${fl}" fill="${s.lin([[0, GR.flapHi], [1, GR.flapLo]], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/>` +
    `<path d="M${P.R - P.F + 6},${P.T + 6} L${P.R - 6},${P.T + P.F - 6}" stroke="#ffffff" stroke-opacity="0.28" stroke-width="3" stroke-linecap="round"/></g>`;
}

export default function folioDark(fmt, px, pt = px) {
  const s = new Svg();
  const h = HUE[fmt.hue], t = tier(pt);
  const isSplit = fmt.kind === 'split', isTar = fmt.kind === 'tar';

  if (t === 'xs' || t === 's') {
    const P = t === 'xs' ? { L: 192, T: 64, R: 832, B: 960, r: 56, F: 224, rc: 0 } : { L: 176, T: 64, R: 848, B: 960, r: 48, F: 208, rc: 8 };
    const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
    let o = '';
    if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="#4A4B52" stroke="#000000" stroke-opacity="0.5" stroke-width="40"/>`;
    o += `<path d="${pagePath(Q)}" fill="${s.lin([[0, '#45464D'], [1, '#202126']], 0, Q.T, 0, Q.B)}" stroke="${t === 'xs' ? '#7C7D86' : '#8A8B93'}" stroke-opacity="${t === 'xs' ? 0.9 : 0.7}" stroke-width="${t === 'xs' ? 44 : 28}"/>`;
    o += `<path d="${flapPath(Q, t === 'xs' ? 0 : 20)}" fill="#74757D" stroke="#9A9BA3" stroke-opacity="0.6" stroke-width="${t === 'xs' ? 30 : 22}" stroke-linejoin="round"/>`;
    const ink = { fill: mix(h.base, h.light, 0.45), light: mix(h.light, '#ffffff', 0.45), dark: h.base };
    const cx = (Q.L + Q.R) / 2;
    if (t === 'xs') {
      if (isTar) {
        o += placeMini(fmt.motif, ink, cx, 480, 52);
        o += `<rect x="${Q.L + 96}" y="800" width="${Q.R - Q.L - 192}" height="80" rx="20" fill="${HUE.tar.light}"/>`;
      } else o += placeMini(fmt.motif, ink, cx, 548, 54);
    } else {
      if (isTar) {
        o += placeMini(fmt.motif, ink, cx, 410, 34);
        o += `<rect x="${cx - 190}" y="618" width="380" height="40" rx="20" fill="${HUE.tar.light}"/>`;
      } else o += placeMini(fmt.motif, ink, cx, 420, 38);
      const lab = fmt.short;
      o += `<text x="${cx}" y="900" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(labelSize(lab, Q.R - Q.L - 96, 252))}" fill="${bright(h, 0.3)}">${lab}</text>`;
    }
    return s.wrap(o, px);
  }

  const P = isSplit ? { ...PAGE, L: 150, R: 796, T: 124, B: 952 } : PAGE;
  const cx = (P.L + P.R) / 2;
  let o = '';
  if (isSplit) {
    for (let i = 2; i >= 1; i--) o += sheet(s, { ...P, L: P.L + i * 26, R: P.R + i * 26, T: P.T - i * 26, B: P.B - i * 26 }, h, { back: i }).o;
  }
  const glyphY = isTar ? 470 : isSplit ? 380 : fmt.motif === 'zip' ? 410 : 440;
  const sh = sheet(s, P, h, { glyphY });
  o += sh.o;
  let art = '';
  if (isTar) {
    art += `<g transform="translate(${cx - 52},400) scale(0.76)">${GLYPHS.tar(s, HUE.tar)}</g>`;
    art += `<g transform="translate(${cx + 150},560)"><circle r="128" fill="${s.lin([[0, '#4B4C54'], [1, '#232428']], 0, -128, 0, 128)}" filter="${s.shadow([[0, 10, 20, '#000000', 0.45], [0, 1, 2, '#000000', 0.4]])}"/>` +
      `<circle r="126" fill="none" stroke="#ffffff" stroke-opacity="0.16" stroke-width="3"/><circle r="112" fill="none" stroke="${h.base}" stroke-width="8"/><g transform="scale(0.40)">${GLYPHS[fmt.motif](s, h)}</g></g>`;
  } else if (isSplit) {
    art += `<g transform="translate(${cx},${fmt.motif === 'zip' ? 330 : 380}) scale(${fmt.motif === 'zip' ? 0.74 : 0.7})">${GLYPHS[fmt.motif](s, h)}</g>`;
    const n = 4, w = 74, gap = 16, total = n * w + (n - 1) * gap;
    for (let i = 0; i < n; i++) {
      const x = cx - total / 2 + i * (w + gap);
      art += i === 0 ? `<rect x="${x}" y="612" width="${w}" height="22" rx="11" fill="${h.light}"/>`
        : `<rect x="${x + 2}" y="614" width="${w - 4}" height="18" rx="9" fill="none" stroke="${h.light}" stroke-opacity="0.45" stroke-width="4"/>`;
    }
  } else {
    art += `<g transform="translate(${cx},${glyphY}) scale(${fmt.motif === 'zip' ? 0.95 : 0.9})">${GLYPHS[fmt.motif](s, h)}</g>`;
  }
  o += `<g clip-path="${sh.clip}">${art}</g>`;
  o += fold(s, P, sh.clip) + rim(s, P, sh.d, sh.clip);
  const big = t === 'm';
  const size = labelSize(fmt.label, P.R - P.L - (big ? 60 : 130), big ? 230 : isTar ? 150 : 168, 0.04);
  const y = isSplit ? 872 : 866;
  const txt = isTar && fmt.label.includes('.')
    ? `<tspan fill="${bright(HUE.tar, 0.2)}">${fmt.label.split('.')[0]}</tspan><tspan fill="${bright(h, 0.05)}">.${fmt.label.split('.')[1]}</tspan>`
    : fmt.label;
  o += `<text x="${cx}" y="${y}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}" fill="${bright(h, 0.18)}">${txt}</text>`;
  if (isSplit && !big) o += `<text x="${cx}" y="700" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="44" letter-spacing="10" fill="${h.light}" opacity="0.6">VOLUME</text>`;
  return s.wrap(o, px);
}
