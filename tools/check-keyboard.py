#!/usr/bin/env python3
"""Exercise the panel with real Qt key events, isolated state, and no network."""
from datetime import datetime, time, timedelta, timezone
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import backend

with tempfile.TemporaryDirectory(prefix='sujood-keyboard-') as temporary:
    base=Path(temporary)
    runtime=base/'runtime'; runtime.mkdir(mode=0o700)
    for name in ('Commons','Ui'):
        (base/name).symlink_to(Path('/usr/share/omarchy/shell')/name)
    plugin=base/'plugin'; plugin.mkdir()
    for pattern in ('*.qml','*.js','qmldir','backend.py'):
        for f in ROOT.glob(pattern): shutil.copy2(f,plugin/f.name)
    shutil.copy2(ROOT/'tests/keyboard.qml',base/'shell.qml')
    state=base/'state'
    prefs=backend.normalize_settings(dict(alerts=False,sound=False,location=dict(
        name='Test City',latitude=45,longitude=0,countryCode='GB',timezone='UTC')))
    today=datetime.now(timezone.utc).date()
    following=(today.replace(day=28)+timedelta(days=4)).replace(day=1)
    end=(following.replace(day=28)+timedelta(days=4)).replace(day=1)
    day=today-timedelta(days=1); days=[]
    while day<end:
        start=datetime.combine(day,time(),timezone.utc)
        rows=[dict(name=n,at=int((start+timedelta(hours=h)).timestamp()*1000),date=day.isoformat(),time=f'{h:02}:00')
              for n,h in zip(backend.ORDER,[5,7,12,15,18,20])]
        days.append(dict(date=day.isoformat(),label=day.isoformat(),hijri='Sample date',rows=rows,
                         start=int(start.timestamp()*1000),end=int((start+timedelta(days=1)).timestamp()*1000)))
        day+=timedelta(days=1)
    backend.atomic_json(state/'settings.json',prefs)
    backend.atomic_json(state/'calendar.json',dict(key=backend.cache_key(prefs),days=days,fetchedAt=1))
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='generic',QT_QUICK_BACKEND='software',
             XDG_RUNTIME_DIR=str(runtime),XDG_CACHE_HOME=str(base/'cache'),SUJOOD_STATE_DIR=str(state),WAYLAND_DISPLAY='')
    result=subprocess.run(['quickshell','-p',str(base),'--no-color'],env=env,text=True,capture_output=True,timeout=12)
    output=result.stdout+result.stderr
    marker='Keyboard checks passed: refresh, navigation, scroll bounds, Tab visibility, city typing, Escape'
    if result.returncode or marker not in output:
        print(output)
        sys.exit(1)
    print(marker)
