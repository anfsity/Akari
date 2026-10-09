"""Deploy Akari and switch the boot login service without stopping a desktop.

The display-manager snapshot belongs to one enable/disable cycle. It is saved
before systemd changes, and retained on failure so recovery works without the
repository or Dart SDK. Release switches affect only the next greeter launch.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile


INSTALLATION = Path('/opt/akari')
CONFIGURATION = Path('/etc/akari')
STATE = Path('/var/lib/akari')
LOGS = Path('/var/log/akari/greeter')
UNIT = Path('/etc/systemd/system/akari.service')
DISPLAY_MANAGER = UNIT.with_name('display-manager.service')
LOCK = Path('/run/lock/akari-login.lock')
PAM = Path('/etc/pam.d/greetd')
GREETER = 'akari-greeter'
SNAPSHOT = STATE / 'display-manager.json'


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
    for command in ['systemctl', 'dbus-run-session', 'busctl', 'swaymsg',
                    'python3', 'bash', 'useradd', 'nologin']:
        if shutil.which(command) is None:
            raise ValueError(f'Missing required command: {command}')
    for binary in [Path('/usr/bin/greetd'), Path('/usr/bin/sway')]:
        if not os.access(binary, os.X_OK):
            raise ValueError(f'Missing executable: {binary}')
    if not PAM.is_file():
        raise ValueError(f'Missing PAM configuration: {PAM}; install greetd first.')


def create_installation(source, bundle, backend, layout):
    validate_runtime()
    for executable in [bundle / 'greeter', backend]:
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError(f'Missing built executable: {executable}')
    managed = (INSTALLATION / 'installation.json').is_file()
    if not managed and any(path.exists() for path in [INSTALLATION, CONFIGURATION, UNIT]):
        raise ValueError('Installation would replace existing unmanaged Akari files.')

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
        for name in ['launch.sh', 'run-greeter.sh']:
            shutil.copy2(source / 'scripts/login' / name, release / name)
            (release / name).chmod(0o755)
        (release / 'scripts').mkdir()
        # Reuse the tested D-Bus and output-layout implementations. The test
        # lifecycle remains entirely separate from this deployment.
        for name in ['debug-dbus.sh', 'lib.sh']:
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
        update_link(current, release)
        controller = INSTALLATION / '.manage.py'
        shutil.copy2(source / 'scripts/login/manage.py', controller)
        controller.chmod(0o644)
        controller.replace(INSTALLATION / 'manage.py')
        write_json(INSTALLATION / 'installation.json', {'schema_version': 1})
        if previous is not None:
            update_link(INSTALLATION / 'previous', previous)
    except Exception:
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
    print('Run akari login enable to select Akari for the next boot.')


def restore_display_manager(snapshot):
    run_systemctl('disable', UNIT.name)
    target = snapshot['target']
    if target is None:
        return
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


def remove_installation():
    validate_installation()
    active = run_systemctl('show', '--property=ActiveState', '--value', UNIT.name)
    if active not in ['inactive', 'failed']:
        raise ValueError('Akari is running. Disable it and reboot before uninstalling.')
    disable_login()
    UNIT.unlink()
    run_systemctl('daemon-reload')
    shutil.rmtree(CONFIGURATION)
    shutil.rmtree(INSTALLATION)
    print('Akari uninstalled. Greeter account, preferences and logs were retained.')


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    install = commands.add_parser('install')
    for name in ['source', 'bundle', 'backend']:
        install.add_argument(f'--{name}', required=True, type=Path)
    install.add_argument('--layout', type=Path)
    for name in ['enable', 'disable', 'rollback', 'uninstall']:
        commands.add_parser(name)
    status = commands.add_parser('status')
    status.add_argument('--format', choices=['text', 'json'], default='text')
    logs = commands.add_parser('logs')
    logs.add_argument('--component', choices=['service', 'backend', 'flutter', 'sway'], default='service')
    logs.add_argument('--lines', type=int, default=100)
    logs.add_argument('--follow', action='store_true')
    arguments = parser.parse_args()
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
    with LOCK.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if arguments.command == 'install':
            create_installation(arguments.source, arguments.bundle, arguments.backend, arguments.layout)
        elif arguments.command == 'enable':
            enable_login()
        elif arguments.command == 'disable':
            disable_login()
        elif arguments.command == 'rollback':
            rollback_installation()
        else:
            remove_installation()
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
