"""Deploy Akari and switch the boot login service without stopping a desktop.

The display-manager snapshot belongs to one enable/disable cycle. It is saved
before systemd changes, and retained on failure so recovery works without the
repository or Dart SDK. Release switches affect only the next greeter launch.
"""

import argparse
from contextlib import ExitStack
import fcntl
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import subprocess
import sys
import tempfile


INSTALLATION = Path('/opt/akari')
TEST_INSTALLATION = Path('/opt/akari-test')
CONFIGURATION = Path('/etc/akari')
STATE = Path('/var/lib/akari')
LOGS = Path('/var/log/akari/greeter')
UNIT = Path('/etc/systemd/system/akari.service')
DISPLAY_MANAGER = UNIT.with_name('display-manager.service')
LOCK = Path('/run/lock/akari-login.lock')
TEST_LOCK = Path('/run/lock/akari-test.lock')
PAM = Path('/etc/pam.d/greetd')
GREETER = 'akari-greeter'
SNAPSHOT = STATE / 'display-manager.json'
KEYRINGS = {
    'gnome': ('GNOME Keyring', 'pam_gnome_keyring.so', 'use_authtok', 'auto_start'),
    'kwallet': ('KWallet', 'pam_kwallet5.so', '', 'auto_start force_run'),
}
PAM_MODULE_ROOTS = [Path(path) for path in ['/usr/lib', '/usr/lib64', '/lib', '/lib64']]
KEYRING_START = '\n# BEGIN Akari keyring\n'
KEYRING_END = '# END Akari keyring\n'
GAZE_SERVICE = 'akari-gaze'
GAZE_PAM = '''#%PAM-1.0
# Managed by Akari: face authentication with the distribution password fallback.
auth       requisite                    pam_shells.so
auth       requisite                    pam_faillock.so preauth
auth       [success=ignore default=3]    pam_gaze.so
auth       requisite                    pam_env.so
auth       requisite                    pam_faillock.so authsucc
auth       sufficient                   pam_permit.so
auth       include                      system-local-login
'''
ARCH_AUTH_RULES = {
    'system-local-login': ['auth include system-login'],
    'system-login': [
        'auth required pam_shells.so',
        'auth requisite pam_nologin.so',
        'auth include system-auth',
    ],
    'system-auth': [
        'auth required pam_faillock.so preauth',
        '-auth [success=2 default=ignore] pam_systemd_home.so',
        'auth [success=1 default=bad] pam_unix.so try_first_pass nullok',
        'auth [default=die] pam_faillock.so authfail',
        'auth optional pam_permit.so',
        'auth required pam_env.so',
        'auth required pam_faillock.so authsucc',
    ],
}


def find_pam_module(module):
    directories = []
    for root in PAM_MODULE_ROOTS:
        directories.append(root / 'security')
        directories.extend(root.glob('*-linux-gnu/security'))
    return next((directory / module for directory in directories
                 if (directory / module).is_file()), None)


def get_installed_keyrings():
    return [name for name, (_, module, _, _) in KEYRINGS.items()
            if find_pam_module(module) is not None]


def get_keyring_install_command(provider):
    distribution = platform.freedesktop_os_release()
    families = [distribution['ID'], *distribution.get('ID_LIKE', '').split()]
    for family in families:
        if family == 'arch':
            return ['pacman', '-S', '--needed',
                    'gnome-keyring' if provider == 'gnome' else 'kwallet-pam']
        if family in ['debian', 'ubuntu']:
            return ['apt-get', 'install', *(['gnome-keyring', 'libpam-gnome-keyring']
                    if provider == 'gnome' else ['libpam-kwallet5'])]
        if family == 'fedora':
            return ['dnf', 'install', *(['gnome-keyring', 'gnome-keyring-pam']
                    if provider == 'gnome' else ['pam-kwallet'])]
    raise ValueError('Automatic keyring installation supports Arch, Debian/Ubuntu and Fedora; '
                     'install the keyring PAM package manually and rerun akari install.')


