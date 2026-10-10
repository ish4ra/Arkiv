# 7-Zip source subset for Arkiv

Upstream: https://github.com/ip7z/7zip
Version: 26.04
Commit: `9128b80e3a471108678e2b3ec3c985861c8d7b0f`
Retrieved: 2026-10-10

`sources.txt` is the exact compilation list, derived from the official `CPP/7zip/Bundles/Alone7z/makefile.gcc` without console/UI code, non-7z archive handlers, registration of archive handlers, or unused SystemInfo. Supporting headers are retained. No RAR source is included or compiled. The compiled subset is LGPL-2.1-or-later and public-domain code as marked in individual files. See the unmodified upstream `License.txt`, `copying.txt`, and `7zC.txt`. Upstream's license notice mentions RAR restrictions to describe its complete distribution; that code is absent here.

Arkiv modifications to upstream source:

- `CPP/7zip/Crypto/7zAes.cpp`: remove the process-global cache retaining passwords/derived keys. Retain codec-instance caches only. Bound KDF exponent to 20 (upstream encoder uses 19), retaining the direct-key special value 63.
- `CPP/7zip/Archive/7z/7zIn.cpp`: bound packed and decoded header buffers to 64 MiB, numeric metadata counts to 1,000,000 and file count to 100,000 before allocation.
- `CPP/7zip/Compress/LzmaDecoder.cpp` and `Lzma2Decoder.cpp`: reject dictionaries larger than 128 MiB before allocation.

These restrictions deliberately reject unusually resource-intensive archives. They do not alter AES or compression algorithms. Modified files retain upstream notices; modifications are LGPL-2.1-or-later.

Build with `python3 scripts/build-sevenzip.py --output .build/sevenzip` from the repository root. On macOS, add `--arch arm64` or `--arch x86_64` to produce individual macOS 13+ slices; the app build script combines them. The build uses only checked-in sources, a C/C++ compiler, Python 3 as a development tool, and system libarchive. It does not fetch dependencies or use an installed 7z executable. Fresh objects are compiled each run so header/compiler/architecture changes cannot reuse stale objects.

The Arkiv bridge in `Sources/CArkivSeven` and this source build script are also licensed LGPL-2.1-or-later. This grant is limited to that bridge, script, and vendor changes; it does not choose a license for the rest of Arkiv.
