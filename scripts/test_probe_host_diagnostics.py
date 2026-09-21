import json, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
from probe_host_diagnostics import collect, process_rows, stack_categories


class HostDiagnosticsTests(unittest.TestCase):
    def test_only_fixture_process_tree_and_fixed_names_are_retained(self):
        rows = process_rows('''10 1 0.2 0.1 S 31 0 /private/path/node
11 10 0.3 0.2 S 31 0 /private/path/workerd
12 1 8.0 1.0 R 31 0 /secret/unrelated/workerd
13 10 0.1 0.1 S 31 0 /private/secret-process
14 13 0.1 0.1 S 31 0 /private/workerd''', 10)
        self.assertEqual([r['pid'] for r in rows], [10, 11, 14])
        self.assertNotIn('private', json.dumps(rows))
        self.assertNotIn('secret', json.dumps(rows))

    def test_stack_report_never_persists_symbols_paths_or_headers(self):
        result = stack_categories('''Process: secret [123]
  + 30 fsync (in libsystem_kernel.dylib) /secret/path
  + 10 v8::internal::secretToken (in node) [0x123]
  + 20 kevent (in libsystem_kernel.dylib)
Authorization: secret
Environment: secret''')
        self.assertEqual(result['file_sync'], 1)
        self.assertEqual(result['javascript'], 1)
        self.assertEqual(result['event_wait'], 1)
        self.assertNotIn('secret', json.dumps(result))

    def test_diagnostic_failure_is_bounded_and_has_no_exception_details(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'result.json'
            with patch('probe_host_diagnostics.subprocess.run', side_effect=OSError('secret')):
                collect(10, path)
            result = json.loads(path.read_text())
            self.assertTrue(result['unavailable'])
            self.assertNotIn('secret', path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
