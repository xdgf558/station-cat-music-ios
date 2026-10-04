#!/usr/bin/env python3
"""Fail-closed checks for the local production driver; no simulator/network required."""
import copy
import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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
                 'production-local-integration.log', 'production-local-service.log', 'production-local-runtime.jsonl')
        for name in names: (output / name).write_text('previous successful run')
        with patch.object(runner, 'ROOT', self.backend), patch.dict(runner.os.environ, {}, clear=True), patch('builtins.print'):
            with self.assertRaises(runner.VerificationError): runner.main()
        self.assertTrue(all(not (output / name).exists() for name in names))

    def test_failed_xctest_retains_runtime_and_original_log_with_matching_run_id(self):
        contracts = self.backend / 'contracts'; contracts.mkdir()
        (contracts / 'backend-production-fixture.json').write_text(json.dumps(self.manifest))
        products = self.backend / '.build/production-e2e/Build/Products'; products.mkdir(parents=True)
        source = {'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'StationCatMusicTests'}]}]}
        (products / 'StationCatMusic_fixture.xctestrun').write_bytes(plistlib.dumps(source))
        simulator = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
        inventory = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
            {'udid': simulator, 'isAvailable': True, 'name': 'iPhone synthetic'}]}}
        launches = []
        class Server:
            def terminate(self): pass
            def wait(self, timeout): return 0
        def launch(arguments, **options):
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
            if failed:
                options['stdout'].write('PRODUCTION_NATIVE_LOCAL_FAILED stage=capability_request category=fixture_response\n')
            return subprocess.CompletedProcess(arguments, 65 if failed else 0)
        with patch.object(runner, 'ROOT', self.backend), patch.object(runner, 'verify_backend', return_value=self.manifest['commit']), \
             patch.dict(runner.os.environ, {'PRODUCTION_BACKEND_PATH': str(self.backend), 'M1_SIMULATOR_ID': simulator}, clear=True), \
             patch.object(runner.subprocess, 'check_output', return_value=json.dumps(inventory)), \
             patch.object(runner.subprocess, 'run', side_effect=execute), patch.object(runner.subprocess, 'Popen', side_effect=launch), \
             patch('builtins.print'):
            with self.assertRaisesRegex(runner.VerificationError, 'production-local-integration.log'):
                runner.main()
        self.assertEqual(len(launches), 1)
        output = self.backend / 'evidence'; runtime = output / 'production-local-runtime.jsonl'
        diagnostic = json.loads(runtime.read_text())
        log = (output / 'production-local-integration.log').read_text()
        self.assertIn(diagnostic['runId'], log)
        self.assertIn('stage=capability_request category=fixture_response', log)
        self.assertEqual(runtime.stat().st_mode & 0o777, 0o600)
        self.assertFalse((output / 'production-local-summary.json').exists())
        self.assertFalse(list(products.glob('production-local-*.xctestrun')))


if __name__ == '__main__': unittest.main()
