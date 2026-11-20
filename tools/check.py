#!/usr/bin/env python3
"""Validate all addons: TOC rules, Lua 5.1 compilation, then the offline range tests."""
import os
import shutil
import subprocess
import sys
from common import ROOT, addons, files, meta, version

lua = shutil.which('luajit')
if not lua:
    raise SystemExit('LuaJIT required (Lua 5.1 semantics)')

total = 0
for addon in addons():
    m = meta(addon)
    assert m.get('Interface') == '16001', addon.name + ': Interface must be 16001'
    version(addon)
    assert m.get('X-BFA-API') == '1', addon.name + ': X-BFA-API must be 1'
    if addon.name != 'BajtFightAssist':
        assert m.get('Dependencies') == 'BajtFightAssist', addon.name + ': must depend on BajtFightAssist'
        assert m.get('X-BFA-Class'), addon.name + ': X-BFA-Class missing'
        assert m.get('LoadOnDemand') == '1', addon.name + ': class modules must be LoadOnDemand'
    for path in files(addon):
        if path.suffix == '.lua':
            # The path travels in the environment: `luajit -e ... file` would run the file as a script instead.
            subprocess.run([lua, '-e', "assert(loadfile(os.getenv('BFA_FILE')))"], check=True,
                           env={**os.environ, 'BFA_FILE': str(path)}, stdin=subprocess.DEVNULL)
            total += 1
print('PASS TOC rules and Lua 5.1 compilation: %d addons, %d lua files' % (len(addons()), total))

status = 0
for test in sorted((ROOT / 'tools').glob('*_test.lua')):
    print('-- ' + test.name)
    status |= subprocess.run([lua, str(test), str(ROOT)], stdin=subprocess.DEVNULL).returncode
sys.exit(status)
