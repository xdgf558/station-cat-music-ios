"""Bounded probe orchestration requiring durable evidence and actual host exit."""
import os
import json
import re
import signal
import subprocess
import time
import errno
import select
import sys
from pathlib import Path
from contextlib import nullcontext


class ProbeRunnerError(RuntimeError):
    def __init__(self, category, message):
        super().__init__(message)
        self.category = category


class ProbeTimeline:
    """Small allowlisted driver timestamps, opened before either host is launched.

    Never accepts command arguments, environment values, response data or exception
    messages. The file remains useful when a launcher or process check stalls.
    """
    EVENTS = frozenset(('prepared', 'launch_begin', 'launch_returned', 'pid_observed',
                        'startup_observed', 'boundary_observed', 'host_exit_confirmed',
                        'launcher_stop_begin', 'launcher_stop_done', 'failed'))
    CATEGORIES = frozenset(('host_exit_check_timeout', 'host_exit_check_failed',
                           'invalid_host_pid', 'launch_failed', 'probe_failed',
                           'evidence_pid_mismatch', 'startup_missing', 'cleanup_missing',
                           'host_did_not_exit', 'boundary_missing', 'launch_pid_missing',
                           'boundary_timeout', 'io_error', 'process_timeout', 'unexpected'))

    def __init__(self, path, stage, mode):
        if stage not in ('A11', 'A12', 'A13') or mode not in ('CRASH', 'RECOVER'):
            raise ValueError('Invalid timeline stage or mode')
        self.stage, self.mode = stage, mode
        self.started = time.monotonic()
        self.fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        self.entries = []
        try: self.record('prepared')
        except Exception:
            os.close(self.fd)
            raise

    def record(self, event, *, pid=None, category=None):
        if event not in self.EVENTS or (category is not None and category not in self.CATEGORIES):
            raise ValueError('Invalid driver diagnostic')
        if pid is not None and (type(pid) is not int or pid <= 1):
            raise ValueError('Invalid driver diagnostic PID')
        if len(self.entries) >= 20:
            raise RuntimeError('Driver diagnostic budget exceeded')
        entry = {'event': event, 'stage': self.stage, 'mode': self.mode,
                 'at': int(time.time() * 1000),
                 'elapsedMs': round((time.monotonic() - self.started) * 1000)}
        if pid is not None: entry['hostPID'] = pid
        if category is not None: entry['category'] = category
        payload = (json.dumps(entry, separators=(',', ':')) + '\n').encode()
        # One bounded local write; deliberately no fsync on the replay-critical path.
        if os.write(self.fd, payload) != len(payload):
            raise OSError('Incomplete driver diagnostic write')
        self.entries.append(entry)

    def __enter__(self): return self
    def __exit__(self, *_): os.close(self.fd)


def failure_category(error):
    if isinstance(error, ProbeRunnerError): return error.category
    if isinstance(error, subprocess.TimeoutExpired): return 'process_timeout'
    if isinstance(error, OSError): return 'io_error'
    return 'unexpected'


def reset_boundary_evidence(output):
    """Invalidate this driver's exact artifact set before checking pins/toolchain.

    Other M2 evidence and unknown files are untouched. Never recurse or follow a
    symlink while removing a stale artifact.
    """
    names = {'M2-boundaries-summary.json', 'M2-fixture-diagnostics.jsonl',
             'M2-runtime-diagnostics.jsonl', 'M2-last-committed-evidence.json'}
    names.update('M2-boundaries-'+step+'.log' for step in
                 ('build', 'sign', 'boot', 'bootstatus', 'install', 'uninstall', 'service'))
    for stage in ('A11', 'A12', 'A13'):
        prefix='M2-boundary-'+stage
        names.update((prefix+'-preparation.json', prefix+'-server-evidence.json'))
        for mode in ('CRASH', 'RECOVER'):
            stem=prefix+'-'+mode
            names.update(stem+suffix for suffix in
                         ('.log', '-durable.log', '-write-timing.log', '-driver.jsonl',
                          '-host.json', '-failure-state.json'))
    output.mkdir(exist_ok=True)
    for name in sorted(names):
        path=output/name
        if path.is_symlink() or path.is_file(): path.unlink()
        elif path.exists(): raise RuntimeError('Boundary artifact path is not a file')


