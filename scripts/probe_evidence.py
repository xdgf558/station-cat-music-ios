"""Bounded, read-only post-recovery evidence collection; never replays a mutation."""
import io
import http.client
import threading
import json
import math
import re
import socket
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request
from urllib.parse import urlsplit

MAX_BYTES = 262_144


def validate_evidence(value, stage):
    """Reject wrong-stage, incomplete, revoked, duplicated or inconsistent evidence."""
    def require(condition):
        if not condition:
            raise ValueError('Invalid post-recovery evidence: ' + stage)
    def integer(value, expected):
        return type(value) is int and value == expected
    require(stage in ('A11', 'A12', 'A13') and isinstance(value, dict))
    require(value.get('stage') == stage and value.get('held') is (stage == 'A11'))
    requests = value.get('requests')
    require(isinstance(requests, list) and len(requests) == 2)
    generation = 2 if stage == 'A13' else 1
    session = value.get('session')
    require(isinstance(session, dict) and integer(session.get('generation'), generation) and integer(session.get('revoked'), 0))
    normalized = []
    for i, request in enumerate(requests):
        require(isinstance(request, dict))
        expected = 1 if stage == 'A13' and i == 1 else 0
        require(integer(request.get('status'), 200) and integer(request.get('generation'), expected)
                and integer(request.get('resultGeneration'), expected + 1))
        identifier = request.get('requestId')
        require(isinstance(identifier, str))
        try:
            uuid.UUID(identifier)
        except (ValueError, AttributeError):
            raise ValueError('Invalid evidence request ID') from None
        fingerprint = request.get('resultFingerprint')
        require(isinstance(fingerprint, str) and re.fullmatch('[0-9a-f]{64}', fingerprint) is not None)
        timestamp = request.get('committedAt')
        require(type(timestamp) in (int, float) and math.isfinite(timestamp) and timestamp > 0)
        normalized.append({key: request[key] for key in ('requestId', 'generation', 'status', 'resultFingerprint', 'resultGeneration', 'committedAt')})
    first, second = normalized
    interval = second['committedAt'] - first['committedAt']
    require(interval >= 0)
    if stage != 'A13':
        require(interval < 120_000 and first['requestId'] == second['requestId']
                and first['resultFingerprint'] == second['resultFingerprint'])
    else:
        require(first['requestId'] != second['requestId'])
    operations = value.get('operations')
    expected_operations = [{'request_id': first['requestId'], 'old_generation': 0}]
    if stage == 'A13':
        expected_operations.append({'request_id': second['requestId'], 'old_generation': 1})
    require(isinstance(operations, list) and len(operations) == generation)
    for actual, expected in zip(operations, expected_operations):
        require(isinstance(actual, dict) and actual.get('request_id') == expected['request_id']
                and integer(actual.get('old_generation'), expected['old_generation']))
    # Archive only known non-secret fields, even if the fixture later adds fields.
    return {'stage': stage, 'held': value['held'], 'requests': normalized,
            'session': {'generation': generation, 'revoked': 0}, 'operations': expected_operations}


def deadline_open(request, timeout):
    """Loopback-only GET with one deadline across connect, headers and body.

    The timer shuts down the socket, waking the blocked reader; no background
    reader survives a timeout. HTTPConnection redirects/proxies are not used.
    """
    url = urlsplit(request.full_url)
    if url.scheme != 'http' or url.hostname != '127.0.0.1' or url.path != '/fixture/evidence' or url.query or url.fragment or request.get_method() != 'GET':
        raise ValueError('Invalid evidence endpoint')
    deadline = time.monotonic() + timeout
    connection = http.client.HTTPConnection(url.hostname, url.port, timeout=timeout)
    expired = threading.Event()
    timer = None
    try:
        connection.connect()
        sock = connection.sock
        def interrupt():
            expired.set()
            try: sock.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        timer = threading.Timer(max(0, deadline - time.monotonic()), interrupt)
        timer.start()
        connection.request('GET', url.path, headers=dict(request.header_items()))
        response = connection.getresponse()
        payload = response.read(MAX_BYTES + 1)
        if expired.is_set() or time.monotonic() >= deadline:
            raise TimeoutError('Evidence request deadline exceeded')
        if response.status != 200:
            raise HTTPError(request.full_url, response.status, 'Evidence request failed', response.headers, io.BytesIO(payload))
        return io.BytesIO(payload)
    except (OSError, http.client.HTTPException):
        if expired.is_set() or time.monotonic() >= deadline:
            raise TimeoutError('Evidence request deadline exceeded') from None
        raise
    finally:
        if timer is not None:
            timer.cancel(); timer.join()
        connection.close()


