// Direction A — "Folio": native macOS paper document carrying a refined,
// format-specific illustration. Calm, Finder-native, closest to Apple's own
// document language; identity comes from the illustration and its hue.
import { Svg, FONT, tier, pagePath, flapPath, rrect, polygon, roundPoly, pts, f, mix, iso, labelSize } from '../lib/core.mjs';
import { HUE } from '../lib/formats.mjs';
import { placeMini } from '../lib/mini.mjs';

const PAGE = { L: 176, T: 72, R: 848, B: 952, r: 40, F: 200 };

// ---------- full-size illustrations (local coords, roughly ±230) ----------
export const GLYPHS = {
  zip(s, h) {
    const tape = s.lin([[0, h.light, 0.55], [1, h.light, 0.25]], 0, -400, 0, 90);
    const toothL = s.lin([[0, h.dark], [0.55, h.base], [1, h.light]], -66, 0, 10, 0);
    const toothR = s.lin([[0, h.dark], [0.55, h.base], [1, h.light]], 66, 0, -10, 0);
    const metal = s.lin([[0, h.light], [0.45, h.base], [1, h.dark]], 0, -10, 0, 120);
    const shade = s.shadow([[0, 6, 10, '#3a2210', 0.28]]);
    let o = `<path d="M-118,-420 H118 V40 L60,96 H-60 L-118,40 Z" fill="${tape}"/>`;
    let teeth = '';
    for (let i = 0; i < 12; i++) {
      const y = -420 + i * 38;
      teeth += `<rect x="-66" y="${y}" width="76" height="24" rx="10" fill="${toothL}"/>`;
      teeth += `<rect x="-10" y="${y + 19}" width="76" height="24" rx="10" fill="${toothR}"/>`;
    }
    // Open section: two tooth rows diverging below the slider.
    const open = (side) => {
      let t = '';
      for (let i = 0; i < 4; i++) {
        const y = 118 + i * 38, x = side * (40 + i * 26);
        t += `<rect x="${f(x - 30)}" y="${y}" width="60" height="24" rx="10" fill="${side < 0 ? toothL : toothR}" transform="rotate(${side * -14} ${f(x)} ${y + 12})"/>`;
      }
      return t;
    };
    o += `<g filter="${shade}">${teeth}${open(-1)}${open(1)}</g>`;
    // slider + pull tab
    o += `<g filter="${s.shadow([[0, 10, 18, '#3a2210', 0.32], [0, 2, 3, '#3a2210', 0.25]])}">`;
    o += `<path d="${roundPoly([[-74, 6], [74, 6], [54, 104], [-54, 104]], 22)}" fill="${metal}"/>`;
    o += `<path d="${rrect(-30, 70, 60, 168, 30)} M0,186 m-14,0 a14,14 0 1 0 28,0 a14,14 0 1 0 -28,0" fill-rule="evenodd" fill="${metal}"/>`;
    o += `<path d="M-50,22 H50" stroke="${h.light}" stroke-width="6" stroke-linecap="round" opacity="0.8"/></g>`;
    return o;
  },
  '7z'(s, h) {
    // Heptagonal rosette: seven petals around a heptagonal core.
    let o = '';
    const shade = s.shadow([[0, 12, 22, '#0d3a2f', 0.30], [0, 2, 3, '#0d3a2f', 0.22]]);
    const outer = roundPoly(polygon(7, 0, 8, 222), 34);
    o += `<g filter="${shade}"><path d="${outer}" fill="${s.lin([[0, h.base], [1, h.dark]], 0, -220, 0, 230)}"/></g>`;
    const P = polygon(7, 0, 8, 196), C = polygon(7, 0, 8, 96);
    for (let i = 0; i < 7; i++) {
      const a = P[i], b = P[(i + 1) % 7], c = C[(i + 1) % 7], d = C[i];
      const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2 - 8;
      const lit = 0.5 + 0.5 * Math.cos(Math.atan2(my, mx) - Math.atan2(-1, -0.6));
      o += `<path d="${roundPoly([a, b, c, d], 16)}" fill="${mix(h.dark, h.light, 0.18 + lit * 0.72)}" stroke="${mix(h.dark, '#000000', 0.1)}" stroke-opacity="0.25" stroke-width="3"/>`;
    }
    o += `<path d="${roundPoly(polygon(7, 0, 8, 82), 14)}" fill="${s.lin([[0, '#ffffff', 0.95], [1, h.light]], 0, -80, 0, 90)}"/>`;
    o += `<path d="${roundPoly(polygon(7, 0, 8, 40), 8)}" fill="${h.base}" opacity="0.9"/>`;
    return o;
  },
  rar(s, h) {
    // Three dense slabs: a compact, layered solid block.
    const P = iso(0, -88, 1);
    const w = 132, t = 46, gap = 20;
    let o = '';
    const sh = s.shadow([[0, 16, 26, '#2b0a19', 0.30], [0, 3, 4, '#2b0a19', 0.22]]);
    for (let k = 2; k >= 0; k--) {
      const z = (2 - k) * (t + gap);
      const top = [[-w, -w, z + t], [w, -w, z + t], [w, w, z + t], [-w, w, z + t]].map(P);
      const bot = [[-w, -w, z], [w, -w, z], [w, w, z], [-w, w, z]].map(P);
      const shadeT = k === 0 ? 0 : k === 1 ? 0.25 : 0.45;
      const sideL = [bot[3], bot[2], top[2], top[3]], sideR = [bot[2], bot[1], top[1], top[2]];
      o += `<g filter="${k === 2 ? sh : 'none'}">`;
      o += `<path d="${roundPoly(sideL, 8)}" fill="${mix(h.base, h.dark, 0.15 + shadeT * 0.3)}"/>`;
      o += `<path d="${roundPoly(sideR, 8)}" fill="${mix(h.base, h.dark, 0.6 + shadeT * 0.3)}"/>`;
      o += `<path d="${roundPoly(top, 26)}" fill="${s.lin([[0, mix(h.light, '#ffffff', 0.35 - shadeT * 0.4)], [1, mix(h.light, h.base, 0.35 + shadeT)]], -60, top[0][1], 60, top[2][1])}"/>`;
      o += `</g>`;
    }
    // embossed ridge on the top slab
    const top = [[-w * 0.55, -w * 0.55, 2 * (t + gap) + t], [w * 0.55, -w * 0.55, 2 * (t + gap) + t], [w * 0.55, w * 0.55, 2 * (t + gap) + t], [-w * 0.55, w * 0.55, 2 * (t + gap) + t]].map(P);
    o += `<path d="${roundPoly(top, 16)}" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="5"/>`;
    return `<g transform="translate(0,30)">${o}</g>`;
  },
  tar(s, h) {
    const id = s.id('m');
    const windows = polygon(5, 0, 0, 128).map(([x, y]) => `<circle cx="${f(x)}" cy="${f(y)}" r="44" fill="black"/>`).join('');
    s.defs.push(`<mask id="${id}" maskUnits="userSpaceOnUse" x="-300" y="-300" width="600" height="600"><circle r="212" fill="white"/>${windows}<circle r="58" fill="black"/></mask>`);
    let o = '';
    // tape strand exits beneath the reel and runs off the page
    o += `<path d="M0,152 H420 V198 H0 Z" fill="${s.lin([[0, h.dark], [1, h.base]], 0, 152, 0, 198)}"/>`;
    o += `<path d="M0,152 H420" stroke="${h.light}" stroke-width="4" opacity="0.6"/>`;
    // wound tape
    o += `<circle r="178" fill="${s.rad([[0, h.dark], [0.55, mix(h.dark, '#000000', 0.25)], [1, h.dark]], 0, 0, 180)}"/>`;
    for (let rr = 76; rr < 178; rr += 14) o += `<circle r="${rr}" fill="none" stroke="${h.light}" stroke-opacity="0.13" stroke-width="2"/>`;
    // flange
    o += `<g filter="${s.shadow([[0, 14, 24, '#0d1a33', 0.32], [0, 2, 3, '#0d1a33', 0.22]])}"><g mask="url(#${id})">`;
    o += `<circle r="212" fill="${s.lin([[0, mix(h.light, '#ffffff', 0.35)], [0.5, h.light], [1, h.base]], -150, -170, 150, 190)}"/>`;
    o += `<circle r="196" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="4"/>`;
    o += `</g></g>`;
    // hub
    o += `<circle r="44" fill="${s.lin([[0, '#ffffff'], [1, h.light]], 0, -44, 0, 44)}" stroke="${h.base}" stroke-width="6"/>`;
    o += polygon(6, 0, 0, 30).map(([x, y]) => `<circle cx="${f(x)}" cy="${f(y)}" r="5" fill="${h.base}"/>`).join('');
    return o;
  },
  gz(s, h) {
    const plate = s.lin([[0, h.light], [0.5, h.base], [1, h.dark]], 0, -30, 0, 30);
    const sh = s.shadow([[0, 10, 18, '#3a120a', 0.30], [0, 2, 3, '#3a120a', 0.2]]);
    let o = `<g filter="${sh}">`;
    // bellows: alternating pleats between two plates
    const n = 7, y0 = -128, y1 = 128, step = (y1 - y0) / n;
    for (let i = 0; i < n; i++) {
      const ya = y0 + i * step, yb = ya + step;
      const wa = i % 2 ? 142 : 176, wb = i % 2 ? 176 : 142;
      const lit = i % 2 ? mix(h.base, h.dark, 0.35) : mix(h.light, h.base, 0.35);
      o += `<polygon points="${pts([[-wa, ya], [wa, ya], [wb, yb], [-wb, yb]])}" fill="${lit}"/>`;
    }
    o += `</g>`;
    o += `<g filter="${sh}">`;
    o += `<g transform="translate(0,-170)"><path d="${rrect(-200, -36, 400, 72, 28)}" fill="${plate}"/><path d="M-176,-24 H176" stroke="#fff" stroke-opacity="0.55" stroke-width="5" stroke-linecap="round"/></g>`;
    o += `<g transform="translate(0,170)"><path d="${rrect(-200, -36, 400, 72, 28)}" fill="${plate}"/><path d="M-176,-24 H176" stroke="#fff" stroke-opacity="0.55" stroke-width="5" stroke-linecap="round"/></g>`;
    o += `</g>`;
    // inward chevrons
    const chev = (y, dir) => `<polyline points="-34,${y - dir * 18} 0,${y + dir * 12} 34,${y - dir * 18}" fill="none" stroke="${h.base}" stroke-width="14" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"/>`;
    return chev(-252, 1) + o + chev(252, -1);
  },
  bz2(s, h) {
    const cells = [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2]];
    const u = 128, g = 18, sz = u - g, ox = -(3 * u - g) / 2, oy = (3 * u - g) / 2;
    let o = `<g filter="${s.shadow([[0, 12, 20, '#1c2208', 0.28], [0, 2, 3, '#1c2208', 0.2]])}">`;
    cells.forEach(([c, r], i) => {
      const x = ox + c * u, y = oy - (r + 1) * u + g;
      const t = i / (cells.length - 1);
      const top = mix(h.light, '#ffffff', 0.35 * (1 - t)), bot = mix(h.base, h.dark, 0.25 + 0.5 * (1 - t));
      o += `<path d="${rrect(x, y, sz, sz, 26)}" fill="${s.lin([[0, mix(top, h.base, 0.15 + 0.5 * (1 - t))], [1, bot]], 0, y, 0, y + sz)}"/>`;
      o += `<path d="${rrect(x + 10, y + 8, sz - 20, sz * 0.42, 18)}" fill="#ffffff" opacity="${0.10 + 0.12 * t}"/>`;
    });
    return o + `</g>`;
  },
  xz(s, h) {
    // Quartz crystal: dense, faceted, high-ratio.
    const A = [0, -238], yS = -112, yB = 196, xs = [-124, -42, 46, 126];
    const fac = [
      [[xs[0], yS], A, [xs[1], yS - 6]], [[xs[1], yS - 6], A, [xs[2], yS - 6]], [[xs[2], yS - 6], A, [xs[3], yS]],
      [[xs[0], yS], [xs[1], yS - 6], [xs[1], yB + 22], [xs[0], yB]],
      [[xs[1], yS - 6], [xs[2], yS - 6], [xs[2], yB + 22], [xs[1], yB + 22]],
      [[xs[2], yS - 6], [xs[3], yS], [xs[3], yB], [xs[2], yB + 22]],
    ];
    const tone = [0.95, 0.78, 0.42, 0.72, 0.50, 0.12];
    let o = `<g transform="rotate(-10)" filter="${s.shadow([[0, 14, 24, '#1a1040', 0.3], [0, 2, 3, '#1a1040', 0.22]])}">`;
    fac.forEach((p, i) => {
      const c = mix(h.dark, h.light, tone[i]);
      const top = Math.min(...p.map((q) => q[1])), bot = Math.max(...p.map((q) => q[1]));
      o += `<polygon points="${pts(p)}" fill="${s.lin([[0, mix(c, '#ffffff', 0.18)], [1, mix(c, h.dark, 0.2)]], 0, top, 0, bot)}" stroke="${mix(h.light, '#ffffff', 0.4)}" stroke-opacity="0.45" stroke-width="3" stroke-linejoin="round"/>`;
    });
    o += `<path d="M${xs[1] - 18},${yS + 40} L${xs[1] - 18},${yB - 30}" stroke="#ffffff" stroke-opacity="0.5" stroke-width="10" stroke-linecap="round"/>`;
    return o + `</g>`;
  },
  zst(s, h) {
    const g = s.lin([[0, h.light], [0.5, h.base], [1, h.dark]], -160, -180, 160, 200);
    const Z = [[-132, -196], [190, -196], [190, -116], [-24, 120], [168, 120], [168, 200], [-190, 200], [-190, 120], [30, -116], [-132, -116]];
    let o = `<g filter="${s.shadow([[0, 12, 22, '#06263a', 0.3], [0, 2, 3, '#06263a', 0.22]])}" transform="skewX(-10)">`;
    o += `<path d="${roundPoly(Z, 18)}" fill="${g}"/>`;
    o += `<path d="M-112,-172 H170" stroke="#ffffff" stroke-opacity="0.55" stroke-width="7" stroke-linecap="round"/></g>`;
    // speed streaks
    [[-238, -156, 64, 0.55], [-262, 2, 92, 0.4], [-236, 160, 58, 0.3]].forEach(([x, y, w, a]) => {
      o += `<path d="M${x},${y} h${w}" stroke="${h.base}" stroke-opacity="${a}" stroke-width="24" stroke-linecap="round"/>`;
    });
    return o;
  },
};

