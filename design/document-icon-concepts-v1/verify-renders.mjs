// Regenerates every concept render into a temporary directory and compares
// each PNG and SVG byte-for-byte with reference/renders.sha256.
//   node verify-renders.mjs            # all families
//   node verify-renders.mjs seal-dark  # one family
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderAll, DIRECTIONS, SIZES } from './render.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const only = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const dirs = only.length ? only : Object.keys(DIRECTIONS);
const manifest = new Map(fs.readFileSync(path.join(here, 'reference/renders.sha256'), 'utf8').trim().split('\n')
  .map((line) => line.split(/\s+/)).map(([hash, file]) => [file, hash]));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'arkiv-icon-verify-'));
await renderAll({ dirs, sizes: SIZES, out: tmp });
let checked = 0; const bad = [];
for (const [file, hash] of manifest) {
  if (!dirs.includes(file.split('/')[1])) continue;
  const p = path.join(tmp, file);
  const got = fs.existsSync(p) ? crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex') : 'missing';
  checked++;
  if (got !== hash) bad.push(file);
}
fs.rmSync(tmp, { recursive: true, force: true });
console.log(`${checked} reference files checked, ${bad.length} differ`);
if (bad.length) { console.log(bad.slice(0, 20).join('\n')); process.exit(1); }
