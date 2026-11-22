// Direction C · Dark — "Seal Dark": a lacquered aubergine document bound by a
// near-black spine. A champagne-brass seam marks the binding, and the jade
// pressure stud sits in a brass bezel with a faint jade halo. Folded-ribbon
// glyphs are re-tuned for a dark ground: lighter ribbon bodies, a lit top edge
// and a low-key halo in the format hue, so colour stays clean, never muddy.
// The Tension Seal mark itself is never reproduced, traced or recoloured.
import { Svg, FONT, tier, pagePath, flapPath, rrect, pts, f, mix, labelSize } from '../lib/core.mjs';
import { HUE, BRAND } from '../lib/formats.mjs';
import { placeMini } from '../lib/mini.mjs';

const PAGE = { L: 176, T: 72, R: 848, B: 952, r: 40, F: 196 };
const SPINE = 132;
const BRASS = { hi: '#F4E2B8', mid: '#CDA66C', lo: '#8C6538' };
const IVORY = '#F5E9DE';

export const SURFACES = {
  aubergine: { name: 'Aubergine', pageHi: '#4C2C3F', pageLo: '#1E111A', spineHi: '#21121A', spineLo: '#0C060A', flapHi: '#835670', flapLo: '#47293B', rim: '#F2C9DA' },
  wine: { name: 'Wine', pageHi: '#5C2333', pageLo: '#220B14', spineHi: '#1F0C12', spineLo: '#0B0407', flapHi: '#924559', flapLo: '#511F2F', rim: '#F6C2CC' },
  noir: { name: 'Noir', pageHi: '#302B33', pageLo: '#121014', spineHi: BRAND.plumHi, spineLo: BRAND.plumLo, flapHi: '#5D5662', flapLo: '#312C34', rim: '#E9DCEA' },
};

// Brighter ribbon body for dark grounds: never ends in the hue's darkest tone.
const ribbon = (s, h, y0 = -220, y1 = 220) => s.lin([[0, mix(h.light, '#ffffff', 0.5)], [0.4, h.light], [1, mix(h.base, h.light, 0.15)]], 0, y0, 0, y1);
const lift = (s) => s.shadow([[0, 10, 16, '#000000', 0.5], [0, 2, 2, '#000000', 0.35]]);
const brass = (s, y0, y1) => s.lin([[0, BRASS.hi], [0.5, BRASS.mid], [1, BRASS.lo]], 0, y0, 0, y1);

