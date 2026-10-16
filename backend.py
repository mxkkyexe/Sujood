#!/usr/bin/env python3
"""Sujood's standard-library backend: geocoding, calendars and durable preferences."""
import argparse
import calendar
from datetime import date, datetime, time, timedelta, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener
from urllib.error import URLError
from zoneinfo import ZoneInfo

PRAYERS = ('Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha')
ORDER = ('Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha')
METHODS = {
    2: 'ISNA North America', 3: 'Muslim World League', 1: 'Karachi',
    4: 'Umm al-Qura, Makkah', 5: 'Egyptian General Authority',
    7: 'University of Tehran', 0: 'Shia Ithna-Ashari', 8: 'Gulf Region',
    9: 'Kuwait', 10: 'Qatar', 11: 'Singapore', 12: 'France (UOIF)',
    13: 'Turkey (Diyanet, experimental)', 14: 'Russia', 15: 'Moonsighting Committee',
    16: 'Dubai (experimental)', 17: 'Malaysia (JAKIM)', 18: 'Tunisia',
    19: 'Algeria', 20: 'Indonesia (Kemenag)', 21: 'Morocco',
    22: 'Lisbon', 23: 'Jordan',
}
# A transparent regional default policy, not Pillars' proprietary selection rules.
REGIONS = {'US': 2, 'CA': 2, 'MX': 2, 'PK': 1, 'IN': 1, 'BD': 1, 'AF': 1,
           'SA': 4, 'EG': 5, 'IR': 7, 'AE': 16, 'KW': 9, 'QA': 10, 'SG': 11,
           'FR': 12, 'TR': 13, 'RU': 14, 'MY': 17, 'TN': 18, 'DZ': 19,
           'ID': 20, 'MA': 21, 'PT': 22, 'JO': 23, 'BH': 8, 'OM': 8}
DEFAULTS = dict(version=1, location=None, method='auto', school=0, highLatitude=3,
                alerts=True, sound=True, countdown=True, animation=True, clock24=False, showSunrise=False,
                offsets={name: 0 for name in PRAYERS})
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_PAYLOAD_BYTES = 64 * 1024
MAX_SEARCH_LENGTH = 160
SERVICE_HOSTS = frozenset(('api.aladhan.com', 'geocoding-api.open-meteo.com'))


class RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('The service redirected the request; refresh was blocked for security.')


def display_text(value, limit):
    return ''.join(char for char in str(value)[:limit] if char.isprintable())


