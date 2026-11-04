"""Check Gaze deployment and evaluate its control flow with an isolated PAM stack."""

import ctypes
import importlib.util
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch


REPOSITORY = Path(__file__).resolve().parents[2]
ARCH_POLICIES = {
    'system-local-login': 'auth include system-login\n',
    'system-login': '''auth required pam_shells.so
auth requisite pam_nologin.so
auth include system-auth
''',
    'system-auth': '''auth required pam_faillock.so preauth
-auth [success=2 default=ignore] pam_systemd_home.so
auth [success=1 default=bad] pam_unix.so try_first_pass nullok
auth [default=die] pam_faillock.so authfail
auth optional pam_permit.so
auth required pam_env.so
auth required pam_faillock.so authsucc
''',
}


class GazePamTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='akari-gaze-pam-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        spec = importlib.util.spec_from_file_location('akari_login', REPOSITORY / 'scripts/login/manage.py')
        self.manager = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.manager)
        self.manager.PAM = self.root / 'pam.d/greetd'
        self.manager.STATE = self.root / 'state'
        self.manager.LOCK = self.root / 'lock'
        self.manager.PAM.parent.mkdir()
        self.original = '''#%PAM-1.0
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login # distribution policy
account    include      system-local-login
session    include      system-local-login

# BEGIN Akari keyring
auth       optional     pam_gnome_keyring.so use_authtok
session    optional     pam_gnome_keyring.so auto_start
# END Akari keyring
'''
        self.manager.PAM.write_text(self.original)
        self.manager.PAM.chmod(0o640)
        for name, policy in ARCH_POLICIES.items():
            self.manager.PAM.with_name(name).write_text(policy)
        self.module_root = self.root / 'lib'
        (self.module_root / 'security').mkdir(parents=True)
        (self.module_root / 'security/pam_gaze.so').touch()
        self.manager.PAM_MODULE_ROOTS = [self.module_root]
        self.helper = self.manager.PAM.with_name('akari-gaze')
        self.backup = self.manager.STATE / 'greetd.pam.before-gaze'

    def test_enable_is_idempotent_and_retains_password_keyring_and_backup(self):
        for _ in range(2):
            self.manager.enable_gaze()
            self.assertEqual(self.manager.PAM.read_text(), self.original.replace(
                'include      system-local-login #', 'substack      akari-gaze #'))
            self.assertEqual(self.backup.read_text(), self.original)
            self.assertEqual(self.helper.read_text(), self.manager.GAZE_PAM)
            self.assertEqual(self.manager.PAM.stat().st_mode & 0o777, 0o640)
            self.assertEqual(self.helper.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.manager.get_gaze_pam_configuration(self.manager.PAM.read_text(), enabled=False), self.original)

    def test_disable_preserves_later_edits_and_is_idempotent(self):
        self.manager.enable_gaze()
        addition = '\nsession optional pam_env.so\n'
        self.manager.PAM.write_text(self.manager.PAM.read_text() + addition)
        for _ in range(2):
            self.manager.disable_gaze()
            self.assertEqual(self.manager.PAM.read_text(), self.original + addition)
            self.assertFalse(self.helper.exists())
            self.assertEqual(self.backup.read_text(), self.original)

    def test_shared_auth_changes_are_rejected_before_any_write(self):
        for service in ARCH_POLICIES:
            with self.subTest(service=service):
                path = self.manager.PAM.with_name(service)
                original = path.read_text()
                path.write_text(original + 'auth required pam_u2f.so\n')
                with self.assertRaisesRegex(ValueError, 'Unsupported auth policy'):
                    self.manager.enable_gaze()
                self.assertEqual(self.manager.PAM.read_text(), self.original)
                self.assertFalse(self.helper.exists())
                self.assertFalse(self.backup.exists())
                path.write_text(original)

    def test_custom_parent_authentication_is_rejected(self):
        for addition in ['auth required pam_u2f.so\n', 'auth sufficient pam_gaze.so\n',
                         'auth optional /usr/lib/security/pam_gaze.so\n', '@include other-auth\n']:
            with self.subTest(addition=addition):
                original = self.original + addition
                self.manager.PAM.write_text(original)
                with self.assertRaises(ValueError):
                    self.manager.enable_gaze()
                self.assertEqual(self.manager.PAM.read_text(), original)
                self.assertFalse(self.helper.exists())

    def test_missing_module_is_rejected_before_any_write(self):
        (self.module_root / 'security/pam_gaze.so').unlink()
        with self.assertRaisesRegex(ValueError, 'pam_gaze.so is missing'):
            self.manager.enable_gaze()
        self.assertEqual(self.manager.PAM.read_text(), self.original)
        self.assertFalse(self.helper.exists())

    def test_custom_helper_is_preserved(self):
        custom = 'auth required pam_u2f.so\n'
        self.helper.write_text(custom)
        with self.assertRaisesRegex(ValueError, 'custom policy'):
            self.manager.enable_gaze()
        self.assertEqual(self.helper.read_text(), custom)
        self.assertEqual(self.manager.PAM.read_text(), self.original)

    def test_disable_retains_an_administrators_modified_helper(self):
        self.manager.enable_gaze()
        custom = self.helper.read_text() + '# local change\n'
        self.helper.write_text(custom)
        self.manager.disable_gaze()
        self.assertEqual(self.manager.PAM.read_text(), self.original)
        self.assertEqual(self.helper.read_text(), custom)

    def test_failed_parent_write_removes_new_helper(self):
        with patch.object(self.manager, 'update_pam', side_effect=OSError('injected write failure')):
            with self.assertRaisesRegex(OSError, 'injected write failure'):
                self.manager.enable_gaze()
        self.assertEqual(self.manager.PAM.read_text(), self.original)
        self.assertFalse(self.helper.exists())

    def test_failed_helper_write_leaves_parent_and_backup_untouched(self):
        with patch.object(Path, 'replace', side_effect=OSError('injected rename failure')):
            with self.assertRaisesRegex(OSError, 'injected rename failure'):
                self.manager.enable_gaze()
        self.assertEqual(self.manager.PAM.read_text(), self.original)
        self.assertFalse(self.helper.exists())
        self.assertFalse(self.backup.exists())
        self.assertEqual(list(self.manager.PAM.parent.glob('.greetd-*')), [])

    def test_cleanup_removes_managed_gaze_and_keyring_rules(self):
        self.manager.enable_gaze()
        self.manager.UNIT = self.root / 'akari.service'
        with patch.object(self.manager, 'restore_login_selection'), \
                patch.object(self.manager, 'run_systemctl'), \
                patch.object(self.manager, 'remove_registered_paths'):
            self.manager.remove_login_files()
        self.assertEqual(self.manager.PAM.read_text(), self.manager.get_pam_without_keyring(self.original))
        self.assertFalse(self.helper.exists())
        self.assertEqual(self.backup.read_text(), self.original)

    def test_commands_only_update_pam(self):
        for operation in ['enable-gaze', 'disable-gaze']:
            with patch.object(self.manager.sys, 'argv', ['manage.py', operation]), \
                    patch.object(self.manager.os, 'geteuid', return_value=0), \
                    patch.object(self.manager.subprocess, 'run') as run:
                self.assertEqual(self.manager.main(), 0)
                run.assert_not_called()
        self.assertEqual(self.manager.PAM.read_text(), self.original)

    def test_real_pam_preserves_lockout_password_fallback_and_parent_hooks(self):
        self.manager.enable_gaze()
        policies = {path.name: path.read_text() for path in self.manager.PAM.parent.iterdir()}
        trace = self.root / 'trace'
        stub = self.root / 'module.py'
        cases = [
            ('face', {}, True, False, True),
            ('password', {'gaze': 1}, True, True, True),
            ('missing-provider', {'missing-provider': 1}, True, True, True),
            ('locked', {'faillock-preauth': 1}, False, False, False),
            ('ineligible-shell', {'shells': 1}, False, False, False),
            ('wrong-password', {'gaze': 1, 'unix': 1}, False, True, False),
            ('environment-error', {'env': 1}, False, False, False),
            ('securetty-error', {'securetty': 1}, False, True, True),
            ('optional-keyring-error', {'gnome_keyring': 1}, True, False, True),
        ]
        for name, failures, success, password, clear_lockout in cases:
            with self.subTest(name=name):
                trace.write_text('')
                outcomes = {'systemd_home': 1, 'faillock-authfail': 1, **failures}
                stub.write_text('import pathlib, sys\n'
                                f'with pathlib.Path({str(trace)!r}).open("a") as trace:\n'
                                '    trace.write(sys.argv[1] + "\\n")\n'
                                f'sys.exit({outcomes!r}.get(sys.argv[1], 0))\n')
                for service, policy in policies.items():
                    lines = []
                    for line in policy.splitlines():
                        module = re.fullmatch(r'(-?auth\s+(?:\[[^]]+\]|\S+)\s+)(pam_\w+\.so)(?:\s+(.*))?', line)
                        if module and module[2] != 'pam_permit.so':
                            stage = module[2][4:-3]
                            if stage == 'faillock':
                                stage += '-' + module[3]
                            if stage == 'gaze' and 'missing-provider' in failures:
                                line = module[1] + '/nonexistent/pam_gaze.so'
                            else:
                                line = module[1] + f'pam_exec.so {sys.executable} {stub} {stage}'
                        lines.append(line)
                    self.manager.PAM.with_name(service).write_text('\n'.join(lines) + '\n')
                self.assertEqual(self.authenticate(), success)
                stages = trace.read_text().splitlines()
                self.assertEqual('unix' in stages, password)
                self.assertEqual('faillock-authsucc' in stages, clear_lockout)
                self.assertIn('gnome_keyring', stages)
                if name in ['locked', 'ineligible-shell']:
                    self.assertNotIn('gaze', stages)

    def authenticate(self):
        # Only auth runs, using a private confdir and harmless pam_exec stubs.
        # No camera, password, host faillock state, account or session is touched.
        callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_void_p,
                                         ctypes.c_void_p, ctypes.c_void_p)
        class Conversation(ctypes.Structure):
            _fields_ = [('conv', callback_type), ('data', ctypes.c_void_p)]
        conversation = Conversation(callback_type(lambda *_: 19), None)
        pam = ctypes.CDLL('libpam.so.0')
        pam.pam_start_confdir.argtypes = [ctypes.c_char_p, ctypes.c_char_p,
                                         ctypes.POINTER(Conversation), ctypes.c_char_p,
                                         ctypes.POINTER(ctypes.c_void_p)]
        pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
        pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
        handle = ctypes.c_void_p()
        self.assertEqual(pam.pam_start_confdir(b'greetd', b'akari-test', ctypes.byref(conversation),
                                              os.fsencode(self.manager.PAM.parent), ctypes.byref(handle)), 0)
        status = pam.pam_authenticate(handle, 0)
        pam.pam_end(handle, status)
        return status == 0


if __name__ == '__main__':
    unittest.main()
