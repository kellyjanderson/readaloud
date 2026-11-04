"""Speaker-embedding diagnostic, separate from routing and listening acceptance.

Uses Qwen Base's maintained speaker encoder on real reference/generated speech.
This is a model-relative diagnostic, not a calibrated human identity decision.
"""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('checkpoint')
parser.add_argument('audio_directory', nargs='+')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'assets/voice_library/library.json').read_text())
import mlx.core as mx
import numpy as np
import soundfile as sf
from mlx_audio.tts import load
model = load(args.checkpoint)


def embedding(path):
    audio, rate = sf.read(path)
    vector = np.asarray(model.extract_speaker_embedding(mx.array(audio, dtype=mx.float32), rate)).reshape(-1)
    return vector / np.linalg.norm(vector)


ids = [v['id'] for v in manifest['voices']]
references = np.stack([embedding(root / v['asset']) for v in manifest['voices']])
for directory in args.audio_directory:
    folder = Path(directory)
    outputs = np.stack([embedding(folder / f'{key}.wav') for key in ids])
    similarities = outputs @ references.T
    output_pairs = outputs @ outputs.T
    reference_pairs = references @ references.T
    np.fill_diagonal(output_pairs, -1)
    np.fill_diagonal(reference_pairs, -1)
    rows = []
    for index, key in enumerate(ids):
        rank = int(np.flatnonzero(np.argsort(-similarities[index]) == index)[0]) + 1
        rows.append(dict(voice=key, ownReferenceSimilarity=float(similarities[index, index]),
                         ownReferenceRank=rank, closestReference=ids[int(similarities[index].argmax())]))
    report = dict(encoder='Qwen Base speaker encoder; uncalibrated diagnostic',
                  count=len(ids), top1Matches=sum(r['ownReferenceRank'] == 1 for r in rows),
                  medianOwnSimilarity=float(np.median(np.diag(similarities))),
                  maximumOutputPairSimilarity=float(output_pairs.max()),
                  maximumReferencePairSimilarity=float(reference_pairs.max()), rows=rows)
    (folder / 'speaker-diagnostic.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({k:v for k,v in report.items() if k != 'rows'}), flush=True)
