"""Exercise orchestration without Xcode, credentials or network access."""
import sys
import tempfile
import time
import threading
import unittest
import json
import subprocess
import os
from pathlib import Path
from crash_probe_runner import (ProbeTimeline,ProbeRunnerError,host_exited,reset_boundary_evidence,run_crash,
                                run_file_probe,run_file_probe_pair,stop_group,wait_ready)
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

    def test_six_second_recovery_cleanup_does_not_consume_exit_budget(self):
        # This clock controls driver scheduling only; no auth clock or replay
        # deadline is replaced. FINISHED appears after six seconds of cleanup.
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'result';log=Path(directory)/'launch';clock=[0.0]
            process=Mock();process.pid=222;process.poll.return_value=0
            content='M2_PROBE_STARTED:A11:RECOVER:pid=333\nM2_BOUNDARY_RECOVERED:A11:generation=1:pid=333\n'
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n');result.write_text(content)
                return process
            def sleep(_):
                if clock[0]==0:
                    clock[0]=6.0
                    result.write_text(content+'M2_PROBE_FINISHED:A11:RECOVER:pid=333\n')
                else: clock[0]+=.05
            with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.host_exited',side_effect=[False,False,True]), patch('crash_probe_runner.time.monotonic',side_effect=lambda:clock[0]), patch('crash_probe_runner.time.sleep',side_effect=sleep):
                value=run_file_probe([],log,result,'A11','RECOVER',timeout=30)
            self.assertGreaterEqual(clock[0],6)
            self.assertTrue(value['hostExitConfirmed'])
            self.assertLess(value['hostExitAfterMarkerSeconds'],1)

    def test_finished_recovery_still_has_five_second_exit_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'result';log=Path(directory)/'launch';clock=[0.0]
            process=Mock();process.pid=222;process.poll.return_value=0
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                result.write_text('M2_PROBE_STARTED:A11:RECOVER:pid=333\nM2_BOUNDARY_RECOVERED:A11:generation=1:pid=333\nM2_PROBE_FINISHED:A11:RECOVER:pid=333\n')
                return process
            def sleep(_):clock[0]+=2
            with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.host_exited',return_value=False), patch('crash_probe_runner.time.monotonic',side_effect=lambda:clock[0]), patch('crash_probe_runner.time.sleep',side_effect=sleep):
                with self.assertRaisesRegex(RuntimeError,'Marked simulator host did not exit'):
                    run_file_probe([],log,result,'A11','RECOVER',timeout=30)
            self.assertEqual(clock[0],6)

