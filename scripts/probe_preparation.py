"""One host-side setup mutation before a crash host starts; never retry it."""
import http.client
import json
import socket
import threading
import time


def prepare_stage(connection, stage, *, timeout=90):
    if stage not in ('A11', 'A12', 'A13') or not 0 < timeout <= 90:
        raise ValueError('Invalid preparation configuration')
    port = connection['port']
    if type(port) is not int or not 0 < port < 65536:
        raise ValueError('Invalid loopback port')
    started = time.monotonic()
    deadline = started + timeout
    client = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
    expired = threading.Event()
    timer = None
    response = None
    try:
        client.connect()
        sock = client.sock
        def interrupt():
            expired.set()
            try: sock.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        timer = threading.Timer(max(0, deadline - time.monotonic()), interrupt)
        timer.start()
        client.request('POST', '/fixture/prepare', json.dumps({'stage': stage}),
                       {'X-Probe-Key': connection['key'], 'Content-Type': 'application/json'})
        response = client.getresponse()
        payload = response.read(1025)
        if expired.is_set() or time.monotonic() >= deadline:
            raise TimeoutError('Preparation deadline exceeded; setup was not retried')
        if response.status != 200 or len(payload) > 1024:
            raise ValueError('Preparation failed; setup was not retried')
        receipt = json.loads(payload)
        if not isinstance(receipt, dict) or set(receipt) != {'stage', 'ready'} or receipt['stage'] != stage or receipt['ready'] is not True:
            raise ValueError('Invalid preparation receipt')
        # No credentials or arbitrary response fields are archived.
        return {'stage': stage, 'ready': True, 'attempts': 1,
                'seconds': round(time.monotonic() - started, 3), 'deadlineSeconds': timeout}
    except (OSError, http.client.HTTPException):
        if expired.is_set() or time.monotonic() >= deadline:
            raise TimeoutError('Preparation deadline exceeded; setup was not retried') from None
        raise
    finally:
        if timer is not None:
            timer.cancel(); timer.join()
        if response is not None:
            response.close()
        client.close()