def select_keyrings(provider):
    if provider == 'none':
        return []
    installed = get_installed_keyrings()
    if provider == 'auto' and installed:
        return installed
    if provider in installed:
        return [provider]
    # Never infer package-install consent from a pipe or unattended invocation.
    if not sys.stdin.isatty():
        if provider != 'auto':
            raise ValueError(f'{KEYRINGS[provider][0]} PAM module is missing; '
                             'install it manually or rerun in a terminal to approve installation.')
        print('No supported keyring PAM module found; skipping keyring setup (no terminal).')
        return []
    if provider == 'auto':
        while True:
            choice = input('No keyring PAM module found. Install GNOME Keyring [g], '
                           'KWallet [k], or skip [N]? ').strip().lower()
            if choice in ['', 'n', 'no']:
                return []
            if choice in ['g', 'gnome', 'k', 'kwallet']:
                provider = 'gnome' if choice in ['g', 'gnome'] else 'kwallet'
                break
    elif input(f'{KEYRINGS[provider][0]} PAM module is missing. Install it? [y/N] ').strip().lower() not in ['y', 'yes']:
        return []
    subprocess.run(get_keyring_install_command(provider), check=True)
    if provider not in get_installed_keyrings():
        raise ValueError(f'Package installation did not provide {KEYRINGS[provider][1]}; '
                         'PAM configuration was not changed.')
    return [provider]


def get_pam_without_keyring(configuration):
    if KEYRING_START.strip() not in configuration and KEYRING_END.strip() not in configuration:
        return configuration
    if configuration.count(KEYRING_START) != 1 or configuration.count(KEYRING_END) != 1:
        raise ValueError(f'Malformed Akari keyring block in {PAM}; repair it before continuing.')
    start = configuration.index(KEYRING_START)
    end = configuration.index(KEYRING_END)
    if end < start:
        raise ValueError(f'Malformed Akari keyring block in {PAM}; repair it before continuing.')
    return configuration[:start] + configuration[end + len(KEYRING_END):]


def get_pam_modules(configuration, phase, ancestors):
    modules = set()
    for line in configuration.splitlines():
        line = line.split('#', 1)[0].strip()
        include = re.fullmatch(r'@include\s+(\S+)', line)
        if include is not None:
            included = include[1]
        else:
            match = re.fullmatch(r'-?(auth|account|password|session)\s+(\[[^]]+\]|\S+)\s+(\S+)(?:\s+.*)?', line)
            if match is None or match[1] != phase:
                continue
            if match[2] not in ['include', 'substack']:
                modules.add(Path(match[3]).name)
                continue
            included = match[3]
        path = PAM.parent / included
        if path in ancestors:
            continue
        modules.update(get_pam_modules(path.read_text(), phase, ancestors | {path}))
    return modules


def get_keyring_pam_configuration(configuration, providers):
    configuration = get_pam_without_keyring(configuration)
    if not providers:
        return configuration
    lines = []
    for phase in ['auth', 'session']:
        modules = get_pam_modules(configuration, phase, {PAM})
        for provider in providers:
            _, module, auth_options, session_options = KEYRINGS[provider]
            if module not in modules:
                options = auth_options if phase == 'auth' else session_options
                lines.append(f'{phase:<10} optional     {module} {options}'.rstrip() + '\n')
    if not lines:
        return configuration
    # PAM evaluates each phase separately. Appending keeps the distribution's
    # authentication and session setup before password capture / daemon startup.
    return configuration + KEYRING_START + ''.join(lines) + KEYRING_END


def update_pam(configuration, backup_name='greetd.pam.before-keyring'):
    if configuration == PAM.read_text():
        return
    STATE.mkdir(parents=True, exist_ok=True)
    backup = STATE / backup_name
    if not backup.exists():
        shutil.copy2(PAM, backup)
    write_pam_file(PAM, configuration)


