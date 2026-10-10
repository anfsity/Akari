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
            'PAM': 'etc/pam.d/greetd',
            'LOCK': 'run/lock/akari-login.lock',
        }.items():
            setattr(self.manager, name, self.root / relative)
        self.manager.LOCK.parent.mkdir(parents=True)
        self.manager.PAM.parent.mkdir(parents=True)
        self.original_pam = ('#%PAM-1.0\n\nauth required pam_unix.so\n'
                             'account required pam_unix.so\nsession required pam_systemd.so\n')
        self.manager.PAM.write_text(self.original_pam)
        self.manager.PAM.chmod(0o640)
        self.module_root = self.root / 'usr/lib'
        self.modules = self.module_root / 'security'
        self.modules.mkdir(parents=True)
        (self.modules / 'pam_gnome_keyring.so').touch()
        self.manager.PAM_MODULE_ROOTS = [self.module_root]
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

    def install(self, layout=None, keyring='auto'):
        self.manager.create_installation(REPOSITORY, self.bundle, self.backend, layout, keyring)

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
        pam = self.manager.PAM.read_text()
        self.assertTrue(pam.startswith(self.original_pam))
        self.assertIn('auth       optional     pam_gnome_keyring.so\n', pam)
        self.assertIn('session    optional     pam_gnome_keyring.so auto_start\n', pam)
        self.assertNotIn('kwallet', pam)
        self.assertEqual(self.manager.PAM.stat().st_mode & 0o777, 0o640)
        self.assertEqual((self.manager.STATE / 'greetd.pam.before-keyring').read_text(), self.original_pam)

    def test_keyring_detection_supports_multiarch_modules_and_requires_pam(self):
        (self.modules / 'pam_gnome_keyring.so').unlink()
        (self.module_root / 'gnome-keyring').touch()
        self.assertEqual(self.manager.get_installed_keyrings(), [])
        multiarch = self.module_root / 'aarch64-linux-gnu/security'
        multiarch.mkdir(parents=True)
        (multiarch / 'pam_gnome_keyring.so').touch()
        (multiarch / 'pam_kwallet5.so').touch()
        self.assertEqual(self.manager.get_installed_keyrings(), ['gnome', 'kwallet'])

    def test_both_installed_providers_are_configured_and_selection_can_change(self):
        (self.modules / 'pam_kwallet5.so').touch()
        self.install()
        pam = self.manager.PAM.read_text()
        self.assertIn('session    optional     pam_kwallet5.so auto_start force_run\n', pam)
        self.install(keyring='gnome')
        pam = self.manager.PAM.read_text()
        self.assertNotIn('kwallet', pam)
        self.assertEqual(pam.count('pam_gnome_keyring.so'), 2)
        self.install(keyring='none')
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam)

    def test_reinstall_is_idempotent_and_uninstall_preserves_user_pam_edits(self):
        self.install()
        configured = self.manager.PAM.read_text()
        self.install()
        self.assertEqual(self.manager.PAM.read_text(), configured)
        addition = '\nsession optional pam_env.so\n'
        self.manager.PAM.write_text(configured + addition)
        self.manager.remove_installation()
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam + addition)

    def test_existing_direct_and_included_rules_are_not_duplicated(self):
        auth = self.manager.PAM.parent / 'common-auth'
        auth.write_text('auth [success=ok default=ignore] /usr/lib/security/pam_gnome_keyring.so\n'
                        'auth include greetd\n')
        session = self.manager.PAM.parent / 'common-session'
        session.write_text('-session optional pam_gnome_keyring.so auto_start\n')
        original = self.original_pam + '@include common-auth\nsession substack common-session\n'
        self.manager.PAM.write_text(original)
        self.install()
        self.assertEqual(self.manager.PAM.read_text(), original)
        self.assertFalse((self.manager.STATE / 'greetd.pam.before-keyring').exists())
        # Fill only the missing phase, retaining an administrator's auth rule.
        original = self.original_pam + 'auth optional pam_gnome_keyring.so\n'
        self.manager.PAM.write_text(original)
        self.install()
        pam = self.manager.PAM.read_text()
        self.assertTrue(pam.startswith(original))
        self.assertEqual(pam.count('pam_gnome_keyring.so'), 2)

    def test_symlinked_pam_policy_is_updated_without_replacing_link(self):
        target = self.manager.PAM.with_name('greetd-policy')
        self.manager.PAM.rename(target)
        self.manager.PAM.symlink_to(target.name)
        self.install()
        self.assertTrue(self.manager.PAM.is_symlink())
        self.assertIn('pam_gnome_keyring.so', target.read_text())
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_missing_modules_prompt_for_installation_then_recheck(self):
        (self.modules / 'pam_gnome_keyring.so').unlink()
        def install_package(arguments, **kwargs):
            self.assertEqual(arguments, ['pacman', '-S', '--needed', 'kwallet-pam'])
            self.assertTrue(kwargs['check'])
            (self.modules / 'pam_kwallet5.so').touch()
        with patch.object(self.manager.sys.stdin, 'isatty', return_value=True), \
                patch('builtins.input', side_effect=['invalid', 'k']), \
                patch.object(self.manager.platform, 'freedesktop_os_release', return_value={'ID': 'arch'}), \
                patch.object(self.manager.subprocess, 'run', side_effect=install_package):
            self.assertEqual(self.manager.select_keyrings('auto'), ['kwallet'])

    def test_declined_and_unattended_installation_never_runs_package_manager(self):
        (self.modules / 'pam_gnome_keyring.so').unlink()
        with patch.object(self.manager.sys.stdin, 'isatty', return_value=True), \
                patch('builtins.input', return_value=''):
            self.assertEqual(self.manager.select_keyrings('auto'), [])
            self.assertEqual(self.manager.select_keyrings('gnome'), [])
        with patch.object(self.manager.sys.stdin, 'isatty', return_value=False):
            self.assertEqual(self.manager.select_keyrings('auto'), [])
            with self.assertRaisesRegex(ValueError, 'PAM module is missing'):
                self.manager.select_keyrings('gnome')
        self.assertEqual(self.calls, [])
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam)

    def test_failed_or_incomplete_package_installation_leaves_pam_untouched(self):
        (self.modules / 'pam_gnome_keyring.so').unlink()
        with patch.object(self.manager.sys.stdin, 'isatty', return_value=True), \
                patch('builtins.input', return_value='yes'), \
                patch.object(self.manager.platform, 'freedesktop_os_release', return_value={'ID': 'arch'}):
            self.failures.append(['-S', '--needed', 'gnome-keyring'])
            with self.assertRaises(subprocess.CalledProcessError):
                self.install(keyring='gnome')
            with self.assertRaisesRegex(ValueError, 'did not provide'):
                self.install(keyring='gnome')
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam)
        self.assertFalse(self.manager.INSTALLATION.exists())

    def test_package_commands_follow_distribution_and_include_pam_package(self):
        cases = [
            ({'ID': 'arch'}, 'gnome', ['pacman', '-S', '--needed', 'gnome-keyring']),
            ({'ID': 'manjaro', 'ID_LIKE': 'arch'}, 'kwallet', ['pacman', '-S', '--needed', 'kwallet-pam']),
            ({'ID': 'ubuntu', 'ID_LIKE': 'debian'}, 'gnome', ['apt-get', 'install', 'gnome-keyring', 'libpam-gnome-keyring']),
            ({'ID': 'debian'}, 'kwallet', ['apt-get', 'install', 'libpam-kwallet5']),
            ({'ID': 'fedora'}, 'gnome', ['dnf', 'install', 'gnome-keyring', 'gnome-keyring-pam']),
            ({'ID': 'fedora'}, 'kwallet', ['dnf', 'install', 'pam-kwallet']),
        ]
        for distribution, provider, command in cases:
            with self.subTest(distribution=distribution, provider=provider), \
                    patch.object(self.manager.platform, 'freedesktop_os_release', return_value=distribution):
                self.assertEqual(self.manager.get_keyring_install_command(provider), command)
        with patch.object(self.manager.platform, 'freedesktop_os_release', return_value={'ID': 'other'}):
            with self.assertRaisesRegex(ValueError, 'manually'):
                self.manager.get_keyring_install_command('gnome')

    def test_malformed_managed_block_fails_before_deployment(self):
        broken = self.original_pam + self.manager.KEYRING_START + 'auth optional pam_gnome_keyring.so\n'
        self.manager.PAM.write_text(broken)
        with self.assertRaisesRegex(ValueError, 'Malformed'):
            self.install()
        self.assertEqual(self.manager.PAM.read_text(), broken)
        self.assertFalse(self.manager.INSTALLATION.exists())

    def test_failure_after_pam_update_restores_previous_pam(self):
        self.install(keyring='none')
        original = (self.manager.INSTALLATION / 'current').resolve()
        with patch.object(self.manager, 'write_json', side_effect=OSError('injected state write failure')):
            with self.assertRaisesRegex(OSError, 'injected'):
                self.install()
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam)
        self.assertEqual((self.manager.INSTALLATION / 'current').resolve(), original)

    def test_configure_keyring_command_only_updates_pam(self):
        with patch.object(self.manager.sys, 'argv', ['manage.py', 'configure-keyring', '--keyring', 'gnome']), \
                patch.object(self.manager.os, 'geteuid', return_value=0):
            self.assertEqual(self.manager.main(), 0)
        self.assertIn('pam_gnome_keyring.so', self.manager.PAM.read_text())
        self.assertFalse(self.manager.INSTALLATION.exists())
        self.assertEqual(self.calls, [])

    def test_failed_atomic_pam_write_keeps_original_policy_and_cleans_temporary_file(self):
        configuration = self.manager.get_keyring_pam_configuration(self.original_pam, ['gnome'])
        with patch.object(Path, 'replace', side_effect=OSError('injected rename failure')):
            with self.assertRaisesRegex(OSError, 'injected rename failure'):
                self.manager.update_pam(configuration)
        self.assertEqual(self.manager.PAM.read_text(), self.original_pam)
        self.assertEqual(list(self.manager.PAM.parent.glob('.greetd-*')), [])

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

    def test_restrictive_installer_umask_keeps_runtime_paths_accessible(self):
        previous = os.umask(0o077)
        try:
            self.install()
        finally:
            os.umask(previous)
        for path in [self.manager.INSTALLATION, self.manager.INSTALLATION / 'releases',
                     self.manager.CONFIGURATION, self.manager.STATE, self.manager.LOGS]:
            self.assertEqual(path.stat().st_mode & 0o777, 0o755, str(path))

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
