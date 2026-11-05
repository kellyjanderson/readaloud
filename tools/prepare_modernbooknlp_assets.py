"""Explicit, pinned acquisition for the isolated provider qualification runtime.

Uses huggingface_hub's existing persistent cache/resume mechanism. Inference is
strictly offline. This CLI is not yet the reader Settings/download integration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def prepare(root, offline=False):
    from huggingface_hub import snapshot_download
    catalog = json.loads((Path(__file__).resolve().parents[1] / 'assets/modernbooknlp_models.json').read_text())
    root = root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    paths, hashes = {}, {}
    for spec in catalog['repositories']:
        options = dict(repo_id=spec['repo'], revision=spec['revision'],
                       cache_dir=str(root / 'hub'), allow_patterns=list(spec['files']), max_workers=2)
        try:
            path = Path(snapshot_download(**options, local_files_only=True))
            if not all((path / name).is_file() for name in spec['files']):
                raise FileNotFoundError('Incomplete cached snapshot')
        except (OSError, ValueError):
            if offline:
                raise
            path = Path(snapshot_download(**options))
        for name, expected in spec['files'].items():
            if digest(path / name) != expected:
                raise ValueError('Provider checksum failed: ' + name)
            hashes[str((path / name).relative_to(root))] = expected
        paths[spec['role']] = path
        print(json.dumps({'stage': 'verifiedRepository', 'repo': spec['repo'], 'files': len(spec['files'])}), flush=True)
    model_dir = root / 'booknlp_models'
    model_dir.mkdir(exist_ok=True)
    for spec in catalog['booknlp']:
        path = model_dir / spec['filename']
        if not path.is_file():
            if offline:
                raise FileNotFoundError(path)
            temporary = path.with_suffix('.partial')
            with urllib.request.urlopen(spec['url'], timeout=60) as source, temporary.open('wb') as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
            if digest(temporary) != spec['sha256']:
                raise ValueError('Provider checksum failed: ' + spec['filename'])
            temporary.replace(path)
        if digest(path) != spec['sha256']:
            raise ValueError('Provider checksum failed: ' + spec['filename'])
        hashes[str(path.relative_to(root))] = spec['sha256']
    qa = model_dir / 'ModernBERT_T2000.safetensors'
    target = paths['qa'] / qa.name
    if not qa.exists():
        qa.symlink_to(target)
    expected = next(s for s in catalog['repositories'] if s['role'] == 'qa')['files'][qa.name]
    if digest(qa) != expected:
        raise ValueError('Quotation model mismatch')
    hashes[str(qa.relative_to(root))] = expected
    manifest = {'schema': 1, 'upstream': catalog['upstream'], 'modelIdentity': expected,
                'runtimePatchSha256': catalog['runtimePatchSha256'],
                'sha256': hashes, **{key: str(paths[key].relative_to(root)) for key in ('encoder', 'entityEncoder', 'corefEncoder')}}
    temporary = root / 'runtime.json.tmp'
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(root / 'runtime.json')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    prepare(args.root, args.offline)
