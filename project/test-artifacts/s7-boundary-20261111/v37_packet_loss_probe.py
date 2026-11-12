import os
for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS'): os.environ[key]='1'
import json,sys
from pathlib import Path
import numpy as np
from scipy.signal import correlate,resample_poly
sys.path.insert(0,'tools')
from analyze_s7_variants import read_audio,resample,MAX_CAPTURE_BYTES
root=Path('/Users/k/Library/Containers/com.kellyjanderson.readAloud.mlxPlaybackTest/Data/s7-4bit-utility-v37-20261111')
dual=json.loads(Path('tmp/s7/4bit-utility-v37-dual.json').read_text())
packet=dual['packets'][4]; before=dual['packets'][3]; after=dual['packets'][5]
rate,source,_,_=read_audio(Path(packet['reference']['path']),48_000_000,600)
hr=192000; source=resample(source,rate,hr)
report={'diagnosticOnly':True,'passed':False,'queueIndex':4,'scope':'Exact-zero and local fragment diagnostics; no threshold relaxation or listening claim.','streams':{}}
for name in ('capture','coreaudio'):
    sr,pcm,_,_=read_audio(root/(name+'.wav'),MAX_CAPTURE_BYTES,300)
    begin=before[name]['captureEndSeconds']; end=after[name]['captureStartSeconds']
    lo=round(begin*sr); hi=round(end*sr); region=pcm[lo:hi]
    mask=region==0; edge=np.diff(np.r_[False,mask,False].astype(np.int8)); starts=np.flatnonzero(edge==1); ends=np.flatnonzero(edge==-1)
    zeros=[{'startSeconds':begin+a/sr,'durationMs':(b-a)*1000/sr} for a,b in zip(starts,ends) if b-a>=sr*.001]
    high=resample(pcm,sr,hr); left=max(0,round((begin-.1)*hr)); right=min(len(high),round((end+.1)*hr)); window=high[left:right]
    fragments=[]
    for at in range(0,len(source)-round(.02*hr)+1,round(.02*hr)):
        f=source[at:at+round(.02*hr)]; power=float(np.dot(f,f))
        if power<=len(f)*1e-8: continue
        cc=correlate(window,f,mode='valid',method='fft'); sums=np.r_[0,np.cumsum(window*window)]; powers=sums[len(f):]-sums[:-len(f)]; scores=np.zeros_like(cc); valid=powers>max(len(f)*1e-10,power*1e-6)
        np.divide(cc,np.sqrt(np.maximum(powers,0)*power),out=scores,where=valid); index=int(scores.argmax())
        actual=(left+index)/hr
        fragments.append({'sourceOffsetMs':at*1000/hr,'bestLocalCorrelation':float(scores[index]),'captureStartSeconds':actual,'relativeToContiguousMs':(actual-begin-at/hr)*1000})
    report['streams'][name]={'contiguousExpectedStartSeconds':begin,'nextVerifiedStartSeconds':end,'intervalMs':len(region)*1000/sr,'exactZeroRuns':zeros,'fragments20ms':fragments}
Path('tmp/s7/v37-packet-loss-micro.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:{'intervalMs':v['intervalMs'],'zeros':v['exactZeroRuns'],'fragmentCorrelationsMin':min(x['bestLocalCorrelation'] for x in v['fragments20ms'])} for k,v in report['streams'].items()}))
