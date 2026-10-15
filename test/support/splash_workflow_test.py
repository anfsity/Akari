"""Check the real VT launcher coordinator without acquiring a display device."""

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
assert sys.argv[1:] == ['kms']
assert int(os.environ['AKARI_SPLASH_PARENT_PID']) == os.getppid()
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
source '{REPOSITORY}/scripts/splash.sh'
akari_show_splash || true
exec '{sys.executable}' -c '
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
                            'AKARI_SPLASH_BIN': str(self.renderer)}

    def test_compositor_waits_for_release_on_success_and_renderer_failure(self):
        for status in [0, 1]:
            with self.subTest(status=status):
                result = subprocess.run(['bash', self.launcher],
                                        env={**self.environment, 'RESULT': str(status)},
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'event=splash_finished status={status}', result.stdout)
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


if __name__ == '__main__':
    unittest.main()