def write_pam_file(path, configuration):
    # Resolve distribution-managed symlinks and retain existing metadata. A new
    # helper is published before greetd refers to it, with normal PAM permissions.
    target = path.resolve()
    descriptor, name = tempfile.mkstemp(prefix='.greetd-', dir=target.parent)
    os.close(descriptor)
    temporary = Path(name)
    try:
        if target.exists():
            shutil.copy2(target, temporary)
            owner = target.stat()
            os.chown(temporary, owner.st_uid, owner.st_gid)
        else:
            temporary.chmod(0o644)
        temporary.write_text(configuration)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def get_auth_rules(configuration):
    rules = []
    for line in configuration.splitlines():
        line = line.split('#', 1)[0].strip()
        if re.match(r'-?auth\b|@include\b', line, re.IGNORECASE):
            rules.append(' '.join(line.split()))
    return rules


def validate_gaze_pam(configuration):
    # A face match bypasses the password include. Accept only the known Arch
    # auth policy so custom MFA or other requirements cannot be bypassed with it.
    for service, expected in ARCH_AUTH_RULES.items():
        path = PAM.with_name(service)
        if not path.is_file() or get_auth_rules(path.read_text()) != expected:
            raise ValueError(f'Unsupported auth policy in {path}; configure Gaze manually without bypassing custom authentication rules.')
    rules = get_auth_rules(configuration)
    if (rules[:2] != ['auth required pam_securetty.so', 'auth requisite pam_nologin.so']
            or len(rules) < 3
            or rules[2] not in ['auth include system-local-login', f'auth substack {GAZE_SERVICE}']
            or any(not re.fullmatch(r'-?auth optional .+', line) for line in rules[3:])):
        raise ValueError(f'Unsupported auth policy in {PAM}; expected the stock Arch greetd stack with optional auth hooks after it.')
    if find_pam_module('pam_gaze.so') is None:
        raise ValueError('pam_gaze.so is missing; install and verify Gaze before enabling it for greetd.')
    helper = PAM.with_name(GAZE_SERVICE)
    if helper.is_symlink() or (helper.exists() and helper.read_text() != GAZE_PAM):
        raise ValueError(f'{helper} contains a custom policy; refusing to replace it.')
    if 'pam_gaze.so' in get_pam_modules('\n'.join(rules[3:]), 'auth', {PAM}):
        raise ValueError('Gaze is already configured in the auth stack; refusing to add another invocation.')


def get_gaze_pam_configuration(configuration, *, enabled):
    source_control, source_service = ('include', 'system-local-login') if enabled else ('substack', GAZE_SERVICE)
    target_control, target_service = ('substack', GAZE_SERVICE) if enabled else ('include', 'system-local-login')
    return re.sub(
        rf'(?m)^([ \t]*auth[ \t]+){source_control}([ \t]+){source_service}(?=[ \t]*(?:#|$))',
        rf'\g<1>{target_control}\g<2>{target_service}', configuration)


def enable_gaze():
    configuration = PAM.read_text()
    validate_gaze_pam(configuration)
    helper = PAM.with_name(GAZE_SERVICE)
    created = not helper.exists()
    if created:
        write_pam_file(helper, GAZE_PAM)
    try:
        update_pam(get_gaze_pam_configuration(configuration, enabled=True), 'greetd.pam.before-gaze')
    except Exception:
        if created:
            helper.unlink()
        raise
    print('Gaze enabled for greetd with password fallback. Existing login sessions keep running.')


def remove_gaze_helper():
    helper = PAM.with_name(GAZE_SERVICE)
    if not helper.is_symlink() and helper.exists() and helper.read_text() == GAZE_PAM:
        helper.unlink()


def disable_gaze():
    update_pam(get_gaze_pam_configuration(PAM.read_text(), enabled=False), 'greetd.pam.before-gaze')
    remove_gaze_helper()
    print('Gaze disabled for greetd. Other PAM rules and backups were retained.')


