"""Measure production-worker throughput for a supplied corpus; no quality claims."""
import argparse
import json
from pathlib import Path
import time

from mlx_protocol_client import MlxClient
from mlx_probe_support import descriptor, load_model, provenance, resolve_voice, synthesize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model')
    parser.add_argument('checkpoint', help='Existing local checkpoint; never downloads')
    parser.add_argument('corpus')
    parser.add_argument('output', help='New evidence directory')
    parser.add_argument('--bits', type=int, choices=(0, 4), default=0)
    parser.add_argument('--voice', required=True, help='Exact production preset or library ID')
    parser.add_argument('--reference-cache', help='Existing app MLX root for downloaded references')
    args = parser.parse_args()
    words = Path(args.corpus).read_text().split()
    if len(words) < 180:
        parser.error('Corpus must contain at least 180 words for the three unchanged workloads')
    output = Path(args.output).resolve()
    with MlxClient() as client:
        metadata = client.metadata()
        model = descriptor(metadata, args.model)
        voice, voice_provenance = resolve_voice(model, args.voice, args.reference_cache)
        output.mkdir(parents=True, exist_ok=False)
        started = time.monotonic()
        loaded = load_model(client, model, args.checkpoint, output / 'hub', args.bits)
        receipt = {**provenance(metadata, model, loaded, args.bits), 'voice': voice_provenance,
                   'loadSeconds': time.monotonic() - started, 'complete': False, 'samples': []}
        for index, count in enumerate((18, 60, 60)):
            text = ' '.join(words[index * 60:index * 60 + count])
            started = time.monotonic()
            evidence = synthesize(client, model, voice, text, output / str(index), f'benchmark-{index}')
            elapsed = time.monotonic() - started
            row = {**evidence, 'words': len(text.split()), 'synthesisSeconds': elapsed,
                   'audioSeconds': evidence['durationSeconds'],
                   'realTimeFactor': elapsed / evidence['durationSeconds']}
            receipt['samples'].append(row)
            (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            print(json.dumps(row), flush=True)
    # A complete receipt includes successful terminal shutdown and verified exit.
    receipt['complete'] = True
    receipt['workerExitCode'] = client.child.returncode
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
