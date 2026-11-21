"""Shared helpers: discover addon folders, read TOC metadata, list runtime files."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def addons():
    """Addon folders (BajtFightAssist, BajtFightAssist_*) that contain a matching TOC, Core first."""
    found = [p for p in sorted(ROOT.iterdir()) if p.is_dir() and (p / (p.name + '.toc')).is_file()]
    return sorted(found, key=lambda p: (p.name != 'BajtFightAssist', p.name))


def toc(addon):
    return addon / (addon.name + '.toc')


def meta(addon):
    """TOC header fields as a dict."""
    fields = {}
    for line in toc(addon).read_text().splitlines():
        m = re.match(r'^## ([^:]+):\s*(.*)$', line)
        if m:
            fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def version(addon):
    v = meta(addon).get('Version', '')
    if not re.fullmatch(r'\d+\.\d+\.\d+', v):
        raise ValueError(addon.name + ': bad Version ' + repr(v))
    return v


def files(addon):
    """Runtime files: the TOC and every file it lists, checked for existence."""
    result = [toc(addon)]
    icon = meta(addon).get('IconTexture')
    if icon:
        path = (addon / 'Artwork' / (icon.replace('\\', '/').rsplit('/', 1)[-1] + '.tga')).resolve()
        if not path.is_file():
            raise ValueError(addon.name + ': missing icon ' + icon)
        result.append(path)
    for line in toc(addon).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            path = (addon / line.replace('\\', '/')).resolve()
            if not path.is_file() or not path.is_relative_to(addon.resolve()):
                raise ValueError(addon.name + ': missing or invalid runtime file ' + line)
            result.append(path)
    return result


def select(names):
    """Addon folders by name (or all when names is empty)."""
    every = addons()
    if not names:
        return every
    by_name = {p.name: p for p in every}
    missing = [n for n in names if n not in by_name]
    if missing:
        raise SystemExit('Unknown addon: ' + ', '.join(missing))
    return [by_name[n] for n in names]
