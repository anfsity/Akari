"""Exercise recovery and preflight with service/privilege boundaries replaced.

No display managers, system timers, or root-owned paths are touched. Fixture
copies bypass only the root guard and redirect the lock and Sway executable.
"""

import os
from pathlib import Path
import pwd
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "scripts/greetd-test"


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mozais-greetd-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.logs = self.root / "logs"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        handler = self.bin / "handler"
        handler.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as log:
    log.write(name + ' ' + ' '.join(args) + '\\n')
if name == 'systemctl':
    if args[0] == 'get-default': print('graphical.target')
    elif args[0] == 'is-enabled': print('enabled')
    elif args[0] == 'is-active':
        unit = args[-1]
        sys.exit(0 if unit == 'sddm.service' or
                 (unit == 'mozais-restore.timer' and (root / 'timer').exists()) else 3)
    elif args == ['stop', 'mozais-restore.timer']:
        (root / 'timer').unlink(missing_ok=True)
elif name == 'systemd-run':
    if '--unit=mozais-restore' in args: (root / 'timer').touch()
    if '--unit=mozais-test' in args and os.environ.get('FAIL_START'): sys.exit(1)
elif name == 'loginctl':
    if args[0] == 'list-sessions': print('11 1000 alice seat0 tty3')
    else: print(os.environ.get('SESSION', 'Class=user\\nType=tty\\nState=active'))
elif name == 'readlink':
    print('/usr/lib/systemd/system/sddm.service' if args[-1] ==
          '/etc/systemd/system/display-manager.service' else
          pathlib.Path(args[-1]).resolve())
elif name == 'install':
    arguments = iter(args)
    mode = 0o755
    paths = []
    for argument in arguments:
        if argument == '-d': continue
        if argument == '-m': mode = int(next(arguments), 8)
        elif argument in ['-o', '-g']: next(arguments)
        else: paths.append(pathlib.Path(argument))
    for path in paths:
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(mode)
elif name == 'runuser':
    sys.exit(1 if os.environ.get('DENY_GREETER_LOG_ACCESS') else 0)
