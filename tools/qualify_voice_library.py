"""Exercise every reference with actual inference. Keeps audio/receipts local."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import time

parser = argparse.ArgumentParser()
parser.add_argument('engine', choices=['qwen3_tts_base_1_7b', 'moss_tts_8b'])
parser.add_argument('checkpoint')
parser.add_argument('output')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('voice_worker', root / 'assets/mlx_tts_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
manifest = json.loads((root / 'assets/voice_library/library.json').read_text())
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
rows = []
import soundfile as sf
import mlx.core as mx
try:
    worker._load(args.engine, args.checkpoint, str(output / 'hub'))
    for index, voice in enumerate(manifest['voices']):
        path = output / f'{voice["id"]}.wav'
        started = time.monotonic()
        mx.random.seed(8931)
        if not path.exists():
            worker._synthesize(dict(
                modelId=args.engine, voice=voice['id'],
                text='The lantern by the window is still burning.',
                outputPath=str(path), referenceAudioPath=str(root / voice['asset']),
                referenceText=voice['referenceText'], synthesisIdentity=f'voices-{index}',
            ))
        audio, rate = sf.read(path)
        row = dict(voice=voice['id'], referenceSha256=voice['sha256'],
                   outputSha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                   durationSeconds=len(audio)/rate, peak=float(abs(audio).max()),
                   synthesisSeconds=time.monotonic()-started, audioPath=str(path))
        if row['durationSeconds'] < 1 or row['peak'] < 0.01:
            raise RuntimeError(f'Unusable output: {row}')
        rows.append(row)
        (output / 'receipt.json').write_text(json.dumps(dict(
            engine=args.engine, voiceCount=len(rows), complete=len(rows)==30,
            rows=rows), indent=2))
        print(json.dumps(row), flush=True)
        mx.clear_cache()
    if len({r['outputSha256'] for r in rows}) != 30:
        raise RuntimeError('Identical outputs across requested reference identities')
finally:
    worker._unload()
