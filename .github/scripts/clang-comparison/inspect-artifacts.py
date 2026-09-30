import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zipfile

import pefile


def pdb_id(data):
    block_size, _, _, size, _, block_map = struct.unpack_from('<6I', data, 32)
    count = (size + block_size - 1) // block_size
    pages = struct.unpack_from(f'<{count}I', data, block_map * block_size)
    directory = b''.join(data[p * block_size:(p + 1) * block_size] for p in pages)[:size]
    stream_count = struct.unpack_from('<I', directory)[0]
    sizes = struct.unpack_from(f'<{stream_count}I', directory, 4)
    offset = 4 + 4 * stream_count
    for index, stream_size in enumerate(sizes):
        count = 0 if stream_size == 0xffffffff else (stream_size + block_size - 1) // block_size
        pages = struct.unpack_from(f'<{count}I', directory, offset)
        offset += 4 * count
        if index == 1:
            stream = b''.join(data[p * block_size:(p + 1) * block_size] for p in pages)[:stream_size]
            return stream[12:28].hex(), struct.unpack_from('<I', stream, 8)[0]
    raise ValueError('PDB information stream is missing')


base = Path(sys.argv[1])
runtime = next(base.glob('php-8*.zip'))
debug = next(base.glob('php-debug*.zip'))
report = {'archive': runtime.name, 'binaries': [], 'sbom': {}}
errors = []
with zipfile.ZipFile(runtime) as archive, zipfile.ZipFile(debug) as symbols:
    pdbs = {PurePosixPath(name).name.lower(): name for name in symbols.namelist()}
    for name in archive.namelist():
        if not name.endswith(('.exe', '.dll')):
            continue
        pe = pefile.PE(data=archive.read(name))
        load_config = getattr(getattr(pe, 'DIRECTORY_ENTRY_LOAD_CONFIG', None), 'struct', None)
        binary = {
            'path': name,
            'machine': pe.FILE_HEADER.Machine,
            'cfg': bool(pe.OPTIONAL_HEADER.DllCharacteristics & 0x4000),
            'guard_flags': getattr(load_config, 'GuardFlags', 0),
            'security_cookie': bool(getattr(load_config, 'SecurityCookie', 0)),
            'imports': sorted(entry.dll.decode() for entry in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', [])),
            'debug': [],
        }
        for entry in getattr(pe, 'DIRECTORY_ENTRY_DEBUG', []):
            if entry.struct.Type != 2:
                continue
            cv = pe.get_data(entry.struct.AddressOfRawData, entry.struct.SizeOfData)
            if cv[:4] != b'RSDS':
                continue
            pdb_name = cv[24:].split(b'\0')[0].decode().replace('\\', '/').split('/')[-1].lower()
            match = None
            if pdb_name in pdbs:
                match = (cv[4:20].hex(), struct.unpack_from('<I', cv, 20)[0]) == pdb_id(symbols.read(pdbs[pdb_name]))
            binary['debug'].append({'pdb': pdb_name, 'match': match})
            if match is False:
                errors.append(f'{name}: mismatched PDB {pdb_name}')
        if PurePosixPath(name).name.startswith('php') and not any(d['match'] for d in binary['debug']):
            errors.append(f'{name}: matching PHP PDB is missing')
        if re.fullmatch(r'php\d+(?:ts)?\.dll', name):
            binary['exports'] = sorted(s.name.decode() for s in pe.DIRECTORY_ENTRY_EXPORT.symbols if s.name)
        report['binaries'].append(binary)

digest = hashlib.sha256(runtime.read_bytes()).hexdigest()
for path in base.glob(runtime.name + '.*.json'):
    document = json.loads(path.read_text(encoding='utf-8-sig'))
    report['sbom'][path.name] = {'parsed': True}
    if path.name.endswith('.cdx.json'):
        component = document['metadata']['component']
        hashes = {h['alg']: h['content'] for h in component['hashes']}
        properties = {p['name']: p['value'] for p in component['properties']}
        report['sbom'][path.name].update(components=len(document['components']), properties=properties, archive_hash_matches=hashes['SHA-256'] == digest)
        if hashes['SHA-256'] != digest or properties['php:artifact-file-name'] != runtime.name:
            errors.append('CycloneDX artifact identity/hash does not match the archive')
report['errors'] = errors
print(json.dumps(report, indent=2))
sys.exit(bool(errors))