export const GLYPHS = {
  zip(s, h) {
    const g = ribbon(s, h);
    const tape = s.lin([[0, mix(h.base, h.light, 0.35)], [1, h.base]], 0, -220, 0, 220);
    let o = `<g filter="${lift(s)}">`;
    o += `<path d="M-132,-206 V206 M132,-206 V206" stroke="${tape}" stroke-width="34" stroke-linecap="round"/>`;
    for (let i = 0; i < 9; i++) {
      const y = -184 + i * 46, left = i % 2 === 0;
      o += `<path d="M${left ? -132 : 132},${y} C${left ? -70 : 70},${y - 16} ${left ? -16 : 16},${y + 16} ${left ? 44 : -44},${y}" stroke="${g}" stroke-width="34" stroke-linecap="round" fill="none"/>`;
    }
    return o + `</g>`;
  },
  '7z'(s, h) {
    let o = `<g filter="${lift(s)}">`;
    for (let i = 0; i < 7; i++) {
      const a = (360 / 7) * i;
      const lit = 0.5 + 0.5 * Math.cos(((a - 315) * Math.PI) / 180);
      const c1 = mix(h.light, '#ffffff', 0.15 + 0.3 * lit), c2 = mix(h.base, h.light, 0.1 + 0.35 * lit);
      o += `<path transform="rotate(${f(a)})" d="M0,-52 C46,-84 58,-172 0,-214 C-58,-172 -46,-84 0,-52 Z" fill="${s.lin([[0, c2], [1, c1]], 0, -52, 0, -214)}" stroke="#ffffff" stroke-opacity="0.18" stroke-width="2.5"/>`;
    }
    o += `</g><circle r="46" fill="none" stroke="${brass(s, -46, 46)}" stroke-width="7"/>`;
    o += `<circle r="38" fill="${s.rad([[0, '#EFFFF5'], [0.45, BRAND.jadeHi], [1, BRAND.jadeLo]], -10, -14, 50)}"/>`;
    return o;
  },
  rar(s, h) {
    let o = `<g filter="${lift(s)}">`;
    [[-150, 46], [-4, 0], [142, -46]].forEach(([y, dx], i) => {
      const t = i / 2;
      const top = mix(h.light, '#ffffff', 0.4 - 0.25 * t), bot = mix(h.base, h.light, 0.35 - 0.3 * t);
      const P = [[-100 + dx, y - 52], [190 + dx, y - 52], [140 + dx, y + 52], [-190 + dx, y + 52]];
      o += `<path d="M${P[0][0] + 26},${P[0][1]} H${P[1][0] - 30} Q${P[1][0] + 6},${P[1][1]} ${P[1][0] - 10},${P[1][1] + 26} L${P[2][0] + 10},${P[2][1] - 26} Q${P[2][0] - 6},${P[2][1]} ${P[2][0] - 30},${P[2][1]} H${P[3][0] + 26} Q${P[3][0] - 8},${P[3][1]} ${P[3][0] + 8},${P[3][1] - 26} L${P[0][0] - 8},${P[0][1] + 26} Q${P[0][0] + 6},${P[0][1]} ${P[0][0] + 26},${P[0][1]} Z" fill="${s.lin([[0, top], [1, bot]], 0, y - 52, 0, y + 52)}"/>`;
      o += `<path d="M${P[0][0] + 24},${y - 38} H${P[1][0] - 34}" stroke="#ffffff" stroke-opacity="0.55" stroke-width="6" stroke-linecap="round"/>`;
    });
    return o + `</g>`;
  },
  tar(s, h) {
    const P = [];
    const turns = 2.35, r0 = 26, r1 = 170;
    for (let i = 0; i <= 220; i++) {
      const t = i / 220, a = -Math.PI / 2 + t * turns * 2 * Math.PI, r = r0 + (r1 - r0) * t;
      P.push([r * Math.cos(a), r * Math.sin(a)]);
    }
    const last = P[P.length - 1];
    // The tail runs straight out to the right, so the coil reads as tape, not a lens.
    let d = `M${P.map(([x, y]) => `${f(x)},${f(y)}`).join(' L')}`;
    d += ` C${f(last[0] + 70)},${f(last[1])} 150,${f(last[1])} 236,${f(last[1])}`;
    return `<g filter="${lift(s)}"><path d="${d}" stroke="${ribbon(s, h)}" stroke-width="40" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>`;
  },
  gz(s, h) {
    const z = [[-150, -150], [150, -95], [-150, -32], [150, 32], [-150, 95], [150, 150]];
    let o = `<g filter="${lift(s)}"><polyline points="${pts(z)}" stroke="${ribbon(s, h, -170, 170)}" stroke-width="50" fill="none" stroke-linejoin="round" stroke-linecap="round"/></g>`;
    o += `<g filter="${lift(s)}"><path d="${rrect(-200, -228, 400, 40, 20)}" fill="${brass(s, -228, -188)}"/><path d="${rrect(-200, 188, 400, 40, 20)}" fill="${brass(s, 188, 228)}"/></g>`;
    return o;
  },
  bz2(s, h) {
    let o = `<g filter="${lift(s)}">`;
    [170, 245, 318, 392].forEach((w, i) => {
      const y = -150 + i * 100, t = i / 3;
      o += `<path d="M-180,${y} C${-180 + w * 0.4},${y - 14} ${-180 + w * 0.7},${y + 14} ${-180 + w},${y}" stroke="${s.lin([[0, mix(h.light, '#ffffff', 0.45 - 0.3 * t)], [1, mix(h.base, h.light, 0.55 - 0.45 * t)]], 0, y - 30, 0, y + 30)}" stroke-width="62" stroke-linecap="round" fill="none"/>`;
    });
    return o + `</g>`;
  },
  xz(s, h) {
    const R = [[0, -210], [150, 0], [0, 210], [-150, 0]];
    return `<g filter="${lift(s)}"><polygon points="${pts(R)}" stroke="${ribbon(s, h)}" stroke-width="44" fill="none" stroke-linejoin="round"/>` +
      `<polygon points="${pts([[0, -96], [70, 0], [0, 96], [-70, 0]])}" fill="${s.lin([[0, mix(h.light, '#ffffff', 0.4)], [1, h.base]], -60, -90, 60, 90)}"/></g>`;
  },
  zst(s, h) {
    let o = `<g filter="${lift(s)}"><polyline points="-120,-150 160,-150 -130,150 150,150" stroke="${ribbon(s, h, -170, 170)}" stroke-width="58" fill="none" stroke-linejoin="round" stroke-linecap="round" transform="skewX(-8)"/></g>`;
    [[-226, -76, 54], [-250, 0, 84], [-224, 76, 48]].forEach(([x, y, w], i) => {
      o += `<path d="M${x},${y} h${w}" stroke="${h.light}" stroke-opacity="${0.6 - i * 0.14}" stroke-width="22" stroke-linecap="round"/>`;
    });
    return o;
  },
};

