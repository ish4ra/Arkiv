#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/engine-tests
if [[ $(uname -s) == Darwin ]]; then
  library=.build/engine-tests/libarkiv.dylib
  cc -std=c11 -Wall -Wextra -Werror -dynamiclib -I Sources/CArkiv/include Sources/CArkiv/ArkivArchive.c -larchive -o "$library"
else
  library=.build/engine-tests/libarkiv.so
  cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -shared -fPIC ${ARKIV_CFLAGS:-} -I Sources/CArkiv/include Sources/CArkiv/ArkivArchive.c -Wl,-l:libarchive.so.13 -o "$library"
fi
ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_engine.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_creation.py -v