class DriverTimelineTests(unittest.TestCase):
    def test_success_records_phase_order_wall_and_monotonic_time(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);result=root/'result';log=root/'launch';trace=root/'driver.jsonl'
            process=Mock();process.pid=222;process.poll.return_value=0
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                result.write_text('M2_PROBE_STARTED:A11:CRASH:pid=333\nM2_BOUNDARY_REACHED:A11:durable-state-verified:pid=333\n')
                return process
            before=int(time.time()*1000)
            with ProbeTimeline(trace,'A11','CRASH') as timeline:
                with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.host_exited',return_value=True):
                    self.assertTrue(run_file_probe([],log,result,'A11','CRASH',timeline=timeline)['hostExitConfirmed'])
            rows=[json.loads(line) for line in trace.read_text().splitlines()]
            self.assertEqual([r['event'] for r in rows],['prepared','launch_begin','launch_returned','pid_observed','startup_observed','boundary_observed','host_exit_confirmed','launcher_stop_begin','launcher_stop_done'])
            self.assertEqual([r['elapsedMs'] for r in rows], sorted(r['elapsedMs'] for r in rows))
            self.assertTrue(all(before<=r['at']<=int(time.time()*1000) for r in rows))
            self.assertEqual(trace.stat().st_mode & 0o777,0o600)

    def test_launch_failure_records_only_allowlisted_category(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);trace=root/'driver.jsonl'
            with ProbeTimeline(trace,'A11','RECOVER') as timeline:
                with patch('crash_probe_runner.subprocess.Popen',side_effect=OSError('secret-token-do-not-log')):
                    with self.assertRaises(OSError):
                        run_file_probe(['secret-token-do-not-log'],root/'launch',root/'result','A11','RECOVER',env={'PROOF':'secret-token-do-not-log'},timeline=timeline)
            text=trace.read_text();rows=[json.loads(line) for line in text.splitlines()]
            self.assertEqual(rows[-1]['event'],'failed');self.assertEqual(rows[-1]['category'],'io_error')
            self.assertNotIn('secret',text);self.assertNotIn('PROOF',text)

    def test_result_failure_retains_last_phase_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);result=root/'result';log=root/'launch';trace=root/'driver.jsonl'
            process=Mock();process.pid=222;process.poll.return_value=0
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                result.write_text('M2_PROBE_STARTED:A12:RECOVER:pid=333\nM2_PROBE_FAILED:pid=333\n')
                return process
            with ProbeTimeline(trace,'A12','RECOVER') as timeline:
                with patch('crash_probe_runner.subprocess.Popen',side_effect=launch):
                    with self.assertRaisesRegex(RuntimeError,'reported failure'):
                        run_file_probe([],log,result,'A12','RECOVER',timeline=timeline)
            rows=[json.loads(line) for line in trace.read_text().splitlines()]
            self.assertEqual([r['event'] for r in rows][-4:],['startup_observed','failed','launcher_stop_begin','launcher_stop_done'])
            self.assertEqual(rows[-3]['category'],'probe_failed')

    def test_rejects_untrusted_event_and_category(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'trace'
            with ProbeTimeline(path,'A11','CRASH') as timeline:
                with self.assertRaises(ValueError):timeline.record('https://secret.invalid')
                with self.assertRaises(ValueError):timeline.record('failed',category='token=secret')
            self.assertNotIn('secret',path.read_text())

    def test_existing_timeline_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'trace';path.write_text('old')
            with self.assertRaises(FileExistsError):ProbeTimeline(path,'A11','CRASH')
            self.assertEqual(path.read_text(),'old')

    def test_diagnostic_failure_always_cleans_launcher_and_fails_closed(self):
        for failing_event in ('launch_returned','launcher_stop_begin','launcher_stop_done'):
            with self.subTest(event=failing_event), tempfile.TemporaryDirectory() as directory:
                result=Path(directory)/'result';log=Path(directory)/'launch'
                process=Mock();process.pid=222;process.poll.return_value=0
                def launch(*args,**kwargs):
                    log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                    result.write_text('M2_PROBE_STARTED:A11:CRASH:pid=333\nM2_BOUNDARY_REACHED:A11:durable-state-verified:pid=333\n')
                    return process
                def record(event,**kwargs):
                    if event==failing_event:raise OSError('diagnostic disk error')
                timeline=Mock();timeline.record.side_effect=record
                with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.host_exited',return_value=True), patch('crash_probe_runner.stop_group') as stop:
                    with self.assertRaisesRegex(OSError,'diagnostic disk error'):
                        run_file_probe([],log,result,'A11','CRASH',timeline=timeline)
                    stop.assert_called_once_with(process)

    def test_failed_diagnostics_preserve_original_probe_error_and_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'result';log=Path(directory)/'launch'
            process=Mock();process.pid=222;process.poll.return_value=0
            def launch(*args,**kwargs):
                log.write_text('org.stationcat.music.recoveryprobe: 333\n')
                result.write_text('M2_PROBE_STARTED:A11:CRASH:pid=333\nM2_PROBE_FAILED:pid=333\n')
                return process
            def record(event,**kwargs):
                if event in ('failed','launcher_stop_begin','launcher_stop_done'):raise OSError('secondary disk error')
            timeline=Mock();timeline.record.side_effect=record
            with patch('crash_probe_runner.subprocess.Popen',side_effect=launch), patch('crash_probe_runner.stop_group') as stop:
                with self.assertRaisesRegex(ProbeRunnerError,'Probe reported failure'):
                    run_file_probe([],log,result,'A11','CRASH',timeline=timeline)
                stop.assert_called_once_with(process)

class BoundaryEvidenceResetTests(unittest.TestCase):
    def test_only_known_boundary_artifacts_are_invalidated(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);output=root/'evidence';output.mkdir()
            stale=['M2-boundaries-summary.json','M2-boundaries-build.log',
                   'M2-boundary-A11-CRASH.log','M2-boundary-A12-RECOVER-durable.log',
                   'M2-boundary-A13-RECOVER-write-timing.log','M2-boundary-A12-preparation.json',
                   'M2-boundary-A13-server-evidence.json','M2-fixture-diagnostics.jsonl',
                   'M2-runtime-diagnostics.jsonl','M2-last-committed-evidence.json']
            keep=['M2-other-summary.json','M3-media.log','M2-boundary-not-owned.log','M2-boundaries-not-owned.log']
            for name in stale+keep:(output/name).write_text('old')
            outside=root/'outside';outside.write_text('keep')
            (output/'M2-boundary-A11-CRASH-driver.jsonl').symlink_to(outside)
            reset_boundary_evidence(output)
            self.assertTrue(all(not (output/name).exists() for name in stale))
            self.assertEqual(sorted(p.name for p in output.iterdir()),sorted(keep))
            self.assertEqual(outside.read_text(),'keep')

    def test_known_directory_is_not_recursively_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory);owned=output/'M2-boundaries-summary.json';owned.mkdir()
            (owned/'user.txt').write_text('keep')
            with self.assertRaisesRegex(RuntimeError,'not a file'):reset_boundary_evidence(output)
            self.assertEqual((owned/'user.txt').read_text(),'keep')

    def test_driver_invalidates_evidence_before_pin_or_toolchain_failure(self):
        source=(Path(__file__).with_name('verify_native_crash_boundaries.py')).read_text()
        for failure in ('pin','toolchain'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root=Path(directory);(root/'scripts').mkdir();(root/'contracts').mkdir();output=root/'evidence';output.mkdir()
                (root/'contracts'/'backend-recovery-fixture.json').write_text(json.dumps({'commit':'expected','sha256':{}}))
                stale=output/'M2-boundaries-summary.json';stale.write_text('old success')
                keep=output/'M2-other-summary.json';keep.write_text('unrelated')
                cwd=Path.cwd()
                try:
                    with patch.dict(os.environ,{'M2_BACKEND_PATH':str(root),'M2_VERIFY_FIXTURE_ONLY':'0'}), patch('subprocess.check_output',side_effect=['wrong'] if failure=='pin' else ['expected','']), patch('subprocess.run',side_effect=subprocess.CalledProcessError(1,['check_toolchain'])) as run:
                        with self.assertRaises(AssertionError if failure=='pin' else subprocess.CalledProcessError):
                            exec(compile(source,'verify_native_crash_boundaries.py','exec'),{'__file__':str(root/'scripts'/'verify_native_crash_boundaries.py'),'__name__':'__main__'})
                        if failure=='pin':run.assert_not_called()
                        else:run.assert_called_once()
                finally:os.chdir(cwd)
                self.assertFalse(stale.exists());self.assertEqual(keep.read_text(),'unrelated')

class HostExitTests(unittest.TestCase):
    def test_ps_timeout_is_bounded_and_never_counts_as_exit(self):
        with patch('crash_probe_runner.subprocess.run',side_effect=subprocess.TimeoutExpired('ps',2)) as run:
            with self.assertRaisesRegex(ProbeRunnerError,'exit check timed out'):host_exited(333)
            self.assertEqual(run.call_args.kwargs['timeout'],2)
    def test_ps_error_and_empty_success_fail_closed(self):
        for code,output in [(2,''),(0,'')]:
            with patch('crash_probe_runner.subprocess.run',return_value=Mock(returncode=code,stdout=output)):
                with self.assertRaisesRegex(ProbeRunnerError,'exit check failed'):host_exited(333)
    def test_absent_and_zombie_are_exited_but_live_is_not(self):
        for code,output,expected in [(1,'',True),(0,'Z',True),(0,'S<',False)]:
            with patch('crash_probe_runner.subprocess.run',return_value=Mock(returncode=code,stdout=output)):
                self.assertEqual(host_exited(333),expected)

class ProbePairTests(unittest.TestCase):
    def plans(self):
        return [{'stage':'A11','mode':mode} for mode in ['CRASH','RECOVER']]

    def test_slow_archival_occurs_only_after_recovery_finishes(self):
        order=[];recovered=threading.Event()
        def runner(**plan):
            order.append('run_'+plan['mode'])
            if plan['mode']=='RECOVER':recovered.set()
            return {'hostPID':333 if plan['mode']=='CRASH' else 444}
        def archive(plan):
            self.assertTrue(recovered.is_set(),'Archive blocked recovery launch')
            time.sleep(.02);order.append('archive_'+plan['mode'])
        run_file_probe_pair(self.plans(),archive=archive,runner=runner)
        self.assertEqual(order,['run_CRASH','run_RECOVER','archive_CRASH','archive_RECOVER'])

    def test_recovery_failure_is_not_retried_and_both_logs_archive(self):
        calls=[];archived=[];failures=[]
        def runner(**plan):
            calls.append(plan['mode'])
            if plan['mode']=='RECOVER':raise RuntimeError('original failure')
            return {'hostPID':333}
        with self.assertRaisesRegex(RuntimeError,'original failure'):
            run_file_probe_pair(self.plans(),archive=lambda p:archived.append(p['mode']),on_failure=lambda p:failures.append(p['mode']),runner=runner)
        self.assertEqual(calls,['CRASH','RECOVER']);self.assertEqual(archived,['CRASH','RECOVER']);self.assertEqual(failures,['RECOVER'])

    def test_crash_failure_never_launches_recovery(self):
        calls=[]
        def runner(**plan):calls.append(plan['mode']);raise RuntimeError('crash failed')
        with self.assertRaisesRegex(RuntimeError,'crash failed'):
            run_file_probe_pair(self.plans(),archive=lambda p:None,runner=runner)
        self.assertEqual(calls,['CRASH'])

    def test_identical_pids_remain_a_failure(self):
        with self.assertRaisesRegex(RuntimeError,'new process'):
            run_file_probe_pair(self.plans(),archive=lambda p:None,runner=lambda **p:{'hostPID':333})

    def test_diagnostic_and_archive_errors_do_not_replace_original_failure(self):
        def fail(*args,**kwargs):raise RuntimeError('diagnostic error')
        def runner(**plan):raise RuntimeError('original failure')
        with self.assertRaisesRegex(RuntimeError,'original failure'):
            run_file_probe_pair(self.plans(),archive=fail,on_failure=fail,runner=runner)

    def test_archive_failure_still_attempts_both_logs_and_fails_successful_pair(self):
        archived=[]
        def archive(plan):
            archived.append(plan['mode']);raise RuntimeError('archive failed')
        with self.assertRaisesRegex(RuntimeError,'archive failed'):
            run_file_probe_pair(self.plans(),archive=archive,runner=lambda **p:{'hostPID':333 if p['mode']=='CRASH' else 444})
        self.assertEqual(archived,['CRASH','RECOVER'])

if __name__=='__main__':unittest.main(verbosity=2)
