"""Speak PDBP to the real host and write down every frame it sends.

Two questions the editor cannot answer about itself:
  * is a breakpoint on the FIRST statement reported as installed, and does it
    then fire?
  * does a failing program produce a `stopped` event with reason `exception`,
    or does it just die?
"""
import json
import os
import socket
import subprocess
import sys
import threading
import time

HOST = r'C:\Dev\Phosphor\bin\phosphor.exe'
D = os.path.dirname(os.path.abspath(__file__))


def session(program, lines, stop_at_entry, label, max_seconds=15):
    print('=' * 70)
    print(label)
    print('  program %s, breakpoints %s, stopAtEntry %s'
          % (program, lines, stop_at_entry))
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    proc = subprocess.Popen(
        [HOST, 'debug', '--port', str(port), program],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        stdin=subprocess.PIPE)

    out = []

    def pump(stream, tag):
        for raw in iter(stream.readline, b''):
            out.append('  %s| %s' % (tag, raw.decode('utf-8', 'replace').rstrip()))

    for st, tag in ((proc.stdout, 'out'), (proc.stderr, 'err')):
        t = threading.Thread(target=pump, args=(st, tag))
        t.daemon = True
        t.start()

    srv.settimeout(10)
    conn, _ = srv.accept()
    conn.settimeout(0.5)

    seq = [0]

    def send(obj):
        seq[0] += 1
        obj['seq'] = seq[0]
        wire = json.dumps(obj) + '\n'
        print('  -> ' + wire.rstrip())
        conn.sendall(wire.encode('utf-8'))
        return seq[0]

    buf = b''
    started = time.time()
    stage = 'init'
    send({'cmd': 'initialize', 'protocol': 1, 'client': 'probe'})

    while time.time() - started < max_seconds:
        try:
            chunk = conn.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            print('  <- (peer closed)')
            break
        buf += chunk
        while b'\n' in buf:
            raw, buf = buf.split(b'\n', 1)
            text = raw.decode('utf-8', 'replace').rstrip('\r')
            if not text:
                continue
            print('  <- ' + text)
            msg = json.loads(text)
            if stage == 'init' and msg.get('seq') == 1:
                stage = 'bp'
                send({'cmd': 'setBreakpoints', 'path': program, 'lines': lines})
            elif stage == 'bp' and msg.get('seq') == 2:
                stage = 'run'
                send({'cmd': 'launch', 'program': program,
                      'stopAtEntry': stop_at_entry})
            elif msg.get('event') == 'stopped':
                send({'cmd': 'variables', 'frame': 0})
                send({'cmd': 'continue'})
            elif msg.get('event') == 'exited':
                stage = 'done'

        if stage == 'done':
            break

    try:
        conn.close()
    finally:
        srv.close()
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    time.sleep(0.3)
    for line in out:
        print(line)
    print('  exit code: %s' % proc.returncode)


if __name__ == '__main__':
    session(D + r'\boom.bas', [1], False, 'boom.bas, breakpoint on line 1')
    session(D + r'\boom.bas', [2], False, 'boom.bas, breakpoint on line 2')
    session(D + r'\lane345.bas', [1, 3], False,
            'lane345.bas, breakpoints on line 1 (statement) and 3 (blank)')
