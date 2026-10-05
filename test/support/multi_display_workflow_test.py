"""Opt-in native checks on an isolated headless Sway compositor.

Run with --app PATH to a built demo greeter. Requires Sway, wtype, and grim;
artifacts remain in a temporary directory for visual inspection.
"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    arguments = parser.parse_args()
    executable = arguments.app.resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error('--app must be an executable demo greeter bundle')

    root = Path(tempfile.mkdtemp(prefix='akari-displays-'))
    runtime = root / 'runtime'
    runtime.mkdir(mode=0o700)
    config = root / 'sway.conf'
    config.write_text('''
    output HEADLESS-1 mode 1280x720
    output HEADLESS-2 mode 1920x1080 scale 2
    output * bg #15191f solid_color
    default_border none
    focus_follows_mouse no
    ''')
    env = dict(os.environ)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    env.pop('SWAYSOCK', None)
    env.update(XDG_RUNTIME_DIR=str(runtime), AKARI_LOG_DIR=str(root), WLR_BACKENDS='headless',
               WLR_HEADLESS_OUTPUTS='2', WLR_RENDERER='gles2',
               WLR_RENDERER_ALLOW_SOFTWARE='1', LIBGL_ALWAYS_SOFTWARE='1',
               GDK_BACKEND='wayland', AKARI_WINDOW_MODE='fullscreen',
               AKARI_DISPLAY_MODE='mirror', NO_AT_BRIDGE='1',
               G_MESSAGES_DEBUG='all')
    print(f'Artifacts: {root}', flush=True)
    layout = root / 'display-layout.json'
    layout.write_text(json.dumps({'axis': 'x', 'outputs': ['HEADLESS-1', 'HEADLESS-2']}))
    layout_runner = Path(__file__).resolve().parents[2] / 'scripts/greetd-test/display-layout.py'
    with (root / 'sway.log').open('w') as sway_log, (root / 'app.log').open('w') as app_log:
        sway = subprocess.Popen(['sway', '--unsupported-gpu', '-c', str(config)],
                                env=env, stdout=sway_log, stderr=subprocess.STDOUT,
                                start_new_session=True)
        app = None
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                sockets = list(runtime.glob('sway-ipc.*.sock'))
                waylands = [p for p in runtime.glob('wayland-*') if not p.name.endswith('.lock')]
                if sockets and waylands:
                    env['SWAYSOCK'] = str(sockets[0])
                    env['WAYLAND_DISPLAY'] = waylands[0].name
                    break
                if sway.poll() is not None:
                    raise RuntimeError((root / 'sway.log').read_text())
                time.sleep(.1)
            else:
                raise RuntimeError('headless Sway did not start')

            def send_sway_command(*args):
                result = subprocess.run(['swaymsg', '-r', *args], env=env,
                                        text=True, capture_output=True, check=True)
                return json.loads(result.stdout)

            def get_windows():
                tree = send_sway_command('-t', 'get_tree')
                found = []
                def collect(node, output=None):
                    if node['type'] == 'output':
                        output = node['name']
                    if node.get('app_id') == 'dev.akari.greeter':
                        found.append((output, node))
                    for child in node.get('nodes', []) + node.get('floating_nodes', []):
                        collect(child, output)
                collect(tree)
                return found

            def wait_for_windows(count, stage, required_id=None, fullscreen=True):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    found = get_windows()
                    outputs = {o['name']: o for o in send_sway_command('-t', 'get_outputs') if o['active']}
                    ordered = sorted(outputs.values(), key=lambda output: (
                        ['HEADLESS-1', 'HEADLESS-2', 'HEADLESS-3'].index(output['name'])))
                    positions = []
                    x = 0
                    for output in ordered:
                        positions.append(output['rect']['x'] == x and output['rect']['y'] == 0)
                        x += output['rect']['width']
                    if (len(found) == count and len({name for name, _ in found}) == count
                        and all(positions)
                        and (required_id is None or required_id in [n['id'] for _, n in found])):
                        if all(node['fullscreen_mode'] == int(fullscreen) and
                               (not fullscreen or node['rect'] == outputs[name]['rect'])
                               for name, node in found):
                            print(f'{stage}: {[(name, n["id"], n["rect"]) for name, n in found]}', flush=True)
                            return found
                    if app.poll() is not None:
                        raise RuntimeError((root / 'app.log').read_text())
                    time.sleep(.2)
                raise RuntimeError(f'{stage}: windows={found}, outputs={outputs}\n' + (root / 'app.log').read_text())

            app = subprocess.Popen([sys.executable, str(layout_runner), 'run',
                                    str(layout), str(executable)],
                                   env=env, stdout=app_log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
            initial = wait_for_windows(2, 'startup')
            log = (root / 'app.log').read_text()
            primary_x = int(re.search(r'Created greeter view 0 on output at (\d+),', log).group(1))
            primary_name, primary_window = next((name, node) for name, node in initial if node['rect']['x'] == primary_x)
            primary_id = primary_window['id']
            print(f'Implicit view is on {primary_name}', flush=True)
            send_sway_command(f'[con_id={primary_id}] focus')
            time.sleep(.5)
            subprocess.run(['wtype', '-s', '500', '-k', 'space'], env=env, check=True)
            time.sleep(3)
            send_sway_command('seat seat0 cursor set 640 200')
            previous_x = 640
            for x, expected_output in [(640, 'HEADLESS-1'), (1760, 'HEADLESS-2'),
                                       (640, 'HEADLESS-1')]:
                send_sway_command(f'seat seat0 cursor move {x - previous_x} 0')
                previous_x = x
                send_sway_command('seat seat0 cursor press button1')
                send_sway_command('seat seat0 cursor release button1')
                focused = next(name for name, node in get_windows() if node['focused'])
                assert focused == expected_output, f'Pointer click focused {focused}, expected {expected_output}'
            print('Pointer clicks cross between both displays.', flush=True)
            snapshot = {output['name']: output['rect'] for output in
                        json.loads((root / 'outputs.json').read_text())}
            assert snapshot['HEADLESS-1']['x'] == 0
            assert snapshot['HEADLESS-2']['x'] == snapshot['HEADLESS-1']['width']
            for name, _ in initial:
                subprocess.run(['grim', '-o', name, str(root / f'{name}-login.png')], env=env, check=True)
            send_sway_command('output HEADLESS-1 scale 2')
            wait_for_windows(2, 'change output scale')
            send_sway_command('output HEADLESS-1 scale 1')
            wait_for_windows(2, 'restore output scale')
            send_sway_command('create_output')
            wait_for_windows(3, 'add third display')
            send_sway_command(f'output {primary_name} disable')
            wait_for_windows(2, 'remove primary display', primary_id)
            other_original = next(name for name, _ in initial if name != primary_name)
            send_sway_command('output HEADLESS-3 disable')
            wait_for_windows(1, 'remove secondary display')
            send_sway_command(f'output {other_original} disable')
            time.sleep(.5)
            assert app.poll() is None, 'application exited when all displays disconnected'
            send_sway_command('output HEADLESS-1 enable')
            wait_for_windows(1, 'reconnect display')
            assert (root / 'app.log').read_text().count('Created greeter view 0') == 1, 'implicit view was recreated'
            subprocess.run(['grim', '-o', 'HEADLESS-1', str(root / 'reconnected-login.png')], env=env, check=True)
            log = (root / 'app.log').read_text()
            assert 'EXCEPTION CAUGHT' not in log, log

            app.terminate()
            app.wait(timeout=5)
            send_sway_command('output HEADLESS-2 enable')
            env['AKARI_WINDOW_MODE'] = 'windowed'
            app = subprocess.Popen([str(executable)], env=env, stdout=app_log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
            wait_for_windows(1, 'windowed preview on two displays', fullscreen=False)
            app.terminate()
            app.wait(timeout=5)
            env['AKARI_WINDOW_MODE'] = 'fullscreen'
            env['AKARI_DISPLAY_MODE'] = 'single'
            app = subprocess.Popen([str(executable)], env=env, stdout=app_log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
            wait_for_windows(1, 'single-view fullscreen host on two displays')
            print('Native multi-display checks passed.', flush=True)
        finally:
            for process in [app, sway]:
                if process is not None and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()


if __name__ == "__main__":
    main()
