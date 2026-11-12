import sys,json,math
from pathlib import Path
import numpy as np
from scipy.signal import resample_poly
sys.path.insert(0,str(Path('tools').resolve()))
from analyze_s7_variants import read_audio,resample,match
root=Path('/Users/k/Library/Containers/com.kellyjanderson.readAloud.mlxPlaybackTest/Data/s7-8bit-production-v52-20261111')
r=json.loads((root/'receipt.json').read_text()); q=r['queuedAudio'][11]
rate,source,_,_=read_audio(Path(q['reference']['path']),20_000_000,5)
cr,capture,_,_=read_audio(root/'capture.wav',300_000_000,300)
start=9.6;finish=10.6
source=resample(source,rate,cr*4)
window=resample_poly(capture[round(start*cr):round(finish*cr)],4,1)
active=np.flatnonzero(np.abs(source)>.01)
full_index,full_score=match(window,source)
part_index,part_score=match(window,source[active[0]:active[-1]+1])
out={'diagnosticOnly':True,'passed':False,'queueIndex':11,'sourcePeak':float(np.max(np.abs(source))),'sourceRms':float(np.sqrt(np.mean(source*source))),'fullFrames':len(source),'aboveThresholdSpanFrames':int(active[-1]-active[0]+1),'fullReferenceMatch':{'captureStartSeconds':None if full_index is None else start+full_index/(cr*4),'score':full_score},'thresholdSpanMatch':{'captureStartSeconds':None if part_index is None else start+(part_index-int(active[0]))/(cr*4),'score':part_score},'limits':'Offline hypothesis probe; no qualification or source placement override.'}
Path('tmp/s7-final/v52-low-information-probe.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out))