class ProcessExitWatcher:
    """Observe one PID without spawning a process on every polling iteration.

    macOS uses a persistent, nonblocking EVFILT_PROC/NOTE_EXIT subscription.
    Linux contract tests read the kernel's bounded /proc stat record. There is no
    permission-error fallback; unknown results fail closed. The caller retains
    the scenario deadline and its unchanged five-second post-marker exit budget.
    """
    def __init__(self, pid, *, system=None, kernel=None, proc_root=Path('/proc')):
        if type(pid) is not int or pid <= 1:
            raise ProbeRunnerError('invalid_host_pid', 'Invalid simulator host PID')
        self.pid=pid;self.system=system or sys.platform;self.kernel=kernel or select
        self.proc_root=proc_root;self.queue=None;self.registered=False
        self.confirmation=None;self.closed=False

    def exited(self):
        if self.closed:raise ProbeRunnerError('host_exit_check_failed', 'Exit watcher is closed')
        if self.confirmation is not None:return True
        if self.system=='darwin':return self._darwin_exited()
        if self.system.startswith('linux'):return self._linux_exited()
        raise ProbeRunnerError('host_exit_check_failed', 'Unsupported host exit observer')

    def _darwin_exited(self):
        registering=not self.registered
        try:
            if self.queue is None:self.queue=self.kernel.kqueue()
            changes=([self.kernel.kevent(self.pid,filter=self.kernel.KQ_FILTER_PROC,
                      flags=self.kernel.KQ_EV_ADD|self.kernel.KQ_EV_ONESHOT,
                      fflags=self.kernel.KQ_NOTE_EXIT)] if registering else None)
            events=self.queue.control(changes,1,0)
            self.registered=True
        except OSError as error:
            # ESRCH is an authoritative missing PID only while attaching its
            # process filter; no other error can substitute for NOTE_EXIT.
            if registering and self.queue is not None and error.errno==errno.ESRCH:
                self.confirmation='kqueue-esrch';return True
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel exit observation failed') from None
        if not events:return False
        if len(events)!=1:raise ProbeRunnerError('host_exit_check_failed', 'Unexpected kernel exit events')
        event=events[0]
        if event.ident!=self.pid or event.filter!=self.kernel.KQ_FILTER_PROC:
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel exit event identity differs')
        if event.flags & self.kernel.KQ_EV_ERROR:
            if registering and event.data==errno.ESRCH:
                self.confirmation='kqueue-esrch';return True
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel rejected exit observation')
        if not event.fflags & self.kernel.KQ_NOTE_EXIT:
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel event does not confirm exit')
        self.confirmation='kqueue-note-exit';return True

    def _linux_exited(self):
        if not self.proc_root.is_dir():
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel process directory unavailable')
        try:
            with (self.proc_root/str(self.pid)/'stat').open('rb') as source:data=source.read(4097)
        except FileNotFoundError:
            if (self.proc_root/str(self.pid)).exists():
                raise ProbeRunnerError('host_exit_check_failed', 'Kernel process state unavailable') from None
            self.confirmation='proc-missing';return True
        except OSError:
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel process state unavailable') from None
        prefix=(str(self.pid)+' (').encode()
        _,separator,fields=data.rpartition(b') ')
        parts=fields.split()
        if len(data)>4096 or not data.startswith(prefix) or not separator or not parts or parts[0] not in (b'R',b'S',b'D',b'Z',b'T',b't',b'X',b'x',b'K',b'W',b'P',b'I'):
            raise ProbeRunnerError('host_exit_check_failed', 'Kernel process state is invalid')
        if parts[0] in (b'Z',b'X',b'x'):
            self.confirmation='proc-exited';return True
        return False

    def close(self):
        if not self.closed:
            self.closed=True
            if self.queue is not None:self.queue.close()

    def __enter__(self):return self
    def __exit__(self,*_):self.close()


def host_exited(pid, watcher=None):
    if watcher is not None:
        if watcher.pid!=pid:raise ProbeRunnerError('host_exit_check_failed', 'Exit watcher PID differs')
        return watcher.exited()
    with ProcessExitWatcher(pid) as observer:return observer.exited()