const spineEdge = (P, w = SPINE) => {
  const { L, T, B } = P, m = (T + B) / 2;
  return `M${L + w},${T - 2} C${L + w},${T + 240} ${L + w + 40},${m - 150} ${L + w + 40},${m} C${L + w + 40},${m + 150} ${L + w},${B - 240} ${L + w},${B + 2}`;
};
const spinePath = (P, w = SPINE) => `M${P.L - 2},${P.T - 2} H${P.L + w} ${spineEdge(P, w).replace(/^M[^ ]+ /, '')} H${P.L - 2} Z`;

function stud(s, x, y, r = 40, halo = true) {
  let o = '';
  if (halo) o += `<circle cx="${x}" cy="${y}" r="${r * 2.4}" fill="${s.rad([[0, BRAND.jadeHi, 0.32], [0.45, BRAND.jadeLo, 0.12], [1, BRAND.jadeLo, 0]], x, y, r * 2.4)}"/>`;
  o += `<circle cx="${x}" cy="${y}" r="${r + 7}" fill="${brass(s, y - r - 7, y + r + 7)}" filter="${s.shadow([[0, 4, 6, '#000000', 0.55]])}"/>`;
  o += `<circle cx="${x}" cy="${y}" r="${r}" fill="${s.rad([[0, '#F0FFF6'], [0.4, BRAND.jadeHi], [1, BRAND.jadeLo]], x - r * 0.3, y - r * 0.4, r * 1.35)}"/>`;
  return o;
}

