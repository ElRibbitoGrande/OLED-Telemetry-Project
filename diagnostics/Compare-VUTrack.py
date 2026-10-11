"""Compare only matching playback positions in two labeled reference captures."""
import csv
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path
import runpy
import math

distribution = runpy.run_path(str(Path(__file__).with_name('Analyze-VURange.py')))['distribution']


def positioned(directory, source, prefix):
    log = (directory / 'track-context.log').read_text(encoding='utf-8-sig')
    context = {}
    for block in re.split(r'(?m)(?=^\d{4}-\d\d-\d\dT)', log):
        lines = block.strip().splitlines()
        if not lines:
            continue
        try:
            epoch = int(datetime.fromisoformat(lines[0].replace('Z', '+00:00')).timestamp())
            fields = dict(line.split('=', 1) for line in lines[1:] if '=' in line)
            context[epoch] = fields
        except ValueError:
            continue
    output = {}
    with (directory / 'rainmeter_comparison.csv').open(encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            fields = context.get(int(row['EpochSecond']))
            if row['Source'] != source or not fields or fields.get('Title') != 'Black Cow':
                continue
            position = int(float(fields.get('PositionSeconds', '-1')))
            if position >= 0:
                output.setdefault(position, []).append(max(float(row[prefix+'Left']), float(row[prefix+'Right'])))
    return output


if __name__ == '__main__':
    root = Path(__file__).parent / 'captures'
    windows = positioned(root / sys.argv[1], 'HTPC', 'WindowsRaw')
    box = positioned(root / sys.argv[2], 'LYR+', 'Box1Final')
    common = sorted(set(windows) & set(box))
    if len(common) < 5:
        raise SystemExit('Insufficient matching playback positions')
    w = [statistics.median(windows[p]) for p in common]
    b = [statistics.median(box[p]) for p in common]
    ratios = [x/y for x,y in zip(w,b) if y > .01]
    ratio = statistics.median(ratios)
    print('Matching positions:', common)
    print('HTPC per-position median distribution:', distribution(w))
    print('Box1 per-position median distribution:', distribution(b))
    print(f'Median HTPC/Box1 ratio: {ratio:.3f} ({20*math.log10(ratio):.2f} dB); descriptive, not a calibration decision.')
