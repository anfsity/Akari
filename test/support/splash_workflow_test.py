"""Check the real VT launcher coordinator without acquiring a display device."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]


class SplashWorkflowTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='akari-splash-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.renderer = self.root / 'renderer'
        self.renderer.write_text(f'''#!{sys.executable}
import os, pathlib, signal, sys, time
root = pathlib.Path(os.environ['FIXTURE'])
assert sys.argv[1:] == ['kms', '--snapshot', str(root / 'splash.png')]
assert int(os.environ['AKARI_SPLASH_PARENT_PID']) == os.getppid()
(root / 'splash.png').touch()
(root / 'renderer.pid').write_text(str(os.getpid()))
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
try:
    time.sleep(float(os.environ.get('HOLD', '0.05')))
finally:
    time.sleep(0.05)
    (root / 'released').touch()
sys.exit(int(os.environ.get('RESULT', '0')))
''')
        self.renderer.chmod(0o755)
        self.launcher = self.root / 'launch.sh'
        self.launcher.write_text(f'''#!/bin/bash
set -euo pipefail
exec /bin/bash '{REPOSITORY}/scripts/splash.sh' '{sys.executable}' -c '
import os, pathlib
root = pathlib.Path(os.environ["FIXTURE"])
pidfile = root / "renderer.pid"
if pidfile.exists():
    assert (root / "released").exists()
    try: os.kill(int(pidfile.read_text()), 0)
    except ProcessLookupError: pass
    else: raise AssertionError("compositor started before renderer exit")
(root / "compositor").touch()
'
''')
        self.environment = {**os.environ, 'FIXTURE': str(self.root),
                            'AKARI_LOG_DIR': str(self.root),
                            'AKARI_SPLASH_BIN': str(self.renderer)}

    def test_compositor_waits_for_release_on_success_and_renderer_failure(self):
        for status in [0, 1]:
            with self.subTest(status=status):
                result = subprocess.run(['bash', self.launcher],
                                        env={**self.environment, 'RESULT': str(status)},
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'event=splash_finished status={status}',
                              (self.root / 'lifecycle.log').read_text())
                self.assertTrue((self.root / 'compositor').exists())

    def test_private_bus_and_backend_are_ready_before_the_animation(self):
        backend = self.root / 'backend'
        backend.write_text(f'''#!{sys.executable}
import pathlib, time
root = pathlib.Path({str(self.root)!r})
(root / 'backend-started').touch()
time.sleep(30)
''')
        backend.chmod(0o755)
        busctl = self.root / 'busctl'
        busctl.write_text(f'''#!{sys.executable}
import pathlib, sys
root = pathlib.Path({str(self.root)!r})
if not (root / 'backend-started').exists():
    sys.exit(1)
(root / 'backend-ready').touch()
''')
        busctl.chmod(0o755)
        self.renderer.write_text(self.renderer.read_text().replace(
            "(root / 'renderer.pid').write_text", "assert (root / 'backend-ready').exists()\n(root / 'renderer.pid').write_text"))
        result = subprocess.run(
            ['bash', REPOSITORY / 'scripts/debug-dbus.sh', '--inside-private-bus',
             '/bin/bash', str(self.launcher)],
            env={**self.environment, 'AKARI_BACKEND_BIN': str(backend),
                 'AKARI_PRIVATE_BUS': '1',
                 'PATH': f'{self.root}:{os.environ["PATH"]}'},
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'splash.png').exists())
        self.assertTrue((self.root / 'compositor').exists())

    def test_missing_renderer_keeps_the_login_path_available(self):
        self.renderer.unlink()
        result = subprocess.run(['bash', self.launcher], env=self.environment,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'compositor').exists())

    def test_termination_reaps_renderer_before_launcher_exit(self):
        for termination, expected in [(signal.SIGTERM, 143), (signal.SIGINT, 130),
                                      (signal.SIGHUP, 129)]:
            with self.subTest(signal=termination):
                for name in ['renderer.pid', 'released']:
                    (self.root / name).unlink(missing_ok=True)
                process = subprocess.Popen(['bash', self.launcher],
                                           env={**self.environment, 'HOLD': '30'},
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 3
                    while not (self.root / 'renderer.pid').exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue((self.root / 'renderer.pid').exists())
                    pid = int((self.root / 'renderer.pid').read_text())
                    process.send_signal(termination)
                    self.assertEqual(process.wait(timeout=5), expected)
                    self.assertTrue((self.root / 'released').exists())
                    self.assertFalse((self.root / 'compositor').exists())
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()


class PrivateBusLifetimeTest(unittest.TestCase):
    def test_session_signals_reap_the_private_bus(self):
        for termination in [None, signal.SIGTERM, signal.SIGHUP, signal.SIGKILL]:
            with self.subTest(signal=termination), tempfile.TemporaryDirectory(
                    prefix='akari-bus-test-') as directory:
                root = Path(directory)
                client = root / 'client.py'
                client.write_text('''import json, os, pathlib, subprocess, time
result = subprocess.check_output([
    'busctl', '--user', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
    'org.freedesktop.DBus', 'GetConnectionUnixProcessID', 's', 'org.freedesktop.DBus'], text=True)
pathlib.Path(os.environ['FIXTURE']).joinpath('bus.json').write_text(json.dumps({
    'pid': int(result.split()[1]), 'address': os.environ['DBUS_SESSION_BUS_ADDRESS']}))
if os.environ['HOLD'] == '1':
    time.sleep(30)
''')
                process = subprocess.Popen(
                    ['bash', str(REPOSITORY / 'scripts/debug-dbus.sh'), sys.executable, str(client)],
                    env={**os.environ, 'FIXTURE': directory, 'XDG_RUNTIME_DIR': directory,
                         'AKARI_LOG_DIR': str(root / 'logs'), 'AKARI_START_BACKEND': '0',
                         'HOLD': '0' if termination is None else '1'},
                    start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 5
                    while not (root / 'bus.json').exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    bus = json.loads((root / 'bus.json').read_text())
                    if termination == signal.SIGKILL:
                        process.kill()
                    elif termination is not None:
                        os.killpg(process.pid, termination)
                    self.assertEqual(process.wait(timeout=5),
                                     -signal.SIGKILL if termination == signal.SIGKILL else
                                     0 if termination is None else 128 + termination)
                    if termination == signal.SIGKILL:
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            result = subprocess.run(
                                ['busctl', '--address='+bus['address'], '--no-pager', 'list'],
                                capture_output=True, timeout=2)
                            if result.returncode != 0:
                                break
                            time.sleep(.01)
                        self.assertNotEqual(result.returncode, 0)
                    else:
                        with self.assertRaises(ProcessLookupError):
                            os.kill(bus['pid'], 0)
                        self.assertFalse(Path(bus['address'].removeprefix('unix:path=')).parent.exists())
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    if termination == signal.SIGKILL:
                        os.killpg(process.pid, signal.SIGTERM)


if __name__ == '__main__':
    unittest.main()
