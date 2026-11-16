"""Clone only production-described caches into a new, isolated QA data root."""
import argparse
from itertools import chain
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from mlx_protocol_client import MlxClient

MLX_SUFFIX = Path('Library/Application Support/read_aloud/mlx-tts')
SOURCE_BUNDLE_ID = 'com.kellyjanderson.readAloud'
QA_BUNDLE_ID = SOURCE_BUNDLE_ID + '.mlxPlaybackTest'


def bundle_mlx_suffix(bundle_id):
    if not isinstance(bundle_id, str) or not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('Invalid bundle ID')
    return MLX_SUFFIX.parent.parent / bundle_id / 'read_aloud/mlx-tts'


def cache_paths(metadata, bundle_id=SOURCE_BUNDLE_ID):
    # Match _prepareModel: path_provider adds the bundle ID, while the
    # installer/older apps used the containing Application Support directory.
    # Deliberately omit runtime, catalog helpers, preferences and generated audio.
    leaves = [Path(model['cacheDirectory']) for model in metadata['models'].values()]
    for path in leaves:
        if path.is_absolute() or '..' in path.parts or path == Path('.'):
            raise ValueError('Catalog cache directory escapes QA root')
    leaves.extend((Path('models'), Path('voice-library'), Path('hub'), Path('runtime-cache/hub')))
    result = [root / leaf for root in (MLX_SUFFIX, bundle_mlx_suffix(bundle_id)) for leaf in leaves]
    result.append(Path('.cache/huggingface/hub'))
    return sorted(set(result), key=str)


def _validate_independent_links(root):
    for entry in chain((root,), root.rglob('*')):
        if entry.is_symlink():
            if entry.readlink().is_absolute():
                raise ValueError(f'Cache symlink escapes independent copying through an absolute target: {entry}')
            resolved = entry.resolve(strict=True)
            if root.resolve() not in resolved.parents:
                raise ValueError(f'Cache symlink escapes its independent copy: {entry}')


def stage_cache(source, destination, metadata, *, source_bundle_id=SOURCE_BUNDLE_ID,
                destination_bundle_id=QA_BUNDLE_ID, clone=None):
    source_suffix = bundle_mlx_suffix(source_bundle_id)
    destination_suffix = bundle_mlx_suffix(destination_bundle_id)
    paths = cache_paths(metadata, source_bundle_id)
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
        for relative in paths:
            origin = source / relative
            # An ancestor link could hide an external cache even when its
            # contents contain no links. Never discover caches outside Data.
            ancestor = source
            for part in relative.parts[:-1]:
                ancestor /= part
                if ancestor.is_symlink():
                    raise ValueError(f'Cache symlink escapes its independent data root: {ancestor}')
            if not origin.exists() and not origin.is_symlink():
                continue
            # Hub uses relative links into its own blobs. Reject any link that
            # would alias the user's files after cloning into the QA sandbox.
            _validate_independent_links(origin)
            mapped = (destination_suffix / relative.relative_to(source_suffix)
                      if relative.is_relative_to(source_suffix) else relative)
            target = stage / mapped
            target.parent.mkdir(parents=True, exist_ok=True)
            if clone is None:
                subprocess.run(['cp', '-cR', str(origin), str(target)], check=True)
            else:
                clone(origin, target)
            # Inspect the actual preserved links too: the source may change
            # between preflight and copying, while this staging tree is ours.
            _validate_independent_links(target)
            copied.append(str(mapped))
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
    parser.add_argument('--source-bundle-id', default=SOURCE_BUNDLE_ID)
    parser.add_argument('--destination-bundle-id', default=QA_BUNDLE_ID)
    args = parser.parse_args()
    # Validate identities before starting the metadata child or staging work.
    bundle_mlx_suffix(args.source_bundle_id)
    bundle_mlx_suffix(args.destination_bundle_id)
    with MlxClient() as client:
        metadata = client.metadata()
    for path in stage_cache(args.source_data, args.new_qa_data, metadata,
                           source_bundle_id=args.source_bundle_id,
                           destination_bundle_id=args.destination_bundle_id):
        print(path)


if __name__ == '__main__':
    main()
