#!/bin/bash
# Export the authoritative artwork without resizing, tracing, or recoloring it.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
[[ $(uname -s) == Darwin ]] || { echo 'Export requires macOS and Swift/AppKit.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swift "$repo/scripts/render-icon.swift" "$work/iconset"
mkdir "$work/exports"
cp "$work/iconset/icon_512x512@2x.png" "$work/exports/Arkiv-AppIcon-1024.png"
for size in 512 256 128; do
    cp "$work/iconset/icon_${size}x${size}.png" "$work/exports/Arkiv-AppIcon-${size}.png"
done
for size in 1024 512; do
    cp "$work/exports/Arkiv-AppIcon-${size}.png" "$work/exports/Arkiv-Mark-Transparent-${size}.png"
done
swift "$repo/branding/verify-assets.swift" "$work/exports"
cp "$work/exports/"*.png "$repo/branding/"
echo 'Exported six original Tension Seal PNGs to branding/.'
