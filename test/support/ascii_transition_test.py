"""Renderer and process-lifetime checks without touching a real console."""

import errno
import importlib.util
import io
import os
from pathlib import Path
import pty
import re
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / 'scripts/ascii-transition.py'
SPEC = importlib.util.spec_from_file_location('ascii_transition', SOURCE)
transition = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(transition)


class AsciiTransitionTest(unittest.TestCase):
    def test_frames_keep_the_same_ascii_glyphs_with_a_moving_highlight(self):
        frames = [transition.get_frame(24, 80, index) for index in (0, 9, 22)]
        stripped = [re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', frame) for frame in frames]
        self.assertEqual(len(set(stripped)), 1)
        self.assertEqual(len(set(frames)), 3)
        for line in transition.LOGO:
            self.assertIn(line, stripped[0])
        self.assertTrue(all(frame.isascii() for frame in frames))

    def test_frames_never_wrap_or_scroll_on_small_or_resized_terminals(self):
        for rows, columns in [(1, 1), (2, 4), (4, 8), (8, 32), (9, 35), (24, 80), (50, 160)]:
            frame = transition.get_frame(rows, columns, 10)
            row, column = 1, 1
            for token in re.findall(r'\x1b\[[0-9;]*[A-Za-z]|[^\x1b]', frame):
                if token.endswith('H') and token.startswith('\x1b['):
                    row, column = map(int, token[2:-1].split(';'))
                    self.assertLessEqual(row, rows)
                    self.assertLessEqual(column, columns)
                elif not token.startswith('\x1b'):
                    self.assertLessEqual(row, rows)
                    self.assertLess(column, columns)
                    column += 1
        self.assertEqual(transition.get_frame(0, 0, 0), '')

    def test_missing_controlling_console_is_optional(self):
        with patch('builtins.open', side_effect=OSError(errno.ENXIO, 'no controlling tty')):
            transition.prepare_transition()
            transition.animate_transition(os.getpid())

    def test_pty_is_not_treated_as_a_linux_console(self):
        primary, secondary = pty.openpty()
        self.addCleanup(os.close, primary)
        self.addCleanup(os.close, secondary)
        script = '''import os, sys
os.setsid()
terminal = os.open(sys.argv[1], os.O_RDWR)
os.execv(sys.executable, [sys.executable, sys.argv[2], 'prepare'])
'''
        result = subprocess.run([sys.executable, '-c', script, os.ttyname(secondary), str(SOURCE)],
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'')
        self.assertEqual(result.stderr, b'')
        os.set_blocking(primary, False)
        with self.assertRaises(BlockingIOError):
            os.read(primary, 4096)

    def run_animation(self, modes, clock):
        terminal = io.BytesIO()
        owner_read, owner_write = os.pipe()
        self.addCleanup(os.close, owner_read)
        self.addCleanup(os.close, owner_write)
        with patch.object(transition, 'get_console_mode', side_effect=modes), \
                patch.object(transition, 'get_terminal_size', return_value=(24, 80)), \
                patch.object(transition, 'FRAME_SECONDS', 0), \
                patch.object(transition.time, 'monotonic', side_effect=clock):
            transition.run_animation(terminal, owner_read)
        return terminal.getvalue()

    def test_graphics_takeover_stops_without_clearing_the_desktop(self):
        output = self.run_animation([transition.KD_TEXT, 1], clock=[0, 0, 0])
        self.assertEqual(output.count(b'\x1b[2J'), 1)
        self.assertIn(b'Loading', output)

    def test_animation_stops_after_the_time_limit(self):
        output = self.run_animation([transition.KD_TEXT], clock=[0, 0, transition.MAX_SECONDS])
        self.assertEqual(output.count(b'Loading'), 1)

    def test_owner_exit_stops_before_drawing(self):
        owner = subprocess.Popen([sys.executable, '-c', 'pass'])
        with os.fdopen(os.pidfd_open(owner.pid), 'rb', buffering=0) as owner_fd:
            owner.wait(timeout=5)
            terminal = io.BytesIO()
            transition.run_animation(terminal, owner_fd)
            self.assertEqual(terminal.getvalue(), b'')

    def test_detached_animation_erases_its_frame_on_graphics_takeover_or_session_exit(self):
        for stop in ['graphics', 'session']:
            with self.subTest(stop=stop), \
                    tempfile.TemporaryDirectory(prefix='akari-ascii-test-') as temporary:
                output = Path(temporary) / 'console'
                graphics = Path(temporary) / 'graphics'
                owner = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
                self.addCleanup(owner.wait)
                self.addCleanup(owner.kill)
                script = '''import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('transition', sys.argv[1])
transition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transition)
transition.open_console = lambda: open(sys.argv[2], 'w+b', buffering=0)
transition.get_console_mode = lambda terminal: int(pathlib.Path(sys.argv[4]).exists())
transition.get_terminal_size = lambda terminal: (24, 80)
transition.animate_transition(int(sys.argv[3]))
'''
                # The detached worker keeps its diagnostic stream open until it
                # stops. Use a file, matching the executor's real redirection.
                with (Path(temporary) / 'animator.log').open('w+b') as log:
                    result = subprocess.run([sys.executable, '-c', script, str(SOURCE), str(output),
                                             str(owner.pid), str(graphics)], stdout=log, stderr=log, timeout=5)
                    log.seek(0)
                    self.assertEqual(result.returncode, 0, log.read())
                deadline = time.monotonic() + 2
                while not output.read_bytes() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertIn(b'Loading', output.read_bytes())
                if stop == 'graphics':
                    graphics.touch()
                else:
                    owner.terminate()
                    owner.wait(timeout=5)
                cleared = (transition.CLEAR + transition.RESTORE).encode()
                while not output.read_bytes().endswith(cleared) \
                        and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(output.read_bytes().endswith(cleared))
                self.assertNotIn(b'Loading', output.read_bytes().rsplit(b'\x1b[2J', 1)[1])


if __name__ == '__main__':
    unittest.main()
