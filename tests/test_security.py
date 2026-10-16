"""Regression tests for process privacy and network resource/trust boundaries."""
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import backend as b


class SecurityTests(unittest.TestCase):
    def response(self, body):
        opener = Mock()
        opener.open.return_value = io.BytesIO(body)
        return patch.object(b, 'build_opener', return_value=opener)

    def test_response_limit_accepts_boundary_and_rejects_larger_body(self):
        body = json.dumps({'results': [], 'padding': 'x'*200}).encode()
        with patch.object(b, 'MAX_RESPONSE_BYTES', len(body)):
            with self.response(body) as factory:
                self.assertEqual(b.get_json('https://geocoding-api.open-meteo.com/v1/search', {})['results'], [])
                self.assertIsInstance(factory.call_args.args[0], b.RejectRedirects)
            with self.response(body+b' '):
                with self.assertRaisesRegex(ValueError, 'too large'):
                    b.get_json('https://api.aladhan.com/v1/calendar/2026/10', {})

    def test_invalid_or_deeply_nested_json_is_reported_cleanly(self):
        for body in (b'<html>Service unavailable</html>', b'['*2000+b']'*2000, b'[]'):
            with self.subTest(body=body[:20]), self.response(body):
                with self.assertRaises(ValueError):
                    b.get_json('https://api.aladhan.com/v1/calendar/2026/10', {})

    def test_unapproved_urls_never_start_a_request(self):
        urls = ['http://api.aladhan.com/test', 'https://example.invalid/test',
                'https://api.aladhan.com.example.invalid/test',
                'https://user:secret@api.aladhan.com/test',
                'https://api.aladhan.com:8443/test', 'file:///etc/passwd']
        with patch.object(b, 'build_opener') as factory:
            for url in urls:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    b.get_json(url, {})
            factory.assert_not_called()

    def test_redirect_policy_blocks_downgrades_and_host_changes(self):
        request = Request('https://api.aladhan.com/v1/calendar/2026/10')
        for status in (301, 302, 303, 307, 308):
            for url in ('http://api.aladhan.com/test', 'https://example.invalid/test',
                        'https://api.aladhan.com/other'):
                with self.subTest(status=status, url=url), self.assertRaisesRegex(ValueError, 'redirected'):
                    b.RejectRedirects().redirect_request(request, None, status, 'Redirect', {}, url)

    def test_search_result_count_and_display_strings_are_bounded(self):
        location = dict(name='x'*500+'\n', latitude=21.4, longitude=39.8,
                        timezone='Asia/Riyadh', country_code='SA',
                        admin1='y'*500, country='Saudi Arabia')
        with patch.object(b, 'get_json', return_value=dict(results=[location]*50)):
            results = b.search('Mecca')
        self.assertEqual(len(results), 10)
        self.assertEqual(len(results[0]['name']), 160)
        self.assertEqual(len(results[0]['region']), 200)
        with patch.object(b, 'get_json') as get:
            with self.assertRaises(ValueError):
                b.search('x'*161)
            get.assert_not_called()

    def test_rejected_response_keeps_valid_matching_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            settings = b.normalize_settings(dict(location=dict(name='Mecca', latitude=21.4,
                longitude=39.8, timezone='Asia/Riyadh', countryCode='SA')))
            cache = dict(key=b.cache_key(settings), days=[dict(date='2026-10-15')], fetchedAt=1)
            b.atomic_json(state/'calendar.json', cache)
            for error in ('response too large', 'redirected request blocked'):
                with patch.object(b, 'fetch_month', side_effect=ValueError(error)):
                    result = b.sync(state, dict(settings=settings, force=True))
                self.assertIn(error, result['error'])
                self.assertEqual(result['data']['days'], cache['days'])
                self.assertEqual(b.read_json(state/'calendar.json'), cache)

    def test_private_stdin_payload_is_not_part_of_process_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            command = [sys.executable, str(Path(b.__file__)), 'sync', '--stdin', '--state-dir', directory]
            payload = dict(settings=dict(school=1, offsets=dict(Fajr=7)))
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                cmdline = Path('/proc')/str(process.pid)/'cmdline'
                if cmdline.exists():
                    self.assertNotIn(b'offsets', cmdline.read_bytes())
                    self.assertNotIn(b'Fajr', cmdline.read_bytes())
                output, error = process.communicate((json.dumps(payload)+'\n').encode(), timeout=5)
                self.assertEqual(process.returncode, 0, error)
                result = json.loads(output)
                self.assertEqual(result['settings']['school'], 1)
                self.assertEqual(result['settings']['offsets']['Fajr'], 7)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_bad_stdin_payloads_return_json_errors_without_writing_state(self):
        with tempfile.TemporaryDirectory() as directory:
            for payload in (b'[]\n', b'{bad json}\n', b'x'*(b.MAX_PAYLOAD_BYTES+1)+b'\n'):
                result = subprocess.run([sys.executable, str(Path(b.__file__)), 'sync', '--stdin',
                                         '--state-dir', directory], input=payload, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 1)
                self.assertIn('error', json.loads(result.stdout))
                self.assertEqual(list(Path(directory).iterdir()), [])
