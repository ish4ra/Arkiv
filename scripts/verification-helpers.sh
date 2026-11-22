# Pipeline-free text checks shared by packaging verification scripts.
# Sourced by scripts/verify-app.sh; tests/test_ci_reliability.py runs it on any OS.
#
# Never write `producer | grep -q PATTERN` under `set -o pipefail`. grep -q
# exits at the first match; a producer that is still writing then dies of
# SIGPIPE (status 141), and pipefail reports the whole pipeline as failed. A
# present library then looks missing (false failure), and inside `if` a
# forbidden dependency looks absent (silent pass). Matching a captured string
# through a here-string has no producer process, so neither can happen.

# text_contains MODE TEXT PATTERN: MODE is F (fixed string) or E (extended regex).
# Returns 0 on a match and 1 on no match. Any grep error (status 2 or higher)
# fails closed by exiting, so it can never be read as "no match".
text_contains() {
  local mode=$1 text=$2 pattern=$3 status=0
  case "$mode" in
    F|E) ;;
    *) echo "text_contains: unsupported mode '$mode'" >&2; exit 2 ;;
  esac
  grep "-${mode}q" -e "$pattern" <<< "$text" || status=$?
  if (( status > 1 )); then
    echo "text_contains: grep failed with status $status" >&2
    exit "$status"
  fi
  return "$status"
}

# verify_slice_libraries ARCH LIBRARIES: LIBRARIES is `otool -arch ARCH -L`
# output for one slice. Requires the caller's `fail MESSAGE` (which exits).
verify_slice_libraries() {
  local arch=$1 libraries=$2 library
  for library in libz.1.dylib libbz2.1.0.dylib liblzma.5.dylib; do
    text_contains F "$libraries" $'\t/usr/lib/'"$library (" || fail "Missing system decoder $library in $arch slice."
  done
  if text_contains E "$libraries" '/usr/local/|/opt/|libzstd'; then
    fail "App $arch slice depends on a non-system host library."
  fi
}