def stop_group(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    except PermissionError:
        # simctl may already have exited, or its group may contain protected helpers.
        # Signal only our own still-running child; never escalate or kill simulator services.
        if process.poll() is None:
            process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def run_crash(args, logfile, stage, timeout=300, env=None):
    marker = re.compile(r'M2_BOUNDARY_REACHED:' + re.escape(stage) + r':durable-state-verified:pid=(\d+)')
    started = time.monotonic()
    observed = None;watcher=None
    with logfile.open('w') as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=env)
        try:
            while time.monotonic() - started < timeout:
                match = marker.search(logfile.read_text(errors='replace'))
                if match:
                    if observed is None:
                        observed = time.monotonic()
                    pid = int(match.group(1))
                    if pid <= 1 or pid in (os.getpid(), process.pid):
                        raise RuntimeError('Invalid simulator host PID')
                    if watcher is None:watcher=ProcessExitWatcher(pid)
                    if host_exited(pid,watcher):
                        stop_group(process)
                        return {'hostExitConfirmed': True, 'crashedHostPID': pid, 'orchestratorStoppedAfterMarkerSeconds': round(time.monotonic() - observed, 3)}
                    if time.monotonic() - observed > 5:
                        raise RuntimeError('Marked simulator host did not exit')
                if process.poll() is not None:
                    raise RuntimeError('Crash runner ended without a confirmed host exit')
                time.sleep(.05)
            raise RuntimeError('Crash boundary timed out')
        finally:
            try:stop_group(process)
            finally:
                if watcher is not None:watcher.close()


def run_file_probe(args, logfile, resultfile, stage, mode, timeout=300, env=None,
                   timeline=None, launch_log=None):
    """simctl exits after launch; trust unique durable app evidence + actual host exit.

    No auto-relaunch: once a refresh may have committed, the original operation and
    fixed replay deadline must be preserved. A missing or failed marker fails closed.
    """
    if resultfile.exists():
        raise RuntimeError('Probe result path must be fresh')
    if stage not in ('A11', 'A12', 'A13') or mode not in ('CRASH', 'RECOVER'):
        raise ValueError('Invalid probe stage or mode')
    started=time.monotonic(); boundary_observed=None; exit_wait_started=None
    pid=None; startup_observed=False; failure=None; process=None;watcher=None
    def record(event, **fields):
        if timeline is not None: timeline.record(event, **fields)
    def fail(category, message): raise ProbeRunnerError(category, message)
    def read_result():
        try: return resultfile.read_text()
        except FileNotFoundError: return ''
    boundary = (r'M2_BOUNDARY_REACHED:'+stage+r':durable-state-verified:pid=(\d+)' if mode=='CRASH'
                else r'M2_BOUNDARY_RECOVERED:'+stage+r':[^\n]*:pid=(\d+)')
    with (nullcontext(launch_log) if launch_log is not None else logfile.open('w')) as log:
        try:
            record('launch_begin')
            process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,env=env)
            record('launch_returned')
            while time.monotonic()-started < timeout:
                launch=logfile.read_text(errors='replace')
                launched=re.search(r'^org\.stationcat\.music\.recoveryprobe: (\d+)$',launch,re.M)
                if launched:
                    candidate=int(launched.group(1))
                    if candidate<=1 or candidate in (os.getpid(),process.pid): fail('invalid_host_pid', 'Invalid simulator host PID')
                    if pid is None:
                        pid=candidate;watcher=ProcessExitWatcher(pid);record('pid_observed', pid=pid)
                    elif pid != candidate: fail('evidence_pid_mismatch', 'Probe launch PID changed')
                code=process.poll()
                if code is not None and code!=0: fail('launch_failed', 'Probe launch command failed')
                content=read_result()
                if pid is not None and not startup_observed and 'M2_PROBE_STARTED:'+stage+':'+mode+':pid='+str(pid) in content:
                    startup_observed=True; record('startup_observed', pid=pid)
                if 'M2_PROBE_FAILED' in content: fail('probe_failed', 'Probe reported failure; see durable evidence')
                match=re.search(boundary,content)
                if match and pid is not None:
                    if int(match.group(1))!=pid: fail('evidence_pid_mismatch', 'Probe evidence PID differs from launched host')
                    ready='M2_PROBE_STARTED:'+stage+':'+mode+':pid='+str(pid)
                    finished='M2_PROBE_FINISHED:'+stage+':RECOVER:pid='+str(pid)
                    if ready not in content: fail('startup_missing', 'Missing probe startup evidence')
                    if boundary_observed is None:
                        boundary_observed=time.monotonic(); record('boundary_observed', pid=pid)
                    if mode=='RECOVER' and finished not in content:
                        if host_exited(pid,watcher):
                            if read_result()!=content: continue
                            fail('cleanup_missing', 'Recovery exited before final cleanup evidence')
                    else:
                        # RECOVER may still be cleaning Keychain after its boundary.
                        # Its five-second exit budget starts only after FINISHED.
                        if exit_wait_started is None: exit_wait_started=time.monotonic()
                        if host_exited(pid,watcher):
                            record('host_exit_confirmed', pid=pid)
                            return {'hostExitConfirmed':True,'hostPID':pid,'evidenceTransport':'unique simulator-container file',
                                    'hostExitAfterMarkerSeconds':round(time.monotonic()-exit_wait_started,3),
                                    'hostExitObservation':watcher.confirmation}
                        if time.monotonic()-exit_wait_started > 5: fail('host_did_not_exit', 'Marked simulator host did not exit')
                elif pid is not None and host_exited(pid,watcher):
                    # The app can publish its final record between our read and ps.
                    if read_result()!=content: continue
                    fail('boundary_missing', 'Probe host exited without expected durable boundary')
                if code is not None and pid is None:
                    if logfile.read_text(errors='replace')!=launch: continue
                    fail('launch_pid_missing', 'Launch returned without a host PID')
                time.sleep(.05)
            fail('boundary_timeout', 'Probe boundary timed out; no automatic relaunch')
        except BaseException as error:
            failure=error
            try: record('failed', category=failure_category(error))
            except Exception: pass  # Keep the triggering failure if diagnostics also fail.
            raise
        finally:
            if process is not None:
                cleanup_failure=None
                try: record('launcher_stop_begin')
                except Exception as error: cleanup_failure=error
                # A diagnostic write must never prevent cleanup of our launcher.
                try: stop_group(process)
                except Exception as error:
                    if cleanup_failure is None: cleanup_failure=error
                else:
                    try: record('launcher_stop_done')
                    except Exception as error:
                        if cleanup_failure is None: cleanup_failure=error
                if watcher is not None:
                    try:watcher.close()
                    except Exception as error:
                        if cleanup_failure is None:cleanup_failure=error
                if cleanup_failure is not None:
                    try: record('failed', category=failure_category(cleanup_failure))
                    except Exception: pass
                    if failure is None: raise cleanup_failure