def run_systemctl(*arguments):
    return subprocess.run(['systemctl', *arguments], check=True,
                          text=True, capture_output=True).stdout.strip()


def write_json(path, value):
    temporary = path.with_name(f'.{path.name}-{os.getpid()}')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.chmod(0o644)
    temporary.replace(path)


def update_link(path, target):
    temporary = path.with_name(f'.{path.name}-{os.getpid()}')
    temporary.symlink_to(target)
    temporary.replace(path)


def get_display_manager_target():
    if DISPLAY_MANAGER.is_symlink():
        return os.readlink(DISPLAY_MANAGER)
    if DISPLAY_MANAGER.exists():
        raise ValueError(f'{DISPLAY_MANAGER} must be a symlink.')
    return None


def is_akari_target(target):
    return target is not None and Path(target).name == UNIT.name


def validate_installation():
    if not (INSTALLATION / 'installation.json').is_file():
        raise ValueError('Akari is not installed; run akari install first.')


def validate_runtime():
    for command in ['systemctl', 'dbus-daemon', 'busctl', 'setpriv', 'swaymsg', 'swaybg',
                    'python3', 'bash', 'useradd', 'nologin']:
        if shutil.which(command) is None:
            raise ValueError(f'Missing required command: {command}')
    for binary in [Path('/usr/bin/greetd'), Path('/usr/bin/sway')]:
        if not os.access(binary, os.X_OK):
            raise ValueError(f'Missing executable: {binary}')
    if not PAM.is_file():
        raise ValueError(f'Missing PAM configuration: {PAM}; install greetd first.')


def create_installation(source, bundle, backend, splash, layout, keyring='auto'):
    validate_runtime()
    for executable in [bundle / 'greeter', backend, splash]:
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError(f'Missing built executable: {executable}')
    managed = (INSTALLATION / 'installation.json').is_file()
    if not managed and any(path.exists() for path in [INSTALLATION, CONFIGURATION, UNIT]):
        raise ValueError('Installation would replace existing unmanaged Akari files.')
    providers = select_keyrings(keyring)
    previous_pam = PAM.read_text()
    keyring_pam = get_keyring_pam_configuration(previous_pam, providers)

    try:
        greeter = pwd.getpwnam(GREETER)
    except KeyError:
        subprocess.run(['useradd', '--system', '--user-group', '--home-dir',
                        str(STATE / 'greeter'), '--shell', shutil.which('nologin'),
                        GREETER], check=True)
        greeter = pwd.getpwnam(GREETER)
    if greeter.pw_uid == 0:
        raise ValueError('The greeter account must be unprivileged.')
    for directory in [STATE, LOGS.parent, CONFIGURATION, INSTALLATION, INSTALLATION / 'releases']:
        directory.mkdir(parents=True, exist_ok=True)
        directory.chmod(0o755)
    for directory in [STATE / 'greeter', LOGS]:
        directory.mkdir(parents=True, exist_ok=True)
        directory.chmod(0o755)
        os.chown(directory, greeter.pw_uid, greeter.pw_gid)

    release = Path(tempfile.mkdtemp(prefix='release-', dir=INSTALLATION / 'releases'))
    release.chmod(0o755)
    current = INSTALLATION / 'current'
    previous = os.readlink(current) if current.is_symlink() else None
    previous_unit = UNIT.read_bytes() if UNIT.exists() else None
    created_configs = []
    try:
        shutil.copytree(bundle, release / 'frontend')
        shutil.copy2(backend, release / 'backend')
        shutil.copy2(splash, release / 'akari-splash')
        for name in ['launch.sh', 'run-greeter.sh']:
            shutil.copy2(source / 'scripts/login' / name, release / name)
            (release / name).chmod(0o755)
        (release / 'scripts').mkdir()
        # Reuse the tested D-Bus and output-layout implementations. The test
        # lifecycle remains entirely separate from this deployment.
        for name in ['debug-dbus.sh', 'lib.sh', 'splash.sh']:
            shutil.copy2(source / 'scripts' / name, release / 'scripts' / name)
        for name in ['display-layout.py', 'display_profile.py']:
            shutil.copy2(source / 'scripts/greetd-test' / name, release / name)
        # Developer umasks must not make the installed bundle unreadable to
        # the separate greeter account.
        for path in release.rglob('*'):
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
        for name in ['greetd.toml', 'sway.conf']:
            target = CONFIGURATION / name
            if not target.exists():
                shutil.copy2(source / 'scripts/login' / name, target)
                target.chmod(0o644)
                created_configs.append(target)
        if layout is not None and not (CONFIGURATION / 'display-layout.json').exists():
            target = CONFIGURATION / 'display-layout.json'
            shutil.copy2(layout, target)
            target.chmod(0o644)
            created_configs.append(target)
        shutil.copy2(source / 'scripts/login/akari.service', UNIT)
        UNIT.chmod(0o644)
        run_systemctl('daemon-reload')
        update_pam(keyring_pam)
        update_link(current, release)
        controller = INSTALLATION / '.manage.py'
        shutil.copy2(source / 'scripts/login/manage.py', controller)
        controller.chmod(0o644)
        controller.replace(INSTALLATION / 'manage.py')
        write_json(INSTALLATION / 'installation.json', {'schema_version': 1})
        if previous is not None:
            update_link(INSTALLATION / 'previous', previous)
    except Exception:
        update_pam(previous_pam)
        if previous is not None:
            update_link(current, previous)
        else:
            current.unlink(missing_ok=True)
        if previous_unit is not None:
            UNIT.write_bytes(previous_unit)
        else:
            UNIT.unlink(missing_ok=True)
        for target in created_configs:
            target.unlink(missing_ok=True)
        shutil.rmtree(release)
        if not managed:
            shutil.rmtree(INSTALLATION)
            CONFIGURATION.rmdir()
        run_systemctl('daemon-reload')
        raise
    print(f'Installed release: {release}')
    print(f'Keyring PAM: {", ".join(providers) or "none"}')
    print('Run akari login enable to select Akari for the next boot.')


