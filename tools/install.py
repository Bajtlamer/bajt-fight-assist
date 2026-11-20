#!/usr/bin/env python3
"""Install addons into a WoW AddOns directory with backup and byte verification.
Usage: install.py --addons-dir DIR [--apply] [AddonName ...]   (no names: all addons; without --apply: preview)"""
import argparse
import pathlib
import shutil
import tempfile
import time
from common import files, select

p = argparse.ArgumentParser()
p.add_argument('--addons-dir', type=pathlib.Path, required=True)
p.add_argument('--apply', action='store_true')
p.add_argument('names', nargs='*')
a = p.parse_args()
base = a.addons_dir.resolve()
if not base.is_dir():
    raise SystemExit('AddOns directory missing')

for addon in select(a.names):
    target = base / addon.name
    if target.is_symlink():
        raise SystemExit('Refusing symlink destination: ' + str(target))
    paths = files(addon)
    print('%s: %d runtime files -> %s' % (addon.name, len(paths), target))
    if not a.apply:
        continue
    backup = None
    with tempfile.TemporaryDirectory(prefix='.addon-install-', dir=base) as temp:
        stage = pathlib.Path(temp) / addon.name
        stage.mkdir()
        for source in paths:
            dest = stage / source.relative_to(addon.resolve())
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        if target.exists():
            backup = base / ('.%s-backup-%d' % (addon.name, time.time_ns()))
            target.rename(backup)
        try:
            stage.rename(target)
            for source in paths:
                if (target / source.relative_to(addon.resolve())).read_bytes() != source.read_bytes():
                    raise RuntimeError('Installed byte mismatch')
        except Exception:
            if target.exists():
                shutil.rmtree(target)
            if backup:
                backup.rename(target)
            raise
    print('  installed and verified. Backup: ' + str(backup))
if not a.apply:
    print('Preview only; add --apply to install.')
