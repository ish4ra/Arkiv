#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -parse-as-library Sources/ArkivApp/FinderEventAuthenticator.swift scripts/verify-finder-auth.swift -o "$work/verify"
codesign --force --sign - --options runtime "$work/verify"
"$work/verify" build/Arkiv.app/Contents/PlugIns/ArkivFinderSync.appex
