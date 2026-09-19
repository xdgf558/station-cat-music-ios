"""Read-only host evidence collection regression; no auth mutation is executed."""
import io
import json
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import Mock
from urllib.error import HTTPError, URLError
from probe_evidence import MAX_BYTES, read_probe_evidence, validate_evidence

CONNECTION = {'port': 12345, 'key': 'FIXTURE_ONLY'}


def fixture(stage='A12'):
    first = {'requestId': '00000000-0000-4000-8000-000000000001', 'generation': 0, 'status': 200,
             'resultFingerprint': 'a' * 64, 'resultGeneration': 1, 'committedAt': 1000}
    second = {**first, 'committedAt': 1500}
    operations = [{'request_id': first['requestId'], 'old_generation': 0}]
    if stage == 'A13':
        second.update(requestId='00000000-0000-4000-8000-000000000002', generation=1,
                      resultGeneration=2, resultFingerprint='b' * 64)
        operations.append({'request_id': second['requestId'], 'old_generation': 1})
    return {'stage': stage, 'held': stage == 'A11', 'requests': [first, second],
            'session': {'generation': 2 if stage == 'A13' else 1, 'revoked': 0}, 'operations': operations}


def response(value): return io.BytesIO(json.dumps(value).encode())


class Clock:
    def __init__(self): self.now = 0
    def __call__(self): return self.now
    def advance(self, seconds): self.now += seconds


