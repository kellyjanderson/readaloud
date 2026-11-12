"""Repair one deliberately corrupted config in an isolated, complete QA cache.

Uses the production HF owner. Never changes weights or a non-QA cache. Failed
attempts restore the original config bytes; a successful repair must preserve
every other file's inode, size and nanosecond modification time.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def probe(model_id, cache, output):
    cache = cache.expanduser().resolve()
    require('com.kellyjanderson.readAloud.mlxPlaybackTest' in str(cache),
            'Requires isolated QA cache')
    require(not output.exists(), 'Preserve existing evidence')
    source = Path(__file__).resolve().parents[1] / 'assets' / 'mlx_tts_worker.py'
    spec = importlib.util.spec_from_file_location('repair_probe_worker', source)
    worker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker)
    manifest = worker._model_manifest(model_id)
    snapshot = (cache / ('models--' + manifest['repo'].replace('/', '--')) /
                'snapshots' / manifest['revision'])
    require(worker._verify_scene_model(snapshot, manifest, output.parent / 'repair-verification'),
            'Requires already complete pinned QA snapshot')
    def identities():
        result = {}
        for name in manifest['files']:
            stat = (snapshot / name).stat()
            result[name] = {'inode': stat.st_ino, 'bytes': stat.st_size,
                            'mtimeNs': stat.st_mtime_ns}
        return result
    before = identities()
    config = (snapshot / 'config.json').resolve()
    require(config.is_relative_to(cache), 'Config outside QA cache')
    original = config.read_bytes()
    require(len(original) <= 256 * 1024, 'Unexpected config size')
    receipt = {'passed': False, 'modelId': model_id,
               'pinnedIdentity': manifest['repo'] + '@' + manifest['revision'],
               'snapshot': str(snapshot), 'before': before,
               'originalConfigSha256': hashlib.sha256(original).hexdigest()}
    try:
        config.write_bytes(b'{"deliberateQaCorruption":true}\n')
        acquired = worker._download_model(model_id, str(cache))
        require(acquired.resolve() == snapshot.resolve(), 'Changed snapshot')
        require(worker._verify_scene_model(snapshot, manifest, output.parent / 'repair-verification'),
                'Repair did not restore pinned integrity')
        after = identities()
        unchanged = all(after[name] == value for name, value in before.items()
                        if name != 'config.json')
        require(unchanged, 'Repair changed a completed non-config artifact')
        require(config.read_bytes() == original, 'Config bytes differ after repair')
        receipt.update(passed=True, after=after,
                       completedNonConfigArtifactsUnchanged=True,
                       repairedConfigSha256=hashlib.sha256(config.read_bytes()).hexdigest())
    except BaseException as error:
        receipt['error'] = repr(error)
        raise
    finally:
        if not config.exists() or config.read_bytes() != original:
            config.write_bytes(original)
        receipt['originalConfigRestored'] = config.read_bytes() == original
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model_id', choices=('fish_drama3_8bit', 'fish_drama3_4bit'))
    parser.add_argument('cache', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = probe(args.model_id, args.cache, args.output)
    print(json.dumps({key: value for key, value in result.items()
                      if key not in ('before', 'after')}))
