"""Failure-only macOS process diagnostics; never archive arguments or raw stacks."""
import json, os, re, subprocess, tempfile, time
from pathlib import Path


def process_rows(text, root_pid):
    rows = []
    for line in text.splitlines():
        parts = line.split(None, 7)
        if len(parts) != 8:
            continue
        try:
            pid, parent = int(parts[0]), int(parts[1])
            cpu, memory, priority, nice = float(parts[2]), float(parts[3]), int(parts[5]), int(parts[6])
        except ValueError:
            continue
        # comm is used only to classify the executable, never persisted.
        name = Path(parts[7]).name
        if not re.fullmatch(r'[A-Za-z+<>-]{1,8}', parts[4]):
            continue
        rows.append({'pid': pid, 'parent': parent, 'cpu': cpu, 'memory': memory,
                     'state': parts[4], 'priority': priority, 'nice': nice,
                     'kind': name if name in ('node', 'workerd') else 'other'})
    children = {root_pid}
    for _ in rows:
        children.update(row['pid'] for row in rows if row['parent'] in children)
    return [row for row in rows if row['pid'] in children and row['kind'] in ('node', 'workerd')][:4]


def stack_categories(text):
    # Only fixed categories and counts leave this function; no symbol, path or message.
    patterns = {
        'file_sync': r'\b(?:fsync|fcntl|F_FULLFSYNC)\b',
        'file_io': r'\b(?:write|writev|pwrite|read|pread|open|rename)\b',
        'event_wait': r'\b(?:kevent|kevent64|poll|select)\b',
        'mach_wait': r'\b(?:mach_msg|mach_msg2_trap|mach_msg_overwrite)\b',
        'lock_wait': r'(?:semaphore_wait|__ulock_wait|__psynch_mutexwait|pthread_cond_wait)',
        'process_wait': r'\b(?:wait4|waitpid)\b',
        'javascript': r'\bv8::',
        'worker': r'\bworkerd::',
    }
    # Sample call-tree frames have a count followed by a symbol and '(in ...)' image.
    frames = [line for line in text.splitlines() if re.match(r'^\s*[+|!: ]*\d+\s+.*\(in ', line)]
    return {name: sum(bool(re.search(pattern, line)) for line in frames)
            for name, pattern in patterns.items()}


def collect(root_pid, destination):
    started = time.monotonic()
    result = {'at': round(time.time() * 1000), 'processes': [], 'samples': []}
    try:
        ps = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,%cpu=,%mem=,state=,pri=,nice=,comm='],
                            capture_output=True, text=True, timeout=3)
        rows = process_rows(ps.stdout, root_pid)
        result['processes'] = rows
        with tempfile.TemporaryDirectory(prefix='probe-host-sample-') as directory:
            for row in rows[:2]:
                if time.monotonic() - started >= 9:
                    break
                path = Path(directory) / 'sample.txt'
                try:
                    call = subprocess.run(['/usr/bin/sample', str(row['pid']), '1', '10', '-file', str(path)],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                          timeout=min(4, 10 - (time.monotonic() - started)))
                    sample = {'pid': row['pid'], 'kind': row['kind'], 'status': call.returncode}
                    if path.exists() and path.stat().st_size <= 2 * 1024 * 1024:
                        sample['frames'] = stack_categories(path.read_text(errors='replace'))
                    result['samples'].append(sample)
                except (OSError, subprocess.TimeoutExpired):
                    result['samples'].append({'pid': row['pid'], 'kind': row['kind'], 'unavailable': True})
                finally:
                    path.unlink(missing_ok=True)
    except (OSError, subprocess.TimeoutExpired):
        result['unavailable'] = True
    result['seconds'] = round(time.monotonic() - started, 3)
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as file:
        json.dump(result, file, indent=2)
        file.write('\n')
