// Arkiv document-icon exploration — shared procedural SVG core.
// Every icon is authored on a 1024 × 1024 canvas (y grows downward) and is
// resolution independent. Small sizes use dedicated geometry (see `tier`).

export const FONT = "'SF Pro Display', -apple-system, 'Inter Display', Inter, 'Helvetica Neue', sans-serif";
export const FONT_ROUNDED = "'SF Pro Rounded', 'SF Pro Display', -apple-system, 'Inter Display', Inter, sans-serif";

// Size tiers: 16 px and 32 px get hand-tuned artwork, everything else the full design.
export const tier = (px) => (px <= 20 ? 'xs' : px <= 40 ? 's' : px <= 80 ? 'm' : 'l');

export const f = (n) => Number(n.toFixed(2));
export const pts = (list) => list.map(([x, y]) => `${f(x)},${f(y)}`).join(' ');

export class Svg {
  constructor() { this.defs = []; this.n = 0; }
  id(prefix) { return `${prefix}${++this.n}`; }
  stops(list) {
    return list.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('');
  }
  lin(list, x1, y1, x2, y2) {
    const id = this.id('lg');
    this.defs.push(`<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}">${this.stops(list)}</linearGradient>`);
    return `url(#${id})`;
  }
  rad(list, cx, cy, r, fx = cx, fy = cy) {
    const id = this.id('rg');
    this.defs.push(`<radialGradient id="${id}" gradientUnits="userSpaceOnUse" cx="${f(cx)}" cy="${f(cy)}" r="${f(r)}" fx="${f(fx)}" fy="${f(fy)}">${this.stops(list)}</radialGradient>`);
    return `url(#${id})`;
  }
  // Layered shadow: list of [dx, dy, blur, color, opacity].
  shadow(layers) {
    const id = this.id('sh');
    const parts = layers.map(([dx, dy, blur, color, op], i) =>
      `<feDropShadow in="SourceGraphic" dx="${dx}" dy="${dy}" stdDeviation="${blur / 2}" flood-color="${color}" flood-opacity="${op}" result="s${i}"/>`);
    // feDropShadow composites the source over its own shadow; merging the
    // results and the source once keeps multiple layers additive.
    const merge = layers.map((_, i) => `<feMergeNode in="s${i}"/>`).join('');
    this.defs.push(`<filter id="${id}" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">${parts.join('')}<feMerge>${merge}<feMergeNode in="SourceGraphic"/></feMerge></filter>`);
    return `url(#${id})`;
  }
  blur(sd) {
    const id = this.id('bl');
    this.defs.push(`<filter id="${id}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${sd}"/></filter>`);
    return `url(#${id})`;
  }
  clip(d) {
    const id = this.id('cp');
    this.defs.push(`<clipPath id="${id}"><path d="${d}"/></clipPath>`);
    return `url(#${id})`;
  }
  mask(content) {
    const id = this.id('mk');
    this.defs.push(`<mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">${content}</mask>`);
    return `url(#${id})`;
  }
  wrap(body, px = 1024) {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="${px}" height="${px}"><defs>${this.defs.join('')}</defs>${body}</svg>`;
  }
}

// macOS-style document page with a folded top-right corner.
export function pagePath({ L, T, R, B, r, F, rc = 14 }) {
  const k = rc * 0.7071;
  return [
    `M${L + r},${T}`, `H${R - F - rc}`, `Q${R - F},${T} ${f(R - F + k)},${f(T + k)}`,
    `L${f(R - k)},${f(T + F - k)}`, `Q${R},${T + F} ${R},${T + F + rc}`,
    `V${B - r}`, `A${r},${r} 0 0 1 ${R - r},${B}`, `H${L + r}`, `A${r},${r} 0 0 1 ${L},${B - r}`,
    `V${T + r}`, `A${r},${r} 0 0 1 ${L + r},${T}`, 'Z',
  ].join(' ');
}
export function flapPath({ T, R, F }, rf = 26) {
  return `M${R - F},${T} V${T + F - rf} Q${R - F},${T + F} ${R - F + rf},${T + F} H${R} Z`;
}
export function rrect(x, y, w, h, r) {
  return `M${f(x + r)},${f(y)} H${f(x + w - r)} A${r},${r} 0 0 1 ${f(x + w)},${f(y + r)} V${f(y + h - r)} A${r},${r} 0 0 1 ${f(x + w - r)},${f(y + h)} H${f(x + r)} A${r},${r} 0 0 1 ${f(x)},${f(y + h - r)} V${f(y + r)} A${r},${r} 0 0 1 ${f(x + r)},${f(y)} Z`;
}
export function polygon(n, cx, cy, r, rot = -90) {
  return Array.from({ length: n }, (_, i) => {
    const a = ((rot + (360 / n) * i) * Math.PI) / 180;
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  });
}
// Rounded polygon path via quadratic corners.
export function roundPoly(points, rad) {
  const n = points.length; let d = '';
  for (let i = 0; i < n; i++) {
    const p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n];
    const v1 = [p0[0] - p1[0], p0[1] - p1[1]], v2 = [p2[0] - p1[0], p2[1] - p1[1]];
    const l1 = Math.hypot(...v1), l2 = Math.hypot(...v2);
    const r = Math.min(rad, l1 / 2, l2 / 2);
    const a = [p1[0] + (v1[0] / l1) * r, p1[1] + (v1[1] / l1) * r];
    const b = [p1[0] + (v2[0] / l2) * r, p1[1] + (v2[1] / l2) * r];
    d += `${i === 0 ? 'M' : 'L'}${f(a[0])},${f(a[1])} Q${f(p1[0])},${f(p1[1])} ${f(b[0])},${f(b[1])} `;
  }
  return d + 'Z';
}
// Isometric projection (true 30° iso). x → right-down, y → left-down, z → up.
export const iso = (ox, oy, s = 1) => ([x, y, z]) => [
  ox + (x - y) * 0.8660254 * s, oy + (x + y) * 0.5 * s - z * s,
];
export const mix = (a, b, t) => {
  const pa = hex(a), pb = hex(b);
  return '#' + pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, '0')).join('');
};
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
export const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

// Fit a label into `maxW` canvas units. Width factor tuned for SF Pro/Inter Bold caps.
export function labelSize(text, maxW, maxSize, spacing = 0) {
  const units = [...text].reduce((w, ch) => w + (ch === '.' ? 0.3 : ch === '·' ? 0.32 : /[0-9]/.test(ch) ? 0.62 : ch === 'Z' ? 0.62 : ch === 'R' || ch === 'P' ? 0.66 : 0.68), 0);
  return Math.min(maxSize, maxW / (units + (spacing * (text.length - 1)))); // spacing in em
}
