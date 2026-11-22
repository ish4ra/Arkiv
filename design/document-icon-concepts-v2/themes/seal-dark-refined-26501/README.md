# Theme: C · Seal Dark, refined production (build 26501), the default

This is the document-icon family shipped in Arkiv development build 26501
(`main` commit `84320dfa4ba81522dd71c63beb046b0b656819ad`). It is the
permanent default and the only family bundled in the app.

What distinguishes it from the approved concept (archive v1 `seal-dark`):

* **ZIP:** meshing ribbon teeth, a brass slider and parting tapes.
* **RAR:** a pressed three-layer block in oblique depth.
* **TGZ / TBZ2 / TXZ:**
  * a larger compressor medallion with a brass bezel and a ring in the compressor's hue
  * a page fold tinted with the compressor's hue
  * at 32 pt, a compressor badge
* **16 / 32 pt, all icons:** a slightly brighter sheet and fold, a firmer rose rim, and a narrower spine and seam.
* **Unchanged from the concept:** 7z, TAR, GZIP, BZIP2, XZ and ZSTD.

Files:

| File | Content |
| --- | --- |
| `seal-dark.mjs` | Byte-identical to `main:design/document-icons/seal-dark.mjs` at `84320df` |
| `SHA256SUMS` | Byte-identical to `main:Resources/DocumentIcons/SHA256SUMS` at `84320df` (110 PNGs) |

The PNGs themselves are not duplicated here. Retrieve them with
`git archive 84320df Resources/DocumentIcons | tar -x`, or regenerate them with
`node reproduce.mjs seal-dark-refined-26501`, which was verified byte-for-byte:
110 files, 0 differ.

`PIXELS.sha256` holds decoded-pixel hashes of the 110 PNGs
(`python3 ../../tooling/verify-pixels.py PIXELS.sha256 <iconsets dir>`). It verifies
the artwork even when a different PNG encoder changes the file bytes.