def restore_display_manager(snapshot):
    if UNIT.exists():
        run_systemctl('disable', UNIT.name)
    elif is_akari_target(get_display_manager_target()):
        # Partial removal can leave a dangling alias. systemctl cannot disable
        # a missing unit, but recovery must still restore the saved selection.
        DISPLAY_MANAGER.unlink()
    target = snapshot['target']
    if target is not None:
        if snapshot['enabled']:
            run_systemctl('enable', '--force', Path(target).name)
        update_link(DISPLAY_MANAGER, target)
    run_systemctl('daemon-reload')


def enable_login():
    validate_installation()
    if run_systemctl('get-default') != 'graphical.target':
        raise ValueError('The default target must be graphical.target before enabling Akari.')
    target = get_display_manager_target()
    if is_akari_target(target):
        print('Akari is already selected for the next boot.')
        return
    if SNAPSHOT.exists():
        raise ValueError('An unfinished switch exists; run akari login disable to recover first.')
    enabled = False
    if target is not None:
        result = subprocess.run(['systemctl', 'is-enabled', Path(target).name],
                                text=True, capture_output=True)
        state = result.stdout.strip()
        if state not in ['enabled', 'disabled', 'static', 'linked']:
            raise ValueError(f'Unsupported previous service state: {state or result.stderr.strip()}')
        enabled = state == 'enabled'
    snapshot = {'target': target, 'enabled': enabled}
    write_json(SNAPSHOT, snapshot)
    try:
        if enabled:
            run_systemctl('disable', Path(target).name)
        run_systemctl('enable', '--force', UNIT.name)
    except Exception:
        restore_display_manager(snapshot)
        SNAPSHOT.unlink()
        raise
    print('Akari selected for the next boot. The current desktop is still running.')


