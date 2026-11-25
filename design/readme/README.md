# README media (design-time)

Sources for the repository homepage's hero animation and artwork gallery.
**Design-time only:** nothing here is built into, linked by or bundled with
Arkiv.app, and nothing runs on GitHub. GitHub never executes the scene's
JavaScript; it only shows the rendered GIF.

| File | Purpose |
| --- | --- |
| `hero.html` | The hero scene: HTML/CSS plus `window.renderFrame(t)`, which poses every element at loop phase `t` ∈ [0, 1). All motion is periodic in `t`, so the loop is seamless |
| `render-hero.mjs` | Renders the 120 frames (1×) and the static fallback (2×) with Playwright |
| `encode-hero.sh` | Encodes `arkiv-hero.gif` and `arkiv-hero.jpg` with ffmpeg |
| `collect-artwork.py` | Copies the gallery artwork byte for byte from the bundled icons and the pinned design archives; `--check` verifies |
| `check-readme.py` | Validates README links, anchors, images, the GIF's structure, size budgets and artwork provenance (standard library only) |
| `package.json`, `package-lock.json` | Pins Playwright 1.63.0, the version the document-icon generator uses |

What the media contains, with exact sizes and colour sources, is in
[`docs/media/README.md`](../../docs/media/README.md).

## Requirements

* Node.js 22 and `npm`
* Playwright 1.63.0's Chromium (`npx playwright install chromium`)
* ffmpeg (tested with 6.1.1)
* Python 3.9 or later (standard library only)
* For the artwork: both design-archive commits, fetched below

## Rebuild

From the repository root:

```sh
(cd design/readme && npm ci && npx playwright install chromium)
node design/readme/render-hero.mjs /tmp/arkiv-hero
design/readme/encode-hero.sh /tmp/arkiv-hero docs/media
git fetch --no-tags origin 7e9b736b123274e28a64727d0e6fde22ca11daf7 8a1b92ae31f5ba4e649022f0cb38ccd9e24647a6
python3 design/readme/collect-artwork.py
python3 design/readme/check-readme.py
```

Rendering takes about 30 seconds. The scene and its timings are deterministic,
but different Chromium or ffmpeg builds can produce slightly different bytes,
so compare the result visually rather than by checksum.

## Design rules

* **Original assets only.** The scene places, scales and moves the unmodified
  Tension Seal app icon and Seal Dark document icons. It never recolours,
  traces, crops or redraws them, and adds no effects to the artwork itself.
* **Restrained motion.** One gold sweep across the wordmark per loop, a steady
  jade glow behind the mark, and a gentle float of the document icons.
* **Lightweight.** Icon offsets snap to whole pixels, the glow does not pulse,
  and the GIF uses one global palette with ordered dithering. Pixels that do not
  move are then identical between frames and cost almost nothing. Keep
  `arkiv-hero.gif` under 1 MB; `check-readme.py` enforces the budgets.
* **Accessible.** The README serves the static JPEG to viewers who ask for
  reduced motion, and the image has descriptive alternative text.
