#!/usr/bin/env python3
"""Compare the engine-extracted app with the exact app used to produce its CI ZIP."""
from pathlib import Path
import hashlib
import os
import stat
import sys

def inventory(root):
    result = {}
    for base, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(base) / name
            mode = path.lstat().st_mode
            relative = str(path.relative_to(root))
            if stat.S_ISLNK(mode):
                result[relative] = ('link', os.readlink(path))
            elif stat.S_ISDIR(mode):
                result[relative] = ('directory',)
            elif stat.S_ISREG(mode):
                result[relative] = ('file', hashlib.sha256(path.read_bytes()).hexdigest(), mode & 0o111)
            else:
                raise AssertionError('Unexpected special entry in official app')
    return result

original, extracted = map(Path, sys.argv[1:])
a, b = inventory(original), inventory(extracted)
assert a == b, 'Extracted app differs in paths, file bytes, link targets or executable permissions'
print(f'Exact app contents verified: {len(a)} entries, {sum(v[0] == "link" for v in a.values())} symbolic links')
