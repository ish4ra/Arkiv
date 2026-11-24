#!/bin/bash
# Fetches the exact headless shell the archived icon renders were made with:
# Chrome for Testing 157.0.8103.78, linux64, pinned by SHA-256. Design-time / CI only.
#   design/document-icon-themes/fetch-headless-shell.sh <directory>
# Then: ARKIV_THEME_HEADLESS_SHELL=<directory>/chrome-headless-shell-linux64 node design/document-icon-themes/render.mjs ...
set -euo pipefail
version=157.0.8103.78
sha256=f90329720fb61e5a76da9b6b509b6ad12a484c9c5df0359403e935177c6d153a
out=${1:?usage: fetch-headless-shell.sh <directory>}
mkdir -p "$out"
curl -sSfL --retry 4 -o "$out/chrome-headless-shell-linux64.zip" \
  "https://storage.googleapis.com/chrome-for-testing-public/$version/linux64/chrome-headless-shell-linux64.zip"
echo "$sha256  $out/chrome-headless-shell-linux64.zip" | sha256sum -c -
unzip -q -o "$out/chrome-headless-shell-linux64.zip" -d "$out"
rm "$out/chrome-headless-shell-linux64.zip"
"$out/chrome-headless-shell-linux64/chrome-headless-shell" --version
