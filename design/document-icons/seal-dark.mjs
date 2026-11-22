// Arkiv production document icons — C · Seal Dark (Aubergine), approved
// 2026-11. Refined from the approved concept preserved on the branch
// archive/document-icon-concepts-v1 (design/document-icon-concepts-v1):
//   * ZIP: interlocking ribbon teeth with a brass slider (was a ribbon ladder)
//   * RAR: a pressed three-layer block with real depth (was flat slanted bars)
//   * TAR.*: larger compressor emblem; the fold takes the compressor's hue
//   * 16/32 pt: brighter sheet and rim, narrower spine, compressor cues
//
// Original concept notes: "Seal Dark": a lacquered aubergine document bound by a
// near-black spine. A champagne-brass seam marks the binding, and the jade
// pressure stud sits in a brass bezel with a faint jade halo. Folded-ribbon
// glyphs are re-tuned for a dark ground: lighter ribbon bodies, a lit top edge
// and a low-key halo in the format hue, so colour stays clean, never muddy.
// The Tension Seal mark itself is never reproduced, traced or recoloured.
import { Svg, FONT, tier, pagePath, flapPath, rrect, pts, f, mix, labelSize } from './lib/core.mjs';
import { HUE, BRAND } from './lib/formats.mjs';
import { placeMini, MINI } from './lib/mini.mjs';

const PAGE = { L: 176, T: 72, R: 848, B: 952, r: 40, F: 196 };
const SPINE = 132;
const BRASS = { hi: '#F4E2B8', mid: '#CDA66C', lo: '#8C6538' };
const IVORY = '#F5E9DE';

export const SURFACES = {
  aubergine: { name: 'Aubergine', pageHi: '#4C2C3F', pageLo: '#1E111A', spineHi: '#21121A', spineLo: '#0C060A', flapHi: '#835670', flapLo: '#47293B', rim: '#F2C9DA' },
};

// Brighter ribbon body for dark grounds: never ends in the hue's darkest tone.
const ribbon = (s, h, y0 = -220, y1 = 220) => s.lin([[0, mix(h.light, '#ffffff', 0.5)], [0.4, h.light], [1, mix(h.base, h.light, 0.15)]], 0, y0, 0, y1);
const lift = (s) => s.shadow([[0, 10, 16, '#000000', 0.5], [0, 2, 2, '#000000', 0.35]]);
const brass = (s, y0, y1) => s.lin([[0, BRASS.hi], [0.5, BRASS.mid], [1, BRASS.lo]], 0, y0, 0, y1);

