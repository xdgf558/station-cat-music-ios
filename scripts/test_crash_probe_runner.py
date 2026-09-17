"""Exercise orchestration without Xcode, credentials or network access."""
import sys
import tempfile
import time
import unittest
from pathlib import Path
from crash_probe_runner import run_crash,stop_group
from unittest.mock import Mock,patch

class CrashRunnerTests(unittest.TestCase):
    def run_fixture(self, source, timeout=5):
        with tempfile.TemporaryDirectory() as directory:
            return run_crash([sys.executable, '-u', '-c', source], Path(directory)/'probe.log', 'A11', timeout)

    def test_stops_long_xctest_teardown_after_actual_child_exit(self):
        start=time.monotonic()
        result=self.run_fixture('''import subprocess,sys,time
p=subprocess.Popen([sys.executable,'-c','import time,os;time.sleep(.2);os._exit(73)'])
print('M2_BOUNDARY_REACHED:A11:durable-state-verified:pid='+str(p.pid),flush=True)
p.wait()
time.sleep(60)
''')
        self.assertTrue(result['hostExitConfirmed'])
        self.assertLess(time.monotonic()-start,5)

    def test_marker_does_not_suffice_while_host_is_alive(self):
        with self.assertRaisesRegex(RuntimeError,'timed out'):
            self.run_fixture('''import subprocess,sys,time
p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'])
print('M2_BOUNDARY_REACHED:A11:durable-state-verified:pid='+str(p.pid),flush=True)
time.sleep(60)
''',timeout=.4)

    def test_unexpected_failure_is_not_accepted(self):
        with self.assertRaisesRegex(RuntimeError,'without a confirmed host exit'):
            self.run_fixture("print('unrelated failure');raise SystemExit(73)")

    def test_already_exited_launcher_is_not_signalled(self):
        process=Mock();process.poll.return_value=0
        with patch('crash_probe_runner.os.killpg') as kill:
            stop_group(process)
            kill.assert_not_called()

    def test_launcher_exit_race_does_not_fail_on_group_permission(self):
        process=Mock();process.poll.side_effect=[None,0]
        with patch('crash_probe_runner.os.killpg',side_effect=PermissionError):
            stop_group(process)
        process.terminate.assert_not_called()
        process.wait.assert_called_once()

    def test_wrong_stage_is_not_accepted(self):
        with self.assertRaisesRegex(RuntimeError,'without a confirmed host exit'):
            self.run_fixture("print('M2_BOUNDARY_REACHED:A12:durable-state-verified:pid=99999999');raise SystemExit(73)")

if __name__=='__main__':unittest.main(verbosity=2)
