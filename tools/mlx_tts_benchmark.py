"""Measure emitted speech throughput for a supplied corpus; no quality claims."""
import argparse
import importlib.util
import json
from pathlib import Path
import time

import mlx.core as mx

parser = argparse.ArgumentParser()
parser.add_argument('model')
parser.add_argument('checkpoint')
parser.add_argument('corpus')
parser.add_argument('output')
parser.add_argument('--bits', type=int, default=0)
args = parser.parse_args()
output = Path(args.output)
output.mkdir(parents=True, exist_ok=False)
spec = importlib.util.spec_from_file_location('worker', Path(__file__).parents[1] / 'assets/mlx_tts_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
started = time.monotonic()
worker._load(args.model, args.checkpoint, str(output / 'hub'))
if args.bits:
    from mlx_audio.lm.convert import quantize_model
    predicate = getattr(worker._model, 'model_quant_predicate', lambda p, m: True)
    worker._model, _ = quantize_model(worker._model, {}, 64, args.bits, quant_predicate=predicate)
    mx.eval(worker._model.parameters())
load_seconds = time.monotonic() - started
words = Path(args.corpus).read_text().split()
rows = []
for index, count in enumerate((18, 60, 60)):
    text = ' '.join(words[index * 60:index * 60 + count])
    path = output / f'{index}.wav'
    mx.random.seed(0)
    started = time.monotonic()
    worker._synthesize({'modelId': args.model, 'text': text, 'outputPath': str(path), 'voice': 'casual_male'})
    elapsed = time.monotonic() - started
    import soundfile as sf
    data, rate = sf.read(path)
    duration = len(data) / rate
    row = {'words': count, 'synthesisSeconds': elapsed, 'audioSeconds': duration, 'realTimeFactor': elapsed / duration, 'audioPath': str(path)}
    rows.append(row)
    print(json.dumps(row), flush=True)
(output / 'receipt.json').write_text(json.dumps({'engine': args.model, 'bits': args.bits, 'loadSeconds': load_seconds, 'samples': rows}, indent=2))
worker._unload()