class EvidenceTests(unittest.TestCase):
    def test_first_evidence_timeout_then_success_uses_get_only(self):
        clock = Clock(); opener = Mock(side_effect=[TimeoutError(), response(fixture())])
        value, stats = read_probe_evidence(CONNECTION, 'A12', opener=opener, clock=clock, sleep=clock.advance)
        self.assertEqual(stats['attempts'], 2); self.assertEqual(value, fixture())
        self.assertEqual(len(value['requests']), 2)  # Never seed, refresh, or restart recovery.
        for call in opener.call_args_list:
            self.assertEqual(call.args[0].get_method(), 'GET')
            self.assertTrue(call.args[0].full_url.endswith('/fixture/evidence'))
            self.assertIsNone(call.args[0].data)

    def test_real_loopback_read_timeout_then_recovery(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append((self.command, self.path))
                if len(requests) == 1: time.sleep(.8)
                body = json.dumps(fixture()).encode()
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                try: self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError): pass
            def log_message(self, *args): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            value, stats = read_probe_evidence({'port': server.server_port, 'key': 'FIXTURE_ONLY'}, 'A12', request_timeout=.5, total_timeout=5)
            self.assertEqual(stats['attempts'], 2); self.assertEqual(value, fixture())
            self.assertEqual(requests, [('GET', '/fixture/evidence')] * 2)
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_absolute_deadline_covers_headers_and_slow_body(self):
        for mode in ['headers_then_body', 'drip']:
            closed = threading.Event()
            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    try:
                        if mode == 'headers_then_body': time.sleep(.14)
                        body = json.dumps(fixture()).encode()
                        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                        if mode == 'headers_then_body':
                            time.sleep(.14); self.wfile.write(body)
                        else:
                            for byte in body:
                                self.wfile.write(bytes([byte])); self.wfile.flush(); time.sleep(.07)
                    except (BrokenPipeError, ConnectionResetError): closed.set()
                def log_message(self, *args): pass
            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                started = time.monotonic()
                with self.assertRaisesRegex(RuntimeError, 'exhausted'):
                    read_probe_evidence({'port': server.server_port, 'key': 'FIXTURE_ONLY'}, 'A12',
                                        request_timeout=.2, total_timeout=.23, max_attempts=1)
                self.assertLess(time.monotonic() - started, .5)
                if mode == 'drip': self.assertTrue(closed.wait(1), 'underlying socket must close')
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_total_budget_exhaustion_caps_each_timeout(self):
        clock = Clock()
        def timeout(request, timeout): clock.advance(timeout); raise TimeoutError()
        opener = Mock(side_effect=timeout)
        with self.assertRaisesRegex(RuntimeError, 'recovery was not rerun'):
            read_probe_evidence(CONNECTION, 'A12', opener=opener, clock=clock, sleep=clock.advance)
        self.assertEqual(clock.now, 20); self.assertEqual(opener.call_count, 4)
        self.assertEqual(opener.call_args.kwargs['timeout'], 3.5)

    def test_attempt_limit_even_for_immediate_connection_failures(self):
        clock = Clock(); opener = Mock(side_effect=URLError('offline'))
        with self.assertRaisesRegex(RuntimeError, '4 attempts'):
            read_probe_evidence(CONNECTION, 'A12', opener=opener, clock=clock, sleep=clock.advance)
        self.assertEqual(opener.call_count, 4)

    def test_late_success_is_not_accepted_past_total_budget(self):
        clock = Clock()
        def late(request, timeout): clock.advance(21); return response(fixture())
        with self.assertRaisesRegex(RuntimeError, 'exhausted'):
            read_probe_evidence(CONNECTION, 'A12', opener=late, clock=clock, sleep=clock.advance)

    def test_wrong_stage_is_not_retried(self):
        opener = Mock(side_effect=[response(fixture('A11')), response(fixture())])
        with self.assertRaises(ValueError): read_probe_evidence(CONNECTION, 'A12', opener=opener)
        self.assertEqual(opener.call_count, 1)

    def test_transient_http_error_retries_but_forbidden_does_not(self):
        clock = Clock()
        opener = Mock(side_effect=[HTTPError('fixture', 503, '', {}, None), response(fixture())])
        self.assertEqual(read_probe_evidence(CONNECTION, 'A12', opener=opener, clock=clock, sleep=clock.advance)[1]['attempts'], 2)
        opener = Mock(side_effect=HTTPError('fixture', 403, '', {}, None))
        with self.assertRaises(HTTPError): read_probe_evidence(CONNECTION, 'A12', opener=opener)
        self.assertEqual(opener.call_count, 1)

    def test_malformed_and_oversized_bodies_fail_without_retry(self):
        for body in [b'{', b'x' * (MAX_BYTES + 1)]:
            opener = Mock(return_value=io.BytesIO(body))
            with self.assertRaises(ValueError): read_probe_evidence(CONNECTION, 'A12', opener=opener)
            self.assertEqual(opener.call_count, 1)

    def test_all_stages_and_allowlisted_archive(self):
        for stage in ['A11', 'A12', 'A13']:
            value = fixture(stage); value['future_private_field'] = 'DO_NOT_ARCHIVE'
            self.assertEqual(validate_evidence(value, stage), fixture(stage))

    def test_inconsistent_evidence_fails_closed(self):
        invalid = []
        def changed(edit):
            value = fixture(); edit(value); invalid.append(value)
        changed(lambda v: v['requests'].pop())
        changed(lambda v: v['requests'].append(v['requests'][0]))
        changed(lambda v: v['session'].update(revoked=1))
        changed(lambda v: v['session'].update(generation=2))
        changed(lambda v: v['requests'][1].update(status=401))
        changed(lambda v: v['requests'][1].update(generation=1))
        changed(lambda v: v['requests'][1].update(resultGeneration=2))
        changed(lambda v: v['requests'][1].update(requestId='00000000-0000-4000-8000-000000000002'))
        changed(lambda v: v['requests'][1].update(resultFingerprint='b' * 64))
        changed(lambda v: v['requests'][1].update(committedAt=121000))
        changed(lambda v: v['requests'][1].update(committedAt=float('nan')))
        changed(lambda v: v['requests'][1].update(committedAt=500))
        changed(lambda v: v['operations'][0].update(old_generation=True))
        changed(lambda v: v['operations'][0].update(request_id='wrong'))
        changed(lambda v: v.update(held=True))
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError): validate_evidence(value, 'A12')
        value = fixture('A13'); value['requests'][1]['requestId'] = value['requests'][0]['requestId']
        with self.assertRaises(ValueError): validate_evidence(value, 'A13')


if __name__ == '__main__': unittest.main(verbosity=2)
