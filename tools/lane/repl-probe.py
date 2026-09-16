"""What the Phosphor REPL does on a pipe, with timings.

Three questions the editor needs answered before it starts one:

  1. How long after an answer does the next prompt arrive? The editor's runner
     emits an unterminated tail only after TWO idle drain ticks (40 ms each), so
     a prompt that is already in the pipe costs about 80 ms of latency. That
     number has never been measured against a child that actually prompts.
  2. Does closing stdin end the child, and how fast?
  3. Does killing it leave anything behind?

Run it from anywhere; it writes nothing.
"""

import os
import subprocess
import sys
import threading
import time

EXE = sys.argv[1] if len(sys.argv) > 1 else r'C:\Dev\Phosphor\bin\phosphor.exe'


def reader(stream, sink, label):
    while True:
        b = stream.read(1)
        if not b:
            break
        sink.append((time.monotonic(), label, b))


def start():
    p = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, bufsize=0)
    sink = []
    for s, label in ((p.stdout, 'out'), (p.stderr, 'err')):
        t = threading.Thread(target=reader, args=(s, sink, label), daemon=True)
        t.start()
    return p, sink


def quiet_for(sink, seconds, timeout=5.0, since=None):
    """Wait for new bytes and then for `seconds` of silence after the last one.

    `since` is the sink length before the send; without it the first call would
    look at a byte that arrived before the question was asked and answer at once,
    which is exactly the mistake the first version of this probe made and it made
    the host look like it was block-buffering."""
    base = len(sink) if since is None else since
    start_t = time.monotonic()
    while time.monotonic() - start_t < timeout:
        if len(sink) > base and time.monotonic() - sink[-1][0] >= seconds:
            return time.monotonic() - start_t
        time.sleep(0.002)
    return None


def text(sink, since=0):
    return b''.join(b for (t, lbl, b) in sink if t >= since and lbl == 'out').decode('utf-8', 'replace')


print('exe:', EXE)
p, sink = start()

# --- 1. the banner and the first prompt ------------------------------------
quiet_for(sink, 0.15)
print('\n-- after start, stdout is:')
print(repr(text(sink)))

# --- 2. an answer, and how long the next prompt takes ----------------------
for line in (b'println 6*7\n', b'x = 1\n', b'println x\n'):
    mark = time.monotonic()
    n = len(sink)
    p.stdin.write(line)
    p.stdin.flush()
    quiet_for(sink, 0.15, since=n)
    first = sink[n][0] - mark if len(sink) > n else None
    last = sink[-1][0] - mark if len(sink) > n else None
    got = b''.join(b for (t, lbl, b) in sink[n:]).decode('utf-8', 'replace')
    print('\n-- sent %r' % line.decode())
    print('   first byte back: %s ms, last byte: %s ms' % (
        '%.1f' % (first * 1000) if first is not None else '(none)',
        '%.1f' % (last * 1000) if last is not None else '(none)'))
    print('   got: %r' % got)

# --- 3. a multi-line block -------------------------------------------------
for line in (b'for i = 1 to 3\n', b'println i\n', b'next\n'):
    n = len(sink)
    p.stdin.write(line)
    p.stdin.flush()
    quiet_for(sink, 0.15, since=n)
    got = b''.join(b for (t, lbl, b) in sink[n:]).decode('utf-8', 'replace')
    print('\n-- sent %r -> %r' % (line.decode(), got))

# --- 4. an error -----------------------------------------------------------
n = len(sink)
p.stdin.write(b'nosuchthing(\n')
p.stdin.flush()
quiet_for(sink, 0.2)
out = b''.join(b for (t, lbl, b) in sink[n:] if lbl == 'out').decode('utf-8', 'replace')
err = b''.join(b for (t, lbl, b) in sink[n:] if lbl == 'err').decode('utf-8', 'replace')
print('\n-- sent an error')
print('   stdout: %r' % out)
print('   stderr: %r' % err)

# --- 5. closing stdin ------------------------------------------------------
mark = time.monotonic()
p.stdin.close()
code = p.wait(timeout=10)
print('\n-- closed stdin: exited %d after %.1f ms' % (code, (time.monotonic() - mark) * 1000))

# --- 6. and killing one instead --------------------------------------------
p2, sink2 = start()
quiet_for(sink2, 0.15)
p2.stdin.write(b'for i = 1 to 3\n')      # left mid-block, deliberately
p2.stdin.flush()
quiet_for(sink2, 0.15)
mark = time.monotonic()
p2.kill()
code = p2.wait(timeout=10)
print('-- killed mid-block: exited %s after %.1f ms' % (code, (time.monotonic() - mark) * 1000))

time.sleep(0.4)
if os.name == 'nt':
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq phosphor.exe'],
                         capture_output=True, text=True).stdout
    left = [l for l in out.splitlines() if 'phosphor.exe' in l.lower()]
    print('-- phosphor.exe still running afterwards:', left or 'none')
