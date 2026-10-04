"""Exercise recovery and preflight with service/privilege boundaries replaced.

No display managers, system timers, or root-owned paths are touched. Fixture
copies bypass the root guard and redirect installation paths, the lock, and Sway.
"""

import json
import os
from pathlib import Path
import pwd
import shutil
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
        }

    def run_script(self, name, *args, **environment):
        if name == "start.sh":
            args = ("--log-dir", str(self.logs), *args)
        return subprocess.run(
            ["bash", str(self.root / name), *args],
            env={**self.environment, **environment}, capture_output=True,
            text=True, timeout=10, umask=0o077,
        )

    def calls(self):
        path = self.root / "calls"
        return path.read_text() if path.exists() else ""

    def test_start_uses_sudo_tty_and_arms_recovery_first(self):
        result = self.run_script("start.sh", "--scale", "1.5")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertLess(calls.index('--unit=mozais-restore'), calls.index('stop sddm.service'))
        self.assertLess(calls.index('stop sddm.service'), calls.index('--unit=mozais-test'))
        self.assertIn('restore.sh --service-stopped', calls)
        current = self.logs / "current"
        self.assertIn('output * scale 1.5', (current / 'sway.conf').read_text())
        self.assertIn('/dev/tty3', (current / 'start.log').read_text())
        self.assertEqual(json.loads((current / "config.json").read_text()),
                         {"scale": 1.5, "logRoot": str(self.logs)})
        self.assertEqual((current / "start.log").stat().st_mode & 0o777, 0o644)
        self.assertEqual((self.root / "current-run").resolve(), current.resolve())
        self.assertFalse((self.root / "test-runs").exists())
        self.assertEqual(self.logs.stat().st_mode & 0o777, 0o755)
        self.assertEqual(current.stat().st_mode & 0o777, 0o755)
        self.assertEqual((current / "greeter").stat().st_mode & 0o7777, 0o755)

    def test_direct_root_start_keeps_diagnostics_readable_by_other_users(self):
        self.environment.pop("SUDO_USER")
        result = self.run_script("start.sh", FAIL_START="1")
        self.assertNotEqual(result.returncode, 0)
        current = self.logs / "current"
        for directory in [self.logs, current, current / "greeter"]:
            self.assertEqual(directory.stat().st_mode & 0o7777, 0o755)
        for name in ["start.log", "journal.log", "restore.log"]:
            self.assertEqual((current / name).stat().st_mode & 0o777, 0o644)
        self.assertIn('install -d -o root -g greeter -m 0755', self.calls())

    def test_preflight_rejections_do_not_stop_sddm(self):
        for args, environment in [
            ([], {"SUDO_TTY": "/dev/pts/2"}),
            ([], {"SESSION": "Class=user\nType=wayland\nState=active"}),
            (["--scale", "0"], {}),
            (["--scale", "1; exit 0"], {}),
            (["--log-dir", "relative/logs"], {}),
            ([], {"DENY_GREETER_LOG_ACCESS": "1"}),
        ]:
            with self.subTest(args=args, environment=environment):
                result = self.run_script("start.sh", *args, **environment)
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
        uid = os.getuid()
        self.assertEqual((self.root / f"latest-run-{uid}").resolve(), latest_run)
        self.assertIn(f"Test logs: {latest_run}", result.stdout)
        self.assertIn(f"Startup log: {latest_run}/start.log", result.stdout)
        self.assertIn("Log out of the desktop", (latest_run / "start.log").read_text())
        self.assertEqual(latest_run.stat().st_mode & 0o777, 0o755)
        self.assertEqual((latest_run / "start.log").stat().st_mode & 0o777, 0o644)

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
            self.assertEqual(session.stat().st_mode & 0o7777, 0o755)
            self.assertEqual((session / 'backend.log').read_text(), 'backend')
            self.assertEqual((session / 'sway.log').read_text(), 'test compositor output\n')
            for log in [session / 'backend.log', session / 'sway.log']:
                self.assertEqual(log.stat().st_mode & 0o777, 0o644)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mozais-install-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repository with spaces"
        self.source = self.repo / "scripts/greetd-test"
        self.source.mkdir(parents=True)
        self.installation = self.root / "installed"
        script = (SOURCE / "install.sh").read_text()
        script = script.replace('[[ "$EUID" -ne 0 ]]', 'false')
        (self.source / "install.sh").write_text(script)
        for name in ["start.sh", "restore.sh", "launch.sh", "greetd.toml", "sway.conf", "display-layout.py"]:
            shutil.copy2(SOURCE / name, self.source / name)
        for name in ["lib.sh", "debug-dbus.sh"]:
            shutil.copy2(SOURCE.parent / name, self.repo / "scripts" / name)
        (self.repo / "source-version").write_text("new")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        handler = self.bin / "handler"
        handler.write_text('''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as log:
    log.write(json.dumps([name, args, os.getcwd()]) + '\\n')
if name == 'systemctl':
    sys.exit(0 if args[-1] == os.environ.get('ACTIVE_UNIT') else 3)
if name == 'hyprctl':
    if args == ['-j', 'instances']:
        print(json.dumps([] if os.environ.get('NO_DESKTOP') else
                         [{'instance': 'test-desktop'}]))
    else:
        assert args == ['-j', '-i', 'test-desktop', 'monitors'], args
        print(json.dumps([{'name': 'external', 'x': 1600, 'y': 0, 'disabled': False},
                          {'name': 'internal', 'x': 0, 'y': 0, 'disabled': False}]))
    sys.exit(0)
if name == 'runuser':
    env = {**os.environ, 'HOME': str(root / 'builder-home')}
    sys.exit(subprocess.run(args[args.index('--') + 1:], env=env).returncode)
if name == 'dart':
    repo = pathlib.Path(os.getcwd())
    assert args == [str(repo / 'tool/mozais.dart'), 'build', '--theme',
                    str(repo / 'themes/default'), '--mode', 'release',
                    '--platform', 'linux', '--jobs', '4'], args
    assert os.environ['HOME'] == str(root / 'builder-home')
    assert os.environ['PATH'].split(':')[0] == str(root / 'builder-home/.cargo/bin')
    version = (repo / 'source-version').read_text()
    for relative in ['build/out/default/greeter', 'build/out/default/lib/libapp.so',
                     'build/out/backend']:
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(version)
        path.chmod(0o755)
    sys.exit(1 if os.environ.get('FAIL_BUILD') else 0)
''')
        handler.chmod(0o755)
        for name in ["systemctl", "runuser", "dart", "hyprctl"]:
            (self.bin / name).symlink_to(handler)
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_ROOT": str(self.root),
            "SUDO_USER": pwd.getpwuid(os.getuid()).pw_name,
            "MOZAIS_DART_BIN": str(self.bin / "dart"),
        }

    def run_installer(self, **environment):
        return subprocess.run(
            ["bash", str(self.source / "install.sh"), str(self.installation)], cwd=self.root,
            env={**self.environment, **environment}, capture_output=True,
            text=True, timeout=10,
        )

    def create_old_installation(self):
        (self.installation / "scripts").mkdir(parents=True)
        for relative in ["frontend/greeter", "frontend/lib/libapp.so", "backend"]:
            path = self.installation / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("old")

    def test_installer_builds_without_existing_artifacts_and_rebuilds_on_repeat(self):
        self.create_old_installation()
        for version in ["new", "newer"]:
            with self.subTest(version=version):
                (self.repo / "source-version").write_text(version)
                result = self.run_installer()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for relative in ["frontend/greeter", "frontend/lib/libapp.so", "backend"]:
                    self.assertEqual((self.installation / relative).read_text(), version)
                self.assertIn(str(self.installation / "launch.sh"),
                              (self.installation / "greetd.toml").read_text())
        backups = sorted((self.installation / "backups").iterdir())
        self.assertEqual(len(backups), 2)
        self.assertEqual((backups[0] / "frontend/greeter").read_text(), "old")
        self.assertEqual((backups[1] / "frontend/greeter").read_text(), "new")
        calls = (self.root / "calls").read_text()
        self.assertIn(f'"-u", "{self.environment["SUDO_USER"]}"', calls)

    def test_direct_root_invocation_builds_as_repository_owner(self):
        self.create_old_installation()
        self.environment.pop("SUDO_USER")
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        owner = pwd.getpwuid(self.repo.stat().st_uid).pw_name
        self.assertIn(f'"-u", "{owner}"', (self.root / "calls").read_text())

    def test_failed_build_preserves_installation_even_with_existing_artifacts(self):
        self.create_old_installation()
        bundle = self.repo / "build/out/default"
        bundle.mkdir(parents=True)
        (bundle / "greeter").write_text("stale")
        result = self.run_installer(FAIL_BUILD="1")
        self.assertNotEqual(result.returncode, 0)
        for relative in ["frontend/greeter", "frontend/lib/libapp.so", "backend"]:
            self.assertEqual((self.installation / relative).read_text(), "old")
        self.assertFalse((self.installation / "backups").exists())

    def test_installer_captures_desktop_order_and_preserves_it_without_a_desktop(self):
        self.create_old_installation()
        self.environment.pop('SWAYSOCK', None)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        saved = self.installation / 'display-layout.json'
        self.assertEqual(saved.read_text().strip(),
                         '{"axis": "x", "outputs": ["internal", "external"]}')
        self.assertEqual(saved.stat().st_mode & 0o777, 0o644)
        result = self.run_installer(NO_DESKTOP='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('keeping the installed layout', result.stdout)
        self.assertEqual(saved.read_text().strip(),
                         '{"axis": "x", "outputs": ["internal", "external"]}')

    def test_active_test_or_timer_rejects_before_build_and_installation(self):
        for unit in ["mozais-test.service", "mozais-restore.timer"]:
            with self.subTest(unit=unit):
                result = self.run_installer(ACTIVE_UNIT=unit)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(unit, result.stderr)
                self.assertNotIn('"runuser"', (self.root / "calls").read_text())
                self.assertFalse(self.installation.exists())


if __name__ == "__main__":
    unittest.main()
