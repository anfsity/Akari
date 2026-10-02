"""Exercise generated completions through zsh's real line editor in a PTY."""

import fcntl
import json
import os
import pty
import select
import shlex
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

completion, output_directory = sys.argv[1:]
output = Path(output_directory)
buffers = output / "buffers.txt"
buffers.write_text("")
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 160, 0, 0))
process = subprocess.Popen(
    ["zsh", "-f", "-i"],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    start_new_session=True,
    cwd=output,
)
os.close(slave)


def drain_output(duration):
    deadline = time.monotonic() + duration
    chunks = []
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
        if ready:
            chunks.append(os.read(master, 65536))
    return b"".join(chunks)


try:
    drain_output(0.1)
    setup = (
        "PROMPT='MOZAIS> '; KEYTIMEOUT=1; autoload -Uz compinit; "
        f"compinit -d {shlex.quote(str(output / 'zcompdump'))}; "
        f"source {shlex.quote(completion)}; "
        "dump-buffer() { "
        f"print -r -- \"$BUFFER\" >> {shlex.quote(str(buffers))}; "
        "BUFFER=''; zle reset-prompt; }; "
        "zle -N dump-buffer; bindkey '^X' dump-buffer; "
        "print -r -- 'MOZAIS''_READY'\n"
    )
    os.write(master, setup.encode())
    transcript = b""
    deadline = time.monotonic() + 10
    while b"\r\nMOZAIS_READY\r\n" not in transcript:
        transcript += drain_output(0.1)
        if time.monotonic() > deadline:
            raise RuntimeError(transcript.decode(errors="replace"))
    probes = [
        "mozais tr",
        "mozais build -m pr",
        "mozais run --backend re",
        "mozais perf -- --mode pr",
        "mozais build --mode=pr",
        "mozais st",
        "mozais build -t theme",
    ]
    for index, probe in enumerate(probes):
        os.write(master, (probe + "\t").encode())
        drain_output(0.2)
        os.write(master, b"\x18")
        deadline = time.monotonic() + 5
        while len(buffers.read_text().splitlines()) <= index:
            drain_output(0.1)
            if time.monotonic() > deadline:
                raise RuntimeError(f"ZLE did not capture completion for {probe}")
        os.write(master, b"\x03")
        drain_output(0.1)
    print(json.dumps(buffers.read_text().splitlines()))
finally:
    process.kill()
    process.wait(timeout=5)
    os.close(master)
