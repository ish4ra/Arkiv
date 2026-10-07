#!/bin/bash
# Preserve normal CI logs; expose only allowlisted diagnostic categories in annotations.
set -euo pipefail
label=$1
shift
mkdir -p .build/ci-logs
log=".build/ci-logs/$label.log"
if "$@" > "$log" 2>&1; then
  cat "$log"
else
  result=$?
  cat "$log"
  python3 scripts/ci-diagnostics.py "$log"
  exit "$result"
fi
