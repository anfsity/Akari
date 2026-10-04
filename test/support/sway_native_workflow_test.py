"""Opt-in nested Sway checks with a real greeter and built mock backend.

The outer compositor is headless and owned by this test. Its scale varies
without changing the developer's desktop. Reports, raw snapshots and inner
screenshots remain in the printed artifact directory. DRM/TTY recovery and
Hyprland-specific window placement require separate native checks.
"""

import argparse
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run_frontend(executable):
    app = subprocess.Popen([executable])
    try:
        deadline = time.monotonic() + 45
        screenshot = Path(os.environ['MOZAIS_NATIVE_SCREENSHOT'])
        while not screenshot.exists() and time.monotonic() < deadline and app.poll() is None:
            time.sleep(.1)
        if not screenshot.exists():
            raise RuntimeError('The session did not capture the greeter.')
        time.sleep(.5)
        return 0
    finally:
        app.terminate()
        app.wait(timeout=5)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--frontend':
        return run_frontend(sys.argv[2])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True, help='Built mock backend')
    arguments = parser.parse_args()
    for path in [arguments.app, arguments.backend]:
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f'Expected an executable: {path}')
    root = Path(tempfile.mkdtemp(prefix='mozais-sway-native-'))
    print(f'Artifacts: {root}', flush=True)
    results = []
    for outer_scale in [1, 1.6]:
        outer = root / f'outer-{outer_scale}'
        outer.mkdir()
        runtime = outer / 'runtime'
        runtime.mkdir(mode=0o700)
        config = outer / 'sway.conf'
        # Let inner test windows adopt their requested dimensions, rather than
        # tiling them to the enclosing output's entire logical rectangle.
        config.write_text(f'output HEADLESS-1 mode 3840x2160 scale {outer_scale}\n'
                          'for_window [app_id=".*"] floating enable\n'
                          'default_floating_border none\n')
        environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless',
                           WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2',
                           WLR_RENDERER_ALLOW_SOFTWARE='1', LIBGL_ALWAYS_SOFTWARE='1',
                           NO_AT_BRIDGE='1', GTK_USE_PORTAL='0')
        for key in ['WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'DISPLAY', 'SWAYSOCK',
                    'HYPRLAND_INSTANCE_SIGNATURE']:
            environment.pop(key, None)
        with (outer / 'sway.log').open('w') as log:
            sway = subprocess.Popen(['sway', '--unsupported-gpu', '-c', str(config)],
                                    env=environment, stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    displays = [path for path in runtime.glob('wayland-*') if path.is_socket()]
                    if displays:
                        break
                    if sway.poll() is not None:
                        raise RuntimeError((outer / 'sway.log').read_text())
                    time.sleep(.1)
                else:
                    raise RuntimeError('Outer Sway did not start.')
                environment['WAYLAND_DISPLAY'] = str(displays[0])
                for inner_scale in [1, 1.6]:
                    session = outer / f'inner-{inner_scale}'
                    profile = json.loads(subprocess.check_output([
                        sys.executable, str(ROOT / 'scripts/greetd-test/display_profile.py'),
                        '--reference', str(ROOT / 'config/sway/reference.json'),
                        '--state', str(root / 'state'), '--display-profile', 'reference',
                        '--scale', str(inner_scale), '--dry-run']))
                    screenshot = session / 'screenshots/WL-1.png'
                    inner_environment = dict(environment,
                        MOZAIS_DISPLAY_PROFILE_JSON=json.dumps(profile),
                        MOZAIS_BACKEND_MODE='mock', MOZAIS_BACKEND_BIN=str(arguments.backend.resolve()),
                        MOZAIS_LOG_DIR=str(session / 'dbus'), MOZAIS_NATIVE_SCREENSHOT=str(screenshot))
                    command = [sys.executable, str(ROOT / 'scripts/sway-session.py'),
                        '--log-dir', str(session), '--backend', 'wayland', '--',
                        'bash', str(ROOT / 'scripts/debug-dbus.sh'),
                        sys.executable, str(Path(__file__).resolve()),
                        '--frontend', str(arguments.app.resolve())]
                    with (outer / f'inner-{inner_scale}.log').open('w') as inner_log:
                        with subprocess.Popen(command, env=inner_environment,
                                stdout=inner_log, stderr=inner_log) as inner:
                            try:
                                inner_status = inner.wait(timeout=60)
                            except subprocess.TimeoutExpired:
                                inner.terminate()
                                inner.wait(timeout=10)
                                raise
                    report = json.loads((session / 'display-report.json').read_text())
                    results.append({'outer_scale': outer_scale, 'inner_scale': inner_scale,
                                    'exit_code': inner_status, 'display': report})
                    (root / 'results.json').write_text(json.dumps(results, indent=2))
                    print(f'Outer scale {outer_scale}, inner scale {inner_scale}: '
                          f'{report["actual"]}', flush=True)
                    if inner_status != 0 or not report['matched']:
                        raise RuntimeError(f'Nested verification failed: {report}')
                    if struct.unpack('>II', screenshot.read_bytes()[16:24]) != (1920, 1080):
                        raise RuntimeError('Inner screenshot did not preserve output pixel dimensions.')
            finally:
                os.killpg(sway.pid, signal.SIGTERM)
                try:
                    sway.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(sway.pid, signal.SIGKILL)
                    sway.wait()
    print('Native nested Sway checks passed.', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
