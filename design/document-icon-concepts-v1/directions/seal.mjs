// Direction C — "Seal": Arkiv-native system. Warm ivory paper bound by a plum
// spine with the jade pressure stud (Tension Seal vocabulary), and a format
// glyph drawn from folded-ribbon geometry. The app mark itself is never
// reproduced, traced or recolored — only its palette and material language.
import { Svg, FONT, tier, pagePath, flapPath, rrect, polygon, pts, f, mix, labelSize } from '../lib/core.mjs';
import { HUE, BRAND } from '../lib/formats.mjs';
import { placeMini } from '../lib/mini.mjs';

const PAGE = { L: 176, T: 72, R: 848, B: 952, r: 40, F: 196 };
const SPINE = 132;

const ribbonGrad = (s, h, y0 = -220, y1 = 220) => s.lin([[0, mix(h.light, '#ffffff', 0.25)], [0.45, h.light], [1, h.dark]], 0, y0, 0, y1);
const soft = (s, c = '#2a1018') => s.shadow([[0, 9, 14, c, 0.24], [0, 2, 2, c, 0.18]]);

export const GLYPHS = {
  zip(s, h) {
    const g = ribbonGrad(s, h);
    const tape = s.lin([[0, h.base], [1, h.dark]], 0, -220, 0, 220);
    let o = `<g filter="${soft(s)}">`;
    o += `<path d="M-132,-206 V206 M132,-206 V206" stroke="${tape}" stroke-width="34" stroke-linecap="round"/>`;
    for (let i = 0; i < 9; i++) {
      const y = -184 + i * 46, left = i % 2 === 0;
      o += `<path d="M${left ? -132 : 132},${y} C${left ? -70 : 70},${y - 16} ${left ? -16 : 16},${y + 16} ${left ? 44 : -44},${y}" stroke="${g}" stroke-width="34" stroke-linecap="round" fill="none"/>`;
    }
    return o + `</g>`;
  },
  '7z'(s, h) {
    let o = `<g filter="${soft(s)}">`;
    for (let i = 0; i < 7; i++) {
      const a = (360 / 7) * i;
      const lit = 0.5 + 0.5 * Math.cos(((a - 315) * Math.PI) / 180);
      const c1 = mix(h.light, '#ffffff', 0.2 * lit), c2 = mix(h.base, h.dark, 0.7 - lit * 0.6);
      o += `<path transform="rotate(${f(a)})" d="M0,-52 C46,-84 58,-172 0,-214 C-58,-172 -46,-84 0,-52 Z" fill="${s.lin([[0, c2], [1, c1]], 0, -52, 0, -214)}" stroke="${mix(h.dark, '#000000', 0.2)}" stroke-opacity="0.18" stroke-width="3"/>`;
    }
    o += `</g><circle r="38" fill="${s.lin([[0, BRAND.jadeHi], [1, BRAND.jadeLo]], 0, -38, 0, 38)}"/>`;
    return o;
  },
  rar(s, h) {
    // three pressed ribbon layers, offset like a compacted stack
    let o = `<g filter="${soft(s)}">`;
    [[-150, 46], [-4, 0], [142, -46]].forEach(([y, dx], i) => {
      const t = i / 2;
      const top = mix(h.light, '#ffffff', 0.25 - 0.2 * t), bot = mix(h.base, h.dark, 0.15 + 0.6 * t);
      const P = [[-140 + dx + 40, y - 52], [190 + dx, y - 52], [140 + dx, y + 52], [-190 + dx, y + 52]];
      o += `<path d="M${P[0][0] + 26},${P[0][1]} H${P[1][0] - 30} Q${P[1][0] + 6},${P[1][1]} ${P[1][0] - 10},${P[1][1] + 26} L${P[2][0] + 10},${P[2][1] - 26} Q${P[2][0] - 6},${P[2][1]} ${P[2][0] - 30},${P[2][1]} H${P[3][0] + 26} Q${P[3][0] - 8},${P[3][1]} ${P[3][0] + 8},${P[3][1] - 26} L${P[0][0] - 8},${P[0][1] + 26} Q${P[0][0] + 6},${P[0][1]} ${P[0][0] + 26},${P[0][1]} Z" fill="${s.lin([[0, top], [1, bot]], 0, y - 52, 0, y + 52)}"/>`;
      o += `<path d="M${P[0][0] + 24},${y - 38} H${P[1][0] - 34}" stroke="#ffffff" stroke-opacity="0.45" stroke-width="6" stroke-linecap="round"/>`;
    });
    return o + `</g>`;
  },
  tar(s, h) {
    const g = ribbonGrad(s, h);
    const P = [];
    const turns = 2.35, r0 = 26, r1 = 170;
    for (let i = 0; i <= 220; i++) {
      const t = i / 220, a = -Math.PI / 2 + t * turns * 2 * Math.PI, r = r0 + (r1 - r0) * t;
      P.push([r * Math.cos(a), r * Math.sin(a)]);
    }
    const last = P[P.length - 1];
    let d = `M${P.map(([x, y]) => `${f(x)},${f(y)}`).join(' L')}`;
    d += ` C${f(last[0] + 60)},${f(last[1] + 40)} 150,170 236,200`;
    return `<g filter="${soft(s)}"><path d="${d}" stroke="${g}" stroke-width="40" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>`;
  },
  gz(s, h) {
    const g = ribbonGrad(s, h, -170, 170);
    const plate = s.lin([[0, mix(BRAND.plumHi, '#ffffff', 0.1)], [1, BRAND.plumLo]], 0, -30, 0, 30);
    const z = [[-150, -150], [150, -95], [-150, -32], [150, 32], [-150, 95], [150, 150]];
    let o = `<g filter="${soft(s)}"><polyline points="${pts(z)}" stroke="${g}" stroke-width="50" fill="none" stroke-linejoin="round" stroke-linecap="round"/></g>`;
    o += `<g filter="${soft(s)}"><path d="${rrect(-200, -228, 400, 40, 20)}" fill="${plate}"/><path d="${rrect(-200, 188, 400, 40, 20)}" fill="${plate}"/></g>`;
    return o;
  },
  bz2(s, h) {
    let o = `<g filter="${soft(s)}">`;
    [170, 245, 318, 392].forEach((w, i) => {
      const y = -150 + i * 100, t = i / 3;
      o += `<path d="M-180,${y} C${-180 + w * 0.4},${y - 14} ${-180 + w * 0.7},${y + 14} ${-180 + w},${y}" stroke="${s.lin([[0, mix(h.light, '#ffffff', 0.3 * (1 - t))], [1, mix(h.base, h.dark, 0.2 + 0.6 * t)]], 0, y - 30, 0, y + 30)}" stroke-width="62" stroke-linecap="round" fill="none"/>`;
    });
    return o + `</g>`;
  },
  xz(s, h) {
    const g = ribbonGrad(s, h);
    const R = [[0, -210], [150, 0], [0, 210], [-150, 0]];
    return `<g filter="${soft(s)}"><polygon points="${pts(R)}" stroke="${g}" stroke-width="44" fill="none" stroke-linejoin="round"/>` +
      `<polygon points="${pts([[0, -96], [70, 0], [0, 96], [-70, 0]])}" fill="${s.lin([[0, h.light], [1, h.dark]], -60, -90, 60, 90)}"/></g>`;
  },
  zst(s, h) {
    const g = ribbonGrad(s, h, -170, 170);
    let o = `<g filter="${soft(s)}"><polyline points="-120,-150 160,-150 -130,150 150,150" stroke="${g}" stroke-width="58" fill="none" stroke-linejoin="round" stroke-linecap="round" transform="skewX(-8)"/></g>`;
    [[-226, -76, 54], [-250, 0, 84], [-224, 76, 48]].forEach(([x, y, w], i) => {
      o += `<path d="M${x},${y} h${w}" stroke="${h.base}" stroke-opacity="${0.55 - i * 0.12}" stroke-width="22" stroke-linecap="round"/>`;
    });
    return o;
  },
};