function paper(s, P, { hueTint } = {}) {
  const d = pagePath(P);
  const clip = s.clip(d);
  let o = `<g filter="${s.shadow([[0, 10, 24, '#1d1418', 0.20], [0, 1.5, 2.5, '#1d1418', 0.22]])}"><path d="${d}" fill="${s.lin([[0, '#FFFFFF'], [0.55, '#FBFAF8'], [1, '#F1EEEA']], 0, P.T, 0, P.B)}"/></g>`;
  if (hueTint) o += `<path d="${d}" fill="${s.lin([[0, hueTint, 0], [0.55, hueTint, 0], [1, hueTint, 0.10]], 0, P.T, 0, P.B)}"/>`;
  return { d, clip, base: o };
}
function fold(s, P) {
  const d = pagePath(P);
  const clip = s.clip(d);
  const fl = flapPath(P);
  return `<g clip-path="${clip}"><path d="${fl}" transform="translate(-7,11)" fill="#2a1e22" opacity="0.16" filter="${s.blur(9)}"/>` +
    `<path d="${fl}" fill="${s.lin([[0, '#FFFFFF'], [1, '#E3DED9']], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/></g>` +
    `<path d="${d}" fill="none" stroke="#3c2a32" stroke-opacity="0.16" stroke-width="3"/>`;
}