def read_probe_evidence(connection, stage, *, total_timeout=20, request_timeout=5,
                        max_attempts=4, opener=deadline_open, clock=time.monotonic, sleep=time.sleep):
    """Retry transient GET failures only, after the recovered process has exited.

    This deadline bounds collection retries, not authentication or the server's
    unchanged 120-second replay deadline. Invalid evidence is never retried.
    """
    started = clock(); deadline = started + total_timeout; attempts = 0
    request = Request('http://127.0.0.1:' + str(connection['port']) + '/fixture/evidence',
                      headers={'X-Probe-Key': connection['key']}, method='GET')
    while attempts < max_attempts and clock() < deadline:
        attempts += 1
        try:
            with opener(request, timeout=min(request_timeout, deadline - clock())) as response:
                payload = response.read(MAX_BYTES + 1)
                if len(payload) > MAX_BYTES:
                    raise ValueError('Post-recovery evidence exceeds size limit')
                value = validate_evidence(json.loads(payload), stage)
            if clock() >= deadline:
                break  # Never accept a result arriving after the collection budget.
            return value, {'attempts': attempts, 'seconds': round(clock() - started, 3)}
        except HTTPError as error:
            retryable = error.code in (500, 502, 503, 504)
            if error.fp is not None:
                error.close()
            if not retryable:
                raise
        except (TimeoutError, socket.timeout, URLError, ConnectionError):
            pass
        remaining = deadline - clock()
        if attempts < max_attempts and remaining > 0:
            sleep(min(.25 * attempts, remaining))
    raise RuntimeError('Post-recovery evidence collection exhausted after ' + str(attempts)
                       + ' attempts; recovery was not rerun')


def read_failure_evidence(connection, stage, *, opener=deadline_open):
    """One bounded read after an already-failed probe; diagnostic, never acceptance.

    Keep only typed counts/statuses. Do not archive payloads, error text, IDs,
    fingerprints, response headers, URL errors or future unknown fixture fields.
    """
    result = {'diagnosticOnly': True, 'stage': stage}
    request = Request('http://127.0.0.1:' + str(connection['port']) + '/fixture/evidence',
                      headers={'X-Probe-Key': connection['key']}, method='GET')
    try:
        with opener(request, timeout=5) as response:
            payload = response.read(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES: raise ValueError()
            value = json.loads(payload)
        if not isinstance(value, dict) or value.get('stage') != stage: raise ValueError()
        requests, session, operations = value.get('requests'), value.get('session'), value.get('operations')
        if not isinstance(requests, list) or len(requests) > 10 or not isinstance(session, dict) or not isinstance(operations, list): raise ValueError()
        def number(record, key):
            v = record.get(key)
            if type(v) is not int or not -10000 <= v <= 10000: raise ValueError()
            return v
        rows = [{key: number(row, key) for key in ('generation', 'status', 'resultGeneration') if key in row} for row in requests if isinstance(row, dict)]
        if len(rows) != len(requests) or type(value.get('held')) is not bool: raise ValueError()
        result.update(readStatus='available', held=value['held'], requestCount=len(requests), requests=rows,
                      session={key: number(session, key) for key in ('generation', 'revoked')}, operationCount=len(operations))
    except HTTPError as error:
        result.update(readStatus='http_error', status=error.code)
        if error.fp is not None: error.close()
    except (TimeoutError, socket.timeout, URLError, ConnectionError, OSError, http.client.HTTPException):
        result['readStatus'] = 'transport_unavailable'
    except (ValueError, TypeError):
        result['readStatus'] = 'invalid_evidence'
    return result
