#!/usr/bin/env python3
"""Embed the SVG sources for QML's runtime theme colour substitution."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
icons={name:(root/'assets'/(name.lower()+'.svg')).read_text().strip()
       for name in ('Fajr','Dhuhr','Asr','Maghrib','Isha')}
(root/'Icons.js').write_text('var icons = '+json.dumps(icons,indent=2)+'\n'
    'function source(name, foreground, accent) {\n'
    '    var svg = icons[name === "Sunrise" ? "Dhuhr" : name] || icons.Fajr\n'
    '    svg = svg.replace(/#eceff4/g, String(foreground)).replace(/#88c0d0/g, String(accent))\n'
    '    return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg)\n}\n')
