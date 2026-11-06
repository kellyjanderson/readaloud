"""Evaluate frozen source-reader labels without exposing them to the provider.

Labels may contain private prose: keep inputs/results outside tracked fixtures.
This measures raw quotation/entity output, not native playback or promotion.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import json
from pathlib import Path
import resource
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('root', type=Path)
parser.add_argument('--labels', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
cases = json.loads(args.labels.read_text())
for case in cases:
    assert hashlib.sha256(case['text'].encode()).hexdigest() == case['sha256']
project = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('provider', project / 'assets/modernbooknlp_worker.py')
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)
started = time.monotonic()
rows = []
with contextlib.redirect_stdout(sys.stderr):
    pipeline, manifest = provider.load_pipeline(args.root.resolve())
    load_seconds = time.monotonic() - started
    for index, case in enumerate(cases):
        request = dict(schema=1, requestId=case['id'], ownerId='qualification',
                       workId=case['id'], sourceRevision=case['sha256'],
                       analysisRevision=1, sequence=index, text=case['text'])
        begin = time.monotonic()
        try:
            result = provider.analyze(pipeline, request)
            names = {e['entityId']: sorted({m['text'] for m in e['mentions'] if m['proper']})
                     for e in result['entities']}
            encoded = case['text'].encode('utf-16-le')
            quotes = [dict(text=encoded[q['startUtf16'] * 2:q['endUtf16'] * 2].decode('utf-16-le'),
                           names=names.get(q['entityId'], []), entityId=q['entityId'])
                      for q in result['quotes']]
            compared = []
            for label in case['labels']:
                matches = [q for q in quotes if q['text'].strip('"“”') == label['text']]
                aliases = case.get('aliases', {})
                actual = {aliases.get(n, n) for q in matches for n in q['names']}
                expected = label['speaker']
                compared.append(dict(expected=expected, actual=sorted(actual),
                                     exactSpan=len(matches) == 1,
                                     correct=len(matches) == 1 and
                                     (actual == {expected} if expected else not actual)))
            rows.append(dict(id=case['id'], sha256=case['sha256'],
                             seconds=time.monotonic() - begin, compared=compared,
                             quotes=quotes, result=result))
        except Exception as error:
            rows.append(dict(id=case['id'], error=f'{type(error).__name__}: {error}'))
        print(case['id'], 'complete', file=sys.stderr, flush=True)
        args.output.write_text(json.dumps(dict(providerRevision=provider.UPSTREAM,
            adapterVersion=provider.ADAPTER_VERSION, modelIdentity=manifest['modelIdentity'],
            labelsSha256=hashlib.sha256(args.labels.read_bytes()).hexdigest(),
            loadSeconds=load_seconds, peakRssBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            results=rows), indent=2) + '\n')
for row in rows:
    print(row['id'], row.get('error') or
          f"{sum(q['correct'] for q in row['compared'])}/{len(row['compared'])}")