export const GLYPHS = {
  zip(s, h) {
    // Two ribbon tapes closed by tightly interlocking teeth, a brass slider,
    // and the tapes parting below it: unmistakably a zip, in ribbon material.
    const tooth = s.lin([[0, mix(h.light, '#ffffff', 0.5)], [0.5, h.light], [1, mix(h.base, h.light, 0.2)]], 0, -12, 0, 12);
    const tape = s.lin([[0, mix(h.base, h.light, 0.45)], [1, h.base]], -80, 0, 80, 0);
    let o = `<g filter="${lift(s)}">`;
    o += `<path d="M-60,-224 V30 L-150,214 M60,-224 V30 L150,214" stroke="${tape}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
    // Meshing chain: alternate teeth from each tape, overlapping at the centre.
    for (let i = 0; i < 13; i++) {
      const y = -214 + i * 19, left = i % 2 === 0;
      o += `<g transform="translate(0,${y})"><rect x="${left ? -64 : -12}" y="-9.5" width="76" height="19" rx="9" fill="${tooth}" stroke="${mix(h.base, h.dark, 0.3)}" stroke-opacity="0.45" stroke-width="2"/></g>`;
    }
    const open = (side) => {
      let t = '';
      for (let i = 0; i < 4; i++) {
        const y = 104 + i * 30, x = side * (82 + i * 14.5);
        t += `<rect x="${f(x - 30)}" y="${y - 8}" width="60" height="16" rx="8" fill="${tooth}" transform="rotate(${side * 26} ${f(x)} ${y})"/>`;
      }
      return t;
    };
    o += open(-1) + open(1) + `</g>`;
    o += `<g filter="${lift(s)}"><path d="M-62,14 H62 Q74,14 70,26 L56,78 Q53,88 42,88 H-42 Q-53,88 -56,78 L-70,26 Q-74,14 -62,14 Z" fill="${brass(s, 14, 88)}"/>`;
    o += `<path d="${rrect(-22, 58, 44, 128, 22)} M0,156 m-10,0 a10,10 0 1 0 20,0 a10,10 0 1 0 -20,0" fill-rule="evenodd" fill="${brass(s, 58, 186)}"/>`;
    o += `<path d="M-48,24 H48" stroke="#ffffff" stroke-opacity="0.6" stroke-width="5" stroke-linecap="round"/></g>`;
    return o;
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
    // Three pressed layers seen in oblique depth: a dense, solid block.
    const W = 300, T = 54, D = 52, G = 12;
    let o = `<g filter="${lift(s)}">`;
    [0, 1, 2].forEach((i) => {
      const t = i / 2, dx = [-8, 10, -6][i];
      const yb = 126 - i * (T + G), x0 = -176 + dx, x1 = x0 + W, yt = yb - T;
      const top = mix(h.light, '#ffffff', 0.42 - 0.22 * t), front = mix(h.base, h.light, 0.4 - 0.25 * t), side = mix(h.base, h.dark, 0.15 + 0.2 * t);
      const join = 'stroke-linejoin="round" stroke-width="10"';
      o += `<polygon points="${pts([[x1, yt], [x1 + D, yt - D], [x1 + D, yb - D], [x1, yb]])}" fill="${side}" stroke="${side}" ${join}/>`;
      o += `<polygon points="${pts([[x0, yt], [x1, yt], [x1, yb], [x0, yb]])}" fill="${s.lin([[0, front], [1, mix(front, h.dark, 0.35)]], 0, yt, 0, yb)}" stroke="${front}" ${join}/>`;
      o += `<polygon points="${pts([[x0, yt], [x0 + D, yt - D], [x1 + D, yt - D], [x1, yt]])}" fill="${top}" stroke="${top}" ${join}/>`;
      o += `<path d="M${x0 + 18},${yt + 12} H${x1 - 18}" stroke="#ffffff" stroke-opacity="0.35" stroke-width="4" stroke-linecap="round"/>`;
    });
    return `<g transform="translate(-20,30)">${o}</g></g>`;
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
function finish(s, P, S, { d, clip }, back = 0, tint = null) {
  const fl = flapPath(P);
  const hi = tint ? mix(S.flapHi, tint, 0.42) : S.flapHi, lo = tint ? mix(S.flapLo, tint, 0.3) : S.flapLo;
  let o = `<g clip-path="${clip}"><path d="${fl}" transform="translate(-8,12)" fill="#000000" opacity="0.5" filter="${s.blur(10)}"/>` +
    `<path d="${fl}" fill="${s.lin([[0, back ? mix(hi, '#000000', 0.2) : hi], [1, lo]], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/>`;
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
      // Dedicated 16/32 pt artwork: a slightly brighter sheet and a firmer
      // rose rim than the large icons, so the silhouette holds on dark Finder
      // backgrounds; narrower spine to give the glyph room.
      const xs = t === 'xs';
      const P = xs ? { L: 192, T: 64, R: 832, B: 960, r: 64, F: 224, rc: 0 } : { L: 176, T: 64, R: 848, B: 960, r: 48, F: 208, rc: 8 };
      const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
      const sw = xs ? 128 : 136, seam = xs ? 44 : 36;
      let o = '';
      if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="${mix(S.flapLo, '#ffffff', 0.08)}" stroke="${S.rim}" stroke-opacity="0.5" stroke-width="36"/>`;
      const d = pagePath(Q);
      o += `<path d="${d}" fill="${s.lin([[0, mix(S.pageHi, '#ffffff', 0.16)], [1, mix(S.pageLo, '#ffffff', 0.07)]], 0, Q.T, 0, Q.B)}"/>`;
      o += `<g clip-path="${s.clip(d)}"><rect x="${Q.L}" y="${Q.T}" width="${sw}" height="${Q.B - Q.T}" fill="${s.lin([[0, S.spineHi], [1, S.spineLo]], 0, Q.T, 0, Q.B)}"/>` +
        `<rect x="${Q.L + sw}" y="${Q.T}" width="${seam}" height="${Q.B - Q.T}" fill="${BRASS.mid}"/></g>`;
      o += `<path d="${d}" fill="none" stroke="${S.rim}" stroke-opacity="${xs ? 0.78 : 0.6}" stroke-width="${xs ? 40 : 28}"/>`;
      o += `<path d="${flapPath(Q, 0)}" fill="${isTar ? mix(S.flapHi, h.base, 0.55) : mix(S.flapHi, '#ffffff', 0.12)}" stroke="${S.rim}" stroke-opacity="0.55" stroke-width="${xs ? 30 : 22}" stroke-linejoin="round"/>`;
      const ink = { fill: mix(h.base, h.light, 0.5), light: mix(h.light, '#ffffff', 0.45), dark: h.base };
      const tarInk = { fill: HUE.tar.light, light: h.light, dark: h.base };
      const cx = Q.L + sw + seam + (Q.R - Q.L - sw - seam) / 2;
      if (xs) {
        o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? tarInk : ink, cx + 4, 548, isTar ? 46 : 48);
      } else {
        o += `<circle cx="${Q.L + sw / 2}" cy="430" r="46" fill="${BRASS.mid}"/><circle cx="${Q.L + sw / 2}" cy="430" r="34" fill="${BRAND.jadeHi}"/>`;
        if (isTar) {
          o += placeMini('tar', tarInk, cx - 56, 392, 30);
          o += `<circle cx="${cx + 118}" cy="568" r="118" fill="${S.spineLo}" stroke="${h.light}" stroke-width="22"/>`;
          o += placeMini(fmt.motif, ink, cx + 118, 568, 16);
        } else o += placeMini(fmt.motif, ink, cx, 420, 36);
        const lab = fmt.short;
        o += `<text x="${cx}" y="900" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(labelSize(lab, Q.R - Q.L - sw - seam - 50, 236))}" fill="${IVORY}">${lab}</text>`;
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
      art += `<g transform="translate(${cx - 62},400) scale(0.62)">${GLYPHS.tar(s, HUE.tar)}</g>`;
      // compressor emblem: a lacquer medallion in a brass bezel, ringed in the compressor hue
      art += `<g transform="translate(${cx + 108},584)"><circle r="146" fill="${s.rad([[0, h.base, 0.30], [1, h.base, 0]], 0, 0, 146)}"/>` +
        `<circle r="134" fill="${s.lin([[0, mix(S.pageHi, '#ffffff', 0.1)], [1, S.spineLo]], 0, -134, 0, 134)}" filter="${s.shadow([[0, 10, 20, '#000000', 0.5], [0, 1, 2, '#000000', 0.4]])}"/>` +
        `<circle r="133" fill="none" stroke="${brass(s, -133, 133)}" stroke-width="4"/><circle r="118" fill="none" stroke="${h.light}" stroke-opacity="0.95" stroke-width="9"/><g transform="scale(0.45)">${GLYPHS[fmt.motif](s, h)}</g></g>`;
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
    o += finish(s, P, S, sh, 0, isTar ? h.base : null);
    const big = t === 'm';
    const size = labelSize(fmt.label, P.R - P.L - SPINE - (big ? 70 : 120), big ? 210 : isTar ? 120 : 150, 0.04);
    const txt = isTar && fmt.label.includes('.') ? `<tspan fill="${IVORY}">${fmt.label.split('.')[0]}</tspan><tspan fill="${mix(h.light, '#ffffff', 0.1)}">.${fmt.label.split('.')[1]}</tspan>` : fmt.label;
    o += `<text x="${cx}" y="872" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}" fill="${IVORY}">${txt}</text>`;
    if (isSplit && !big) o += `<text x="${cx}" y="712" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="40" letter-spacing="10" fill="${IVORY}" opacity="0.55">VOLUME</text>`;
    return s.wrap(o, px);
  };
}

export default makeSealDark('aubergine');
