"""Report acquisition/delivery cadence without treating nominal frame time as wall time."""
import csv
import statistics
import sys
from pathlib import Path


def percentile(values, q):
    return sorted(values)[round((len(values)-1)*q)]


def analyze(path):
    with (path/'box1_raw.csv').open(encoding='utf-8-sig', newline='') as f:
        raw = list(csv.DictReader(f))
    with (path/'rainmeter_comparison.csv').open(encoding='utf-8-sig', newline='') as f:
        frames = list(csv.DictReader(f))
    ticks = [int(r['UtcTicks']) for r in raw]
    intervals = [(b-a)/10000 for a,b in zip(ticks,ticks[1:]) if b>=a]
    sequences = [int(r['Sequence']) for r in raw]
    observed = [int(r['Box1Sequence']) for r in frames]
    unique = len(set(observed))
    run = longest = 1
    for a,b in zip(observed,observed[1:]):
        run = run+1 if a==b else 1
        longest = max(longest,run)
    wall = int(frames[-1]['EpochSecond'])-int(frames[0]['EpochSecond'])
    print(path.name)
    print(f'Raw records={len(raw)}, rate={(len(raw)-1)/((ticks[-1]-ticks[0])/1e7):.2f} Hz, '
          f'receipt intervals median={statistics.median(intervals):.2f} ms p95={percentile(intervals,.95):.2f} ms '
          f'p99={percentile(intervals,.99):.2f} ms max={max(intervals):.2f} ms')
    print(f'Raw sequence discontinuities={sum(b!=a+1 for a,b in zip(sequences,sequences[1:]))}; '
          f'frames={len(frames)}, approx frame rate={(len(frames)-1)/wall:.2f} Hz; '
          f'unique Box sequences/frame={100*unique/len(frames):.2f}%; longest held sequence={longest} frames')
    print('Collector completion marker:', (path/'box1_collector_capture.complete').exists())


if __name__ == '__main__':
    root = Path(__file__).parent/'captures'
    for name in sys.argv[1:]:
        analyze(root/name)
