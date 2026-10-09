"""Production deployment tests with systemd and account boundaries replaced."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


REPOSITORY = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('akari_login', REPOSITORY / 'scripts/login/manage.py')


class LoginWorkflowTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='akari-login-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.manager = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.manager)
        for name, relative in {
            'INSTALLATION': 'opt/akari', 'CONFIGURATION': 'etc/akari',
            'STATE': 'var/lib/akari', 'LOGS': 'var/log/akari/greeter',
            'UNIT': 'etc/systemd/system/akari.service',
            'DISPLAY_MANAGER': 'etc/systemd/system/display-manager.service',
            'SNAPSHOT': 'var/lib/akari/display-manager.json',
        }.items():
            setattr(self.manager, name, self.root / relative)
        self.manager.UNIT.parent.mkdir(parents=True)
        self.manager.DISPLAY_MANAGER.symlink_to('/usr/lib/systemd/system/sddm.service')
        self.bundle = self.root / 'bundle with spaces'
        (self.bundle / 'lib').mkdir(parents=True)
        (self.bundle / 'greeter').write_text('original frontend')
        (self.bundle / 'greeter').chmod(0o700)
        (self.bundle / 'lib/plugin.so').write_text('library')
        (self.bundle / 'lib/plugin.so').chmod(0o600)
        (self.bundle / 'lib').chmod(0o700)
        self.backend = self.root / 'backend'
        self.backend.write_text('original backend')
        self.backend.chmod(0o700)
        self.calls = []
        self.failures = []
        self.enabled = {'sddm.service'}
        self.active = 'inactive'
        self.target = 'graphical.target'
        self.addCleanup(patch.stopall)
        patch.object(self.manager, 'validate_runtime').start()
        patch.object(self.manager.pwd, 'getpwnam', return_value=SimpleNamespace(
            pw_uid=os.getuid(), pw_gid=os.getgid())).start()
        patch.object(self.manager.os, 'chown').start()
        patch.object(self.manager.subprocess, 'run', side_effect=self.run_boundary).start()

    def run_boundary(self, arguments, **kwargs):
        self.calls.append(arguments)
        operation = arguments[1:]
        output = ''
        status = 0
        if operation in self.failures:
            self.failures.remove(operation)
            raise subprocess.CalledProcessError(1, arguments, stderr='injected failure')
        if operation == ['get-default']:
            output = self.target
        elif operation[0] == 'is-enabled':
            output = 'enabled' if operation[-1] in self.enabled else 'disabled'
            status = 0 if output == 'enabled' else 1
        elif operation[0] == 'enable':
            unit = operation[-1]
            self.enabled.add(unit)
            self.manager.DISPLAY_MANAGER.unlink(missing_ok=True)
            self.manager.DISPLAY_MANAGER.symlink_to(self.manager.UNIT if unit == 'akari.service'
                                                    else f'/usr/lib/systemd/system/{unit}')
        elif operation[0] == 'disable':
            unit = operation[-1]
            self.enabled.discard(unit)
            alias = self.manager.DISPLAY_MANAGER
            if alias.is_symlink() and Path(os.readlink(alias)).name == unit:
                alias.unlink()
        elif operation[:3] == ['show', '--property=ActiveState', '--value']:
            output = self.active
        elif operation[0] == 'show':
            output = 'Id=akari.service\nLoadState=not-found\nActiveState=inactive\nSubState=dead\n'
            status = 1
        result = subprocess.CompletedProcess(arguments, status, output, '')
        if kwargs.get('check') and status:
            raise subprocess.CalledProcessError(status, arguments)
        return result

    def install(self, layout=None):
        self.manager.create_installation(REPOSITORY, self.bundle, self.backend, layout)

    def test_install_deploys_complete_bundle_and_preserves_system_login(self):
        self.install()
        release = (self.manager.INSTALLATION / 'current').resolve()
        self.assertEqual((release / 'frontend/lib/plugin.so').read_text(), 'library')
        self.assertEqual((release / 'frontend/lib').stat().st_mode & 0o777, 0o755)
        self.assertEqual((release / 'frontend/lib/plugin.so').stat().st_mode & 0o777, 0o644)
        self.assertEqual((release / 'frontend/greeter').stat().st_mode & 0o777, 0o755)
        self.assertTrue((release / 'scripts/debug-dbus.sh').is_file())
        self.assertTrue((release / 'display_profile.py').is_file())
        self.assertEqual(os.readlink(self.manager.DISPLAY_MANAGER), '/usr/lib/systemd/system/sddm.service')
        self.assertEqual(self.enabled, {'sddm.service'})
        self.assertFalse(self.manager.SNAPSHOT.exists())

    def test_upgrade_preserves_config_and_state_and_can_rollback(self):
        self.install()
        original = (self.manager.INSTALLATION / 'current').resolve()
        configuration = self.manager.CONFIGURATION / 'sway.conf'
        configuration.write_text('custom monitor scale')
        preferences = self.manager.STATE / 'greeter/preferences.json'
        preferences.write_text('saved session')
        self.backend.write_text('updated backend')
        self.install()
        updated = (self.manager.INSTALLATION / 'current').resolve()
        self.assertNotEqual(original, updated)
        self.assertEqual((original / 'backend').read_text(), 'original backend')
        self.assertEqual((updated / 'backend').read_text(), 'updated backend')
        self.assertEqual(configuration.read_text(), 'custom monitor scale')
        self.assertEqual(preferences.read_text(), 'saved session')
        self.manager.rollback_installation()
        self.assertEqual((self.manager.INSTALLATION / 'current').resolve(), original)
        self.assertEqual((self.manager.INSTALLATION / 'previous').resolve(), updated)

    def test_failed_deploy_keeps_previous_release_and_service(self):
        self.install()
        original = (self.manager.INSTALLATION / 'current').resolve()
        self.manager.UNIT.write_text('previous unit')
        self.failures.append(['daemon-reload'])
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual((self.manager.INSTALLATION / 'current').resolve(), original)
        self.assertEqual(self.manager.UNIT.read_text(), 'previous unit')
        self.assertEqual(len(list((self.manager.INSTALLATION / 'releases').iterdir())), 1)

    def test_failed_initial_install_can_be_retried(self):
        self.failures.append(['daemon-reload'])
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertFalse(self.manager.INSTALLATION.exists())
        self.assertFalse(self.manager.UNIT.exists())
        self.install()

    def test_missing_artifact_and_unmanaged_files_fail_before_changes(self):
        self.backend.unlink()
        with self.assertRaisesRegex(ValueError, 'Missing built executable'):
            self.install()
        self.assertFalse(self.manager.INSTALLATION.exists())
        self.backend.write_text('backend')
        self.backend.chmod(0o755)
        self.manager.UNIT.write_text('unrelated unit')
        with self.assertRaisesRegex(ValueError, 'unmanaged'):
            self.install()
        self.assertEqual(self.manager.UNIT.read_text(), 'unrelated unit')
        self.assertEqual(self.calls, [])

    def test_enable_disable_is_idempotent_and_never_stops_desktop(self):
        self.install()
        for _ in range(2):
            self.manager.enable_login()
        self.assertEqual(self.enabled, {'akari.service'})
        self.assertEqual(json.loads(self.manager.SNAPSHOT.read_text()), {
            'target': '/usr/lib/systemd/system/sddm.service', 'enabled': True})
        for _ in range(2):
            self.manager.disable_login()
        self.assertEqual(self.enabled, {'sddm.service'})
        self.assertEqual(os.readlink(self.manager.DISPLAY_MANAGER), '/usr/lib/systemd/system/sddm.service')
        self.assertFalse(self.manager.SNAPSHOT.exists())
        self.assertFalse(any(call[1] in ['start', 'stop', 'restart'] for call in self.calls))

    def test_enable_failure_restores_prior_service(self):
        self.install()
        self.failures.append(['enable', '--force', 'akari.service'])
        with self.assertRaises(subprocess.CalledProcessError):
            self.manager.enable_login()
        self.assertEqual(self.enabled, {'sddm.service'})
        self.assertEqual(os.readlink(self.manager.DISPLAY_MANAGER), '/usr/lib/systemd/system/sddm.service')
        self.assertFalse(self.manager.SNAPSHOT.exists())

    def test_failed_recovery_retains_snapshot_and_disable_can_retry(self):
        self.install()
        self.failures.extend([['enable', '--force', 'akari.service'],
                              ['enable', '--force', 'sddm.service']])
        with self.assertRaises(subprocess.CalledProcessError):
            self.manager.enable_login()
        self.assertTrue(self.manager.SNAPSHOT.exists())
        self.manager.disable_login()
        self.assertEqual(self.enabled, {'sddm.service'})
        self.assertFalse(self.manager.SNAPSHOT.exists())

    def test_enable_disable_with_no_previous_display_manager(self):
        self.install()
        self.manager.DISPLAY_MANAGER.unlink()
        self.enabled.clear()
        self.manager.enable_login()
        self.manager.disable_login()
        self.assertFalse(self.manager.DISPLAY_MANAGER.is_symlink())
        self.assertEqual(self.enabled, set())

    def test_disable_does_not_overwrite_another_selected_manager(self):
        self.install()
        self.manager.enable_login()
        self.manager.DISPLAY_MANAGER.unlink()
        self.manager.DISPLAY_MANAGER.symlink_to('/usr/lib/systemd/system/gdm.service')
        with self.assertRaisesRegex(ValueError, 'Another display manager'):
            self.manager.disable_login()
        self.assertTrue(self.manager.SNAPSHOT.exists())
        self.assertEqual(Path(os.readlink(self.manager.DISPLAY_MANAGER)).name, 'gdm.service')

    def test_uninstall_requires_inactive_service_and_retains_preferences(self):
        self.install()
        preferences = self.manager.STATE / 'greeter/preferences.json'
        preferences.write_text('saved session')
        self.manager.enable_login()
        self.active = 'active'
        with self.assertRaisesRegex(ValueError, 'running'):
            self.manager.remove_installation()
        self.active = 'inactive'
        self.manager.remove_installation()
        self.assertFalse(self.manager.UNIT.exists())
        self.assertFalse(self.manager.INSTALLATION.exists())
        self.assertEqual(preferences.read_text(), 'saved session')
        self.assertEqual(self.enabled, {'sddm.service'})

    def test_status_reports_missing_unit_but_exposes_failed_systemd_connection(self):
        self.assertFalse(self.manager.get_status()['installed'])
        with patch.object(self.manager.subprocess, 'run', return_value=subprocess.CompletedProcess(
                ['systemctl'], 1, '', 'Failed to connect to systemd')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.manager.get_status()

    def test_non_graphical_boot_target_is_not_changed(self):
        self.install()
        self.target = 'multi-user.target'
        with self.assertRaisesRegex(ValueError, 'graphical.target'):
            self.manager.enable_login()
        self.assertFalse(self.manager.SNAPSHOT.exists())
        self.assertEqual(self.enabled, {'sddm.service'})


class GreeterLifetimeTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='akari-login-runtime-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        binary = self.root / 'bin'
        binary.mkdir()
        boundary = binary / 'boundary'
        boundary.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
root = pathlib.Path(os.environ['FIXTURE'])
command = pathlib.Path(sys.argv[0]).name
if command == 'python3':
    (root / 'frontend.pid').write_text(str(os.getpid()))
    if os.environ.get('LONG_FRONTEND'):
        time.sleep(30)
elif command == 'busctl':
    if os.environ.get('FAIL_BACKEND'):
        while not (root / 'frontend.pid').exists():
            time.sleep(0.01)
        sys.exit(1)
elif command == 'swaymsg':
    (root / 'sway-exited').touch()
''')
        boundary.chmod(0o755)
        # An absolute interpreter keeps the python3 fixture from recursively
        # invoking itself through /usr/bin/env.
        boundary.write_text(boundary.read_text().replace(
            '#!/usr/bin/env python3', f'#!{sys.executable}'))
        for name in ['python3', 'busctl', 'swaymsg']:
            (binary / name).symlink_to(boundary)
        self.environment = {**os.environ, 'PATH': f'{binary}:{os.environ["PATH"]}',
                            'AKARI_RELEASE': str(self.root), 'AKARI_APP': 'fixture',
                            'AKARI_LOG_DIR': str(self.root), 'FIXTURE': str(self.root)}

    def run_greeter(self, **environment):
        return subprocess.run(['bash', str(REPOSITORY / 'scripts/login/run-greeter.sh')],
                              env={**self.environment, **environment}, text=True,
                              capture_output=True, timeout=5)

    def test_frontend_exit_releases_compositor(self):
        result = self.run_greeter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'sway-exited').exists())
        self.assertIn('Frontend exited: 0', (self.root / 'lifecycle.log').read_text())

    def test_launch_pins_release_and_publishes_readable_real_login_logs(self):
        release = self.root / 'release'
        (release / 'scripts').mkdir(parents=True)
        (self.root / 'logs').mkdir()
        source = (REPOSITORY / 'scripts/login/launch.sh').read_text()
        (release / 'launch.sh').write_text(source.replace(
            '/var/log/akari/greeter', str(self.root / 'logs')))
        boundary = release / 'scripts/debug-dbus.sh'
        boundary.write_text(f'''#!{sys.executable}
import json, os, pathlib
logs = pathlib.Path(os.environ['AKARI_LOG_DIR'])
print(json.dumps({{'release': os.environ['AKARI_RELEASE'],
                  'mode': os.environ['AKARI_BACKEND_MODE'],
                  'nested_backend': os.environ.get('WLR_BACKENDS'),
                  'log_permissions': logs.stat().st_mode & 0o777}}))
''')
        boundary.chmod(0o755)
        current = self.root / 'current'
        current.symlink_to(release)
        result = subprocess.run(['bash', str(current / 'launch.sh')],
                                env={**os.environ, 'WLR_BACKENDS': 'headless'},
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        sessions = list((self.root / 'logs').glob('session-*'))
        self.assertEqual(len(sessions), 1)
        self.assertEqual(json.loads((sessions[0] / 'sway.log').read_text()), {
            'release': str(release), 'mode': 'real', 'nested_backend': None,
            'log_permissions': 0o755})

    def test_backend_exit_terminates_frontend_and_releases_compositor(self):
        result = self.run_greeter(LONG_FRONTEND='1', FAIL_BACKEND='1')
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertTrue((self.root / 'sway-exited').exists())
        pid = int((self.root / 'frontend.pid').read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_termination_cleans_up_frontend(self):
        process = subprocess.Popen(['bash', str(REPOSITORY / 'scripts/login/run-greeter.sh')],
                                   env={**self.environment, 'LONG_FRONTEND': '1'})
        try:
            deadline = time.monotonic() + 3
            while not (self.root / 'frontend.pid').exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue((self.root / 'frontend.pid').exists())
            process.terminate()
            self.assertEqual(process.wait(timeout=5), 143)
            self.assertTrue((self.root / 'sway-exited').exists())
            pid = int((self.root / 'frontend.pid').read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
