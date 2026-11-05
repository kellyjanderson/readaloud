"""Shared pinned acquisition for app Settings and the isolated provider CLI.

Uses huggingface_hub's existing persistent cache/resume mechanism. Inference is
strictly offline after acquisition.
"""
import argparse
import contextlib
import time
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def prepare(root, offline=False, progress=lambda **values: None):
    from huggingface_hub import snapshot_download
    catalog = json.loads(Path(__file__).with_name('modernbooknlp_models.json').read_text())
    root = root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    paths, hashes = {}, {}
    completed_files = 0
    total_files = sum(len(spec['files']) for spec in catalog['repositories']) + len(catalog['booknlp'])
    def verified():
        nonlocal completed_files
        completed_files += 1
        progress(stage='verify', completed=completed_files, total=total_files, unit='files', message='Verifying analysis files')
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
            # Pinned Hub 0.36.2 exposes byte updates in this context. Keep its
            # cache, locking and retry implementation; adapt telemetry only.
            from huggingface_hub import file_download
            original = file_download._get_progress_bar_context
            @contextlib.contextmanager
            def measured(*args, **kwargs):
                with original(*args, **kwargs) as bar:
                    update = bar.update
                    last = [0.0]
                    # tqdm deliberately stops counting when its terminal UI is
                    # disabled. App telemetry counts the actual byte callbacks.
                    completed = kwargs.get('initial', 0)
                    total = kwargs.get('total')
                    def report(n=1):
                        nonlocal completed
                        completed += n
                        result = update(n)
                        now = time.monotonic()
                        if now-last[0] >= 0.15 or completed == total:
                            last[0] = now
                            progress(stage='download', completed=completed, total=total, unit='bytes', message='Downloading ' + str(kwargs.get('desc', spec['repo'])))
                        return result
                    bar.update = report
                    try:
                        yield bar
                    finally:
                        bar.update = update
            file_download._get_progress_bar_context = measured
            try:
                options['max_workers'] = 1
                path = Path(snapshot_download(**options))
            finally:
                file_download._get_progress_bar_context = original
        for name, expected in spec['files'].items():
            if digest(path / name) != expected:
                raise ValueError('Provider checksum failed: ' + name)
            hashes[str((path / name).relative_to(root))] = expected
            verified()
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
                total = int(source.headers['Content-Length']) if source.headers.get('Content-Length') else None
                copied = 0
                while chunk := source.read(1024 * 1024):
                    target.write(chunk)
                    copied += len(chunk)
                    progress(stage='download', completed=copied, total=total, unit='bytes', message='Downloading ' + spec['filename'])
            if digest(temporary) != spec['sha256']:
                raise ValueError('Provider checksum failed: ' + spec['filename'])
            temporary.replace(path)
        if digest(path) != spec['sha256']:
            raise ValueError('Provider checksum failed: ' + spec['filename'])
        hashes[str(path.relative_to(root))] = spec['sha256']
        verified()
    qa = model_dir / 'ModernBERT_T2000.safetensors'
    target = paths['qa'] / qa.name
    if not qa.exists():
        qa.symlink_to(Path('..') / target.relative_to(root))
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