function label(s, text, { cx = 512, y, max, maxW, color, accent, split }) {
  const size = labelSize(text, maxW, max, 0.04);
  if (split && text.includes('.')) {
    const [a, b] = text.split('.');
    return `<text x="${cx}" y="${y}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}"><tspan fill="${color}">${a}</tspan><tspan fill="${accent}">.${b}</tspan></text>`;
  }
  return `<text x="${cx}" y="${y}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.04)}" fill="${color}">${text}</text>`;
}

const backPages = (s, P, n = 2) => {
  let o = '';
  for (let i = n; i >= 1; i--) {
    const Q = { ...P, L: P.L + i * 26, R: P.R + i * 26, T: P.T - i * 26, B: P.B - i * 26 };
    o += `<path d="${pagePath(Q)}" fill="${mix('#F6F3EF', '#D9D3CD', i / n * 0.6)}" stroke="#3c2a32" stroke-opacity="0.16" stroke-width="3" filter="${s.shadow([[0, 4, 10, '#1d1418', 0.14]])}"/>`;
  }
  return o;
};

const segments = (h, cx, y, active = 0, n = 4, w = 74, gap = 16) => {
  const total = n * w + (n - 1) * gap; let o = '';
  for (let i = 0; i < n; i++) {
    const x = cx - total / 2 + i * (w + gap);
    o += i === active
      ? `<rect x="${x}" y="${y}" width="${w}" height="22" rx="11" fill="${h.base}"/>`
      : `<rect x="${x + 2}" y="${y + 2}" width="${w - 4}" height="18" rx="9" fill="none" stroke="${h.base}" stroke-opacity="0.55" stroke-width="4"/>`;
  }
  return o;
};

