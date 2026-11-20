#!/usr/bin/env python3
"""Build one zip per addon into dist/ (usage: package.py [AddonName ...])."""
import hashlib
import sys
import zipfile
from common import ROOT, files, select, version

dist = ROOT / 'dist'
dist.mkdir(exist_ok=True)
sums = []
for addon in select(sys.argv[1:]):
    target = dist / (addon.name + '-' + version(addon) + '.zip')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for path in files(addon):
            info = zipfile.ZipInfo(addon.name + '/' + path.relative_to(addon.resolve()).as_posix(), (2026, 11, 20, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, path.read_bytes())
    sums.append(hashlib.sha256(target.read_bytes()).hexdigest() + '  ' + target.name)
    print(target)
(dist / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')
