#!/usr/bin/env python3
"""Reproduce the pinned official single-file library. Developer-only; no build network."""
import hashlib, pathlib, subprocess, tarfile, tempfile, urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
URL='https://codeload.github.com/facebook/zstd/tar.gz/refs/tags/v1.5.7'
SHA='37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3'
with tempfile.TemporaryDirectory() as temporary:
    work=pathlib.Path(temporary); archive=work/'zstd.tar.gz'
    with urllib.request.urlopen(URL,timeout=60) as response: data=response.read()
    if hashlib.sha256(data).hexdigest()!=SHA: raise SystemExit('Upstream source SHA256 mismatch')
    archive.write_bytes(data)
    with tarfile.open(archive) as tar: tar.extractall(work,filter='data')
    source=work/'zstd-1.5.7'; target=ROOT/'Sources/CZstd'
    subprocess.run(['python3',str(source/'build/single_file_libs/combine.py'),'-r',str(source/'lib'),'-x','legacy/zstd_legacy.h','-o',str(target/'zstd.c'),str(source/'build/single_file_libs/zstd-in.c')],check=True)
    for name in ['zstd.h','zstd_errors.h']:(target/'include'/name).write_bytes((source/'lib'/name).read_bytes())
    (ROOT/'licenses/zstd-LICENSE.txt').write_bytes((source/'LICENSE').read_bytes())