function spinePath(P, w = SPINE) {
  const { L, T, B } = P, m = (T + B) / 2;
  return `M${L - 2},${T - 2} H${L + w} C${L + w},${T + 240} ${L + w + 40},${m - 150} ${L + w + 40},${m} C${L + w + 40},${m + 150} ${L + w},${B - 240} ${L + w},${B + 2} H${L - 2} Z`;
}

export default function seal(fmt, px, pt = px) {
  const s = new Svg();
  const h = HUE[fmt.hue], t = tier(pt);
  const isSplit = fmt.kind === 'split', isTar = fmt.kind === 'tar';
  const plum = s.lin([[0, BRAND.plumHi], [1, BRAND.plumLo]], 0, 72, 0, 952);

  if (t === 'xs' || t === 's') {
    const P = t === 'xs' ? { L: 192, T: 64, R: 832, B: 960, r: 64, F: 224, rc: 0 } : { L: 176, T: 64, R: 848, B: 960, r: 48, F: 208, rc: 8 };
    const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
    const sw = t === 'xs' ? 160 : 144;
    let o = '';
    if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="#DED5CB" stroke="${BRAND.plumLo}" stroke-opacity="0.45" stroke-width="40"/>`;
    const d = pagePath(Q);
    o += `<path d="${d}" fill="${s.lin([[0, BRAND.paperHi], [1, BRAND.paperLo]], 0, Q.T, 0, Q.B)}"/>`;
    o += `<g clip-path="${s.clip(d)}"><rect x="${Q.L}" y="${Q.T}" width="${sw}" height="${Q.B - Q.T}" fill="${plum}"/></g>`;
    o += `<path d="${d}" fill="none" stroke="${BRAND.plumLo}" stroke-opacity="${t === 'xs' ? 0.5 : 0.35}" stroke-width="${t === 'xs' ? 44 : 30}"/>`;
    o += `<path d="${flapPath(Q, 0)}" fill="#E6DCD2" stroke="${BRAND.plumLo}" stroke-opacity="0.35" stroke-width="${t === 'xs' ? 36 : 26}" stroke-linejoin="round"/>`;
    const ink = { fill: h.base, light: h.light, dark: h.dark };
    const cx = Q.L + sw + (Q.R - Q.L - sw) / 2;
    if (t === 'xs') {
      o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { fill: HUE.tar.base, light: h.base, dark: h.dark } : ink, cx + 8, 548, 46);
    } else {
      o += `<circle cx="${Q.L + sw / 2}" cy="430" r="40" fill="${BRAND.jadeLo}"/>`;
      o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { fill: HUE.tar.base, light: h.base, dark: h.dark } : ink, cx, 420, 34);
      const lab = fmt.short;
      o += `<text x="${cx}" y="900" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(labelSize(lab, Q.R - Q.L - sw - 60, 236))}" fill="${BRAND.plumInk}">${lab}</text>`;
    }
    return s.wrap(o, px);
  }

  const P = isSplit ? { ...PAGE, L: 150, R: 796, T: 124 } : PAGE;
  const d = pagePath(P), clip = s.clip(d);
  let o = '';
  if (isSplit) {
    for (let i = 2; i >= 1; i--) {
      const Q = { ...P, L: P.L + i * 26, R: P.R + i * 26, T: P.T - i * 26, B: P.B - i * 26 };
      const dq = pagePath(Q);
      o += `<g filter="${s.shadow([[0, 4, 10, '#1d1418', 0.14]])}"><path d="${dq}" fill="${mix('#F3ECE4', '#D8CDC2', i / 2 * 0.6)}"/></g>`;
      o += `<g clip-path="${s.clip(dq)}"><path d="${spinePath(Q)}" fill="${mix(BRAND.plumHi, '#ffffff', 0.1 * i)}" opacity="0.85"/></g>`;
      o += `<path d="${dq}" fill="none" stroke="#3c2a32" stroke-opacity="0.18" stroke-width="3"/>`;
    }
  }
  o += `<g filter="${s.shadow([[0, 10, 24, '#1d1418', 0.2], [0, 1.5, 2.5, '#1d1418', 0.22]])}"><path d="${d}" fill="${s.lin([[0, BRAND.paperHi], [1, BRAND.paperLo]], 0, P.T, 0, P.B)}"/></g>`;
  o += `<g clip-path="${clip}">`;
  // subtle paper grain: a faint diagonal wash
  o += `<path d="${d}" fill="${s.lin([[0, '#ffffff', 0.5], [0.5, '#ffffff', 0], [1, BRAND.amberLo, 0.06]], P.L, P.T, P.R, P.B)}"/>`;
  o += `<path d="${spinePath(P)}" fill="${plum}"/>`;
  o += `<path d="${spinePath(P).split(' H')[1] ? '' : ''}M${P.L + SPINE},${P.T} C${P.L + SPINE},${P.T + 240} ${P.L + SPINE + 40},${(P.T + P.B) / 2 - 150} ${P.L + SPINE + 40},${(P.T + P.B) / 2}" stroke="#ffffff" stroke-opacity="0.16" stroke-width="5" fill="none"/>`;
  const my = (P.T + P.B) / 2;
  o += `<circle cx="${P.L + 70}" cy="${my}" r="40" fill="${s.lin([[0, BRAND.jadeHi], [1, BRAND.jadeLo]], 0, my - 40, 0, my + 40)}" filter="${s.shadow([[0, 4, 6, '#120a0e', 0.35]])}"/>`;
  const cx = P.L + SPINE + 40 + (P.R - P.L - SPINE - 40) / 2;
  let art = '';
  if (isTar) {
    art += `<g transform="translate(${cx - 50},420) scale(0.66)">${GLYPHS.tar(s, HUE.tar)}</g>`;
    art += `<g transform="translate(${cx + 120},560)"><circle r="122" fill="${BRAND.paperHi}" filter="${s.shadow([[0, 8, 16, '#1d1418', 0.22], [0, 1, 2, '#1d1418', 0.2]])}"/><circle r="108" fill="none" stroke="${h.base}" stroke-width="8"/><g transform="scale(0.40)">${GLYPHS[fmt.motif](s, h)}</g></g>`;
  } else if (isSplit) {
    art += `<g transform="translate(${cx - 8},410) scale(0.66)">${GLYPHS[fmt.motif](s, h)}</g>`;
    const n = 4, w = 64, gap = 14, total = n * w + (n - 1) * gap;
    for (let i = 0; i < n; i++) {
      const x = cx - total / 2 + i * (w + gap);
      art += i === 0 ? `<rect x="${x}" y="622" width="${w}" height="20" rx="10" fill="${h.base}"/>` : `<rect x="${x + 2}" y="624" width="${w - 4}" height="16" rx="8" fill="none" stroke="${h.base}" stroke-opacity="0.6" stroke-width="4"/>`;
    }
  } else {
    art += `<g transform="translate(${cx - 8},476) scale(0.86)">${GLYPHS[fmt.motif](s, h)}</g>`;
  }
  o += art + `</g>`;
  // fold
  const fl = flapPath(P);
  o += `<g clip-path="${clip}"><path d="${fl}" transform="translate(-7,11)" fill="#2a1e22" opacity="0.16" filter="${s.blur(9)}"/><path d="${fl}" fill="${s.lin([[0, '#FFFFFF'], [1, '#E7DED4']], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/></g>`;
  o += `<path d="${d}" fill="none" stroke="#3c2a32" stroke-opacity="0.18" stroke-width="3"/>`;
  const big = t === 'm';
  const maxW = P.R - P.L - SPINE - (big ? 70 : 120);
  const size = labelSize(fmt.label, maxW, big ? 210 : isTar ? 120 : 150, 0.04);
  const txt = isTar ? `<tspan fill="${BRAND.plumInk}">${fmt.label.split('.')[0]}</tspan>${fmt.label.includes('.') ? `<tspan fill="${h.dark}">.${fmt.label.split('.')[1]}</tspan>` : ''}` : fmt.label;
  o += `<text x="${cx}" y="${isSplit ? 872 : 872}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}" fill="${BRAND.plumInk}">${txt}</text>`;
  if (isSplit && !big) o += `<text x="${cx}" y="712" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="40" letter-spacing="10" fill="${BRAND.plumInk}" opacity="0.6">VOLUME</text>`;
  return s.wrap(o, px);
}
