// Direction B — "Strata": a tinted glass document card holding a dimensional
// porcelain archive object. Objects are real polyhedra (procedural 3-D, iso
// projection, facet lighting) so depth is consistent across the family.
import { Svg, FONT, tier, pagePath, flapPath, rrect, polygon, pts, f, mix, labelSize } from '../lib/core.mjs';
import { HUE } from '../lib/formats.mjs';
import { placeMini } from '../lib/mini.mjs';

const CARD = { L: 168, T: 64, R: 856, B: 960, r: 72, F: 176, rc: 22 };
const PORC = '#F5F0EA';

// ---------- tiny polyhedron engine ----------
const LIGHT = (() => { const v = [0.25, 0.55, 1]; const n = Math.hypot(...v); return v.map((x) => x / n); })();
const sub = (a, b) => a.map((v, i) => v - b[i]);
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (v) => { const n = Math.hypot(...v) || 1; return v.map((x) => x / n); };
const proj = ([x, y, z]) => [(x - y) * 0.8660254, (x + y) * 0.5 - z];

function normalOf(poly) {
  let n = [0, 0, 0];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    n = [n[0] + (a[1] - b[1]) * (a[2] + b[2]), n[1] + (a[2] - b[2]) * (a[0] + b[0]), n[2] + (a[0] - b[0]) * (a[1] + b[1])];
  }
  return norm(n);
}
// faces: { p: [[x,y,z]...] (CCW seen from outside), c: color, gloss?, flat? }
function shadeColor(c, n, k = 1) {
  const d = Math.max(0, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]);
  const b = 0.34 + 0.66 * d;
  return b > 0.8 ? mix(c, '#ffffff', (b - 0.8) * 1.2 * k) : mix(c, '#140b10', (0.8 - b) * 0.75 * k);
}
function prism(poly, z0, z1, c, { top = c, sides = c } = {}) {
  const faces = [];
  faces.push({ p: poly.map(([x, y]) => [x, y, z1]), c: top });
  faces.push({ p: [...poly].reverse().map(([x, y]) => [x, y, z0]), c: sides });
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    faces.push({ p: [[a[0], a[1], z0], [b[0], b[1], z0], [b[0], b[1], z1], [a[0], a[1], z1]], c: sides });
  }
  return faces;
}
const box = (x0, y0, z0, x1, y1, z1, c, opts) => prism([[x0, y0], [x1, y0], [x1, y1], [x0, y1]], z0, z1, c, opts);
const circle = (r, n = 64, cx = 0, cy = 0) => Array.from({ length: n }, (_, i) => [cx + r * Math.cos((i / n) * 2 * Math.PI), cy + r * Math.sin((i / n) * 2 * Math.PI)]);
// Extrude a 2-D outline drawn in the (x, z) plane through y ∈ [y0, y1].
function extrudeXZ(poly, y0, y1, c, { front = c } = {}) {
  const faces = [{ p: poly.map(([x, z]) => [x, y1, z]).reverse(), c: front }, { p: poly.map(([x, z]) => [x, y0, z]), c }];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    faces.push({ p: [[a[0], y1, a[1]], [b[0], y1, b[1]], [b[0], y0, b[1]], [a[0], y0, a[1]]], c });
  }
  return faces;
}