def disable_login():
    validate_installation()
    restore_login_selection()


def restore_login_selection():
    target = get_display_manager_target()
    if not SNAPSHOT.exists():
        if is_akari_target(target):
            raise ValueError('The previous display-manager snapshot is missing.')
        print('Akari is not selected for boot.')
        return
    snapshot = json.loads(SNAPSHOT.read_text())
    if target is not None and not is_akari_target(target) and target != snapshot['target']:
        raise ValueError('Another display manager was selected; refusing to replace it.')
    restore_display_manager(snapshot)
    SNAPSHOT.unlink()
    print('Previous login service restored for the next boot. The current desktop is still running.')


def rollback_installation():
    validate_installation()
    previous = INSTALLATION / 'previous'
    if not previous.is_symlink():
        raise ValueError('No previous release is available.')
    current = INSTALLATION / 'current'
    old_current = os.readlink(current)
    update_link(current, os.readlink(previous))
    update_link(previous, old_current)
    print(f'Next greeter launch will use {current.resolve()}.')


def validate_inactive_units(units):
    for unit in units:
        result = subprocess.run(['systemctl', 'show', '--property=ActiveState', '--value', unit],
                                text=True, capture_output=True)
        # Missing units report inactive with a nonzero exit code. A failed bus
        # connection supplies no state and must not be treated as safe to clean.
        active = result.stdout.strip()
        if result.returncode != 0 and not active:
            raise subprocess.CalledProcessError(result.returncode, result.args, stderr=result.stderr)
        if active not in ['inactive', 'failed']:
            recovery = ('Run akari login disable and reboot first.' if unit == UNIT.name
                        else 'Run akari greetd-test restore first.')
            raise ValueError(f'{unit} is running ({active}). {recovery}')


def remove_registered_paths(paths):
    for path in paths:
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)


def remove_login_files():
    configuration = get_pam_without_keyring(get_gaze_pam_configuration(PAM.read_text(), enabled=False)) if PAM.exists() else None
    restore_login_selection()
    if configuration is not None:
        update_pam(configuration)
    remove_gaze_helper()
    UNIT.unlink(missing_ok=True)
    run_systemctl('daemon-reload')
    remove_registered_paths([CONFIGURATION, INSTALLATION])


def remove_installation(scope='login'):
    # Validate the entire selected scope before removing recovery resources.
    # Test-only removal must not alter production PAM or boot selection.
    units = [UNIT.name] if scope in ['login', 'all'] else []
    if scope in ['test', 'all']:
        units += ['akari-test.service', 'akari-restore.service', 'akari-restore.timer']
    validate_inactive_units(units)
    if scope in ['login', 'all']:
        remove_login_files()
    if scope in ['test', 'all']:
        remove_registered_paths([TEST_INSTALLATION])
    print(f'Akari {scope} installation resources removed. Greeter accounts, preferences, logs and CLI launcher were retained.')


def get_status():
    result = subprocess.run(['systemctl', 'show', '--no-pager',
                             '--property=Id,LoadState,ActiveState,SubState,Result',
                             UNIT.name, 'display-manager.service'], text=True, capture_output=True)
    # A missing unit still has properties; a failed bus connection does not.
    if result.returncode != 0 and not result.stdout.strip():
        raise subprocess.CalledProcessError(result.returncode, result.args, stderr=result.stderr)
    units = result.stdout.strip()
    return {
        'installed': (INSTALLATION / 'installation.json').is_file(),
        'release': str((INSTALLATION / 'current').resolve()) if (INSTALLATION / 'current').exists() else None,
        'display_manager': get_display_manager_target(),
        'recovery_pending': SNAPSHOT.exists(),
        'log_directory': str(LOGS),
        'units': [dict(line.split('=', 1) for line in block.splitlines() if '=' in line)
                  for block in units.split('\n\n') if block],
    }


