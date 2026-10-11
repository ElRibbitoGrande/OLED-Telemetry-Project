"""Align simultaneously captured signals; separate playback offset from shape error.

EpochSecond is quantized: within-second frame times are interpolated, so sub-frame
lag estimates are approximate. Do not interpret them as exact hardware latency.
"""
import csv
import json
import sys
import math
from pathlib import Path
import numpy as np


def stereo(rows, prefix):
    left = np.array([float(r[prefix+'Left']) for r in rows])
    right = np.array([float(r[prefix+'Right']) for r in rows])
    return np.sqrt((left*left+right*right)/2)


def alignment(reference, candidate, maxlag):
    best = None
    for lag in range(-maxlag,maxlag+1):
        if lag >= 0:
            a,b = reference[:len(reference)-lag or None],candidate[lag:]
        else:
            a,b = reference[-lag:],candidate[:len(candidate)+lag]
        da,db = a-a.mean(),b-b.mean()
        denom = np.sqrt(np.dot(da,da)*np.dot(db,db))
        corr = float(np.dot(da,db)/denom) if denom else -1
        if best is None or corr > best[0]:
            gain = float(np.dot(a,b)/np.dot(b,b)) if np.dot(b,b) else 0
            best = (corr,lag,gain,float(np.sqrt(np.mean((a-b*gain)**2))))
    return dict(correlation=best[0],lag_seconds=best[1]*.02,fit_gain=best[2],fit_rmse=best[3])


if __name__ == '__main__':
    directory = Path(__file__).parent/'captures'/sys.argv[1]
    with (directory/'rainmeter_comparison.csv').open(encoding='utf-8-sig',newline='') as f:
        rows = list(csv.DictReader(f))
    groups = {}
    for i,row in enumerate(rows):
        groups.setdefault(int(row['EpochSecond']),[]).append(i)
    first = min(groups)
    times = np.zeros(len(rows))
    for epoch,indices in groups.items():
        for index,row_index in enumerate(indices):
            times[row_index] = epoch-first+(index+.5)/len(indices)
    # Exclude initial setup and edge interpolation. User starts both after arming.
    grid = np.arange(25,times[-1]-2,.02)
    windows = np.interp(grid,times,stereo(rows,'WindowsEnvelope'))
    box_raw = np.interp(grid,times,stereo(rows,'Box1Pre'))
    box_final = np.interp(grid,times,stereo(rows,'Box1Envelope'))
    results = dict(
        note='Lags include playback offset; timestamps interpolated within epoch seconds. Gain fit is descriptive, not calibration.',
        approximate_frame_ms=1000*len(groups)/len(rows),
        windows_p95=float(np.quantile(windows,.95)),
        box_raw_p95=float(np.quantile(box_raw,.95)),
        box_envelope_p95=float(np.quantile(box_final,.95)),
        raw_vs_windows=alignment(windows,box_raw,min(1000,len(grid)//3)),
        envelope_vs_windows=alignment(windows,box_final,min(1000,len(grid)//3)))
    (directory/'paired-analysis.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(json.dumps(results,indent=2))
    if '--sweep' in sys.argv:
        with (directory/'box1_raw.csv').open(encoding='utf-8-sig',newline='') as f:
            raw = list(csv.DictReader(f))
        raw_time = np.array([(int(r['UtcTicks'])-621355968000000000)/1e7-first for r in raw])
        powers = [(10**(float(r['LeftRmsDb'])/10),10**(float(r['RightRmsDb'])/10)) for r in raw]
        fit_grid = grid[grid < times[-1]-5]
        reference = np.interp(fit_grid,times,stereo(rows,'WindowsEnvelope'))
        split = len(reference)//2
        center_lag = results['envelope_vs_windows']['lag_seconds']
        candidates = []
        for attack in (10,25,40,60,85,110):
            for decay in (250,350,420,520,650):
                left = right = 0.0
                values = []
                previous = raw_time[0]
                for stamp,(target_l,target_r) in zip(raw_time,powers):
                    dt = max(0,(stamp-previous)*1000)
                    left = target_l + math.exp(-2*dt/(decay if target_l < left else attack))*(left-target_l)
                    right = target_r + math.exp(-2*dt/(decay if target_r < right else attack))*(right-target_r)
                    values.append(math.sqrt(max(0,(left+right)/2)))
                    previous = stamp
                best = None
                for lag in np.arange(center_lag-.3,center_lag+.301,.02):
                    candidate = np.interp(fit_grid+lag,raw_time,values)
                    a,b = reference[:split],candidate[:split]
                    gain = float(np.dot(a,b)/np.dot(b,b))
                    error = float(np.sqrt(np.mean((a-b*gain)**2)))
                    if best is None or error < best['train_rmse']:
                        test_a,test_b = reference[split:],candidate[split:]*gain
                        best = dict(attack_ms=attack,decay_ms=decay,lag_seconds=float(lag),fit_gain=gain,
                                    train_rmse=error,test_rmse=float(np.sqrt(np.mean((test_a-test_b)**2))),
                                    test_correlation=float(np.corrcoef(test_a,test_b)[0,1]))
                candidates.append(best)
        candidates.sort(key=lambda c:c['train_rmse'])
        with (directory/'ballistic-candidates.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=list(candidates[0]))
            writer.writeheader();writer.writerows(candidates)
        print('Best training fits, with held-out second-half results:')
        print(json.dumps(candidates[:5],indent=2))
        print('Existing 85/520 baseline:',json.dumps(next(c for c in candidates if c['attack_ms']==85 and c['decay_ms']==520)))
