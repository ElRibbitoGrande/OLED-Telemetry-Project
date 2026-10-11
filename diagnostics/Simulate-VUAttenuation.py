"""Offline attenuation candidates only; does not change production meter gain."""
import csv
import math
import statistics
from collections import deque
from pathlib import Path


def quantile(values, q):
    values = sorted(values)
    p = (len(values)-1)*q
    lo = math.floor(p)
    hi = math.ceil(p)
    return values[lo] + (values[hi]-values[lo])*(p-lo)


def load(directory, source='HTPC'):
    seconds = {}
    with (directory/'rainmeter_comparison.csv').open(encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            if row['Source'] != source:
                continue
            envelope = 'WindowsEnvelope' if source == 'HTPC' else 'Box1Envelope'
            mapped = 'WindowsRaw' if source == 'HTPC' else 'Box1Final'
            if envelope+'Left' in row:
                pair = tuple(float(row[envelope+ch])*2.7 for ch in ('Left','Right'))
            else:
                pair = tuple(float(row[mapped+ch]) for ch in ('Left','Right'))
                if max(pair) >= 1:
                    raise ValueError('Cannot reconstruct clipped headroom from old captures')
            seconds.setdefault(int(row['EpochSecond']), []).append(pair)
    return [(stamp, seconds[stamp]) for stamp in sorted(seconds)]


def simulate(seconds, window, rate, high_target):
    # Prototype: linked one-second program medians, sustained-high gate,
    # robust upper quantile, bounded attenuation, no gain increase.
    history = deque(maxlen=window)
    gain_db = target_db = 0.0
    output = []
    first = seconds[0][0]
    trace = []
    for stamp, pairs in seconds:
        linked = [max(pair) for pair in pairs]
        median = statistics.median(linked)
        if median >= .01:
            history.append(median)
            current = 10**(gain_db/20)
            if len(history) == window and sum(v*current >= .9 for v in history)/window >= .5:
                target_db = min(target_db, max(-12, 20*math.log10(high_target/quantile(history,.9))))
            gain_db = max(target_db, gain_db-rate)
        # Both channels receive exactly the same multiplier. No envelope filter.
        gain = 10**(gain_db/20)
        for left,right in pairs:
            output.append((stamp-first, min(1,left*gain), min(1,right*gain)))
        trace.append((stamp-first,gain_db,target_db))
    return output,trace


def simulate_distribution(seconds, calibration=1.0, window=20, rate=.15):
    history = deque(maxlen=window)
    gain_db = target_db = 0.0
    output = []
    first = seconds[0][0]
    trace = []
    for stamp,pairs in seconds:
        pairs = [(l*calibration,r*calibration) for l,r in pairs]
        linked = [max(pair) for pair in pairs]
        if statistics.median(linked) >= .01:
            history.append(linked)
            if len(history) == window:
                recent = [v for bucket in history for v in bucket]
                gain = 10**(gain_db/20)
                # Normal Corea pinning was 2.5%; hot HTPC pinning was 41%.
                # Test a sustained 10% clipping threshold, not single peaks.
                if sum(v*gain >= .99 for v in recent)/len(recent) >= .10:
                    target_db = min(target_db,max(-6,20*math.log10(.90/quantile(recent,.95))))
            gain_db = max(target_db,gain_db-rate)
        gain = 10**(gain_db/20)
        output.extend((stamp-first,min(1,l*gain),min(1,r*gain)) for l,r in pairs)
        trace.append((stamp-first,gain_db,target_db))
    return output,trace


if __name__ == '__main__':
    root = Path(__file__).parent/'captures'
    normal = load(root/'Box1VUComparison_20260908_215850_915')
    hot = load(root/'Box1VUComparison_20260908_223323_519')
    lines = ['window_seconds,rate_db_per_second,upper_target,normal_max_change,hot_final_gain_db,hot_pinned_pct,hot_last30_pinned_pct,hot_last30_p95']
    for window in (10,20,30):
        for rate in (.10,.15,.25):
            for target in (.85,.90):
                n,nt = simulate(normal,window,rate,target)
                h,ht = simulate(hot,window,rate,target)
                linked = [max(l,r) for _,l,r in h]
                tail = [max(l,r) for t,l,r in h if t >= h[-1][0]-30]
                line = f'{window},{rate},{target},{max(abs(t[1]) for t in nt):.3f},{ht[-1][1]:.3f},{100*sum(v>=.99 for v in linked)/len(linked):.2f},{100*sum(v>=.99 for v in tail)/len(tail):.2f},{quantile(tail,.95):.3f}'
                lines.append(line)
    (root/'attenuation-candidates.csv').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines))
    box_path = root/'Box1VUComparison_20260908_223854_932'
    if (box_path/'rainmeter_comparison.csv').exists():
        box = load(box_path, 'LYR+')
        output,trace = simulate(box,20,.15,.9)
        linked = [max(l,r) for _,l,r in output]
        print(f'Box1 same candidate: final gain {trace[-1][1]:.3f} dB, p95 {quantile(linked,.95):.3f}, pinned {100*sum(v>=.99 for v in linked)/len(linked):.2f}%')
    print('Distribution candidate with provisional Box1 calibration:')
    for name,source,calibration in (
        ('Box1VUComparison_20260908_215850_915','HTPC',1),
        ('Box1VUComparison_20260908_224933_594','HTPC',1),
        ('Box1VUComparison_20260908_223323_519','HTPC',1),
        ('Box1VUComparison_20260908_221946_334','LYR+',1.6),
        ('Box1VUComparison_20260908_223854_932','LYR+',1.6)):
        data=load(root/name,source)
        output,trace=simulate_distribution(data,calibration)
        tail=[max(l,r) for t,l,r in output if t>=output[-1][0]-30]
        print(name,source,'gain dB',round(trace[-1][1],3),'settled pin %',round(100*sum(v>=.99 for v in tail)/len(tail),2),'settled p95',round(quantile(tail,.95),3))