def show_logs(component, lines, follow):
    if component == 'service':
        command = ['journalctl', '--no-pager', '-u', UNIT.name, '-n', str(lines)]
        if follow:
            command.append('-f')
    else:
        sessions = sorted(LOGS.glob('session-*'), key=lambda path: path.stat().st_mtime)
        if not sessions:
            raise ValueError(f'No greeter logs found in {LOGS}.')
        command = ['tail', '-n', str(lines)]
        if follow:
            command.append('-F')
        command.extend(['--', str(sessions[-1] / f'{component}.log')])
    return subprocess.call(command)


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    install = commands.add_parser('install')
    for name in ['source', 'bundle', 'backend', 'splash']:
        install.add_argument(f'--{name}', required=True, type=Path)
    install.add_argument('--layout', type=Path)
    keyring_options = ['auto', *KEYRINGS, 'none']
    install.add_argument('--keyring', choices=keyring_options, default='auto')
    keyring = commands.add_parser('configure-keyring', help='Configure greetd keyring PAM without rebuilding Akari.')
    keyring.add_argument('--keyring', choices=keyring_options, default='auto')
    uninstall = commands.add_parser('uninstall')
    uninstall.add_argument('--scope', choices=['login', 'test', 'all'], default='login')
    for name in ['enable', 'disable', 'rollback', 'enable-gaze', 'disable-gaze']:
        commands.add_parser(name)
    status = commands.add_parser('status')
    status.add_argument('--format', choices=['text', 'json'], default='text')
    logs = commands.add_parser('logs')
    logs.add_argument('--component', choices=['service', 'backend', 'flutter', 'sway'], default='service')
    logs.add_argument('--lines', type=int, default=100)
    logs.add_argument('--follow', action='store_true')
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    if arguments.command == 'status':
        result = get_status()
        if arguments.format == 'json':
            print(json.dumps(result))
        else:
            print(f"Installed: {result['installed']}\nRelease: {result['release']}\n"
                  f"Boot login: {result['display_manager']}\nRecovery pending: {result['recovery_pending']}\n"
                  f"Greeter logs: {result['log_directory']}")
            for unit in result['units']:
                print(f"{unit['Id']}: {unit['LoadState']}, {unit['ActiveState']}/{unit['SubState']}")
        return 0
    if arguments.command == 'logs':
        if arguments.lines < 1:
            raise ValueError('--lines must be a positive integer.')
        return show_logs(arguments.component, arguments.lines, arguments.follow)
    if os.geteuid() != 0:
        raise ValueError('This operation requires root; invoke it through akari or sudo python3.')
    lock_paths = [LOCK]
    if arguments.command == 'uninstall':
        lock_paths = {'login': [LOCK], 'test': [TEST_LOCK], 'all': [LOCK, TEST_LOCK]}[arguments.scope]
    with ExitStack() as resources:
        for path in lock_paths:
            lock = resources.enter_context(path.open('a'))
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if path == TEST_LOCK else 0))
            except BlockingIOError:
                raise ValueError('Another test setup is running; retry uninstall after it finishes.') from None
        match arguments.command:
            case 'install':
                create_installation(arguments.source, arguments.bundle, arguments.backend, arguments.splash, arguments.layout, arguments.keyring)
            case 'configure-keyring':
                providers = select_keyrings(arguments.keyring)
                update_pam(get_keyring_pam_configuration(PAM.read_text(), providers))
                print(f'Configured greetd keyring PAM: {", ".join(providers) or "none"}')
            case 'enable-gaze':
                enable_gaze()
            case 'disable-gaze':
                disable_gaze()
            case 'enable':
                enable_login()
            case 'disable':
                disable_login()
            case 'rollback':
                rollback_installation()
            case 'uninstall':
                remove_installation(arguments.scope)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(error.stderr or str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError) as error:
        print(f'Akari login: {error}', file=sys.stderr)
        sys.exit(1)
