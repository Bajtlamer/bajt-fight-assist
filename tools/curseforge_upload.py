#!/usr/bin/env python3
"""Upload the release ZIPs of Bajt's Fight Assist to its three CurseForge projects.

    python3 tools/curseforge_upload.py plan --game-version 17053           # what would be uploaded (no network write)
    python3 tools/curseforge_upload.py upload --apply --game-version 17053

The author upload token (CF_UPLOAD_TOKEN) is read from ../curseforge/.env and never printed. The core is the project every
module requires. Project IDs are in ../curseforge/ref-curseforge-project-ids.md.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = 'https://wow.curseforge.com/api'
ENV = ROOT.parent / 'curseforge' / '.env'
CORE_SLUG = 'bajts-fight-assist'
# folder: (project id, title)
PROJECTS = {
    'BajtFightAssist': (1824297, "Bajt's Fight Assist"),
    'BajtFightAssist_Hunter': (1824302, "Bajt's Fight Assist: Hunter"),
    'BajtFightAssist_Rogue': (1824306, "Bajt's Fight Assist: Rogue"),
}


def token():
    for line in ENV.read_text().splitlines():
        match = re.match(r'^\s*CF_UPLOAD_TOKEN\s*=\s*(.*?)\s*$', line)
        if match:
            return match.group(1).strip('\'"')
    raise SystemExit('CF_UPLOAD_TOKEN is not in ' + str(ENV))


def request(path, data=None, headers=None):
    req = urllib.request.Request(API + path, data=data, headers={'X-Api-Token': token(), **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as reply:
            return json.loads(reply.read().decode() or 'null')
    except urllib.error.HTTPError as error:
        raise SystemExit('HTTP %s from %s: %s' % (error.code, path, error.read().decode(errors='replace')[:400]))


def find_zip(release_dir, folder):
    """The one ZIP of the folder in the release directory, and its version."""
    found = sorted(release_dir.glob(folder + '-*.zip'))
    if len(found) != 1:
        raise SystemExit('Expected one %s-<version>.zip in %s, found %d' % (folder, release_dir, len(found)))
    return found[0], found[0].name[len(folder) + 1:-4]


def changelog(section):
    """The section of CHANGELOG.md whose heading starts with the given text."""
    text = (ROOT / 'CHANGELOG.md').read_text()
    for part in re.split(r'^## ', text, flags=re.M)[1:]:
        if part.startswith(section):
            return '## ' + part.strip() + '\n'
    raise SystemExit('No section starting with %r in CHANGELOG.md' % section)


def multipart(metadata, path):
    boundary = uuid.uuid4().hex
    parts = [
        b'--' + boundary.encode() + b'\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'
        + json.dumps(metadata).encode() + b'\r\n',
        b'--' + boundary.encode() + b'\r\nContent-Disposition: form-data; name="file"; filename="' + path.name.encode()
        + b'"\r\nContent-Type: application/zip\r\n\r\n' + path.read_bytes() + b'\r\n',
        b'--' + boundary.encode() + b'--\r\n',
    ]
    return b''.join(parts), 'multipart/form-data; boundary=' + boundary


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=('plan', 'upload'))
    parser.add_argument('--game-version', type=int, action='append', required=True)
    parser.add_argument('--release-type', default='release', choices=('alpha', 'beta', 'release'))
    parser.add_argument('--release-dir', type=Path, default=ROOT / 'dist', help='directory with the three release ZIPs')
    parser.add_argument('--section', default='First release', help='CHANGELOG.md section used as the file changelog')
    parser.add_argument('--no-relations', action='store_true', help='skip the required dependency on the core (while the core project is not approved yet CurseForge rejects its slug)')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--only', action='append', help='folder name, repeat for several (default: all)')
    args = parser.parse_args()
    notes = changelog(args.section)
    for folder, (project, title) in PROJECTS.items():
        if args.only and folder not in args.only:
            continue
        path, ver = find_zip(args.release_dir, folder)
        meta = {'changelog': notes, 'changelogType': 'markdown', 'displayName': '%s %s' % (title, ver),
                'gameVersions': args.game_version, 'releaseType': args.release_type}
        if folder != 'BajtFightAssist' and not args.no_relations:
            meta['relations'] = {'projects': [{'slug': CORE_SLUG, 'type': 'requiredDependency'}]}
        print('%s -> project %d: %s, %d bytes, %s' % (folder, project, path.name, path.stat().st_size, args.release_type))
        if args.command == 'upload' and args.apply:
            body, content_type = multipart(meta, path)
            reply = request('/projects/%d/upload-file' % project, body, {'Content-Type': content_type})
            print('   uploaded, file id', reply.get('id') if isinstance(reply, dict) else reply)
    if args.command == 'upload' and not args.apply:
        print('Nothing was uploaded: add --apply.')


if __name__ == '__main__':
    sys.exit(main())
