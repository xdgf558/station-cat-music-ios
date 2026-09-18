"""Bounded probe orchestration requiring durable evidence and actual host exit."""
import os
import json
import re
import signal
import subprocess
import time


def host_exited(pid):
    # Simulator processes share the host PID namespace; include zombies as exited.
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
    return result.returncode == 1 or (result.returncode == 0 and result.stdout.strip().startswith('Z'))


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
    observed = None
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
                    if host_exited(pid):
                        stop_group(process)
                        return {'hostExitConfirmed': True, 'crashedHostPID': pid, 'orchestratorStoppedAfterMarkerSeconds': round(time.monotonic() - observed, 3)}
                    if time.monotonic() - observed > 5:
                        raise RuntimeError('Marked simulator host did not exit')
                if process.poll() is not None:
                    raise RuntimeError('Crash runner ended without a confirmed host exit')
                time.sleep(.05)
            raise RuntimeError('Crash boundary timed out')
        finally:
            stop_group(process)


def run_file_probe(args, logfile, resultfile, stage, mode, timeout=300, env=None):
    """simctl exits after launch; trust unique durable app evidence + actual host exit.

    No auto-relaunch: once a refresh may have committed, the original operation and
    fixed replay deadline must be preserved. A missing or failed marker fails closed.
    """
    if resultfile.exists():
        raise RuntimeError('Probe result path must be fresh')
    if stage not in ('A11', 'A12', 'A13') or mode not in ('CRASH', 'RECOVER'):
        raise ValueError('Invalid probe stage or mode')
    started=time.monotonic(); observed=None; pid=None
    def read_result():
        try: return resultfile.read_text()
        except FileNotFoundError: return ''
    boundary = (r'M2_BOUNDARY_REACHED:'+stage+r':durable-state-verified:pid=(\d+)' if mode=='CRASH'
                else r'M2_BOUNDARY_RECOVERED:'+stage+r':[^\n]*:pid=(\d+)')
    with logfile.open('w') as log:
        process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,env=env)
        try:
            while time.monotonic()-started < timeout:
                launch=logfile.read_text(errors='replace')
                launched=re.search(r'^org\.stationcat\.music\.recoveryprobe: (\d+)$',launch,re.M)
                if launched:
                    pid=int(launched.group(1))
                    if pid<=1 or pid in (os.getpid(),process.pid): raise RuntimeError('Invalid simulator host PID')
                code=process.poll()
                if code is not None and code!=0: raise RuntimeError('Probe launch command failed')
                content=read_result()
                if 'M2_PROBE_FAILED' in content: raise RuntimeError('Probe reported failure; see durable evidence')
                match=re.search(boundary,content)
                if match and pid is not None:
                    if int(match.group(1))!=pid: raise RuntimeError('Probe evidence PID differs from launched host')
                    ready='M2_PROBE_STARTED:'+stage+':'+mode+':pid='+str(pid)
                    finished='M2_PROBE_FINISHED:'+stage+':RECOVER:pid='+str(pid)
                    if ready not in content: raise RuntimeError('Missing probe startup evidence')
                    if mode=='RECOVER' and finished not in content:
                        if host_exited(pid):
                            if read_result()!=content: continue
                            raise RuntimeError('Recovery exited before final cleanup evidence')
                    else:
                        if observed is None: observed=time.monotonic()
                        if host_exited(pid):
                            stop_group(process)
                            return {'hostExitConfirmed':True,'hostPID':pid,'evidenceTransport':'unique simulator-container file',
                                    'hostExitAfterMarkerSeconds':round(time.monotonic()-observed,3)}
                        if time.monotonic()-observed > 5: raise RuntimeError('Marked simulator host did not exit')
                elif pid is not None and host_exited(pid):
                    # The app can publish its final record between our read and ps.
                    if read_result()!=content: continue
                    raise RuntimeError('Probe host exited without expected durable boundary')
                if code is not None and pid is None:
                    if logfile.read_text(errors='replace')!=launch: continue
                    raise RuntimeError('Launch returned without a host PID')
                time.sleep(.05)
            raise RuntimeError('Probe boundary timed out; no automatic relaunch')
        finally:
            stop_group(process)


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