def read_json(path, fallback=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def get_json(url, params):
    target = urlsplit(url)
    if (target.scheme != 'https' or target.hostname not in SERVICE_HOSTS
            or target.username is not None or target.password is not None
            or target.port not in (None, 443)):
        raise ValueError('Only approved HTTPS prayer and location services are allowed')
    req = Request(url + '?' + urlencode(params), headers={'User-Agent': 'Sujood/0.1', 'Accept': 'application/json'})
    try:
        with build_opener(RejectRedirects()).open(req, timeout=12) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except (URLError, TimeoutError, OSError) as exc:
        raise ValueError('Cannot reach the service. Check your connection; a retry is scheduled.') from exc
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ValueError('The service response was too large; refresh was blocked for security.')
    try:
        result = json.loads(raw)
    except (ValueError, RecursionError) as exc:
        raise ValueError('The service returned invalid JSON') from exc
    if not isinstance(result, dict) or result.get('error') or result.get('code', 200) != 200:
        raise ValueError('The prayer or location service returned an error')
    return result


def normalize_location(loc):
    if not isinstance(loc, dict) or not loc.get('name'):
        return None
    try:
        lat, lon = float(loc['latitude']), float(loc['longitude'])
        if not math.isfinite(lat) or not math.isfinite(lon) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return None
        zone = str(loc.get('timezone', ''))
        if len(zone) > 128:
            return None
        if zone:
            ZoneInfo(zone)
        return dict(name=display_text(loc['name'], 160), latitude=lat, longitude=lon,
                    countryCode=str(loc.get('countryCode', loc.get('country_code', ''))).upper()[:2],
                    region=display_text(loc.get('region', ''), 200), timezone=zone)
    except (ValueError, KeyError, TypeError):
        return None


def normalize_settings(raw):
    raw = raw if isinstance(raw, dict) else {}
    result = dict(DEFAULTS, offsets=dict(DEFAULTS['offsets']))
    for key in ('alerts', 'sound', 'countdown', 'animation', 'clock24', 'showSunrise'):
        if type(raw.get(key)) is bool:
            result[key] = raw[key]
    result['location'] = normalize_location(raw.get('location'))
    if str(raw.get('method')) in [str(i) for i in METHODS]:
        result['method'] = int(raw['method'])
    if raw.get('school') in (0, 1):
        result['school'] = int(raw['school'])
    if raw.get('highLatitude') in (1, 2, 3):
        result['highLatitude'] = int(raw['highLatitude'])
    for key in PRAYERS:
        try:
            result['offsets'][key] = max(-60, min(60, int(raw.get('offsets', {}).get(key, 0))))
        except (TypeError, ValueError, AttributeError):
            pass
    return result


def search(query):
    if not isinstance(query, str) or len(query.strip()) > MAX_SEARCH_LENGTH:
        raise ValueError('City searches must contain at most 160 characters')
    if len(query.strip()) < 2:
        return []
    data = get_json('https://geocoding-api.open-meteo.com/v1/search',
                    dict(name=query.strip(), count=10, language='en', format='json'))
    results = []
    matches = data.get('results', [])
    if not isinstance(matches, list):
        raise ValueError('The location service returned invalid search results')
    for r in matches[:10]:
        if not isinstance(r, dict):
            continue
        loc = normalize_location(dict(r, region=', '.join(filter(None, [r.get('admin1'), r.get('country')]))))
        if loc and loc['timezone']:
            results.append(loc)
    return results


def migrate_legacy_state(state):
    """Keep pre-release preferences, calendars and notification claims on the Sujood rename."""
    if state.name != 'sujood' or (state / 'settings.json').exists():
        return
    legacy = state.parent / 'prayer'
    prefs = read_json(legacy / 'settings.json')
    if not isinstance(prefs, dict):
        return
    # Write preferences last: a partial migration is safe to retry.
    for name in ('calendar.json', 'notified.json'):
        value = read_json(legacy / name)
        if isinstance(value, dict) and not (state / name).exists():
            atomic_json(state / name, value)
    atomic_json(state / 'settings.json', normalize_settings(prefs))


def load_settings(state):
    migrate_legacy_state(state)
    saved = read_json(state / 'settings.json')
    if saved is not None:
        return normalize_settings(saved)
    olddir = Path.home() / '.local/state/omarchy/settings'
    old = read_json(olddir / 'prayer-alerts.json', {}) or {}
    return normalize_settings(dict(old, school=1 if old.get('hanafiAsr') else 0,
                                   location=read_json(olddir / 'weather.json')))


def enrich_location(loc):
    if loc['timezone'] and loc['countryCode']:
        return loc
    matches = search(loc['name'])
    # Retain the saved coordinates. Only borrow metadata from a nearby city.
    matches.sort(key=lambda r: (r['latitude']-loc['latitude'])**2 +
                 ((r['longitude']-loc['longitude'])*math.cos(math.radians(loc['latitude'])))**2)
    if matches:
        near = matches[0]
        distance = math.hypot(near['latitude']-loc['latitude'],
                              (near['longitude']-loc['longitude'])*math.cos(math.radians(loc['latitude'])))
        if distance < .5:
            return dict(loc, countryCode=near['countryCode'], timezone=near['timezone'], region=near['region'])
    raise ValueError('Click the city name to confirm its country and timezone')


def method_for(settings):
    return REGIONS.get((settings.get('location') or {}).get('countryCode'), 3) if settings['method'] == 'auto' else settings['method']


def cache_key(settings):
    loc = settings['location'] or {}
    calc = dict(latitude=loc.get('latitude'), longitude=loc.get('longitude'), timezone=loc.get('timezone'),
                method=method_for(settings), school=settings['school'], highLatitude=settings['highLatitude'], offsets=settings['offsets'])
    return hashlib.sha256(json.dumps(calc, sort_keys=True).encode()).hexdigest()


def parse_day(data, settings, zone):
    d = datetime.strptime(data['date']['gregorian']['date'], '%d-%m-%Y').date()
    hijri = data['date']['hijri']
    rows = []
    for name in ORDER:
        raw = data['timings'][name]
        value = datetime.fromisoformat(raw)
        if value.utcoffset() is None:
            raise ValueError('Prayer service returned a time without a timezone')
        value = (value.astimezone(timezone.utc) + timedelta(minutes=settings['offsets'].get(name, 0))).astimezone(zone)
        rows.append(dict(name=name, at=int(value.timestamp()*1000), time=value.strftime('%H:%M'), date=d.isoformat()))
    epochs = [row['at'] for row in rows]
    if epochs != sorted(epochs) or len(set(epochs)) != len(epochs):
        raise ValueError('Prayer times overlap; check the minute adjustments or calculation method')
    return dict(date=d.isoformat(), label=d.strftime('%a, %d %b %Y'),
                start=int(datetime.combine(d, time(), zone).timestamp()*1000),
                end=int(datetime.combine(d+timedelta(days=1), time(), zone).timestamp()*1000),
                hijri=display_text(f"{hijri['day']} {hijri['month']['en']} {hijri['year']} AH", 128), rows=rows)


def fetch_month(settings, year, month):
    loc = settings['location']
    params = dict(latitude=loc['latitude'], longitude=loc['longitude'], method=method_for(settings),
                  school=settings['school'], latitudeAdjustmentMethod=settings['highLatitude'],
                  timezonestring=loc['timezone'], iso8601='true')
    raw = get_json(f'https://api.aladhan.com/v1/calendar/{year}/{month}', params)
    data = raw.get('data')
    if not isinstance(data, list) or len(data) != calendar.monthrange(year, month)[1]:
        raise ValueError('Prayer service returned an incomplete month')
    zone = ZoneInfo(loc['timezone'])
    days = [parse_day(day, settings, zone) for day in data]
    expected = [date(year, month, day).isoformat() for day in range(1, len(days)+1)]
    if [day['date'] for day in days] != expected:
        raise ValueError('Prayer service returned unexpected calendar dates')
    return days


def sync(state, payload):
    prefs = normalize_settings(payload['settings']) if 'settings' in payload else load_settings(state)
    old = read_json(state / 'calendar.json', {}) or {}
    error = ''
    try:
        if not prefs['location']:
            raise ValueError('Click “Choose city” above to load prayer times')
        prefs['location'] = enrich_location(prefs['location'])
    except Exception as exc:
        error = str(exc)
    atomic_json(state / 'settings.json', prefs)
    key = cache_key(prefs)
    cache = old if old.get('key') == key else dict(key=key, days=[], fetchedAt=0)
    if not error:
        zone = ZoneInfo(prefs['location']['timezone'])
        today = datetime.now(zone).date()
        months = [(today.year, today.month)]
        # Cache the next month too: tomorrow's actual Fajr survives month/year rollover.
        next_month = (today.replace(day=28)+timedelta(days=4)).replace(day=1)
        months.append((next_month.year, next_month.month))
        days = {d['date']: d for d in cache.get('days', [])}
        try:
            for year, month in months:
                expected = [date(year, month, d).isoformat() for d in range(1, calendar.monthrange(year, month)[1]+1)
                            if date(year, month, d) >= today-timedelta(days=1)]
                if payload.get('force') or not all(d in days for d in expected):
                    days.update({d['date']: d for d in fetch_month(prefs, year, month)})
                    # Persist each complete month so a later request failure cannot discard it.
                    keep_from = (today-timedelta(days=1)).isoformat()
                    cache = dict(key=key, days=sorted((d for d in days.values() if d['date'] >= keep_from), key=lambda d: d['date']),
                                 fetchedAt=int(datetime.now(timezone.utc).timestamp()*1000))
                    atomic_json(state / 'calendar.json', cache)
        except Exception as exc:
            error = 'Refresh failed: ' + str(exc)
    return dict(settings=prefs, data=dict(cache, location=prefs['location'], method=METHODS[method_for(prefs)],
                methodId=method_for(prefs), automatic=prefs['method']=='auto'), error=error)


def alert(state, payload):
    """Persistently claim a real cached prayer, avoiding duplicates across screens/restarts."""
    prefs = load_settings(state)
    if not prefs['alerts']:
        return {'notified': False}
    cache = read_json(state / 'calendar.json', {}) or {}
    if cache.get('key') != cache_key(prefs):
        return {'notified': False}
    now = datetime.now(timezone.utc).timestamp()*1000
    found = next((r for d in cache.get('days', []) for r in d['rows']
                  if r['name'] in PRAYERS and r['name']==payload.get('name') and r['at']==payload.get('at')
                  and 0 <= now-r['at'] < 60000), None)
    if found is None:
        return {'notified': False}
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'alerts.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        notified = read_json(state / 'notified.json', {}) or {}
        # Identity is prayer name + timetable date, including after changing calculation settings.
        identity = found['date'] + ':' + found['name']
        if identity in notified:
            return {'notified': False}
        notified = {k:v for k,v in notified.items() if now-v < 3*86400000}
        notified[identity] = now
        atomic_json(state / 'notified.json', notified)
    notification_time = found['time']
    if not prefs['clock24']:
        hour, minute = notification_time.split(':')
        hour = int(hour)
        notification_time = f"{hour % 12 or 12}:{minute} {'PM' if hour >= 12 else 'AM'}"
    subprocess.run(['notify-send', '-a', 'Sujood', '-u', 'normal', '-t', '8000',
                    found['name'], f"It's time for {found['name']} · {notification_time}"], check=False, timeout=5)
    if prefs['sound']:
        subprocess.Popen(['paplay', '/usr/share/sounds/freedesktop/stereo/bell.oga'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {'notified': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['load', 'sync', 'search', 'alert'])
    parser.add_argument('payload', nargs='?', help='Legacy JSON argument; prefer --stdin for private data')
    parser.add_argument('--stdin', action='store_true', help='Read one JSON payload line from stdin')
    parser.add_argument('--state-dir', type=Path, default=Path(os.environ.get('SUJOOD_STATE_DIR') or os.environ.get('PRAYER_STATE_DIR') or
                        str(Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'omarchy/sujood')))
    args = parser.parse_args()
    try:
        if args.stdin and args.payload is not None:
            raise ValueError('Choose stdin or a legacy payload argument, not both')
        raw = sys.stdin.buffer.readline(MAX_PAYLOAD_BYTES + 1) if args.stdin else (args.payload or '{}').encode('utf-8')
        if len(raw) > MAX_PAYLOAD_BYTES:
            raise ValueError('The request payload is too large')
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError('The request payload must be a JSON object')
        if args.action == 'search':
            result = dict(results=search(payload.get('query', '')))
        elif args.action == 'load':
            prefs = load_settings(args.state_dir)
            cache = read_json(args.state_dir/'calendar.json', {}) or {}
            result = dict(settings=prefs, data=dict(cache, location=prefs['location'], method=METHODS[method_for(prefs)])
                          if cache.get('key')==cache_key(prefs) else None, error='')
        elif args.action == 'alert':
            result = alert(args.state_dir, payload)
        else:
            result = sync(args.state_dir, payload)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({'error': str(exc)}))
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
