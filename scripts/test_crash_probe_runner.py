"""Exercise orchestration without Xcode, credentials or network access."""
import sys
import tempfile
import time
import threading
import unittest
from pathlib import Path
from crash_probe_runner import run_crash,run_file_probe,stop_group,wait_ready
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

    def test_delayed_service_readiness_is_checked_before_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'ready.json';process=Mock();process.poll.return_value=None
            def ready():
                path.write_text('{')
                time.sleep(.15)
                path.write_text('{"port":12345}')
            thread=threading.Thread(target=ready);thread.start()
            try:self.assertEqual(wait_ready(path,process,2),{'port':12345})
            finally:thread.join()

    def test_service_exit_does_not_wait_for_readiness_timeout(self):
        process=Mock();process.poll.return_value=1
        with self.assertRaisesRegex(RuntimeError,'failed before readiness'):
            wait_ready(Path('/unused-ready'),process,.5)

    def test_missing_readiness_has_explicit_bounded_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            process=Mock();process.poll.return_value=None
            with self.assertRaisesRegex(RuntimeError,'before any refresh operation'):
                wait_ready(Path(directory)/'ready.json',process,.1)

    def test_wrong_stage_is_not_accepted(self):
        with self.assertRaisesRegex(RuntimeError,'without a confirmed host exit'):
            self.run_fixture("print('M2_BOUNDARY_REACHED:A12:durable-state-verified:pid=99999999');raise SystemExit(73)")

class FileProbeRunnerTests(unittest.TestCase):
    def fixture(self, lines, mode='CRASH', hold=0, timeout=3):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'unique-result.log'
            child=("import os,time,pathlib;time.sleep(.05);"
                   +"pathlib.Path("+repr(str(result))+").write_text("+repr('\n'.join(lines))+".replace('{pid}',str(os.getpid())));"
                   +"time.sleep("+str(hold)+");os._exit(73)")
            launch=("import subprocess,sys; p=subprocess.Popen([sys.executable,'-c',"+repr(child)+"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);"
                    +"print('org.stationcat.music.recoveryprobe: '+str(p.pid),flush=True)")
            return run_file_probe([sys.executable,'-u','-c',launch],Path(directory)/'launch.log',result,'A11',mode,timeout)
    def ready(self, mode='CRASH'): return 'M2_PROBE_STARTED:A11:'+mode+':pid={pid}'
    def boundary(self): return 'M2_BOUNDARY_REACHED:A11:durable-state-verified:pid={pid}'
    def recovered(self): return 'M2_BOUNDARY_RECOVERED:A11:generation=1:pid={pid}'
    def test_launcher_exit_before_child_marker_is_supported(self):
        value=self.fixture([self.ready(),self.boundary()])
        self.assertTrue(value['hostExitConfirmed']);self.assertGreater(value['hostPID'],1)
    def test_recovery_requires_boundary_finish_and_actual_exit(self):
        value=self.fixture([self.ready('RECOVER'),self.recovered(),'M2_PROBE_FINISHED:A11:RECOVER:pid={pid}'],mode='RECOVER')
        self.assertTrue(value['hostExitConfirmed'])
    def test_missing_marker_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError,'without expected durable boundary'): self.fixture([self.ready()])
    def test_wrong_stage_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError,'without expected durable boundary'): self.fixture([self.ready(),self.boundary().replace('A11','A12')])
    def test_wrong_host_pid_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'PID differs'): self.fixture([self.ready(),self.boundary().replace('{pid}','99999999')])
    def test_missing_startup_evidence_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'startup evidence'): self.fixture([self.boundary()])
    def test_failure_overrides_success_marker(self):
        with self.assertRaisesRegex(RuntimeError,'reported failure'): self.fixture([self.ready(),self.boundary(),'M2_PROBE_FAILED'])
    def test_recovery_without_final_cleanup_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'final cleanup'): self.fixture([self.ready('RECOVER'),self.recovered()],mode='RECOVER')
    def test_live_host_is_not_accepted(self):
        with self.assertRaisesRegex(RuntimeError,'timed out'): self.fixture([self.ready(),self.boundary()],hold=.6,timeout=.2)
    def test_final_record_racing_exit_check_is_reread(self):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'result'; log=Path(directory)/'launch'
            process=Mock();process.pid=222;process.poll.return_value=0
            ready=self.ready().replace('{pid}','333')
            boundary=self.boundary().replace('{pid}','333')
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                result.write_text(ready);return process
            def exited(pid):
                result.write_text(ready+'\n'+boundary);return True
            with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.host_exited',side_effect=exited):
                self.assertTrue(run_file_probe([],log,result,'A11','CRASH')['hostExitConfirmed'])

    def test_stale_result_is_rejected_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'result';result.write_text(self.boundary())
            with patch('crash_probe_runner.subprocess.Popen') as launch:
                with self.assertRaisesRegex(RuntimeError,'fresh'): run_file_probe([],Path(directory)/'launch',result,'A11','CRASH')
                launch.assert_not_called()

if __name__=='__main__':unittest.main(verbosity=2)
