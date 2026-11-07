#!/usr/bin/env python3
"""Fail a build if a bundled effect texture is missing, stale or malformed."""
import hashlib
import json
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
for category, prefix, count in [('light-leaks', 'light-leak', 41), ('aging', 'aging', 5)]:
    folder = root / 'textures' / category
    records = json.loads((folder / 'manifest.json').read_text())['materials']
    expected = {f'{prefix}-{n:03}.spkleak' for n in range(1, count + 1)}
    assert {r['file'] for r in records} == expected and len(records) == count, category
    assert {p.name for p in folder.glob('*.spkleak')} == expected, category
    for record in records:
        path = folder / record['file']
        data = path.read_bytes()
        magic, version, width, height, mode, front = struct.unpack('<4sIIIIf', data[:24])
        assert magic == b'SPKL' and version == 1 and mode in (0, 1), path
        assert (width, height) == (record['width'], record['height']), path
        assert width > 0 and height > 0 and len(data) == 24 + width * height * 6, path
        assert hashlib.sha256(data).hexdigest() == record['sha256'], path
print('PASS: 41 light-leak and 5 aging textures, names, dimensions and SHA256')
