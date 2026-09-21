import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import threading
import time
import unittest
from probe_preparation import prepare_stage


class PreparationTests(unittest.TestCase):
    def request(self, *, status=200, value=None, headers_delay=0, body_delay=0, drip=False, timeout=1):
        calls = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                calls.append((self.path, self.headers['X-Probe-Key'],
                              json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
                try:
                    time.sleep(headers_delay)
                    self.send_response(status); self.end_headers()
                    payload = json.dumps(value if value is not None else {'stage': 'A11', 'ready': True}).encode()
                    if drip:
                        for byte in payload:
                            self.wfile.write(bytes([byte])); self.wfile.flush(); time.sleep(.02)
                    else:
                        time.sleep(body_delay); self.wfile.write(payload)
                except (BrokenPipeError, ConnectionResetError): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever); thread.start()
        start = time.monotonic()
        try:
            try:
                result = prepare_stage({'port': server.server_port, 'key': 'test-only-proof'}, 'A11', timeout=timeout)
            except Exception as error:
                result = error
            elapsed = time.monotonic() - start
        finally:
            server.shutdown(); server.server_close(); thread.join()
        self.assertEqual(calls, [('/fixture/prepare', 'test-only-proof', {'stage': 'A11'})])
        return result, elapsed

    def test_success_once(self):
        result, _ = self.request()
        self.assertEqual(result['attempts'], 1)
        self.assertEqual(result['stage'], 'A11')
        self.assertNotIn('key', result)

    def test_http_failure_not_retried(self):
        for status in (409, 500, 503):
            with self.subTest(status=status):
                self.assertIsInstance(self.request(status=status)[0], ValueError)

    def test_wrong_or_extra_receipt_fields_fail(self):
        for value in ({'stage': 'A12', 'ready': True}, {'stage': 'A11', 'ready': False},
                      {'stage': 'A11', 'ready': True, 'secret': 'not-allowed'}):
            with self.subTest(value=value):
                self.assertIsInstance(self.request(value=value)[0], ValueError)

    def test_header_and_body_share_deadline(self):
        result, elapsed = self.request(headers_delay=.15, body_delay=.15, timeout=.23)
        self.assertIsInstance(result, TimeoutError)
        self.assertLess(elapsed, .5)

    def test_drip_body_is_interrupted(self):
        result, elapsed = self.request(drip=True, timeout=.15)
        self.assertIsInstance(result, TimeoutError)
        self.assertLess(elapsed, .4)

    def test_invalid_stage_sends_nothing(self):
        with self.assertRaises(ValueError):
            prepare_stage({'port': 1, 'key': 'unused'}, 'OTHER')

    def test_driver_prepares_before_crash_host_loop(self):
        source = (Path(__file__).parent/'verify_native_crash_boundaries.py').read_text()
        self.assertLess(source.index('preparation=prepare_stage(connection,stage)'), source.index("for mode in ['CRASH','RECOVER']"))


if __name__ == '__main__': unittest.main()
