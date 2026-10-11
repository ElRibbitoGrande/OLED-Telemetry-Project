"""Build Git-ignored amplitude-only fixtures for the real Rainmeter Lua runtime."""
from pathlib import Path
import runpy

root=Path(__file__).parent
load=runpy.run_path(str(root/'Simulate-VUAttenuation.py'))['load']
cases=[
    ('Aja HTPC','Box1VUComparison_20260908_215850_915','HTPC',1,True),
    ('Corea HTPC','Box1VUComparison_20260908_224933_594','HTPC',1,True),
    ('Expert HTPC','Box1VUComparison_20260908_223323_519','HTPC',1,False),
    ('Aja Box1','Box1VUComparison_20260908_221946_334','LYR+',1.6,True),
    ('Expert Box1','Box1VUComparison_20260908_223854_932','LYR+',1.6,False)]
lines=['return {']
for name,path,source,calibration,normal in cases:
    data=load(root/'captures'/path,source)
    first=data[0][0]
    lines.append('{name="'+name+'",normal='+str(normal).lower()+',rows={')
    for stamp,pairs in data:
        for left,right in pairs:
            lines.append('{%d,%.17g,%.17g},'%(stamp-first,left*calibration,right*calibration))
    lines.append('}},')
lines.append('}')
(root/'captures'/'adaptive-replay.lua').write_text('\n'.join(lines),encoding='utf-8')
print('Built five recorded-program fixtures.')