// groups are drawn in order; faces inside a group are depth sorted.
function renderGroups(groups) {
  const out = [];
  for (const g of groups) {
    const vis = g.filter((fc) => {
      fc.n = normalOf(fc.p);
      return fc.n[0] + fc.n[1] + fc.n[2] > 1e-6;
    });
    vis.forEach((fc) => { fc.depth = fc.p.reduce((s, q) => s + q[0] + q[1] + q[2] * 0.9, 0) / fc.p.length; });
    vis.sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || a.depth - b.depth);
    out.push(...vis.map((fc) => ({ ...fc, s: fc.p.map(proj) })));
  }
  return out;
}
function drawFaces(faces) {
  return faces.map((fc) => {
    const col = fc.flat ? fc.c : shadeColor(fc.c, fc.n, fc.k ?? 1);
    return `<polygon points="${pts(fc.s)}" fill="${col}" stroke="${col}" stroke-width="1.2" stroke-linejoin="round"${fc.op ? ` opacity="${fc.op}"` : ''}/>`;
  }).join('');
}
function fit(faces, cx, cy, maxW, maxH, maxScale = 1.4) {
  const all = faces.flatMap((fc) => fc.s);
  const xs = all.map((p) => p[0]), ys = all.map((p) => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  const k = Math.min(maxW / (x1 - x0), maxH / (y1 - y0), maxScale);
  return { k, tx: cx - ((x0 + x1) / 2) * k, ty: cy - ((y0 + y1) / 2) * k, bottom: cy + ((y1 - y0) / 2) * k, w: (x1 - x0) * k };
}

// ---------- objects ----------
export const OBJECTS = {
  zip(h) {
    const S = 125, H = 230, g1 = [], g2 = [];
    g1.push(...box(-S, -S, 0, S, S, H, PORC));
    for (let i = 0; i < 10; i++) {
      const y = -S + 6 + i * 24, l = i % 2 === 0;
      g2.push(...box(l ? -18 : -4, y, H, l ? 4 : 18, y + 13, H + 7, h.base));
    }
    for (let i = 0; i < 6; i++) {
      const z = H - 30 - i * 24, l = i % 2 === 0;
      g2.push(...box(l ? -18 : -4, S, z, l ? 4 : 18, S + 7, z + 13, h.base));
    }
    const sl = box(-26, S - 22, H - 6, 26, S + 16, H + 26, h.light);
    const pull = box(-13, S + 16, 62, 13, S + 24, H - 4, h.base);
    return [g1, g2, [...sl, ...pull]];
  },
  '7z'(h) {
    const P = (r) => polygon(7, 0, 0, r, -90 + 45);
    return [
      prism(P(150), 0, 172, h.dark),
      prism(P(166), 0, 52, PORC),
      prism(P(166), 60, 112, h.base),
      prism(P(166), 120, 172, PORC),
      [{ p: P(98).map(([x, y]) => [x, y, 172.5]), c: h.base }, { p: P(44).map(([x, y]) => [x, y, 173]), c: PORC, order: 1 }],
    ];
  },
  rar(h) {
    const S = 150, T = 58, G = 12;
    return [
      box(-S, -S, 0, S, S, T, h.dark),
      box(-S, -S, T + G, S, S, 2 * T + G, h.base),
      box(-S, -S, 2 * (T + G), S, S, 3 * T + 2 * G, PORC),
      [{ p: [[-96, -96, 3 * T + 2 * G + 0.5], [96, -96, 3 * T + 2 * G + 0.5], [96, 96, 3 * T + 2 * G + 0.5], [-96, 96, 3 * T + 2 * G + 0.5]], c: h.light, k: 0.6 },
       { p: [[-70, -70, 3 * T + 2 * G + 1], [70, -70, 3 * T + 2 * G + 1], [70, 70, 3 * T + 2 * G + 1], [-70, 70, 3 * T + 2 * G + 1]], c: PORC, order: 1 }],
    ];
  },
  tar(h, tape = HUE.tar) {
    const R = 178, r = 152;
    const t = norm([1, -1, 0]), p0 = [r * 0.7071, r * 0.7071];
    const strand = [];
    const len = 250;
    const a = [p0[0], p0[1]], b = [p0[0] + t[0] * len, p0[1] + t[1] * len];
    strand.push({ p: [[a[0], a[1], 18], [b[0], b[1], 18], [b[0], b[1], 80], [a[0], a[1], 80]], c: tape.base });
    const windows = polygon(5, 0, 0, 112, -45).map(([x, y]) => ({ p: circle(34, 28, x, y).map(([u, v]) => [u, v, 96.5]), c: tape.dark, k: 0.7 }));
    return [
      prism(circle(R), 0, 16, PORC),
      prism(circle(r), 16, 80, tape.dark),
      strand,
      prism(circle(R), 80, 96, PORC),
      windows,
      prism(circle(38, 32), 96, 116, tape.base),
    ];
  },
  gz(h) {
    const groups = [box(-150, -150, 0, 150, 150, 36, PORC)];
    let z = 36;
    for (let i = 0; i < 7; i++) {
      const s = i % 2 ? 108 : 130;
      groups.push(box(-s, -s, z, s, s, z + 20, i % 2 ? h.dark : h.base));
      z += 20;
    }
    groups.push(box(-150, -150, z, 150, 150, z + 36, PORC));
    groups.push([{ p: [[-40, -110, z + 36.5], [40, -110, z + 36.5], [40, 110, z + 36.5], [-40, 110, z + 36.5]], c: h.base, k: 0.5 }]);
    return groups;
  },
  bz2(h) {
    const u = 112, g = 10, groups = [];
    const heights = [3, 2, 1];
    for (let c = 0; c < 3; c++) {
      for (let k = 0; k < heights[c]; k++) {
        const x0 = c * u - 1.5 * u, z0 = k * u;
        const top = k === heights[c] - 1;
        const fc = box(x0, -u / 2, z0, x0 + u - g, u / 2 - g, z0 + u - g, PORC);
        if (top) fc[0].c = mix(h.light, h.base, c / 2);
        groups.push(fc);
      }
    }
    return groups;
  },
  xz(h) {
    // elongated octahedron, rotated so three upper facets catch light differently
    const H = 220, A = 150, top = [0, 0, 2 * H], bot = [0, 0, 0];
    const eq = [0, 90, 180, 270].map((d) => { const a = ((d + 20) * Math.PI) / 180; return [A * Math.cos(a), A * Math.sin(a), H]; });
    const faces = [];
    for (let i = 0; i < 4; i++) {
      const a = eq[i], b = eq[(i + 1) % 4];
      faces.push({ p: [a, b, top], c: h.light });
      faces.push({ p: [b, a, bot], c: h.base });
    }
    // inner table facet for a cut-gem sparkle
    return [faces, [{ p: [[0, 0, 2 * H], eq[0], eq[1]].map(([x, y, z]) => [x * 0.45, y * 0.45, z + (2 * H - z) * 0.55]), c: '#ffffff', k: 0.4, op: 0.55, order: 1 }]];
  },
  zst(h) {
    const Z = [[-120, 190], [150, 190], [150, 130], [-30, -60], [140, -60], [140, -120], [-150, -120], [-150, -60], [30, 130], [-120, 130]]
      .map(([x, z]) => [x + z * 0.18, z + 120]);
    const streaks = [[-300, 278, 120], [-330, 160, 150], [-300, 30, 100]].map(([x, z, w]) => box(x, 30, z, x + w, 46, z + 18, h.light));
    return [...streaks, extrudeXZ(Z, -46, 46, h.dark, { front: h.base })];
  },
};

function card(s, P, h, { glowY = 470 } = {}) {
  const d = pagePath(P);
  const clip = s.clip(d);
  let o = `<g filter="${s.shadow([[0, 14, 28, '#120a0e', 0.26], [0, 2, 3, '#120a0e', 0.28]])}"><path d="${d}" fill="${s.lin([[0, mix(h.base, h.light, 0.18)], [0.55, h.base], [1, mix(h.dark, '#000000', 0.12)]], 300, P.T, 720, P.B)}"/></g>`;
  o += `<g clip-path="${clip}">`;
  o += `<circle cx="512" cy="${glowY}" r="380" fill="${s.rad([[0, mix(h.light, '#ffffff', 0.3), 0.55], [0.6, h.light, 0.12], [1, h.light, 0]], 512, glowY, 380)}"/>`;
  o += `<rect x="${P.L}" y="${P.B - 260}" width="${P.R - P.L}" height="260" fill="${s.lin([[0, '#000000', 0], [1, '#000000', 0.22]], 0, P.B - 260, 0, P.B)}"/>`;
  o += `</g>`;
  return { o, clip, d };
}
function cardFinish(s, P, h) {
  const d = pagePath(P), fl = flapPath(P, 30), clip = s.clip(d);
  return `<g clip-path="${clip}"><path d="${fl}" transform="translate(-8,12)" fill="#000" opacity="0.28" filter="${s.blur(10)}"/>` +
    `<path d="${fl}" fill="${s.lin([[0, mix(h.light, '#ffffff', 0.7)], [1, mix(h.light, h.base, 0.35)]], P.R - P.F / 2, P.T + P.F / 2, P.R - P.F, P.T + P.F)}"/></g>` +
    `<path d="${d}" fill="none" stroke="${s.lin([[0, '#ffffff', 0.7], [0.3, '#ffffff', 0.18], [1, '#ffffff', 0.08]], 0, P.T, 0, P.B)}" stroke-width="5" clip-path="${clip}"/>` +
    `<path d="${d}" fill="none" stroke="${mix(h.dark, '#000000', 0.35)}" stroke-opacity="0.45" stroke-width="2.5"/>`;
}

export default function strata(fmt, px, pt = px) {
  const s = new Svg();
  const h = HUE[fmt.hue], t = tier(pt);
  const isSplit = fmt.kind === 'split', isTar = fmt.kind === 'tar';

  if (t === 'xs' || t === 's') {
    const P = t === 'xs' ? { L: 192, T: 64, R: 832, B: 960, r: 96, F: 224, rc: 0 } : { L: 176, T: 64, R: 848, B: 960, r: 80, F: 208, rc: 10 };
    const Q = isSplit ? { ...P, L: P.L - 32, R: P.R - 64, T: P.T + 64 } : P;
    let o = '';
    if (isSplit) o += `<path d="${pagePath({ ...Q, L: Q.L + 64, R: Q.R + 64, T: Q.T - 64, B: Q.B - 64 })}" fill="${h.dark}" opacity="0.7"/>`;
    o += `<path d="${pagePath(Q)}" fill="${s.lin([[0, mix(h.base, h.light, 0.2)], [1, h.dark]], 0, Q.T, 0, Q.B)}" stroke="${mix(h.dark, '#000000', 0.3)}" stroke-opacity="0.6" stroke-width="${t === 'xs' ? 36 : 24}"/>`;
    o += `<path d="${flapPath(Q, 0)}" fill="${mix(h.light, '#ffffff', 0.5)}"/>`;
    const ink = { fill: '#FFFFFF', light: mix(h.light, '#ffffff', 0.55), dark: mix(h.light, '#ffffff', 0.15) };
    const cx = (Q.L + Q.R) / 2;
    if (t === 'xs') {
      o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { ...ink, dark: h.dark } : ink, cx, 548, 54);
    } else {
      o += placeMini(isTar ? 'tar' : fmt.motif, isTar ? { ...ink, dark: h.dark } : ink, cx, 420, 38);
      const lab = fmt.short;
      o += `<text x="${cx}" y="896" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="${f(labelSize(lab, Q.R - Q.L - 110, 240))}" fill="#ffffff">${lab}</text>`;
    }
    return s.wrap(o, px);
  }

  const P = isSplit ? { ...CARD, L: 140, R: 790, T: 124 } : CARD;
  const cx = (P.L + P.R) / 2;
  let o = '';
  if (isSplit) {
    for (let i = 2; i >= 1; i--) {
      const Q = { ...P, L: P.L + i * 28, R: P.R + i * 28, T: P.T - i * 28, B: P.B - i * 28 };
      o += `<path d="${pagePath(Q)}" fill="${mix(h.dark, '#000000', 0.1 * i)}" stroke="${mix(h.light, '#ffffff', 0.3)}" stroke-opacity="0.35" stroke-width="3" filter="${s.shadow([[0, 6, 12, '#000000', 0.2]])}"/>`;
    }
  }
  const c = card(s, P, h, { glowY: isSplit ? 420 : 450 });
  o += c.o;
  const groups = isTar ? OBJECTS.tar(h, h) : OBJECTS[fmt.motif](h);
  const faces = renderGroups(groups);
  const fitBox = isSplit ? fit(faces, cx, 380, 420, 380) : fit(faces, cx, 450, 470, 450);
  // contact shadow
  o += `<g clip-path="${c.clip}"><ellipse cx="${cx}" cy="${f(fitBox.bottom - 10)}" rx="${f(fitBox.w * 0.42)}" ry="40" fill="#000" opacity="0.32" filter="${s.blur(18)}"/>`;
  o += `<g transform="translate(${f(fitBox.tx)},${f(fitBox.ty)}) scale(${f(fitBox.k)})">${drawFaces(faces)}</g></g>`;
  o += cardFinish(s, P, h);
  const big = t === 'm';
  if (isSplit) {
    const n = 4, w = 70, gap = 14, total = n * w + (n - 1) * gap;
    for (let i = 0; i < n; i++) {
      const x = cx - total / 2 + i * (w + gap);
      o += i === 0 ? `<rect x="${x}" y="660" width="${w}" height="20" rx="10" fill="#ffffff"/>` : `<rect x="${x + 2}" y="662" width="${w - 4}" height="16" rx="8" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="4"/>`;
    }
  }
  const size = labelSize(fmt.label, P.R - P.L - (big ? 70 : 150), big ? 230 : isTar ? 136 : 156, 0.06);
  o += `<text x="${cx}" y="${isSplit ? 872 : 868}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${f(size)}" letter-spacing="${f(size * 0.06)}" fill="#ffffff" filter="${s.shadow([[0, 3, 6, '#000000', 0.25]])}">${fmt.label}</text>`;
  return s.wrap(o, px);
}
