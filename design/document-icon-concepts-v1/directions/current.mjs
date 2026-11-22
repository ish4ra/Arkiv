// Reproduction of the CURRENT shipping document icons, for comparison boards
// only. Geometry mirrors scripts/render-document-icons.swift (AppKit y-up,
// flipped here) and embeds the unmodified branding/Arkiv-Mark-Transparent-512.png.
// Only ZIP / 7z / TAR / RAR have icons today; other formats get the system
// generic document icon in Finder, shown here as a neutral placeholder.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Svg, FONT } from '../lib/core.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const MARK = 'data:image/png;base64,' + fs.readFileSync(path.join(here, '../../../branding/Arkiv-Mark-Transparent-512.png')).toString('base64');
const SHIPPING = { zip: 'ZIP', '7z': '7z', tar: 'TAR', rar: 'RAR' };

export default function current(fmt, px, pt = px) {
  const s = new Svg();
  const label = SHIPPING[fmt.id];
  if (!label) {
    // generic placeholder (Finder would show the system document/archive icon)
    const d = 'M200,80 H640 L824,264 V944 H200 Z';
    return s.wrap(`<path d="${d}" fill="#F2F2F2" stroke="#B5B5B5" stroke-width="8"/><path d="M640,80 V264 H824" fill="#DADADA" stroke="#B5B5B5" stroke-width="8" stroke-linejoin="round"/>` +
      `<text x="512" y="640" text-anchor="middle" font-family="${FONT}" font-size="110" font-weight="600" fill="#9a9a9a">generic</text>`, px);
  }
  const paper = 'M180,948 H844 V276 L656,80 H180 Z';
  let o = `<g filter="${s.shadow([[0, 8, 16, '#000000', 0.18]])}"><path d="${paper}" fill="rgb(245,242,237)"/></g>`;
  o += `<path d="${paper}" fill="none" stroke="rgb(166,153,156)" stroke-width="5"/>`;
  o += `<path d="M656,80 V276 H844 Z" fill="rgb(214,207,207)"/>`;
  o += `<image href="${MARK}" x="230" y="159" width="570" height="570"/>`;
  const size = px <= 64 ? 224 : 148;
  o += `<text x="512" y="${px <= 64 ? 862 : 858}" text-anchor="middle" font-family="${FONT}" font-weight="600" font-size="${size}" fill="rgb(77,38,56)">${label}</text>`;
  return s.wrap(o, px);
}
