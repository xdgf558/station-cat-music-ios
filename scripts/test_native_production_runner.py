#!/usr/bin/env python3
"""Fail-closed checks for the local production driver; no simulator/network required."""
import copy
import base64
import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path
import subprocess
import threading
import time
import tempfile
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('production_runner', Path(__file__).with_name('verify_native_production.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


class ProductionRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='production-pin-test-')
        self.addCleanup(self.temporary.cleanup)
        self.backend = Path(self.temporary.name)
        for name in runner.REQUIRED:
            path = self.backend / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}\n' if name.endswith('.json') else 'synthetic dependency\n')
        def git(*args):
            return subprocess.check_output(['git', *args], cwd=self.backend, text=True, stderr=subprocess.DEVNULL).strip()
        git('init'); git('config', 'user.email', 'fixture@example.test'); git('config', 'user.name', 'Local fixture')
        git('add', '.'); git('commit', '-m', 'Synthetic test baseline')
        self.manifest = {'schemaVersion': 1, 'repository': 'xdgf558/caption-ai-landing-site',
            'profileId': 'station-native-production-v1', 'commit': git('rev-parse', 'HEAD'), 'protectedPaths': list(runner.PROTECTED),
            'sha256': {name: hashlib.sha256((self.backend / name).read_bytes()).hexdigest() for name in runner.REQUIRED}}
        self.matrix = self.backend / 'tests/fixtures/mobile-links/canonical-link-cases.json'

    def check(self, manifest=None):
        return runner.verify_backend(self.backend, manifest or self.manifest, self.matrix)

    def prepare_driver_fixture(self, state='Shutdown'):
        contracts = self.backend / 'contracts'; contracts.mkdir(exist_ok=True)
        (contracts / 'backend-production-fixture.json').write_text(json.dumps(self.manifest))
        products = self.backend / '.build/production-e2e/Build/Products'; products.mkdir(parents=True, exist_ok=True)
        source = {'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'StationCatMusicTests'}]}]}
        (products / 'StationCatMusic_fixture.xctestrun').write_bytes(plistlib.dumps(source))
        simulator = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
        inventory = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
            {'udid': simulator, 'isAvailable': True, 'name': 'iPhone synthetic', 'state': state}]}}
        return simulator, inventory, products

    def test_reviewed_clean_source_passes(self):
        self.assertEqual(self.check(), self.manifest['commit'])

    def test_wrong_commit_rejected(self):
        self.manifest['commit'] = 'a' * 40
        with self.assertRaises(runner.VerificationError): self.check()

    def test_missing_pin_or_extra_inventory_rejected(self):
        del self.manifest['sha256']['src/worker.js']
        with self.assertRaises(runner.VerificationError): self.check()

    def test_changed_source_missing_source_or_digest_rejected(self):
        source = self.backend / 'src/worker.js'; original = source.read_bytes()
        source.write_text('changed')
        with self.assertRaises(runner.VerificationError): self.check()
        source.unlink()
        with self.assertRaises(runner.VerificationError): self.check()
        source.write_bytes(original); self.manifest['sha256']['src/worker.js'] = '0' * 64
        with self.assertRaises(runner.VerificationError): self.check()

    def test_new_untracked_dependency_rejected(self):
        (self.backend / 'src/new-import.js').write_text('changed')
        with self.assertRaises(runner.VerificationError): self.check()

    def test_matrix_mismatch_rejected(self):
        with tempfile.NamedTemporaryFile() as matrix:
            Path(matrix.name).write_text('different')
            with self.assertRaises(runner.VerificationError): runner.verify_backend(self.backend, self.manifest, Path(matrix.name))

    def test_connection_cannot_choose_host_or_invalid_proof(self):
        valid = {'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43}
        self.assertEqual(runner.validate_connection(valid), valid)
        for change in [{'port': True}, {'port': 443}, {'port': 65536}, {'key': 'bad'}, {'host': 'wwwstationcat.org'}, {'schemaVersion': 2}, {'schemaVersion': True}]:
            with self.assertRaises(runner.VerificationError): runner.validate_connection(valid | change)

    def test_only_available_simulator_is_accepted(self):
        identifier = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
        rows = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
            {'udid': identifier, 'isAvailable': True, 'name': 'iPhone synthetic'}]}}
        self.assertEqual(runner.validate_simulator(identifier, rows), 'iPhone synthetic')
        for rejected in ['', 'platform=iOS,id=' + identifier, 'AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF']:
            with self.assertRaises(runner.VerificationError): runner.validate_simulator(rejected, rows)
        rows['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-4'][0]['isAvailable'] = False
        with self.assertRaises(runner.VerificationError): runner.validate_simulator(identifier, rows)

    def test_already_booted_simulator_still_waits_for_bootstatus(self):
        simulator, inventory, _ = self.prepare_driver_fixture('Booted')
        run = Mock()
        runner.boot_simulator(simulator, inventory, run)
        run.assert_called_once_with(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], 'production-local-bootstatus.log')

    def test_unknown_simulator_boot_state_fails_closed(self):
        simulator, inventory, _ = self.prepare_driver_fixture('Shutting Down')
        run = Mock()
        with self.assertRaisesRegex(runner.VerificationError, 'boot state'):
            runner.boot_simulator(simulator, inventory, run)
        run.assert_not_called()

    def test_proof_injected_only_into_unit_target(self):
        data = {'TestConfigurations': [{'TestTargets': [
            {'BlueprintName': 'StationCatMusicTests'}, {'BlueprintName': 'StationCatMusicUITests'}]}]}
        result = runner.inject_connection(copy.deepcopy(data), {'port': 49152, 'key': 'K' * 43})
        targets = result['TestConfigurations'][0]['TestTargets']
        self.assertEqual(targets[0]['EnvironmentVariables']['PRODUCTION_ENABLE_LOCAL_E2E'], 'YES')
        self.assertNotIn('EnvironmentVariables', targets[1])
        with self.assertRaises(runner.VerificationError): runner.inject_connection({'TestConfigurations': []}, {'port': 49152, 'key': 'K' * 43})

    def test_skipped_or_partial_evidence_rejected(self):
        runner.require_evidence('\n'.join(runner.MARKERS))
        for value in ['', '\n'.join(runner.MARKERS[:-1]), '\n'.join(runner.MARKERS) + '\nPRODUCTION_NATIVE_LOCAL_FAILED']:
            with self.assertRaises(runner.VerificationError): runner.require_evidence(value)

    def test_legacy_xctestrun_shape_keeps_proof_scoped(self):
        data = {'StationCatMusicTests': {'BlueprintName': 'StationCatMusicTests'},
                'StationCatMusicUITests': {'BlueprintName': 'StationCatMusicUITests'}, '__xctestrun_metadata__': {'FormatVersion': 1}}
        result = runner.inject_connection(data, {'port': 49152, 'key': 'K' * 43})
        self.assertEqual(result['StationCatMusicTests']['EnvironmentVariables']['PRODUCTION_ENABLE_LOCAL_E2E'], 'YES')
        self.assertNotIn('EnvironmentVariables', result['StationCatMusicUITests'])
        self.assertNotIn('EnvironmentVariables', result['__xctestrun_metadata__'])

    def test_worker_evidence_rejects_network_effects_missing_counts_and_open_sessions(self):
        valid = {'schemaVersion': 1, 'scope': 'local-production-profile-e2e', 'outboundRequests': 0,
            'hasProductionSideEffects': False, 'requests': [{}, {}, {}], 'requestCount': 3,
            'counts': {'sessions': 3, 'revokedSessions': 3, 'refreshOperations': 1, 'favorites': 1, 'recent': 1}}
        self.assertEqual(runner.validate_service_evidence(valid)['requestCount'], 3)
        for change in [{'outboundRequests': 1}, {'outboundRequests': False}, {'hasProductionSideEffects': True},
                       {'requestCount': 0}, {'requestCount': 4}, {'counts': {}},
                       {'counts': valid['counts'] | {'recent': 0}}, {'counts': valid['counts'] | {'revokedSessions': 1}}]:
            with self.assertRaises(runner.VerificationError): runner.validate_service_evidence(valid | change)

    def test_failed_rerun_clears_previous_passed_report_and_logs(self):
        output = self.backend / 'evidence'; output.mkdir()
        names = ('production-local-summary.json', 'production-local-build.log',
                 'production-local-boot.log', 'production-local-bootstatus.log',
                         'production-local-integration.log', 'production-local-service.log', 'production-local-runtime.jsonl',
                         'production-local-readiness.log')
        for name in names: (output / name).write_text('previous successful run')
        with patch.object(runner, 'ROOT', self.backend), patch.dict(runner.os.environ, {}, clear=True), patch('builtins.print'):
            with self.assertRaises(runner.VerificationError): runner.main()
        self.assertTrue(all(not (output / name).exists() for name in names))

    def test_failed_xctest_retains_runtime_and_original_log_with_matching_run_id(self):
        simulator, inventory, products = self.prepare_driver_fixture()
        launches = []; events = []
        class Server:
            def terminate(self): pass
            def wait(self, timeout): return 0
        def launch(arguments, **options):
            self.assertEqual(events[-1], 'bootstatus_completed')
            events.append('service_started')
            launches.append(arguments)
            self.assertIn('--import', arguments)
            directory = Path(arguments[-1]); ready = directory / 'ready.json'
            ready.write_text(json.dumps({'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43})); ready.chmod(0o600)
            env = options['env']
            Path(env['PRODUCTION_RUNTIME_DIAGNOSTICS_FILE']).write_text(json.dumps({
                'event': 'observer_started', 'runId': env['PRODUCTION_RUNTIME_DIAGNOSTICS_RUN_ID']}) + '\n')
            return Server()
        def execute(arguments, **options):
            failed = 'test-without-building' in arguments
            if 'build-for-testing' in arguments: events.append('build_completed')
            if arguments[:3] == ['xcrun', 'simctl', 'boot']:
                self.assertEqual(events[-1], 'build_completed')
                self.assertEqual(options['timeout'], 900)
                events.append('boot_completed')
            if arguments[:3] == ['xcrun', 'simctl', 'bootstatus']:
                self.assertEqual(events[-1], 'boot_completed')
                self.assertEqual(options['timeout'], 900)
                events.append('bootstatus_completed')
            if failed:
                self.assertEqual(events[-1], 'worker_ready')
                options['stdout'].write('PRODUCTION_NATIVE_LOCAL_FAILED stage=capability_request category=fixture_response\n')
            return subprocess.CompletedProcess(arguments, 65 if failed else 0)
        def readiness(connection, **options):
            self.assertEqual(events[-1], 'service_started')
            events.append('worker_ready')
            options['record']({'event': 'ready', 'attempts': 1, 'seconds': .1})
            return {'attempts': 1, 'seconds': .1}
        with patch.object(runner, 'ROOT', self.backend), patch.object(runner, 'verify_backend', return_value=self.manifest['commit']), \
             patch.dict(runner.os.environ, {'PRODUCTION_BACKEND_PATH': str(self.backend), 'M1_SIMULATOR_ID': simulator}, clear=True), \
             patch.object(runner.subprocess, 'check_output', return_value=json.dumps(inventory)), \
             patch.object(runner.subprocess, 'run', side_effect=execute), patch.object(runner.subprocess, 'Popen', side_effect=launch), \
             patch.object(runner, 'wait_for_worker_readiness', side_effect=readiness), \
             patch('builtins.print'):
            with self.assertRaisesRegex(runner.VerificationError, 'production-local-integration.log'):
                runner.main()
        self.assertEqual(len(launches), 1)
        self.assertEqual(events, ['build_completed', 'boot_completed', 'bootstatus_completed', 'service_started', 'worker_ready'])
        output = self.backend / 'evidence'; runtime = output / 'production-local-runtime.jsonl'
        diagnostic = json.loads(runtime.read_text())
        log = (output / 'production-local-integration.log').read_text()
        self.assertIn(diagnostic['runId'], log)
        self.assertIn('stage=capability_request category=fixture_response', log)
        self.assertEqual(runtime.stat().st_mode & 0o777, 0o600)
        self.assertFalse((output / 'production-local-summary.json').exists())
        self.assertFalse(list(products.glob('production-local-*.xctestrun')))

    def test_readiness_failure_never_starts_xctest_and_preserves_diagnostics(self):
        simulator, inventory, products = self.prepare_driver_fixture('Booted')
        commands = []; closed = []
        class Server:
            def terminate(self): closed.append('terminated')
            def wait(self, timeout): return 0
        def launch(arguments, **options):
            directory = Path(arguments[-1]); ready = directory / 'ready.json'
            ready.write_text(json.dumps({'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43})); ready.chmod(0o600)
            env = options['env']
            Path(env['PRODUCTION_RUNTIME_DIAGNOSTICS_FILE']).write_text(json.dumps({
                'event': 'observer_started', 'runId': env['PRODUCTION_RUNTIME_DIAGNOSTICS_RUN_ID']}) + '\n')
            return Server()
        def execute(arguments, **options):
            commands.append(arguments)
            return subprocess.CompletedProcess(arguments, 0)
        def readiness(connection, **options):
            options['record']({'event': 'exhausted', 'attempts': 4, 'seconds': 20})
            raise runner.VerificationError('Local Worker readiness exhausted; XCTest was not started')
        output = self.backend / 'evidence'; output.mkdir()
        (output / 'production-local-summary.json').write_text('old successful summary')
        with patch.object(runner, 'ROOT', self.backend), patch.object(runner, 'verify_backend', return_value=self.manifest['commit']), \
             patch.dict(runner.os.environ, {'PRODUCTION_BACKEND_PATH': str(self.backend), 'M1_SIMULATOR_ID': simulator}, clear=True), \
             patch.object(runner.subprocess, 'check_output', return_value=json.dumps(inventory)), \
             patch.object(runner.subprocess, 'run', side_effect=execute), patch.object(runner.subprocess, 'Popen', side_effect=launch), \
             patch.object(runner, 'wait_for_worker_readiness', side_effect=readiness), patch('builtins.print'):
            with self.assertRaisesRegex(runner.VerificationError, 'readiness exhausted'): runner.main()
        self.assertFalse(any('test-without-building' in command for command in commands))
        self.assertEqual(closed, ['terminated'])
        self.assertFalse((output / 'production-local-summary.json').exists())
        self.assertFalse(list(products.glob('production-local-*.xctestrun')))
        log = (output / 'production-local-readiness.log').read_text()
        runtime = json.loads((output / 'production-local-runtime.jsonl').read_text())
        self.assertIn(runtime['runId'], log)
        self.assertIn('exhausted', log)
        self.assertNotIn('K' * 43, log)

    def test_boot_or_bootstatus_failure_clears_old_green_and_never_starts_service(self):
        simulator, inventory, _ = self.prepare_driver_fixture()
        for failed_step in ('boot', 'bootstatus'):
            with self.subTest(step=failed_step):
                output = self.backend / 'evidence'; output.mkdir(exist_ok=True)
                stale = ('production-local-summary.json', 'production-local-integration.log',
                         'production-local-service.log', 'production-local-runtime.jsonl')
                for name in stale: (output / name).write_text('previous successful run')
                commands = []
                def execute(arguments, **options):
                    commands.append(arguments)
                    failed = arguments[:3] == ['xcrun', 'simctl', failed_step]
                    if failed: self.assertEqual(options['timeout'], 900)
                    return subprocess.CompletedProcess(arguments, 1 if failed else 0)
                with patch.object(runner, 'ROOT', self.backend), patch.object(runner, 'verify_backend', return_value=self.manifest['commit']), \
                     patch.dict(runner.os.environ, {'PRODUCTION_BACKEND_PATH': str(self.backend), 'M1_SIMULATOR_ID': simulator}, clear=True), \
                     patch.object(runner.subprocess, 'check_output', return_value=json.dumps(inventory)), \
                     patch.object(runner.subprocess, 'run', side_effect=execute), patch.object(runner.subprocess, 'Popen') as launch, patch('builtins.print'):
                    with self.assertRaisesRegex(runner.VerificationError, 'production-local-' + failed_step + '.log'):
                        runner.main()
                    launch.assert_not_called()
                self.assertTrue(all(not (output / name).exists() for name in stale))
                self.assertEqual(commands[-1][:3], ['xcrun', 'simctl', failed_step])
                self.assertFalse(any('test-without-building' in command for command in commands))


class WorkerReadinessTests(unittest.TestCase):
    def envelope(self, flags=None, status=200):
        expected = {'nativeAuthentication': True, 'musicCatalog': True, 'musicPlayback': True,
                    'personalSync': True, 'accountDeletion': False, 'musicPurchases': False}
        payload = json.dumps({'data': {'apiVersion': '1', 'capabilities': expected | (flags or {})}}).encode()
        return {'status': status, 'headers': {'content-type': 'application/json; charset=utf-8'},
                'bodyBase64': base64.b64encode(payload).decode()}

    def server(self, replies):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                requests.append((self.path, self.headers.get('X-Production-Probe-Key'), json.loads(body)))
                reply = replies[min(len(requests) - 1, len(replies) - 1)]
                status, value = reply[:2]
                header_delay = reply[2] if len(reply) > 2 else 0
                body_delay = reply[3] if len(reply) > 3 else 0
                chunk_delay = reply[4] if len(reply) > 4 else 0
                payload = value if isinstance(value, bytes) else json.dumps(value).encode()
                try:
                    time.sleep(header_delay)
                    self.send_response(status); self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(payload))); self.end_headers()
                    time.sleep(body_delay)
                    if chunk_delay:
                        for offset in range(0, len(payload), 8):
                            self.wfile.write(payload[offset:offset + 8]); self.wfile.flush(); time.sleep(chunk_delay)
                    else: self.wfile.write(payload)
                except (BrokenPipeError, ConnectionResetError): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .01}, daemon=True); thread.start()
        def cleanup():
            server.shutdown(); server.server_close(); thread.join()
        self.addCleanup(cleanup)
        return {'schemaVersion': 1, 'port': server.server_port, 'key': 'K' * 43}, requests

    def test_fixed_get_over_protected_loopback_and_scalar_ready_report(self):
        connection, requests = self.server([(200, self.envelope())])
        events = []
        result = runner.wait_for_worker_readiness(connection, record=events.append)
        self.assertEqual(result['attempts'], 1)
        self.assertEqual(requests, [('/request', 'K' * 43, {
            'url': 'https://wwwstationcat.org/api/mobile/v1/config', 'method': 'GET', 'headers': {}})])
        self.assertEqual(events[0]['event'], 'ready')
        self.assertEqual(set(events[0]), {'event', 'attempts', 'seconds'})

    def test_only_bridge_request_timeout_is_retried(self):
        connection, requests = self.server([(408, {'error': {'code': 'REQUEST_TIMEOUT'}}), (200, self.envelope())])
        events = []
        result = runner.wait_for_worker_readiness(connection, record=events.append)
        self.assertEqual(result['attempts'], 2)
        self.assertEqual([event['event'] for event in events], ['deadline', 'ready'])
        self.assertEqual(events[0]['source'], 'bridge')
        self.assertEqual(requests[0], requests[1])

    def test_worker_408_and_other_bridge_failures_are_not_retried(self):
        for status, payload in [(200, self.envelope(status=408)), (408, {'error': {'code': 'OTHER'}}),
                                (503, {'error': {'code': 'SERVICE_CLOSED'}}), (302, self.envelope())]:
            with self.subTest(status=status, payload=payload):
                connection, requests = self.server([(status, payload)])
                with self.assertRaises(runner.VerificationError): runner.wait_for_worker_readiness(connection)
                self.assertEqual(len(requests), 1)

    def test_wrong_or_non_boolean_capabilities_fail_closed_without_retry(self):
        for change in [{'nativeAuthentication': False}, {'musicCatalog': 1}, {'musicPlayback': False},
                       {'personalSync': 'true'}, {'accountDeletion': True}, {'musicPurchases': True}]:
            with self.subTest(change=change):
                connection, requests = self.server([(200, self.envelope(flags=change))])
                with self.assertRaisesRegex(runner.VerificationError, 'capability mismatch'):
                    runner.wait_for_worker_readiness(connection)
                self.assertEqual(len(requests), 1)

    def test_malformed_oversized_or_invalid_base64_response_fails_without_retry(self):
        cases = [b'{', b' ' * 16_385, self.envelope() | {'bodyBase64': 'INVALID!'},
                 self.envelope() | {'status': True}, self.envelope() | {'headers': {}}]
        for payload in cases:
            with self.subTest(payload_type=type(payload).__name__):
                connection, requests = self.server([(200, payload)])
                with self.assertRaises(runner.VerificationError): runner.wait_for_worker_readiness(connection)
                self.assertEqual(len(requests), 1)

    def test_transport_timeout_then_ready_is_bounded(self):
        connection = {'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43}
        probe = Mock(side_effect=[runner.ReadinessTimeout('synthetic'), None])
        result = runner.wait_for_worker_readiness(connection, probe=probe, sleep=lambda seconds: None)
        self.assertEqual(result['attempts'], 2)
        self.assertEqual(probe.call_count, 2)
        self.assertTrue(all(0 < call.args[1] <= 5 for call in probe.call_args_list))

    def test_four_deadlines_exhaust_without_starting_any_operation(self):
        connection = {'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43}
        probe = Mock(side_effect=runner.ReadinessTimeout('synthetic')); events = []
        with self.assertRaisesRegex(runner.VerificationError, 'exhausted'):
            runner.wait_for_worker_readiness(connection, probe=probe, sleep=lambda seconds: None, record=events.append)
        self.assertEqual(probe.call_count, 4)
        self.assertEqual(events[-1]['event'], 'exhausted')

    def test_absolute_collection_deadline_rejects_late_success(self):
        connection = {'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43}; now = [0]
        def late(connection, timeout): now[0] = 21
        with self.assertRaisesRegex(runner.VerificationError, 'Late readiness'):
            runner.wait_for_worker_readiness(connection, probe=late, clock=lambda: now[0], sleep=lambda seconds: None)

    def test_header_and_body_share_absolute_deadline(self):
        connection, requests = self.server([(200, self.envelope(), .12, .12)])
        started = time.monotonic()
        with self.assertRaises(runner.ReadinessTimeout): runner.probe_worker_readiness(connection, .2)
        self.assertLess(time.monotonic() - started, .6)
        self.assertEqual(len(requests), 1)

    def test_drip_body_cannot_extend_deadline(self):
        connection, requests = self.server([(200, self.envelope(), 0, 0, .04)])
        started = time.monotonic()
        with self.assertRaises(runner.ReadinessTimeout): runner.probe_worker_readiness(connection, .2)
        self.assertLess(time.monotonic() - started, .6)
        self.assertEqual(len(requests), 1)

    def test_wrong_connection_or_unbounded_budgets_never_connect(self):
        connection = {'schemaVersion': 1, 'port': 49152, 'key': 'K' * 43}
        with patch.object(runner.http.client, 'HTTPConnection') as client:
            with self.assertRaises(runner.VerificationError): runner.probe_worker_readiness(connection | {'host': 'example.com'}, 5)
            for timeout in (0, -1, 6):
                with self.assertRaises(runner.VerificationError): runner.probe_worker_readiness(connection, timeout)
            for change in [{'total_timeout': 21}, {'max_attempts': 5}, {'max_attempts': True}]:
                with self.assertRaises(runner.VerificationError): runner.wait_for_worker_readiness(connection, **change)
            client.assert_not_called()


if __name__ == '__main__': unittest.main()
