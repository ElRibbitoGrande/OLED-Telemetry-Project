"""Characterize existing VU captures without assuming both paths play the same audio."""
import csv
import json
import statistics
from pathlib import Path


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    def pct(p):
        return values[round((len(values) - 1) * p)]
    return dict(n=len(values), p10=pct(.10), p50=pct(.50), p90=pct(.90), p95=pct(.95),
                p99=pct(.99), maximum=values[-1],
                rest_pct=100*sum(v < .05 for v in values)/len(values),
                mid_pct=100*sum(.05 <= v < .8 for v in values)/len(values),
                upper_pct=100*sum(.8 <= v < .99 for v in values)/len(values),
                pinned_pct=100*sum(v >= .99 for v in values)/len(values))


def analyze(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    result = {'capture': path.parent.name, 'sources': {}}
    for source, prefix in [('HTPC', 'WindowsRaw'), ('LYR+', 'Box1Final')]:
        selected = [r for r in rows if r['Source'] == source]
        if not selected:
            continue
        left = [float(r[prefix+'Left']) for r in selected]
        right = [float(r[prefix+'Right']) for r in selected]
        linked = [max(l, r) for l, r in zip(left, right)]
        seconds = {}
        for row, level in zip(selected, linked):
            seconds.setdefault(int(row['EpochSecond']), []).append(level)
        result['sources'][source] = {
            'observed_seconds': len(seconds), 'left': distribution(left),
            'right': distribution(right), 'linked': distribution(linked),
            'active_linked': distribution([v for v in linked if v >= .01]),
            'one_second_means': distribution([statistics.fmean(v) for v in seconds.values()]),
            'one_second_peaks': distribution([max(v) for v in seconds.values()]),
        }
        if source == 'LYR+':
            result['sources'][source]['raw_amplitude'] = distribution([
                max(10**(float(r['Box1LeftRmsDb'])/20), 10**(float(r['Box1RightRmsDb'])/20)) for r in selected])
        envelope_prefix = 'WindowsEnvelope' if source == 'HTPC' else 'Box1Envelope'
        if envelope_prefix+'Left' in selected[0]:
            envelopes = [max(float(r[envelope_prefix+'Left']), float(r[envelope_prefix+'Right'])) for r in selected]
            result['sources'][source]['unclipped_envelope'] = distribution(envelopes)
            result['sources'][source]['unclipped_fixed_gain'] = distribution([v*2.7 for v in envelopes])
            result['sources'][source]['baseline_mapping_max_error'] = max(
                abs(float(r['Display'+channel]) - min(1.0, float(r[envelope_prefix+channel])*2.7))
                for r in selected for channel in ('Left', 'Right'))
    return result


if __name__ == '__main__':
    root = Path(__file__).parent / 'captures'
    results = [analyze(p) for p in sorted(root.glob('Box1VUComparison_*/rainmeter_comparison.csv'))]
    (root / 'vu-range-analysis.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    for result in results:
        for source, data in result['sources'].items():
            d = data['linked']
            print(f"{result['capture']} {source:4} {data['observed_seconds']:4}s "
                  f"p50={d['p50']:.3f} p95={d['p95']:.3f} "
                  f"rest={d['rest_pct']:.1f}% mid={d['mid_pct']:.1f}% "
                  f"upper={d['upper_pct']:.1f}% pinned={d['pinned_pct']:.1f}%")
