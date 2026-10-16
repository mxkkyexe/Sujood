import copy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import backend as b

LOC=dict(name="Toronto",latitude=43.6532,longitude=-79.3832,countryCode='CA',timezone='America/Toronto')
def prefs(**kw):
    return b.normalize_settings(dict(location=LOC, **kw))
def raw_day():
    return {'date':{'gregorian':{'date':'01-11-2026'},'hijri':{'day':'21','month':{'en':'Test'},'year':'1448'}},
            'timings':{n:f'2026-11-01T{h:02}:00:00-05:00' for n,h in zip(b.ORDER,[5,7,12,15,18,20])}}

class BackendTests(unittest.TestCase):
    def test_regional_and_manual_methods(self):
        self.assertEqual(b.method_for(prefs()),2)
        self.assertEqual(b.method_for(prefs(method=3)),3)
        self.assertEqual(b.method_for(b.normalize_settings({'location':dict(LOC,countryCode='SA')})),4)
        self.assertEqual(b.method_for(b.normalize_settings({'location':dict(LOC,countryCode='GB')})),3)

    def test_timezone_and_dst_day_boundary(self):
        day=b.parse_day(raw_day(),prefs(),ZoneInfo('America/Toronto'))
        self.assertEqual(day['end']-day['start'],25*3600000)
        self.assertEqual(day['rows'][0]['at'],int(datetime(2026,11,1,10,0,tzinfo=timezone.utc).timestamp()*1000))

    def test_offsets_and_reject_overlapping_prayers(self):
        day=b.parse_day(raw_day(),prefs(offsets={'Fajr':7}),ZoneInfo('America/Toronto'))
        self.assertEqual(day['rows'][0]['time'],'05:07')
        raw=raw_day(); raw['timings']['Fajr']='2026-11-01T06:55:00-05:00'
        with self.assertRaisesRegex(ValueError,'overlap'):
            b.parse_day(raw,prefs(offsets={'Fajr':10}),ZoneInfo('America/Toronto'))

    def test_invalid_location_and_corrupt_settings_defaults(self):
        self.assertIsNone(b.normalize_location(dict(LOC,latitude=float('nan'))))
        self.assertIsNone(b.normalize_location(dict(LOC,timezone='Bad/Zone')))
        self.assertEqual(b.normalize_settings({'alerts':'false'})['alerts'],True)
        self.assertEqual(b.normalize_settings({'offsets':{'Fajr':999}})['offsets']['Fajr'],60)

    def test_sunrise_preference_defaults_off_and_survives_save(self):
        self.assertFalse(prefs()['showSunrise'])
        self.assertFalse(b.normalize_settings({'showSunrise': 'true'})['showSunrise'])
        enabled = prefs(showSunrise=True)
        self.assertEqual(b.cache_key(enabled), b.cache_key(prefs()))
        with tempfile.TemporaryDirectory() as td:
            state = Path(td)
            b.atomic_json(state/'settings.json', enabled)
            self.assertTrue(b.load_settings(state)['showSunrise'])

    def test_cache_fingerprint_includes_all_calculation_settings(self):
        p=prefs(); key=b.cache_key(p)
        for name,value in [('method',3),('school',1),('highLatitude',1),('offsets',{'Fajr':1})]:
            changed=copy.deepcopy(p); changed[name]=value
            self.assertNotEqual(b.cache_key(changed),key)
        p['sound']=False
        self.assertEqual(b.cache_key(p),key)

    def test_partial_month_cache_reused_offline(self):
        with tempfile.TemporaryDirectory() as td:
            state=Path(td); p=prefs()
            today=datetime.now(ZoneInfo(LOC['timezone'])).date()
            end=(today.replace(day=28)+timedelta(days=4)).replace(day=1)
            end=(end.replace(day=28)+timedelta(days=4)).replace(day=1)
            days=[]; d=today-timedelta(days=1)
            while d<end:
                days.append({'date':d.isoformat()}); d+=timedelta(days=1)
            b.atomic_json(state/'calendar.json',dict(key=b.cache_key(p),days=days,fetchedAt=1))
            with patch.object(b,'fetch_month',side_effect=AssertionError('Network should not be called')):
                result=b.sync(state,{'settings':p})
            self.assertEqual(result['error'],'')
            self.assertEqual(result['data']['fetchedAt'],1)

    def test_failed_refresh_keeps_matching_cache_but_rejects_other_method(self):
        with tempfile.TemporaryDirectory() as td:
            state=Path(td); p=prefs(); cache=dict(key=b.cache_key(p),days=[{'date':'2026-10-15'}],fetchedAt=1)
            b.atomic_json(state/'calendar.json',cache)
            with patch.object(b,'fetch_month',side_effect=ValueError('offline')):
                result=b.sync(state,{'settings':p,'force':True})
                self.assertEqual(result['data']['days'],cache['days'])
                changed=b.sync(state,{'settings':prefs(method=3)})
                self.assertEqual(changed['data']['days'],[])
            self.assertEqual(b.read_json(state/'calendar.json'),cache)

    def test_alert_claim_survives_restarts_and_ignores_stale_prayers(self):
        with tempfile.TemporaryDirectory() as td:
            state=Path(td); p=prefs(sound=False)
            row=dict(name='Asr',at=int(datetime.now(timezone.utc).timestamp()*1000)-1000,date='2026-10-15',time='15:42')
            b.atomic_json(state/'settings.json',p)
            b.atomic_json(state/'calendar.json',dict(key=b.cache_key(p),days=[{'rows':[row]}]))
            with patch.object(b.subprocess,'run') as run:
                self.assertTrue(b.alert(state,row)['notified'])
                self.assertFalse(b.alert(state,row)['notified'])
                run.assert_called_once()
            row['at']-=60000
            b.atomic_json(state/'calendar.json',dict(key=b.cache_key(p),days=[{'rows':[row]}]))
            self.assertFalse(b.alert(state,row)['notified'])

    def test_alert_uses_clock_preference(self):
        for clock24 in (False, True):
            for time, twelve_hour in [('00:05', '12:05 AM'), ('05:07', '5:07 AM'),
                                      ('12:00', '12:00 PM'), ('15:42', '3:42 PM')]:
                with self.subTest(clock24=clock24, time=time), tempfile.TemporaryDirectory() as td:
                    state = Path(td)
                    p = prefs(sound=False, clock24=clock24)
                    row = dict(name='Asr', at=int(datetime.now(timezone.utc).timestamp()*1000)-1000,
                               date='2026-10-15', time=time)
                    b.atomic_json(state/'settings.json', p)
                    b.atomic_json(state/'calendar.json', dict(key=b.cache_key(p), days=[{'rows': [row]}]))
                    with patch.object(b.subprocess, 'run') as run:
                        self.assertTrue(b.alert(state, row)['notified'])
                    expected = time if clock24 else twelve_hour
                    self.assertEqual(run.call_args.args[0][-1], f"It's time for Asr · {expected}")

    def test_sujood_migration_preserves_preferences_cache_and_alert_claims(self):
        with tempfile.TemporaryDirectory() as td:
            legacy=Path(td)/'prayer'; state=Path(td)/'sujood'
            saved=prefs(showSunrise=True,sound=False)
            cache=dict(key=b.cache_key(saved),days=[],fetchedAt=1)
            claims={'2026-10-15:Asr': 123}
            b.atomic_json(legacy/'settings.json',saved)
            b.atomic_json(legacy/'calendar.json',cache)
            b.atomic_json(legacy/'notified.json',claims)
            self.assertEqual(b.load_settings(state),saved)
            self.assertEqual(b.read_json(state/'calendar.json'),cache)
            self.assertEqual(b.read_json(state/'notified.json'),claims)
            changed=prefs(showSunrise=False)
            b.atomic_json(state/'settings.json',changed)
            self.assertEqual(b.load_settings(state),changed)
            self.assertEqual(b.read_json(legacy/'settings.json'),saved)

    def test_fresh_sujood_install_needs_no_old_plugin(self):
        with tempfile.TemporaryDirectory() as td:
            state=Path(td)/'sujood'
            with patch.object(b.Path,'home',return_value=Path(td)/'clean-home'):
                self.assertIsNone(b.load_settings(state)['location'])
            result=b.sync(state,{'settings':b.DEFAULTS})
            self.assertEqual(result['data']['days'],[])
            self.assertIn('Choose city',result['error'])

if __name__=='__main__': unittest.main()
