"""ASCII handoff on a Linux VT, without changing its display or keyboard mode.

The greeter prepares the text buffer before Sway exits. A short-lived animator
then follows the user executor across exec, stopping when the compositor takes
over. It observes a pidfd rather than a reusable process number. The animator
detaches so the desktop keeps its process identity and does not inherit a child
it must reap. Ordinary terminals are excluded by KDGETMODE.
"""

import argparse
import errno
import fcntl
import os
import select
import signal
import struct
import sys
import termios
import time


# Generated with FIGlet's Slant font by Glenn Chappell, based on Standard.
LOGO = (
    r"    ___    __ __ ___    ____  ____",
    r"   /   |  / //_//   |  / __ \/  _/",
    r"  / /| | / ,<  / /| | / /_/ // /",
    r" / ___ |/ /| |/ ___ |/ _, _// /",
    r"/_/  |_/_/ |_/_/  |_/_/ |_/___/",
)
KDGETMODE = 0x4B3B
KD_TEXT = 0
FRAME_SECONDS = 0.08
MAX_SECONDS = 15
CLEAR = "\x1b[0;37;40m\x1b[2J\x1b[3J\x1b[H"
RESTORE = "\x1b[0m\x1b[?25h"


def get_console_mode(terminal):
    return struct.unpack('i', fcntl.ioctl(terminal, KDGETMODE, bytes(4)))[0]


def open_console():
    try:
        terminal = open('/dev/tty', 'r+b', buffering=0)
    except OSError as error:
        if error.errno in (errno.ENXIO, errno.ENODEV, errno.EACCES, errno.ENOENT):
            return None
        raise
    try:
        get_console_mode(terminal)
    except OSError as error:
        terminal.close()
        if error.errno == errno.ENOTTY:
            return None
        raise
    return terminal


def get_terminal_size(terminal):
    rows, columns, _, _ = struct.unpack(
        'HHHH', fcntl.ioctl(terminal, termios.TIOCGWINSZ, bytes(8)))
    return rows, columns


def get_frame(rows, columns, frame):
    if rows == 0 or columns == 0:
        return ''
    lines = LOGO if columns > max(map(len, LOGO)) and rows >= 9 else ('AKARI',)
    width = max(map(len, lines))
    top = max(1, (rows - len(lines) - 2) // 2 + 1)
    left = max(1, (columns - width) // 2 + 1)
    sweep = frame % (width + 12) - 6
    output = []
    for index, line in enumerate(lines):
        # Leave the last column free so a narrow VT never wraps or scrolls.
        line = line[:columns - left]
        output.append(f'\x1b[{top + index};{left}H')
        previous_color = None
        for column, character in enumerate(line):
            color = '\x1b[1;36;40m' if abs(column - sweep) <= 2 else '\x1b[0;37;40m'
            if color != previous_color:
                output.append(color)
                previous_color = color
            output.append(character)
    if rows >= len(lines) + 3 and columns > 9:
        output.append(f'\x1b[{top + len(lines) + 2};{max(1, (columns - 7) // 2 + 1)}H'
                      '\x1b[0;37mLoading')
    output.append('\x1b[0m')
    return ''.join(output)


def prepare_transition():
    terminal = open_console()
    if terminal is None:
        return
    with terminal:
        rows, columns = get_terminal_size(terminal)
        # Prepare the buffer even while Sway owns graphics mode. Showing the
        # cursor here leaves it usable if the launcher never gets to animate.
        terminal.write((CLEAR + get_frame(rows, columns, 0) + RESTORE).encode('ascii'))


def animate_transition(owner):
    terminal = open_console()
    if terminal is None:
        return
    with terminal:
        if get_console_mode(terminal) != KD_TEXT:
            return
        with os.fdopen(os.pidfd_open(owner), 'rb', buffering=0) as owner_fd:
            # The intermediary exits and is reaped by the executor before its
            # exec. The bounded animator is adopted by the system's reaper.
            if os.fork():
                return
            result = 0
            try:
                os.setsid()
                run_animation(terminal, owner_fd)
            except OSError as error:
                print(f'ASCII transition: {error}', file=sys.stderr, flush=True)
                result = 1
            finally:
                try:
                    # Graphics mode hides the VT buffer but does not discard it.
                    # Erase our frame and scrollback before the desktop can exit
                    # back to this console; no display mode change is needed.
                    terminal.write((CLEAR + RESTORE).encode('ascii'))
                finally:
                    os._exit(result)


def run_animation(terminal, owner_fd):
    stopped = False

    def stop_animation(signum, frame):
        nonlocal stopped
        stopped = True

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop_animation)
    poller = select.poll()
    poller.register(owner_fd, select.POLLIN)
    deadline = time.monotonic() + MAX_SECONDS
    previous_size = None
    frame = 0
    while not stopped and time.monotonic() < deadline:
        if poller.poll(0) or get_console_mode(terminal) != KD_TEXT:
            return
        size = get_terminal_size(terminal)
        if size != previous_size:
            terminal.write((CLEAR + '\x1b[?25l').encode('ascii'))
            previous_size = size
        terminal.write(get_frame(*size, frame).encode('ascii'))
        frame += 1
        if poller.poll(round(FRAME_SECONDS * 1000)):
            return


def preview_transition(frames):
    if not sys.stdout.isatty():
        print('\n'.join(LOGO))
        return
    try:
        sys.stdout.write('\x1b[0;37;40m\x1b[2J\x1b[H\x1b[?25l')
        for frame in range(frames):
            size = os.get_terminal_size(sys.stdout.fileno())
            sys.stdout.write(get_frame(size.lines, size.columns, frame))
            sys.stdout.flush()
            time.sleep(FRAME_SECONDS)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(RESTORE + '\n')
        sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    commands.add_parser('prepare')
    animate = commands.add_parser('animate')
    animate.add_argument('--owner', type=int, required=True)
    preview = commands.add_parser('preview')
    preview.add_argument('--frames', type=int, default=80)
    arguments = parser.parse_args()
    if arguments.operation == 'prepare':
        prepare_transition()
    elif arguments.operation == 'animate':
        animate_transition(arguments.owner)
    else:
        preview_transition(arguments.frames)


if __name__ == '__main__':
    main()