export default function folio(fmt, px, pt = px) {
  const s = new Svg();
  const h = HUE[fmt.hue], t = tier(pt);
  const isSplit = fmt.kind === 'split', isTar = fmt.kind === 'tar';

  if (t === 'xs' || t === 's') {
    const P = t === 'xs'
      ? { L: 192, T: 64, R: 832, B: 960, r: 56, F: 224, rc: 0 }
      : { L: 176, T: 64, R: 848, B: 960, r: 48, F: 208, rc: 8 };
    const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
    let o = '';
    if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="#DCD6D0" stroke="#3c2a32" stroke-opacity="0.35" stroke-width="40"/>`;
    o += `<path d="${pagePath(Q)}" fill="${s.lin([[0, '#FFFFFF'], [1, '#F0EDE9']], 0, Q.T, 0, Q.B)}" stroke="#3c2a32" stroke-opacity="${t === 'xs' ? 0.42 : 0.30}" stroke-width="${t === 'xs' ? 48 : 32}"/>`;
    o += `<path d="${flapPath(Q, t === 'xs' ? 0 : 20)}" fill="#E2DDD8" stroke="#3c2a32" stroke-opacity="${t === 'xs' ? 0.42 : 0.3}" stroke-width="${t === 'xs' ? 40 : 28}" stroke-linejoin="round"/>`;
    const ink = { fill: h.base, light: h.light, dark: h.dark };
    const cx = (Q.L + Q.R) / 2;
    if (t === 'xs') {
      if (isTar) {
        o += placeMini(fmt.motif, ink, cx, 480, 52);
        o += `<rect x="${Q.L + 96}" y="800" width="${Q.R - Q.L - 192}" height="80" rx="20" fill="${HUE.tar.base}"/>`;
      } else o += placeMini(fmt.motif, ink, cx, 548, 54);
    } else {
      const lab = fmt.short;
      if (isTar) {
        o += placeMini(fmt.motif, ink, cx, 410, 34);
        o += `<rect x="${cx - 190}" y="618" width="380" height="40" rx="20" fill="${HUE.tar.base}"/>`;
      } else o += placeMini(fmt.motif, ink, cx, 420, 38);
      const fs = labelSize(lab, Q.R - Q.L - 96, 252);
      o += `<text x="${cx}" y="900" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(fs)}" fill="${h.ink}">${lab}</text>`;
    }
    return s.wrap(o, px);
  }

  // ---------- full size ----------
  const P = isSplit ? { ...PAGE, L: 150, R: 796, T: 124, B: 952 } : PAGE;
  const cx = (P.L + P.R) / 2;
  const pg = paper(s, P, { hueTint: h.base });
  let o = isSplit ? backPages(s, P) : '';
  o += pg.base;
  let art = '';
  if (isTar) {
    art += `<g transform="translate(${cx - 52},400) scale(0.76)">${GLYPHS.tar(s, HUE.tar)}</g>`;
    art += `<g transform="translate(${cx + 150},560)"><circle r="128" fill="#ffffff" filter="${s.shadow([[0, 8, 18, '#1d1418', 0.22], [0, 1, 2, '#1d1418', 0.2]])}"/>` +
      `<circle r="114" fill="none" stroke="${h.base}" stroke-width="8"/><g transform="scale(0.40)">${GLYPHS[fmt.motif](s, h)}</g></g>`;
  } else if (isSplit) {
    art += `<g transform="translate(${cx},${fmt.motif === 'zip' ? 330 : 380}) scale(${fmt.motif === 'zip' ? 0.74 : 0.7})">${GLYPHS[fmt.motif](s, h)}</g>`;
    art += segments(h, cx, 612, 0);
  } else {
    art += `<g transform="translate(${cx},${fmt.motif === 'zip' ? 410 : 440}) scale(${fmt.motif === 'zip' ? 0.95 : 0.9})">${GLYPHS[fmt.motif](s, h)}</g>`;
  }
  o += `<g clip-path="${pg.clip}">${art}</g>`;
  o += fold(s, P);
  const big = t === 'm';
  o += label(s, fmt.label, {
    cx, y: isSplit ? 872 : 866, max: big ? 230 : (isTar ? 150 : 168), maxW: P.R - P.L - (big ? 60 : 130),
    color: isTar ? HUE.tar.ink : h.ink, accent: h.base, split: isTar,
  });
  if (isSplit && !big) o += `<text x="${cx}" y="${700}" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="44" letter-spacing="10" fill="${h.ink}" opacity="0.65">VOLUME</text>`;
  return s.wrap(o, px);
}
