# Document icon theme packs (design-time pipeline)

Builds Arkiv's optional, downloadable document-icon themes from the preserved
design archives. **Design-time and CI only:** nothing here is built into,
linked by or bundled with Arkiv.app. The app's runtime side is
`Sources/ArkivThemes`; the user-facing design is in
[docs/document-icon-themes.md](../../docs/document-icon-themes.md).

| File | Purpose |
| --- | --- |
| `themes.json` | The complete theme inventory: stable ids and versions, families, kinds, parents, and the archive source of each theme, pinned to the archive commits |
| `render.mjs` | Extracts the pinned archives, runs the archived generators unmodified, renders what they define at every representation, and self-checks against their outputs |
| `build.py` | Verifies every pixel against the archived manifests, optimizes losslessly, deduplicates, and writes the packs, preview packs, unsigned catalogue payload and inventory |
| `inventory.json` | The committed lock: every pack's SHA-256, sizes and pixel hash. A build that differs fails |

`docs/document-icon-theme-inventory.md` is generated from `inventory.json`.

## Build

The same toolchain as `design/document-icons` (Node 22, Playwright 1.63.0
with Chromium 157.0.8103.78, opentype.js 1.3.4, and the hash-locked oxipng),
plus both archive commits:

```sh
git fetch origin 7e9b736b123274e28a64727d0e6fde22ca11daf7 8a1b92ae31f5ba4e649022f0cb38ccd9e24647a6
(cd design/document-icons && npm ci && npx playwright install chromium)
python3.13 -m pip install --require-hashes -r design/document-icons/requirements-optimize.txt
node design/document-icon-themes/render.mjs --work /tmp/arkiv-theme-work        # about 5 minutes
python3 design/document-icon-themes/build.py --work /tmp/arkiv-theme-work --out /tmp/arkiv-theme-packs
```

The full build takes about 20 minutes on 4 cores, most of it the lossless
optimizer. Local rebuilds can pass `--cache <dir>` to reuse optimizer output.
Every cached result is decoded again and checked against its input's pixels;
CI never uses the cache.

`build.py` fails unless the result is byte-identical to `inventory.json`.
After an approved theme change, such as a new theme or a version bump, run it
with `--write`. That rewrites `inventory.json` and the inventory page; commit
both. Then, to sign and verify locally with a throwaway key kept outside the
repository:

```sh
swift scripts/document-icon-theme-catalog.swift test-key /tmp/arkiv-theme-test-key
ARKIV_THEME_PRIVATE_ED_KEY="$(cat /tmp/arkiv-theme-test-key/theme-test-signing.key)" \
  swift scripts/document-icon-theme-catalog.swift sign /tmp/arkiv-theme-packs/catalog-payload.json /tmp/catalog.json
ARKIV_THEME_PUBLIC_ED_KEY="$(cat /tmp/arkiv-theme-test-key/theme-test-signing.pub)" \
  swift scripts/document-icon-theme-catalog.swift verify /tmp/catalog.json /tmp/arkiv-theme-packs/catalog-payload.json
```

Production packs are published only by the protected, manual `publish` job of
`.github/workflows/document-icon-themes.yml`.

## Provenance rules

* **Sources:** only the archive commits pinned in `themes.json`, read with
  `git archive`, never a branch tip.
* **Rendered by the archived generators:** v1 families, Classic and the
  Restored candidate come from the archived generators, run unmodified, and
  must reproduce the archived pixel manifests. Restored uses its own preserved
  PNGs.
* **Variations:** each one uses its exact archived source substitutions, read
  from `iterations/render-iterations.mjs`, rendered through its parent family's
  pipeline.
  * Its output at the archived script's own sizes must be byte-identical to
    the script's.
  * A control icon rendered from the unpatched parent must equal the parent's
    archived pixels.
  * Only the formats the archive records for a variation use its artwork.
    Every other format is the parent's.
* **Extras:** the unregistered artwork of the two v2 Seal Dark themes, whose
  512 px renders must equal the preserved previews byte-for-byte.
* **Lossless:** every PNG is recompressed with the pinned optimizer, and its
  decoded RGBA must equal the archived pixels.
* **Never generated:** replacement artwork, mock-ups or simplified previews.
  Previews are the themes' own 128 px files.
