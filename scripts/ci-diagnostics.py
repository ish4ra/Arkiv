"""Emit fixed categories and repository-owned test/API identifiers, never log excerpts."""
import ast
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text(errors='replace')
labels = []
categories = {
    'Header unavailable': 'file not found',
    'Undeclared API': 'undeclared function',
    'Link failure': 'Undefined symbols',
    'Swift name resolution': 'cannot find',
    'Swift type mismatch': 'cannot convert',
    'Unsupported API member': 'has no member',
    'Concurrency isolation': 'actor-isolated',
    'Engine fixture assertion failure': 'AssertionError',
    'Python fixture exception': 'Traceback',
}
for label, pattern in categories.items():
    if pattern in text: labels.append(label)
# These literal API identifiers are public source identifiers, not extracted log text.
for name in ['archive_read_support_format_rar5', 'archive_entry_is_encrypted',
             'archive_entry_pathname_utf8', 'archive.h', 'NSStackView', 'NSAffineTransform',
             'UnicodeScalar', 'NSSearchFieldDelegate', 'NSToolbarItemValidation']:
    if name in text: labels.append('Referenced API: ' + name)
# Only names declared in our committed tests can appear in annotations.
for node in ast.walk(ast.parse(Path('tests/test_engine.py').read_text())):
    if isinstance(node, ast.FunctionDef) and node.name.startswith('test_'):
        if re.search(r'(?:FAIL|ERROR): ' + re.escape(node.name) + r'\b', text):
            labels.append('Failing test: ' + node.name)
if not labels: labels.append('Command failed; detailed diagnostics require authenticated Actions log access.')
for label in labels:
    print('::error title=Arko sanitized diagnostic::' + label)
