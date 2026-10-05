"""Own one nested/headless compositor, its output checks and theme session.

The CLI prepares the theme. Its session command starts the private bus inside
this process's owned child group. Output checks continue because an
outer window resize can change the adopted mode after successful startup.
"""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / 'greetd-test'))
from display_profile import (get_outputs, get_virtual_outputs, get_output_commands,
                             get_output_differences, write_json_atomic)


def stop_process(process):
    if process is None:
        return
    # A leader may already have exited while descendants still own its pipes.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    # Reap the whole owned group, including descendants whose leader exited.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def get_sway_reply(environment, *arguments):
    return json.loads(subprocess.check_output(
        ['swaymsg', '-r', *arguments], env=environment, timeout=5))


def get_hyprland_targets(environment, pid, target, actual):
    monitors = {monitor['id']: monitor for monitor in json.loads(subprocess.check_output(
        ['hyprctl', '-j', 'monitors'], env=environment, timeout=5))}
    clients = json.loads(subprocess.check_output(
        ['hyprctl', '-j', 'clients'], env=environment, timeout=5))
    owned = {}
    for client in clients:
        if client['pid'] == pid:
            owned[client['title'].rsplit(' - ', 1)[-1]] = client
    actual_by_name = {output['name']: output for output in actual}
    if any(output['name'] not in owned or output['name'] not in actual_by_name
           for output in target):
        return None
    effective = []
    for output in target:
        name = output['name']
        monitor = monitors[owned[name]['monitor']]
        host_scale = monitor['scale']
        if type(host_scale) not in [int, float] or not math.isfinite(host_scale) or host_scale <= 0:
            raise ValueError(f'Invalid Hyprland monitor scale: {monitor["name"]}')
        # The Wayland backend receives the outer window's logical dimensions.
        # Compensating the host scale restores TTY sizing when fullscreen;
        # tiling only changes the viewport, never the intended content scale.
        adopted = actual_by_name[name]
        expected = dict(output, mode=adopted['mode'],
                        scale=output['scale'] / host_scale,
                        host_monitor=monitor['name'], host_scale=host_scale)
        expected['rect'] = dict(output['rect'], width=adopted['rect']['width'],
                                height=adopted['rect']['height'])
        effective.append(expected)
    return effective


def update_output_scales(environment, target, actual):
    actual_by_name = {output['name']: output for output in actual}
    commands = [f'output {json.dumps(output["name"])} scale {output["scale"]}'
                for output in target
                if not math.isclose(output['scale'], actual_by_name[output['name']]['scale'], abs_tol=1e-6)]
    if commands:
        results = get_sway_reply(environment, '; '.join(commands))
        if not all(result['success'] for result in results):
            raise RuntimeError(f'Could not apply nested output scales: {results}')
    return bool(commands)


def get_greeter_outputs(tree):
    found = set()

    def collect(node, output=None):
        if node['type'] == 'output':
            output = node['name']
        if node.get('app_id') == 'dev.akari.greeter':
            found.add(output)
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            collect(child, output)

    collect(tree)
    return found