function sheet(s, P, S, h, { back = 0, glyphY = 476, cx } = {}) {
  const d = pagePath(P), clip = s.clip(d);
  const k = 0.14 * back;
  let o = `<g filter="${s.shadow([[0, 12, 26, '#000000', 0.36], [0, 1.5, 2.5, '#000000', 0.45]])}"><path d="${d}" fill="${s.lin([[0, mix(S.pageHi, '#000000', k)], [1, mix(S.pageLo, '#000000', k)]], 0, P.T, 0, P.B)}"/></g>`;
  o += `<g clip-path="${clip}">`;
  if (!back) {
    o += `<path d="${d}" fill="${s.lin([[0, '#ffffff', 0.09], [0.4, '#ffffff', 0], [1, '#ffffff', 0]], P.L, P.T, P.R * 0.85, P.B * 0.75)}"/>`;
    o += `<circle cx="${cx}" cy="${glyphY}" r="320" fill="${s.rad([[0, h.light, 0.22], [0.5, h.base, 0.08], [1, h.base, 0]], cx, glyphY, 320)}"/>`;
  }
  // lacquer spine, its shadow on the page, and the brass seam
  o += `<path d="${spineEdge(P)}" stroke="#000000" stroke-opacity="0.45" stroke-width="16" fill="none" transform="translate(8,0)" filter="${s.blur(6)}"/>`;
  o += `<path d="${spinePath(P)}" fill="${s.lin([[0, mix(S.spineHi, '#000000', k)], [1, S.spineLo]], 0, P.T, 0, P.B)}"/>`;
  o += `<path d="${spinePath(P)}" fill="${s.lin([[0, '#ffffff', 0.10], [0.5, '#ffffff', 0], [1, '#ffffff', 0.03]], P.L, 0, P.L + SPINE, 0)}"/>`;
  o += `<path d="${spineEdge(P)}" stroke="${back ? BRASS.lo : s.lin([[0, BRASS.hi], [0.5, BRASS.mid], [1, BRASS.lo]], 0, P.T, 0, P.B)}" stroke-width="${back ? 3 : 5}" fill="none" opacity="${back ? 0.6 : 0.95}"/>`;
  o += `</g>`;
  return { o, d, clip };
}
function finish(s, P, S, { d, clip }, back = 0) {
  const fl = flapPath(P);
  let o = `<g clip-path="${clip}"><path d="${fl}" transform="translate(-8,12)" fill="#000000" opacity="0.5" filter="${s.blur(10)}"/>` +
    `<path d="${fl}" fill="${s.lin([[0, back ? mix(S.flapHi, '#000000', 0.2) : S.flapHi], [1, S.flapLo]], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/>`;
  if (!back) o += `<path d="M${P.R - P.F + 6},${P.T + 6} L${P.R - 6},${P.T + P.F - 6}" stroke="${BRASS.hi}" stroke-opacity="0.55" stroke-width="3" stroke-linecap="round"/>`;
  o += `</g>`;
  o += `<path d="${d}" fill="none" stroke="${s.lin([[0, S.rim, 0.42], [0.3, S.rim, 0.14], [1, S.rim, 0.08]], 0, P.T, 0, P.B)}" stroke-width="6" clip-path="${clip}"/>`;
  o += `<path d="${d}" fill="none" stroke="#000000" stroke-opacity="0.6" stroke-width="2.5"/>`;
  return o;
}

