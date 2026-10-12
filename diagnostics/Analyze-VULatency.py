"""Measure delivery with honest clock bounds, plus deterministic sample-time replays."""
import csv, json, sys, math
from pathlib import Path
from datetime import datetime
import numpy as np

def load(path):
    with path.open(encoding='utf-8-sig', newline='') as f: return list(csv.DictReader(f))
def stats(values):
    a=np.asarray(values,dtype=float)
    if not len(a): return {'count':0}
    return {'count':len(a),'median':float(np.median(a)),'p95':float(np.quantile(a,.95)),
            'p99':float(np.quantile(a,.99)),'max':float(np.max(a))}
def replay(rows, fixed=False):
    previous=int(rows[0]['UtcTicks']); power=np.zeros(2); result=[]
    for row in rows:
        tick=int(row['UtcTicks']); dt=10.0 if fixed else max(0,(tick-previous)/10000); previous=tick
        target=np.power(10,np.array([float(row['LeftRmsDb']),float(row['RightRmsDb'])])/10)
        tau=np.where(target<power,520,85)
        power=target+np.exp(-2*dt/tau)*(power-target)
        result.append(np.sqrt(np.maximum(0,power)))
    return np.asarray(result)
def analyze(directory):
    all_raw=load(directory/'box1_raw.csv')
    raw=[r for r in all_raw if all(r.get(k) for k in ['UtcTicks','LeftRmsDb','RightRmsDb'])]
    frames=load(directory/'rainmeter_comparison.csv')
    dt=np.diff([int(r['UtcTicks']) for r in raw])/10000
    result={'capture':directory.name,'malformed_tail_rows':len(all_raw)-len(raw),'collector_completed':(directory/'box1_collector_capture.complete').exists(),'receipt_interval_ms':stats(dt),
            'receipt_intervals_under_1ms_percent':float(np.mean(dt<1)*100),
            'raw_rate_hz':float((len(raw)-1)/sum(dt)*1000),
            'frame_count':len(frames), 'limitations':['No synchronized audible/ADC reference; software delivery is not end-to-end latency.',
             'Diagnostic frame clock is sampled; receipt timestamps are truncated to milliseconds in HKLM.',
             'Host sequence counts received records, not firmware frames; gaps cannot prove device-side loss absence.']}
    rms=np.maximum([float(r['LeftRmsDb']) for r in raw],[float(r['RightRmsDb']) for r in raw])
    peaks=np.maximum([float(r['LeftPeakDb']) for r in raw],[float(r['RightPeakDb']) for r in raw])
    if np.max(rms)-np.min(rms)>10:
        candidates=[]
        for lag in range(-10,11):
            a=peaks[:len(peaks)-lag or None] if lag>=0 else peaks[-lag:]
            b=rms[lag:] if lag>=0 else rms[:len(rms)+lag]
            candidates.append((float(np.corrcoef(a,b)[0,1]),lag*10))
        best=max(candidates)
        result['peak_to_rms_descriptive_alignment']={'correlation':best[0],'approx_lag_ms_at_100Hz':best[1],
            'limit':'Both fields may share an unknown window/delay; this does not measure analog-event latency.'}
    if (directory/'box1_delivery.csv').exists():
        probe=load(directory/'box1_delivery.csv')
        pts=np.array([float(r['ObservedUtcMs']) for r in probe])
        result['receipt_to_first_registry_observation_ms']=stats([float(r['ObservedUtcMs'])-float(r['ReceiptUtcMs']) for r in probe])
        result['probe_observation_spacing_ms']=stats(np.diff(pts))
        good=[r for r in frames if float(r.get('ProbeUtcMs',0))>0 and r.get('ReceiptLocal')
              and abs(float(r['ProbeUtcMs'])-float(r['EpochSecond'])*1000)<2000]
        result['frames_without_current_probe_clock']=len(frames)-len(good)
        frame_times=np.array([float(r['ProbeUtcMs']) for r in good])
        ages=[float(r['ProbeUtcMs'])-datetime.fromisoformat(r['ReceiptLocal']).timestamp()*1000 for r in good]
        result['receipt_to_command_frame_clock_estimate_ms']=stats(ages)
        result['frame_clock_spacing_ms']=stats(np.diff(frame_times))
        result['clock_uncertainty_bound_observed_ms']=float(np.max(np.diff(pts))) if len(pts)>1 else None
    before=replay(raw); after=replay(raw,True)
    b=np.max(before,axis=1)*2.7*1.6; a=np.max(after,axis=1)*2.7*1.6
    result['receipt_timed_replay']={'travel':stats(np.minimum(1,b)), 'pin_percent':float(np.mean(b>=.99)*100)}
    result['sample_timed_replay']={'travel':stats(np.minimum(1,a)), 'pin_percent':float(np.mean(a>=.99)*100),
                                  'delta_rmse':float(np.sqrt(np.mean((before-after)**2)))}
    print(json.dumps(result,indent=2))
    (directory/'latency-analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result
if __name__=='__main__':
    for name in sys.argv[1:]: analyze(Path(__file__).parent/'captures'/name)