def start_session(directory, backend, command):
    profile = json.loads(os.environ['AKARI_DISPLAY_PROFILE_JSON'])
    target = get_virtual_outputs(profile, backend)
    parent_environment = dict(os.environ)
    hyprland = (backend == 'wayland' and not parent_environment.get('SWAYSOCK')
                and bool(parent_environment.get('HYPRLAND_INSTANCE_SIGNATURE')))
    runtime = directory / 'runtime'
    screenshots = directory / 'screenshots'
    directory.mkdir(parents=True, exist_ok=True)
    screenshots.mkdir()
    config = directory / 'sway.conf'
    base = Path(__file__).resolve().parents[1] / 'config/sway/debug.conf'
    config.write_text(base.read_text() + '\n' + '\n'.join(
        get_output_commands(target, configure_mode=not hyprland)) + '\n')
    report = {'source': profile['source'], 'custom': profile['custom'],
              'selection': profile['selection'], 'backend': backend,
              'geometry': 'compositor' if hyprland else 'fixed',
              'target': target, 'actual': [], 'matched': False,
              'screenshots': [], 'log_directory': str(directory), 'checks': []}
    report_path = directory / 'display-report.json'
    environment = dict(parent_environment)
    outer_display = environment.get('WAYLAND_DISPLAY')
    outer_runtime = environment.get('XDG_RUNTIME_DIR')
    for key in ['DISPLAY', 'SWAYSOCK', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET',
                'WLR_WAYLAND_DISPLAY', 'AKARI_DISPLAY_SOURCE', 'AKARI_TEST_RUN']:
        environment.pop(key, None)
    environment.update(XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS=backend,
                       GDK_BACKEND='wayland', XDG_CURRENT_DESKTOP='Sway',
                       XDG_SESSION_DESKTOP='sway', XDG_SESSION_TYPE='wayland',
                       AKARI_WINDOW_MODE='fullscreen', AKARI_DISPLAY_MODE='mirror')
    if backend == 'wayland':
        if not outer_display or (not Path(outer_display).is_absolute() and not outer_runtime):
            raise ValueError('Run nested Sway from a Wayland desktop, or select --sway-backend headless.')
        environment['WAYLAND_DISPLAY'] = str(
            Path(outer_display) if Path(outer_display).is_absolute() else Path(outer_runtime) / outer_display)
        environment['WLR_WL_OUTPUTS'] = str(len(target))
    else:
        environment.update(WLR_HEADLESS_OUTPUTS=str(len(target)), WLR_RENDERER='gles2',
                           WLR_RENDERER_ALLOW_SOFTWARE='1', LIBGL_ALWAYS_SOFTWARE='1')
    sway = app = None
    output_thread = None
    sway_log = app_log = None
    interrupted = 0

    def handle_signal(signum, frame):
        nonlocal interrupted
        interrupted = 128 + signum

    handlers = {signum: signal.signal(signum, handle_signal)
                for signum in [signal.SIGINT, signal.SIGTERM]}

    def update_report(expected, actual, stage):
        differences = get_output_differences(expected, actual)
        report.update(effective_target=expected, actual=actual, matched=not differences)
        report['checks'].append({'stage': stage, 'differences': differences})
        write_json_atomic(report_path, report, mode=0o644)
        print(f'Actual outputs ({stage}): {json.dumps(actual)}', flush=True)
        if differences:
            raise RuntimeError('Requested and actual Sway outputs differ: ' + '; '.join(differences))

    print(f'Display source: {profile["source"]["kind"]}'
          f'{" (user overrides)" if profile["custom"] else ""}\n'
          f'Target outputs: {json.dumps(target)}\n'
          f'Sway logs: {directory}\nInner screenshots: {screenshots}', flush=True)
    runtime.mkdir(mode=0o700)
    try:
        for executable in ['sway', 'swaymsg', 'grim']:
            if shutil.which(executable) is None:
                raise ValueError(f'{executable} is required for Sway testing.')
        sway_log = (directory / 'sway.log').open('w')
        app_log = (directory / 'flutter.log').open('wb')
        sway = subprocess.Popen(['sway', '--unsupported-gpu', '-c', str(config)],
                                env=environment, stdout=sway_log, stderr=subprocess.STDOUT,
                                start_new_session=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not interrupted:
            sockets = list(runtime.glob('sway-ipc.*.sock'))
            waylands = [path for path in runtime.glob('wayland-*') if path.is_socket()]
            if sockets and waylands:
                environment.update(SWAYSOCK=str(sockets[0]), WAYLAND_DISPLAY=waylands[0].name)
                break
            if sway.poll() is not None:
                raise RuntimeError(f'Sway exited before startup; see {directory / "sway.log"}.')
            time.sleep(.1)
        else:
            if interrupted:
                return interrupted
            raise RuntimeError('Timed out waiting for inner Sway sockets.')
        # Wait for mapping and output configuration before launching the theme.
        deadline = time.monotonic() + 3
        while True:
            raw = get_sway_reply(environment, '-t', 'get_outputs')
            actual = get_outputs(raw)
            expected = (get_hyprland_targets(parent_environment, sway.pid, target, actual)
                        if hyprland else target)
            if expected is not None and hyprland:
                update_output_scales(environment, expected, actual)
            if ((expected is not None and not get_output_differences(expected, actual))
                    or time.monotonic() >= deadline):
                break
            if interrupted:
                return interrupted
            time.sleep(.1)
        write_json_atomic(directory / 'outputs.json', raw, mode=0o644)
        if expected is None:
            raise RuntimeError('Timed out waiting for owned Hyprland output windows.')
        update_report(expected, actual, 'startup')
        app = subprocess.Popen(command, env=environment, stdin=sys.stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True)
        def copy_app_output():
            for chunk in iter(lambda: app.stdout.read1(65536), b''):
                app_log.write(chunk)
                app_log.flush()
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
        output_thread = threading.Thread(target=copy_app_output)
        output_thread.start()
        ready_at = None
        while app.poll() is None and not interrupted:
            if sway.poll() is not None:
                raise RuntimeError('Sway exited while the theme was running.')
            raw = get_sway_reply(environment, '-t', 'get_outputs')
            current = get_outputs(raw)
            expected = (get_hyprland_targets(parent_environment, sway.pid, target, current)
                        if hyprland else target)
            if expected is None:
                raise RuntimeError('Owned Hyprland output windows disappeared.')
            if hyprland and update_output_scales(environment, expected, current):
                # Output configuration is applied asynchronously. Reconcile on
                # the next poll, as at startup, before verifying or capturing.
                time.sleep(.1)
                continue
            if (expected != report['effective_target']
                    or get_output_differences(report['actual'], current)):
                write_json_atomic(directory / 'outputs.json', raw, mode=0o644)
                update_report(expected, current, 'output-change')
            if not report['screenshots']:
                visible = get_greeter_outputs(get_sway_reply(environment, '-t', 'get_tree'))
                if visible == {output['name'] for output in target}:
                    if ready_at is None:
                        ready_at = time.monotonic()
                    if time.monotonic() - ready_at >= 1:
                        for output in current:
                            screenshot = screenshots / f'{output["name"]}.png'
                            subprocess.run(['grim', '-s', str(output['scale']), '-o', output['name'], str(screenshot)],
                                           env=environment, check=True, timeout=10)
                            report['screenshots'].append(str(screenshot))
                        write_json_atomic(report_path, report, mode=0o644)
                        print(f'Inner screenshots saved: {screenshots}', flush=True)
                else:
                    ready_at = None
            time.sleep(.2)
        if interrupted:
            return interrupted
        raw = get_sway_reply(environment, '-t', 'get_outputs')
        current = get_outputs(raw)
        expected = (get_hyprland_targets(parent_environment, sway.pid, target, current)
                    if hyprland else target)
        if expected is None:
            raise RuntimeError('Owned Hyprland output windows disappeared.')
        write_json_atomic(directory / 'outputs.json', raw, mode=0o644)
        update_report(expected, current, 'theme-exit')
        return app.returncode
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report['error'] = str(error)
        report['matched'] = False
        print(f'Sway session: {error}', file=sys.stderr, flush=True)
        return 1
    finally:
        stop_process(app)
        if output_thread is not None:
            output_thread.join()
        stop_process(sway)
        for log in [app_log, sway_log]:
            if log is not None:
                log.close()
        for signum, handler in handlers.items():
            signal.signal(signum, handler)
        shutil.rmtree(runtime)
        write_json_atomic(report_path, report, mode=0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log-dir', type=Path, required=True)
    parser.add_argument('--backend', choices=['wayland', 'headless'], default='wayland')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if not arguments.command or arguments.command[0] != '--' or len(arguments.command) == 1:
        parser.error('Supply the theme session command after --.')
    try:
        return start_session(arguments.log_dir.resolve(), arguments.backend, arguments.command[1:])
    except (OSError, ValueError) as error:
        print(f'Sway session: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
