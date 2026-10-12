"""Compare audio-sample asymmetric RMS with windowed-RMS input, not constant DC.

This exposes information lost before Box1's collector; it is not a firmware model
until its actual window is established. No gain/ballistic retuning is selected.
"""
import math, json
from pathlib import Path
import numpy as np

fs=48000; seconds=3; t=np.arange(fs*seconds)/fs
amplitude=np.where(t<1,.12,np.where(t<2,.36,0))
samples=amplitude*np.sin(2*math.pi*1000*t)
attack=math.exp(-2/(fs*.085)); decay=math.exp(-2/(fs*.520))
power=0.; pcm=[]
for sample in samples:
    target=float(sample*sample)
    power=target+(decay if target<power else attack)*(power-target)
    pcm.append(math.sqrt(max(0,power)))
pcm=np.array(pcm)
results={}
def onset(values,times):
    low=float(np.median(values[(times>.8)&(times<.99)]))
    high=float(np.median(values[(times>1.8)&(times<1.99)]))
    result={}
    for threshold in (.1,.5,.9):
        indices=np.flatnonzero((times>=1)&(times<2)&(values>=low+threshold*(high-low)))
        result[f'rise_{int(threshold*100)}_ms']=float((times[indices[0]]-1)*1000) if len(indices) else None
    result['steady_level']=high
    return result
results['HTPC_audio_sample_reference']=onset(pcm,t)
for window in (5,10,20,40,80):
    size=int(fs*window/1000); state=0.; values=[]; times=[]
    for end in range(size,len(samples)+1,size):
        target=float(np.mean(samples[end-size:end]**2))
        response=520 if target<state else 85
        state=target+math.exp(-2*window/response)*(state-target)
        values.append(math.sqrt(max(0,state))); times.append(end/fs)
    results[f'Illustrative_{window}ms_nonoverlapping_RMS_window']=onset(np.asarray(values),np.asarray(times))
results['limitations']=['1 kHz sine only; both engines normalized to their own steady levels.',
 'Real firmware window/source waveform/render timing unknown; these are mechanisms, not measured hardware latency.',
 'The old constant-RMS equivalence test cannot establish equivalence to sample-by-sample audio processing.']
path=Path(__file__).parent/'captures'/'envelope-model.json'
path.write_text(json.dumps(results,indent=2),encoding='utf-8')
print(json.dumps(results,indent=2))
