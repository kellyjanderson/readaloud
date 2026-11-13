"""Clone only production-described caches into a new, isolated QA data root."""
import argparse
from itertools import chain
from pathlib import Path
import shutil
import subprocess
import tempfile

from mlx_protocol_client import MlxClient

MLX_SUFFIX = Path('Library/Application Support/read_aloud/mlx-tts')


def cache_paths(metadata):
    result = [MLX_SUFFIX / model['cacheDirectory'] for model in metadata['models'].values()]
    result.extend((MLX_SUFFIX / 'voice-library', Path('.cache/huggingface/hub'),
                   MLX_SUFFIX / 'hub'))
    for path in result:
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('Catalog cache directory escapes QA root')
    return sorted(set(result), key=str)


def stage_cache(source, destination, metadata, *, clone=None):
    source, destination = Path(source).expanduser().resolve(), Path(destination).expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('QA data root already exists; refusing to overwrite user or prior QA data')
    destination = destination.resolve()
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError('QA data root must be independent from source data')
    source = source.resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.mlx-qa-', dir=destination.parent))
    copied = []
    try:
        for relative in cache_paths(metadata):
            origin = source / relative
            if not origin.exists():
                continue
            # Hub uses relative links into its own blobs. Reject any link that
            # would alias the user's files after cloning into the QA sandbox.
            for entry in chain((origin,), origin.rglob('*')):
                if entry.is_symlink():
                    resolved = entry.resolve(strict=True)
                    if origin.resolve() not in resolved.parents:
                        raise ValueError(f'Cache symlink escapes its independent copy: {entry}')
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if clone is None:
                subprocess.run(['cp', '-cR', str(origin), str(target)], check=True)
            else:
                clone(origin, target)
            copied.append(str(relative))
        # Reserve the destination exclusively before moving our staged entries.
        destination.mkdir(exist_ok=False)
        try:
            for entry in stage.iterdir():
                entry.rename(destination / entry.name)
        except BaseException:
            shutil.rmtree(destination)
            raise
        return copied
    finally:
        shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_data')
    parser.add_argument('new_qa_data')
    args = parser.parse_args()
    with MlxClient() as client:
        metadata = client.metadata()
    for path in stage_cache(args.source_data, args.new_qa_data, metadata):
        print(path)


if __name__ == '__main__':
    main()
