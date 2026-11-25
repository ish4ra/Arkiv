#!/usr/bin/env bash
# Encodes the rendered hero frames for the README. Design-time only.
#
#   design/readme/encode-hero.sh <work dir> <output dir>
#
# - arkiv-hero.gif: one global 255-colour palette and ordered (Bayer) dithering,
#   so pixels that do not move stay byte-identical between frames; ffmpeg's GIF
#   encoder then stores only the changed rectangle of each frame, with unchanged
#   pixels transparent. 20 fps (5 cs per frame), infinite loop.
# - arkiv-hero.jpg: the 2x static fallback (reduced motion), 4:4:4 chroma.
# Tested with ffmpeg 6.1.1. Other ffmpeg versions can produce different bytes.
set -euo pipefail
work=${1:?work dir}; out=${2:?output dir}
mkdir -p "$out"
ffmpeg -v error -y -framerate 20 -i "$work/frames/frame-%03d.png" \
  -vf "split[a][b];[a]palettegen=max_colors=255:stats_mode=diff:reserve_transparent=1[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 "$out/arkiv-hero.gif"
ffmpeg -v error -y -i "$work/static.png" -pix_fmt yuvj444p -q:v 3 "$out/arkiv-hero.jpg"
ls -l "$out/arkiv-hero.gif" "$out/arkiv-hero.jpg"
