#!/usr/bin/env python3
"""Which statement is the one a breakpoint cannot stop on?

`setBreakpoints` answers `lines: [1]` for boom.bas and the program then runs to
completion. Is that line ONE, or the FIRST EXECUTED STATEMENT whatever its line?
lane345.bas opens with a `rem`, so its first statement is on line 2 -- which
separates the two readings. It is the first statement.

No editor, no window: one process and a socket. The mechanism this exposes is
written up in docs/phosphor-debugger-debts.md.

    python3 tools/lane/first-statement-probe.py [path\\to\\phosphor]
"""
import json
import os
import socket
import subprocess
import sys
import threading
import time

D = os.path.dirname(os.path.abspath(__file__))
DEFAULT_HOST = os.path.join(D, '..', '..', '..', 'Phosphor', 'bin',
                            'phosphor.exe' if os.name == 'nt' else 'phosphor')


def run(host, program, lines, stop_at_entry, label):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    proc = subprocess.Popen([host, 'debug', '--port', str(port), program],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # The program's own streams still have to be read, or it stalls behind a full
    # pipe buffer with no protocol symptom at all.
    for st in (proc.stdout, proc.stderr):
        t = threading.Thread(target=lambda s=st: list(iter(s.readline, b'')))
        t.daemon = True
        t.start()

    srv.settimeout(10)
    conn, _ = srv.accept()
    conn.settimeout(0.4)

    seq = [0]
    installed = None
    stops = []

    def send(obj):
        seq[0] += 1
        obj['seq'] = seq[0]
        conn.sendall((json.dumps(obj) + '\n').encode('utf-8'))

    send({'cmd': 'initialize', 'protocol': 1, 'client': 'first-statement-probe'})
    buf = b''
    stage = 'init'
    started = time.time()
    while time.time() - started < 12:
        try:
            chunk = conn.recv(8192)
        except socket.timeout:
            continue
        except OSError:
            # A HOST THAT CLOSES IS NOT AN ERROR. After an exception stop this
            # one emits the event and drops the socket in the same breath, and
            # Windows answers the next recv with WSAECONNABORTED rather than
            # with an orderly zero-length read. Whoever arrives first, the
            # session is over.
            break
        if not chunk:
            break
        buf += chunk
        while b'\n' in buf:
            raw, buf = buf.split(b'\n', 1)
            text = raw.decode('utf-8', 'replace').rstrip('\r')
            if not text:
                continue
            msg = json.loads(text)
            if stage == 'init' and msg.get('seq') == 1:
                stage = 'bp'
                send({'cmd': 'setBreakpoints', 'path': program, 'lines': lines})
            elif stage == 'bp' and msg.get('seq') == 2:
                installed = msg.get('lines')
                stage = 'run'
                send({'cmd': 'launch', 'program': program,
                      'stopAtEntry': stop_at_entry})
            elif msg.get('event') == 'stopped':
                stops.append('%s@%s' % (msg.get('reason'), msg.get('line')))
                send({'cmd': 'continue'})
            elif msg.get('event') == 'exited':
                stage = 'done'
        if stage == 'done':
            break

    conn.close()
    srv.close()
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    print('%-44s asked %-9s installed %-9s stops %s'
          % (label, lines, installed, stops if stops else '(none)'))


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HOST
    if not os.path.exists(host):
        raise SystemExit('no phosphor binary at %s' % host)
    boom = os.path.join(D, 'boom.bas')       # line 1 IS the first statement
    lane = os.path.join(D, 'lane345.bas')    # line 1 is a rem; line 2 is first
    run(host, boom, [1], False, 'boom.bas bp on 1 (first statement)')
    run(host, boom, [2], False, 'boom.bas bp on 2')
    run(host, boom, [1, 2], False, 'boom.bas bp on 1 and 2')
    run(host, boom, [1], True, 'boom.bas bp on 1, stopAtEntry')
    run(host, lane, [2], False, 'lane345.bas bp on 2 (first statement)')
    run(host, lane, [9], False, 'lane345.bas bp on 9')
    run(host, lane, [2, 9], False, 'lane345.bas bp on 2 and 9')


if __name__ == '__main__':
    main()
