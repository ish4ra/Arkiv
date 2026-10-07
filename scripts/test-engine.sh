#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/engine-tests
if [[ $(uname -s) == Darwin ]]; then
  library=.build/engine-tests/libarko.dylib
  cc -std=c11 -Wall -Wextra -Werror -dynamiclib -I Sources/CArko/include Sources/CArko/ArkoArchive.c -larchive -o "$library"
else
  library=.build/engine-tests/libarko.so
  cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -shared -fPIC ${ARKO_CFLAGS:-} -I Sources/CArko/include Sources/CArko/ArkoArchive.c -Wl,-l:libarchive.so.13 -o "$library"
fi
ARKO_TEST_LIBRARY="$PWD/$library" python3 tests/test_engine.py -v
