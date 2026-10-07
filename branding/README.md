# Arko branding — Tension Seal

**Tension Seal is the official Arko app icon and brand mark.** The original
ceramic clasp, three folded ribbons, green seal, colors, gradients, shadow, and
transparent padding are one design. [scripts/render-icon.swift](../scripts/render-icon.swift)
is the authoritative artwork. These exports do not introduce a separate logo.

| Asset | Recommended use |
| --- | --- |
| `Arko-AppIcon-1024.png` | High-resolution app identity and social-card composition |
| `Arko-AppIcon-512.png` | README headers, documentation covers, support pages |
| `Arko-AppIcon-256.png` | Compact README/docs illustrations; up to 128 CSS px at 2× density |
| `Arko-AppIcon-128.png` | Small app badges; up to 64 CSS px at 2× density |
| `Arko-Mark-Transparent-1024.png` | Website hero artwork and large marketing compositions |
| `Arko-Mark-Transparent-512.png` | Website headers, support pages, and smaller compositions |

All six PNGs retain the renderer's transparent background. The two transparent
mark files are **byte-identical** to the corresponding app-icon PNGs; the names
make their intended uses easier to find. No background, crop, or extra effects
are applied. Social-card artwork should place the 1024 px export on a separate
card background rather than flattening or altering the source asset.

Use at least **32 × 32 CSS px**, preferably 48 px or larger when recognition of
the full mark matters. Choose a source at least twice the displayed dimensions
for Retina screens. Keep the full square canvas and its existing clear space.
Do not stretch, recolor, rotate, crop, distort, trace, or remove parts of the mark.
Do not add shadows, outlines, or filters. Check contrast on the intended background.

## Source and verification

The committed PNGs were extracted byte-for-byte from the installed `Arko.icns`
uploaded in [commit 3ffeef7](https://github.com/ish4ra/Arko/commit/3ffeef7f6de0d65828378fec7fa5773a1614648e).
That supplied icon is authoritative for this asset export; the unchanged Swift
renderer remains the source of truth for the artwork. The temporary root ICNS
is not retained in the final repository tree.

Source ICNS SHA-256:
`f1c099a4651cd732220c29ae80cc1cc66ba3fd51247ff8fea6340656ce8fbd36`.

The PNG representations are `ic10` (1024), `ic09` (512), `ic08` (256), and `ic07`
(128). All preserve the original PNG bytes, color information, alpha, and padding.
`SHA256SUMS` records the six exported file checksums.

To repeat the extraction from an installed app on any platform with Python 3
and Pillow installed:

```sh
python3 branding/extract-icns.py /path/to/Arko.icns
```

This validates decoded dimensions, transparent corners, opaque artwork, and
partial alpha before copying the embedded PNGs. It never resizes or re-encodes.
To check the committed exports on Linux, run `sha256sum -c SHA256SUMS` from this
directory; on macOS, use `shasum -a 256 -c SHA256SUMS`.

## Regenerate from the original renderer

On macOS with Xcode Command Line Tools installed, run from the repository root:

```sh
bash branding/export.sh
swift branding/verify-assets.swift branding
```

The export command invokes the unmodified app-icon renderer in a temporary
directory and copies its PNGs directly, without resampling or re-encoding. The
1024 px source is `icon_512x512@2x.png`; the other sources are the matching
`icon_<size>x<size>.png` files. Validation checks dimensions, decoded alpha,
transparent corners, opaque artwork, partial transparency, and matching mark
copies before replacing the exports. It does not run or change app packaging/CI. If deliberately regenerating the
exports, verify them and refresh `SHA256SUMS`; renderer output may vary across
macOS versions, so the installed-icon extraction above records this set exactly.

## SVG

No SVG is supplied. The Bézier geometry could be translated, but that alone does
not establish an exact match for AppKit's gradient rendering, color handling,
and blurred shadow. An unverified SVG approximation would become a conflicting
brand asset. The PNG exports and the original Swift renderer remain authoritative.
