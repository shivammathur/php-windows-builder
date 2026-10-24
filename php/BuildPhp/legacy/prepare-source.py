"""Apply reviewed compiler compatibility patches and archive the exact build source."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(root, repository, ref):
    root = Path(root).resolve()
    version = re.search(r'^#define PHP_VERSION "([^"]+)"',
                        (root / 'main/php_version.h').read_text(), re.M)[1]
    minor = '.'.join(version.split('.')[:2])
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    original = subprocess.check_output(['git', 'archive', '--format=zip', 'HEAD'], cwd=root)
    descriptor = Path(__file__).parent / ('php' + minor.replace('.', '') + '-msvc-compat.json')
    adjustments = None
    if descriptor.exists():
        adjustments = json.loads(descriptor.read_text())
        patch = descriptor.parent / adjustments['patch']
        if sha(patch.read_bytes()) != adjustments['sha256']:
            raise ValueError('Compatibility patch checksum mismatch')
        # Some PHP 5 files enable Git's ident checkout filter. Restore only that
        # expansion to the committed bytes before checking the reviewed hashes.
        for f in adjustments['files']:
            path = root / f['path']
            committed = subprocess.check_output(['git', 'show', 'HEAD:' + f['path']], cwd=root)
            current = path.read_bytes()
            ident = rb'\$Id(?::[^\r\n$]*)?\$'
            if re.sub(ident, b'$Id$', current) == re.sub(ident, b'$Id$', committed):
                path.write_bytes(committed)
            elif sha(re.sub(ident, b'$Id$', current)) == f['after_sha256']:
                path.write_bytes(re.sub(ident, b'$Id$', current))
        before = all(sha((root / f['path']).read_bytes()) == f['before_sha256'] for f in adjustments['files'])
        after = all(sha((root / f['path']).read_bytes()) == f['after_sha256'] for f in adjustments['files'])
        if not before and not after:
            raise ValueError('Source files differ from reviewed compatibility patch inputs')
        if before:
            for check in [True, False]:
                subprocess.run(['git', '-c', 'core.autocrlf=false', 'apply'] +
                               (['--check'] if check else []) + ['--whitespace=error', str(patch)],
                               cwd=root, check=True)
        for f in adjustments['files']:
            path = root / f['path']
            data = path.read_bytes()
            normalized = re.sub(rb'\$Id(?::[^\r\n$]*)?\$', b'$Id$', data)
            if sha(normalized) == f['after_sha256']:
                path.write_bytes(normalized)
            if sha(path.read_bytes()) != f['after_sha256']:
                raise ValueError('Patched source checksum mismatch: ' + f['path'])
    output = root / 'artifacts'
    output.mkdir(exist_ok=True)
    archive = output / ('php-' + version + '-src.zip')
    changed = {f['path'] for f in adjustments['files']} if adjustments else set()
    with zipfile.ZipFile(io.BytesIO(original)) as source, zipfile.ZipFile(archive, 'w') as target:
        for entry in source.infolist():
            data = (root / entry.filename).read_bytes() if entry.filename in changed else source.read(entry)
            target.writestr(entry, data)
    proof = dict(repository=repository, ref=ref, commit=commit, version=version,
                 original_archive_sha256=sha(original), source_archive_sha256=sha(archive.read_bytes()),
                 source_adjustments=adjustments)
    (output / 'source-provenance.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(proof))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root')
    parser.add_argument('--repository', required=True)
    parser.add_argument('--ref', required=True)
    args = parser.parse_args()
    prepare(args.root, args.repository, args.ref)