elif name == 'journalctl': print('test journal')
elif name == 'sway': print('test compositor output')
''')
        handler.chmod(0o755)
        for name in ["systemctl", "systemd-run", "loginctl", "readlink", "install", "runuser", "journalctl", "sway"]:
            (self.bin / name).symlink_to(handler)
        for name in ["start.sh", "restore.sh", "launch.sh"]:
            script = (SOURCE / name).read_text()
            script = script.replace('[[ "$EUID" -ne 0 ]]', 'false')
            script = script.replace('/run/lock/mozais-test.lock', str(self.root / 'lock'))
            script = script.replace('/usr/bin/sway', str(self.bin / 'sway'))
            target = self.root / name
            target.write_text(script)
            target.chmod(0o755)
        (self.root / "frontend").mkdir()
        for path in [self.root / "frontend/greeter", self.root / "backend"]:
            path.touch()
            path.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_ROOT": str(self.root),
            "SUDO_TTY": "/dev/tty3",
            "SUDO_USER": pwd.getpwuid(os.getuid()).pw_name,
            "MOZAIS_TEST_LOG_DIR": str(self.logs),
        }

    def run_script(self, name, *args, **environment):
        return subprocess.run(
            ["bash", str(self.root / name), *args],
            env={**self.environment, **environment}, capture_output=True,
            text=True, timeout=10, umask=0o077,
        )

    def calls(self):
        path = self.root / "calls"
        return path.read_text() if path.exists() else ""

    def test_start_uses_sudo_tty_and_arms_recovery_first(self):
        result = self.run_script("start.sh", MOZAIS_TEST_SCALE="1.5")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertLess(calls.index('--unit=mozais-restore'), calls.index('stop sddm.service'))
        self.assertLess(calls.index('stop sddm.service'), calls.index('--unit=mozais-test'))
        self.assertIn('restore.sh --service-stopped', calls)
        current = self.logs / "current"
        self.assertIn('output * scale 1.5', (current / 'sway.conf').read_text())
        self.assertIn('/dev/tty3', (current / 'start.log').read_text())
        self.assertEqual((current / "start.log").stat().st_mode & 0o777, 0o644)
        self.assertEqual((self.root / "current-run").resolve(), current.resolve())
        self.assertFalse((self.root / "test-runs").exists())
        self.assertEqual(current.stat().st_mode & 0o777, 0o750)
        self.assertEqual((current / "greeter").stat().st_mode & 0o7777, 0o2750)

    def test_preflight_rejections_do_not_stop_sddm(self):
        for environment in [
            {"SUDO_TTY": "/dev/pts/2"},
            {"SESSION": "Class=user\nType=wayland\nState=active"},
            {"MOZAIS_TEST_SCALE": "0"},
            {"MOZAIS_TEST_SCALE": "1; exit 0"},
            {"MOZAIS_TEST_LOG_DIR": "relative/logs"},
            {"DENY_GREETER_LOG_ACCESS": "1"},
        ]:
            with self.subTest(environment=environment):
                result = self.run_script("start.sh", **environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('stop sddm.service', self.calls())

    def test_closing_desktop_session_does_not_block_test(self):
        result = self.run_script("start.sh", SESSION="Class=user\nType=wayland\nState=closing")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_attempt_is_discoverable_without_replacing_recovery_run(self):
        self.assertEqual(self.run_script("start.sh").returncode, 0)
        runs = self.logs
        armed_run = (runs / "current").resolve()

        result = self.run_script("start.sh", SUDO_TTY="/dev/pts/2")
        self.assertNotEqual(result.returncode, 0)
        latest_run = (runs / "latest").resolve()
        self.assertNotEqual(latest_run, armed_run)
        self.assertEqual((runs / "current").resolve(), armed_run)
        self.assertEqual((self.root / "current-run").resolve(), armed_run)
        self.assertIn(f"Test logs: {latest_run}", result.stdout)
        self.assertIn(f"Startup log: {latest_run}/start.log", result.stdout)
        self.assertIn("Log out of the desktop", (latest_run / "start.log").read_text())

    def test_start_failure_restores_sddm(self):
        result = self.run_script("start.sh", FAIL_START="1")
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls()
        self.assertIn('stop mozais-test.service', calls)
        self.assertLess(calls.index('start sddm.service'), calls.index('stop mozais-restore.timer'))
        self.assertEqual((self.logs / 'current/journal.log').read_text(), 'test journal\n')
        self.assertEqual((self.logs / 'current/journal.log').stat().st_mode & 0o777, 0o644)

    def test_service_exit_restores_without_stopping_itself(self):
        result = self.run_script("restore.sh", "--service-stopped")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('stop mozais-test.service', self.calls())
        self.assertIn('start sddm.service', self.calls())

    def test_each_greeter_keeps_its_own_logs(self):
        self.assertEqual(self.run_script("start.sh").returncode, 0)
        (self.root / 'scripts').mkdir()
        launcher = self.root / 'scripts/debug-dbus.sh'
        launcher.write_text('#!/bin/sh\nprintf backend > "$MOZAIS_LOG_DIR/backend.log"\nexec "$@"\n')
        launcher.chmod(0o755)
        for _ in range(2):
            result = self.run_script('launch.sh')
            self.assertEqual(result.returncode, 0, result.stderr)
        sessions = list((self.logs / 'current/greeter').iterdir())
        self.assertEqual(len(sessions), 2)
        for session in sessions:
            self.assertEqual(session.stat().st_mode & 0o7777, 0o2750)
            self.assertEqual(session.stat().st_gid, os.getgid())
            self.assertEqual((session / 'backend.log').read_text(), 'backend')
            self.assertEqual((session / 'sway.log').read_text(), 'test compositor output\n')
            for log in [session / 'backend.log', session / 'sway.log']:
                self.assertEqual(log.stat().st_mode & 0o777, 0o640)


if __name__ == "__main__":
    unittest.main()
