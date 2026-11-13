"""Exercise the selected production voice bank with offline references.

Receipts prove emitted PCM/accounting, not perceptual speaker distinctness.
"""
import argparse
import json
from pathlib import Path
import time

from mlx_protocol_client import MlxClient
from mlx_probe_support import descriptor, load_model, provenance, resolve_voice, synthesize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', help='Exact installed production model ID')
    parser.add_argument('checkpoint', help='Existing local checkpoint; never downloads')
    parser.add_argument('output', help='New evidence directory; existing files are never reused')
    parser.add_argument('--reference-cache', help='Existing app MLX root containing voice-library')
    parser.add_argument('--bits', type=int, choices=(0, 4), default=0)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    with MlxClient() as client:
        metadata = client.metadata()
        model = descriptor(metadata, args.engine)
        # Resolve the complete bank before inference; a missing remote reference
        # is an actionable offline blocker, never a silently reduced voice count.
        voices = [resolve_voice(model, voice['id'], args.reference_cache) for voice in model['voices']]
        if not voices:
            raise ValueError('Production engine has no usable voices')
        output.mkdir(parents=True, exist_ok=False)
        loaded = load_model(client, model, args.checkpoint, output / 'hub', args.bits)
        receipt = {**provenance(metadata, model, loaded, args.bits), 'expectedVoiceCount': len(voices),
                   'complete': False, 'rows': []}
        for index, (voice, voice_provenance) in enumerate(voices):
            started = time.monotonic()
            evidence = synthesize(client, model, voice, 'The lantern by the window is still burning.',
                                  output / voice['voice'], f'voices-{index}')
            row = {**evidence, 'voice': voice_provenance, 'synthesisSeconds': time.monotonic() - started}
            if row['durationSeconds'] < 1 or row['peak'] < .01:
                raise RuntimeError(f'Output failed duration/peak signal checks: {row}')
            receipt['rows'].append(row)
            receipt['voiceCount'] = len(receipt['rows'])
            # Hash equality is a diagnostic. Different bytes cannot establish
            # perceptual diversity; identical bytes must not imply listening.
            receipt['distinctOutputHashes'] = len({value['outputSha256'] for value in receipt['rows']})
            (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            print(json.dumps(row), flush=True)
        if receipt['distinctOutputHashes'] != len(voices):
            raise RuntimeError('Repeated output bytes across requested voice identities; perceptual identity remains untested')
    receipt['complete'] = True
    receipt['workerExitCode'] = client.child.returncode
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
