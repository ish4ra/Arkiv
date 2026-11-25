// Renders the README hero loop to PNG frames, plus the static fallback.
//
//   node render-hero.mjs <work dir>
//
// Writes <work>/frames/frame-000.png … (FPS × SECONDS frames, 1280 × 440, 1×)
// and <work>/static.png (2×). encode-hero.py turns them into docs/media.
// Design-time only; nothing here is part of the app.
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

export const FPS = 20;          // GIF delays are whole centiseconds: 5 cs = exactly 20 fps
export const SECONDS = 6;
export const STATIC_PHASE = 0.62; // sweep finished, documents mid-float

const here = path.dirname(fileURLToPath(import.meta.url));
const work = process.argv[2];
if (!work) { console.error('usage: node render-hero.mjs <work dir>'); process.exit(2); }
mkdirSync(path.join(work, 'frames'), { recursive: true });

const browser = await chromium.launch({ args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });
async function open(scale) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 440 }, deviceScaleFactor: scale });
  await page.goto(pathToFileURL(path.join(here, 'hero.html')).href);
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(i => i.decode()));
    if ([...document.fonts].some(f => f.status !== 'loaded' && f.family === 'Inter Display')) {
      await Promise.all([...document.fonts].map(f => f.load()));
    }
  });
  const fonts = await page.evaluate(() => [...document.fonts].map(f => `${f.family} ${f.weight} ${f.status}`));
  if (fonts.some(f => !f.endsWith('loaded'))) throw new Error(`Fonts not loaded: ${fonts}`);
  return page;
}

const page = await open(1);
const count = FPS * SECONDS;
for (let i = 0; i < count; i++) {
  await page.evaluate(t => window.renderFrame(t), i / count);
  await page.screenshot({ path: path.join(work, 'frames', `frame-${String(i).padStart(3, '0')}.png`) });
}
const still = await open(2);
await still.evaluate(t => window.renderFrame(t), STATIC_PHASE);
await still.screenshot({ path: path.join(work, 'static.png') });
await browser.close();
console.log(`Rendered ${count} frames at ${FPS} fps and the 2× static fallback into ${work}`);