export function makeSealDark(surface = 'aubergine') {
  const S = SURFACES[surface];
  return function sealDark(fmt, px, pt = px) {
    const s = new Svg();
    const h = HUE[fmt.hue], t = tier(pt);
    const isSplit = fmt.kind === 'split', isTar = fmt.kind === 'tar';

    if (t === 'xs' || t === 's') {
      const P = t === 'xs' ? { L: 192, T: 64, R: 832, B: 960, r: 64, F: 224, rc: 0 } : { L: 176, T: 64, R: 848, B: 960, r: 48, F: 208, rc: 8 };
      const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
      const sw = t === 'xs' ? 160 : 144;
      let o = '';
      if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="${S.flapLo}" stroke="${S.rim}" stroke-opacity="0.35" stroke-width="36"/>`;
      const d = pagePath(Q);
      o += `<path d="${d}" fill="${s.lin([[0, mix(S.pageHi, '#ffffff', 0.06)], [1, S.pageLo]], 0, Q.T, 0, Q.B)}"/>`;
      o += `<g clip-path="${s.clip(d)}"><rect x="${Q.L}" y="${Q.T}" width="${sw}" height="${Q.B - Q.T}" fill="${s.lin([[0, S.spineHi], [1, S.spineLo]], 0, Q.T, 0, Q.B)}"/>` +
        `<rect x="${Q.L + sw}" y="${Q.T}" width="${t === 'xs' ? 56 : 40}" height="${Q.B - Q.T}" fill="${BRASS.mid}"/></g>`;
      o += `<path d="${d}" fill="none" stroke="${S.rim}" stroke-opacity="${t === 'xs' ? 0.55 : 0.42}" stroke-width="${t === 'xs' ? 40 : 28}"/>`;
      o += `<path d="${flapPath(Q, 0)}" fill="${S.flapHi}" stroke="${S.rim}" stroke-opacity="0.45" stroke-width="${t === 'xs' ? 30 : 22}" stroke-linejoin="round"/>`;
      const ink = { fill: mix(h.base, h.light, 0.5), light: mix(h.light, '#ffffff', 0.45), dark: h.base };
      const cx = Q.L + sw + (Q.R - Q.L - sw) / 2;
      if (t === 'xs') {
        o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { fill: HUE.tar.light, light: h.light, dark: h.base } : ink, cx + 12, 548, 46);
      } else {
        o += `<circle cx="${Q.L + sw / 2}" cy="430" r="46" fill="${BRASS.mid}"/><circle cx="${Q.L + sw / 2}" cy="430" r="34" fill="${BRAND.jadeHi}"/>`;
        o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { fill: HUE.tar.light, light: h.light, dark: h.base } : ink, cx, 420, 34);
        const lab = fmt.short;
        o += `<text x="${cx}" y="900" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(labelSize(lab, Q.R - Q.L - sw - 60, 236))}" fill="${IVORY}">${lab}</text>`;
      }
      return s.wrap(o, px);
    }

    const P = isSplit ? { ...PAGE, L: 150, R: 796, T: 124 } : PAGE;
    const cx = P.L + SPINE + 40 + (P.R - P.L - SPINE - 40) / 2;
    let o = '';
    if (isSplit) {
      for (let i = 2; i >= 1; i--) {
        const Q = { ...P, L: P.L + i * 26, R: P.R + i * 26, T: P.T - i * 26, B: P.B - i * 26 };
        const sq = sheet(s, Q, S, h, { back: i });
        o += sq.o + finish(s, Q, S, sq, i);
      }
    }
    const glyphY = isTar ? 470 : isSplit ? 410 : 476;
    const sh = sheet(s, P, S, h, { glyphY, cx: cx - 8 });
    o += sh.o;
    const my = (P.T + P.B) / 2;
    let art = stud(s, P.L + 66, my, 36);
    if (isTar) {
      art += `<g transform="translate(${cx - 50},420) scale(0.66)">${GLYPHS.tar(s, HUE.tar)}</g>`;
      art += `<g transform="translate(${cx + 120},570)"><circle r="122" fill="${s.lin([[0, mix(S.pageHi, '#ffffff', 0.08)], [1, S.spineLo]], 0, -122, 0, 122)}" filter="${s.shadow([[0, 10, 20, '#000000', 0.5], [0, 1, 2, '#000000', 0.4]])}"/>` +
        `<circle r="121" fill="none" stroke="${BRASS.mid}" stroke-opacity="0.85" stroke-width="3"/><circle r="106" fill="none" stroke="${h.light}" stroke-opacity="0.9" stroke-width="7"/><g transform="scale(0.40)">${GLYPHS[fmt.motif](s, h)}</g></g>`;
    } else if (isSplit) {
      art += `<g transform="translate(${cx - 8},410) scale(0.66)">${GLYPHS[fmt.motif](s, h)}</g>`;
      const n = 4, w = 64, gap = 14, total = n * w + (n - 1) * gap;
      for (let i = 0; i < n; i++) {
        const x = cx - total / 2 + i * (w + gap);
        art += i === 0 ? `<rect x="${x}" y="622" width="${w}" height="20" rx="10" fill="${h.light}"/>` : `<rect x="${x + 2}" y="624" width="${w - 4}" height="16" rx="8" fill="none" stroke="${h.light}" stroke-opacity="0.5" stroke-width="4"/>`;
      }
    } else {
      art += `<g transform="translate(${cx - 8},476) scale(0.86)">${GLYPHS[fmt.motif](s, h)}</g>`;
    }
    o += `<g clip-path="${sh.clip}">${art}</g>`;
    o += finish(s, P, S, sh);
    const big = t === 'm';
    const size = labelSize(fmt.label, P.R - P.L - SPINE - (big ? 70 : 120), big ? 210 : isTar ? 120 : 150, 0.04);
    const txt = isTar && fmt.label.includes('.') ? `<tspan fill="${IVORY}">${fmt.label.split('.')[0]}</tspan><tspan fill="${mix(h.light, '#ffffff', 0.1)}">.${fmt.label.split('.')[1]}</tspan>` : fmt.label;
    o += `<text x="${cx}" y="872" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}" fill="${IVORY}">${txt}</text>`;
    if (isSplit && !big) o += `<text x="${cx}" y="712" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="40" letter-spacing="10" fill="${IVORY}" opacity="0.55">VOLUME</text>`;
    return s.wrap(o, px);
  };
}

export default makeSealDark('aubergine');
