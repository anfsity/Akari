"""Drive one interactive CLI step through a real terminal and retain its report."""

import os
import pty
import select
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[1:], stdin=slave, stdout=slave, stderr=slave)
os.close(slave)
output = b''
sent_quit = False
try:
    deadline = time.monotonic() + 20
    while process.poll() is None and time.monotonic() < deadline:
        if select.select([master], [], [], .1)[0]:
            try:
                output += os.read(master, 65536)
            except OSError:
                break
        if b'INTERACTIVE_READY' in output and not sent_quit:
            os.write(master, b'q')
            sent_quit = True
    process.wait(timeout=5)
    sys.stdout.buffer.write(output)
    sys.exit(process.returncode)
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