def run_file_probe_pair(plans, *, archive, on_failure=None, runner=run_file_probe):
    """Launch recovery once, before optional copying, unlinking or CI stdout.

    Callers prepare BOTH environments, log handles and timeline handles in advance.
    Archival is attempted for both hosts after recovery succeeds or the pair fails.
    """
    if len(plans) != 2 or [p['mode'] for p in plans] != ['CRASH', 'RECOVER'] or plans[0]['stage'] != plans[1]['stage']:
        raise ValueError('Invalid probe pair')
    failure=None; results=[]
    try:
        for plan in plans:
            value=runner(**plan); results.append(value)
        if results[0]['hostPID'] == results[1]['hostPID']:
            raise ProbeRunnerError('evidence_pid_mismatch', 'Recovery must use a new process')
        return results
    except Exception as error:
        failure=error
        if on_failure is not None:
            try: on_failure(plan)
            except Exception: pass  # Diagnostics must not replace the original failure.
        raise
    finally:
        archive_failure=None
        for plan in plans:
            try: archive(plan)
            except Exception as error:
                if archive_failure is None: archive_failure=error
        if failure is None and archive_failure is not None: raise archive_failure


def wait_ready(path, process, timeout=120):
    """Wait before creating any credentials; this is not part of the replay deadline."""
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if process.poll() is not None:
            raise RuntimeError('Local service failed before readiness')
        try:
            return json.loads(path.read_text())
        except (FileNotFoundError,json.JSONDecodeError):
            time.sleep(.1)
    raise RuntimeError('Local service readiness timed out before any refresh operation')
