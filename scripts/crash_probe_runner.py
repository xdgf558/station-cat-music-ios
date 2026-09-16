"""Stop XCTest orchestration only after the marked simulator host actually exits."""
import os
import re
import signal
import subprocess
import time


def host_exited(pid):
    # Simulator processes share the host PID namespace; include zombies as exited.
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
    return result.returncode == 1 or (result.returncode == 0 and result.stdout.strip().startswith('Z'))


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def run_crash(args, logfile, stage, timeout=300):
    marker = re.compile(r'M2_BOUNDARY_REACHED:' + re.escape(stage) + r':durable-state-verified:pid=(\d+)')
    started = time.monotonic()
    observed = None
    with logfile.open('w') as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
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
                        return {'hostExitConfirmed': True, 'orchestratorStoppedAfterMarkerSeconds': round(time.monotonic() - observed, 3)}
                    if time.monotonic() - observed > 5:
                        raise RuntimeError('Marked simulator host did not exit')
                if process.poll() is not None:
                    raise RuntimeError('Crash runner ended without a confirmed host exit')
                time.sleep(.05)
            raise RuntimeError('Crash boundary timed out')
        finally:
            stop_group(process)
