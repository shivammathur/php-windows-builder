"""Fetch a hash-pinned existing aggregate for tests, without building PHP."""
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile


def sha_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def validate_archive(path, expected_sha, version, source_commit, arch, ts):
    if not re.fullmatch(r'[0-9a-f]{64}', expected_sha) or sha_file(path) != expected_sha:
        raise ValueError('Aggregate SHA256 mismatch')
    if not re.fullmatch(r'[0-9a-f]{40}', source_commit):
        raise ValueError('An exact source commit is required')
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or any('/' in n or '\\' in n or n in ('.', '..') for n in names):
            raise ValueError('Aggregate must contain unique, flat file names')
        if archive.testzip() is not None:
            raise ValueError('Corrupt aggregate ZIP')
        proof = json.loads(archive.read('source-provenance.json'))
        if proof['repository'] != 'shivammathur/php-src-backports' or proof['commit'] != source_commit or proof['version'] != version:
            raise ValueError('Source provenance does not match requested public backport')
        source = archive.read(f'php-{version}-src.zip')
        if hashlib.sha256(source).hexdigest() != proof['source_archive_sha256'] or archive.read(f'php-test-pack-{version}.zip') != source:
            raise ValueError('Source/test archive hash mismatch')
        pattern = rf'php-{re.escape(version)}-{("nts-" if ts == "nts" else "")}Win32-v[sc]\d+-{re.escape(arch)}\.zip'
        if sum(bool(re.fullmatch(pattern, n, re.I)) for n in names) != 1:
            raise ValueError('Requested binary variant is missing or ambiguous')
        return proof, [{'name': n, 'sha256': hashlib.sha256(archive.read(n)).hexdigest()} for n in names]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    run_id = os.environ['BUILD_RUN_ID']
    digest = os.environ['ARTIFACT_SHA256'].removeprefix('sha256:')
    if repo != 'shivammathur/php-windows-builder' or not run_id.isdecimal():
        raise ValueError('Unexpected build repository or run ID')
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        raise ValueError('Expected aggregate SHA256 is required')
    headers = {'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
    base = f'https://api.github.com/repos/{repo}'
    with urllib.request.urlopen(urllib.request.Request(f'{base}/actions/runs/{run_id}/artifacts?per_page=100', headers=headers), timeout=60) as response:
        listing = json.load(response)
    if listing['total_count'] > 100:
        raise ValueError('Artifact pagination required')
    assets = [a for a in listing['artifacts'] if a['name'] == 'artifacts' and not a['expired']]
    if len(assets) != 1:
        raise ValueError('Expected exactly one existing aggregate')
    asset = assets[0]
    if asset['workflow_run']['id'] != int(run_id) or asset.get('digest') != 'sha256:' + digest:
        raise ValueError('GitHub artifact identity/digest mismatch')
    request = urllib.request.Request(f'{base}/actions/artifacts/{asset["id"]}/zip', headers=headers)
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        location = error.headers['Location']
        if urllib.parse.urlparse(location).scheme != 'https':
            raise ValueError('Artifact download requires HTTPS')
        # Do not forward GitHub credentials to the signed blob URL or log it.
        response = urllib.request.urlopen(location, timeout=120)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'aggregate.zip'
        with response, path.open('wb') as out:
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
        proof, files = validate_archive(path, digest, os.environ['PHP_VERSION'], os.environ['SOURCE_COMMIT'], os.environ['BUILD_ARCH'], os.environ['BUILD_TS'])
        with zipfile.ZipFile(path) as archive:
            for item in files:
                target = Path(item['name'])
                if target.exists():
                    raise ValueError('Refusing to overwrite an existing workspace file')
                target.write_bytes(archive.read(item['name']))
    receipt = {'build_repository': repo, 'build_run_id': int(run_id), 'artifact_id': asset['id'], 'artifact_sha256': digest, 'builder_revision': asset['workflow_run']['head_sha'], 'source': proof, 'files': files}
    Path('test-input-provenance.json').write_text(json.dumps(receipt, indent=2))
    print(f'Verified existing PHP {proof["version"]} artifact {asset["id"]}, source {proof["commit"]}')


if __name__ == '__main__':
    main()
