#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/engine-tests
python3 scripts/build-sevenzip.py --output .build/sevenzip
export LD_LIBRARY_PATH="$PWD/.build/sevenzip${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$PWD/.build/sevenzip${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
if [[ $(uname -s) == Darwin ]]; then
  library=.build/engine-tests/libarkiv.dylib
  sdk=$(xcrun --sdk macosx --show-sdk-path)
  for decoder in libz.1 libbz2.1.0 liblzma.5; do
    if [[ -f "$sdk/usr/lib/$decoder.tbd" ]]; then
      echo "::notice title=Arkiv SDK decoder evidence::$decoder stub present"
    else
      echo "::error title=Arkiv SDK decoder evidence::$decoder stub absent"
      exit 1
    fi
  done
  xcrun --sdk macosx clang -isysroot "$sdk" -std=c11 -Wall -Wextra -Werror -dynamiclib -I Sources/CArkiv/include -I Sources/CArkiv/vendor/xz Sources/CArkiv/ArkivArchive.c Sources/CArkiv/ArkivOpenWorkspace.c Sources/CArkiv/ArkivCompressedTAR.c -larchive -Xlinker "$sdk/usr/lib/libz.1.tbd" -Xlinker "$sdk/usr/lib/libbz2.1.0.tbd" -Xlinker "$sdk/usr/lib/liblzma.5.tbd" -L .build/sevenzip -lArkivSeven -Wl,-rpath,"$PWD/.build/sevenzip" -o "$library"
else
  library=.build/engine-tests/libarkiv.so
  cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -shared -fPIC ${ARKIV_CFLAGS:-} -I Sources/CArkiv/include -I Sources/CArkiv/vendor/xz Sources/CArkiv/ArkivArchive.c Sources/CArkiv/ArkivOpenWorkspace.c Sources/CArkiv/ArkivCompressedTAR.c -Wl,-l:libarchive.so.13 -lz -Wl,-l:libbz2.so.1 -Wl,-l:liblzma.so.5 -L .build/sevenzip -lArkivSeven -Wl,-rpath,"$PWD/.build/sevenzip" -o "$library"
fi
echo "::notice title=Arkiv engine link evidence::Engine library linked"
ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_engine.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_creation.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" ARKIV_SEVEN_LIBRARY="$PWD/.build/sevenzip/$(basename "$library" | sed "s/libarkiv/libArkivSeven/")" python3 tests/test_sevenzip.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_integrity.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_zip_addition.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_zip_deletion.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_zip_rename.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_zip_replacement.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_open_workspace.py -v

ARKIV_TEST_LIBRARY="$PWD/$library" python3 tests/test_compressed_tar.py -v

python3 tests/test_macos_decoder_linking.py -v
