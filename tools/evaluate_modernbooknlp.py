"""Fixed synthetic smoke cases, not a held-out literary quality benchmark."""
import argparse
import contextlib
import importlib.util
import json
from pathlib import Path
import resource
import sys
import time

parser=argparse.ArgumentParser()
parser.add_argument('root', type=Path)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
project=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('provider',project/'assets/modernbooknlp_worker.py')
provider=importlib.util.module_from_spec(spec);spec.loader.exec_module(provider)
cases=json.loads((project/'test/fixtures/modernbooknlp/smoke_cases.json').read_text())
started=time.monotonic()
with contextlib.redirect_stdout(sys.stderr):
 pipeline,manifest=provider.load_pipeline(args.root.resolve())
 loaded=time.monotonic()
 rows=[]
 for i,case in enumerate(cases):
  request=dict(schema=1,requestId=case['id'],ownerId='evaluation',workId='synthetic-smoke',sourceRevision=case['id'],analysisRevision=1,sequence=i,text=case['text'])
  begin=time.monotonic()
  try:
   result=provider.analyze(pipeline,request)
   names={e['entityId']:sorted({m['text'] for m in e['mentions'] if m['proper']}) for e in result['entities']}
   actual=[names.get(q['entityId'],[]) if q['entityId'] is not None else None for q in result['quotes']]
   matches=len(actual)==len(case['speakers']) and all((got is None if expected is None else got==[expected]) for expected,got in zip(case['speakers'],actual))
   rows.append(dict(id=case['id'],expected=case['speakers'],actual=actual,passed=matches,seconds=time.monotonic()-begin,result=result))
  except Exception as error:
   rows.append(dict(id=case['id'],passed=False,error=f'{type(error).__name__}: {error}',seconds=time.monotonic()-begin))
receipt=dict(suite='synthetic smoke; not promotion evidence',providerRevision=provider.UPSTREAM,adapterVersion=provider.ADAPTER_VERSION,modelIdentity=manifest['modelIdentity'],loadSeconds=loaded-started,peakRssBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,results=rows)
args.output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({**{k:v for k,v in receipt.items() if k!='results'},'passed':sum(r['passed'] for r in rows),'total':len(rows)}))
