#!/usr/bin/env python3
"""Render the final native UI with sample data; never touches desktop preferences."""
from datetime import date, datetime, time, timedelta
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import backend

OUTPUT=ROOT/'docs/images'
OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='sujood-previews-') as temporary:
    base=Path(temporary)
    runtime=base/'runtime';runtime.mkdir(mode=0o700)
    for name in ('Commons','Ui'):
        (base/name).symlink_to(Path('/usr/share/omarchy/shell')/name)
    plugin=base/'plugin';plugin.mkdir()
    for pattern in ('*.qml','*.js','qmldir','backend.py'):
        for f in ROOT.glob(pattern):shutil.copy2(f,plugin/f.name)
    shutil.copy2(ROOT/'tools/preview.qml',base/'shell.qml')
    prefs=backend.normalize_settings(dict(alerts=False,sound=False,location=dict(
        name='Mecca',latitude=21.42664,longitude=39.82563,countryCode='SA',
        region='Mecca Region, Saudi Arabia',timezone='Asia/Riyadh')))
    zone=ZoneInfo(prefs['location']['timezone'])
    today=datetime.now(zone).date()
    following=(today.replace(day=28)+timedelta(days=4)).replace(day=1)
    end=(following.replace(day=28)+timedelta(days=4)).replace(day=1)
    dates={date(2026,10,15),date(2026,10,16)}
    d=today-timedelta(days=1)
    while d<end:dates.add(d);d+=timedelta(days=1)
    days=[]
    for d in sorted(dates):
        times=['05:02','06:17','12:07','15:28','17:57','19:27']
        if d==date(2026,10,16):times[0]='05:03'
        rows=[]
        for name,hhmm in zip(backend.ORDER,times):
            h,m=map(int,hhmm.split(':'))
            value=datetime.combine(d,time(h,m),zone)
            rows.append(dict(name=name,time=hhmm,at=int(value.timestamp()*1000),date=d.isoformat()))
        days.append(dict(date=d.isoformat(),label=d.strftime('%a, %d %b %Y'),hijri='4 Jumādá al-ūlá 1448 AH',rows=rows,
                         start=int(datetime.combine(d,time(),zone).timestamp()*1000),
                         end=int(datetime.combine(d+timedelta(days=1),time(),zone).timestamp()*1000)))
    state=base/'state'
    backend.atomic_json(state/'settings.json',prefs)
    backend.atomic_json(state/'calendar.json',dict(key=backend.cache_key(prefs),days=days,fetchedAt=1))
    for mode in ('dark','light','city','arrival'):
        images=base/mode;images.mkdir()
        env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='generic',QT_QUICK_BACKEND='software',
                 XDG_RUNTIME_DIR=str(runtime),XDG_CACHE_HOME=str(base/'cache'),SUJOOD_STATE_DIR=str(state),
                 SUJOOD_PREVIEW_MODE=mode,SUJOOD_PREVIEW_DIR=str(images),WAYLAND_DISPLAY='')
        result=subprocess.run(['quickshell','-p',str(base),'--no-color'],env=env,text=True,capture_output=True,timeout=15)
        if result.returncode:
            raise SystemExit(result.stdout+result.stderr)
        if mode=='arrival':
            frames=sorted(images.glob('frame-*.png'))
            if len(frames)!=55:raise SystemExit('Incomplete arrival animation render')
            subprocess.run(['magick','-delay','8','-loop','0',*map(str,frames),'-layers','Optimize',str(OUTPUT/'arrival.gif')],check=True)
        else:
            destination={'dark':'sujood-dark.png','light':'sujood-light.png','city':'city-search.png'}[mode]
            shutil.copy2(images/(mode+'.png'),OUTPUT/destination)
        print('Rendered '+mode,flush=True)

# The exact final SVGs, with a neutral documentation palette.
parts=['<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="190" viewBox="0 0 1000 190">',
       '<rect width="1000" height="190" fill="#2e3440"/>']
for i,name in enumerate(('Fajr','Dhuhr','Asr','Maghrib','Isha')):
    svg=(ROOT/'assets'/(name.lower()+'.svg')).read_text()
    start=svg.index('>')+1
    inner=svg[start:svg.rindex('</svg>')].replace('#eceff4','#d8dee9').replace('#88c0d0','#81a1c1')
    x=42+i*200
    parts.append(f'<svg x="{x}" y="14" width="116" height="120" viewBox="0 -3 43 39">{inner}</svg>')
    parts.append(f'<text x="{x+58}" y="163" text-anchor="middle" fill="#d8dee9" font-family="monospace" font-size="18">{name}</text>')
parts.append('</svg>')
(OUTPUT/'prayer-icons.svg').write_text(''.join(parts)+'\n')
