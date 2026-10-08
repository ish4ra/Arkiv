"""Publish aggregate compiler warning counts/categories, never raw diagnostics."""
from pathlib import Path
import sys
lines = [line for line in Path(sys.argv[1]).read_text(errors='replace').splitlines() if 'warning:' in line.lower()]
print(f'::notice title=Arkiv compiler diagnostics::Compiler warning lines: {len(lines)}')
for label, pattern in {
    'Deprecated API warning': 'deprecated',
    'Concurrency isolation warning': 'actor-isolated',
    'Sendability warning': 'Sendable',
    'Unused value warning': 'never used',
    'Immutable value suggestion': 'never mutated',
}.items():
    if any(pattern in line for line in lines):
        print('::warning title=Arkiv compiler diagnostics::' + label)
