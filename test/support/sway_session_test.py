"""Exercise Sway startup, drift, screenshot and cleanup at process boundaries."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SwaySessionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='akari-sway-session-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        handler = self.bin / 'handler'
        handler.write_text('''#!/usr/bin/env python3
import json, os, pathlib, re, signal, socket, subprocess, sys, time
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ['SESSION_TEST_ROOT'])
runtime = pathlib.Path(os.environ['XDG_RUNTIME_DIR'])
profile = json.loads(os.environ['AKARI_DISPLAY_PROFILE_JSON'])
prefix = 'HEADLESS' if os.environ.get('WLR_BACKENDS') == 'headless' else 'WL'
outputs = []
for index, source in enumerate(profile['outputs'], 1):
    outputs.append(dict(source, name=f'{prefix}-{index}', active=True,
                        current_mode=source['mode']))
if name == 'sway':
    (root / 'sway.pid').write_text(str(os.getpid()))
    (root / 'sway-env.json').write_text(json.dumps(dict(os.environ)))
    if os.environ.get('FAIL_SWAY'): sys.exit(5)
    sockets = []
    for filename in ['sway-ipc.test.sock', 'wayland-1']:
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(runtime / filename))
        sockets.append(sock)
    while True: time.sleep(.1)
elif name == 'swaymsg':
    if sys.argv[-1] == 'get_outputs':
        counter = root / 'query-count'
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        scales_path = root / 'adopted-scales.json'
        scales = json.loads(scales_path.read_text()) if scales_path.exists() else {}
        if os.environ.get('HYPR_TEST'):
            for index, output in enumerate(outputs, 1):
                output['scale'] = scales.get(str(index), output['scale'])
                fullscreen = int(os.environ.get('FULLSCREEN_AFTER', '9999'))
                width, height = [1600, 1000] if count > fullscreen else [766, 988]
                if os.environ.get('RETILE_AFTER') and count > int(os.environ['RETILE_AFTER']):
                    width, height = [766, 988]
                output['current_mode'] = dict(output['mode'], width=width, height=height)
                output['rect'] = dict(output['rect'], width=round(width / output['scale']),
                                     height=round(height / output['scale']))
        if os.environ.get('DRIFT_AFTER') and count > int(os.environ['DRIFT_AFTER']):
            outputs[0]['rect']['width'] -= 100
            outputs[0]['current_mode']['width'] -= 100
        print(json.dumps(outputs))
    elif ' scale ' in sys.argv[-1]:
        commands = sys.argv[-1].split('; ')
        scales_path = root / 'adopted-scales.json'
        scales = json.loads(scales_path.read_text()) if scales_path.exists() else {}
        for command in commands:
            index, scale = re.search(r'WL-([0-9]+)" scale ([0-9.e+-]+)', command).groups()
            scales[index] = float(scale)
        scales_path.write_text(json.dumps(scales))
        print(json.dumps([{'success': not os.environ.get('FAIL_SCALE')} for _ in commands]))
    else:
        print(json.dumps({'type': 'root', 'nodes': [
            {'type': 'output', 'name': output['name'], 'nodes': [
                {'type': 'con', 'app_id': 'dev.akari.greeter'}]}
            for output in outputs]}))
elif name == 'hyprctl':
    (root / 'hypr-env.json').write_text(json.dumps(dict(os.environ)))
    if sys.argv[-1] == 'monitors':
        print(json.dumps([dict(id=0, name='eDP-1', scale=float(os.environ.get('HOST_SCALE', '1.6'))),
                          dict(id=1, name='DP-1', scale=2)]))
    elif sys.argv[-1] == 'clients':
        counter = root / 'parent-query-count'
        count = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(count))
        pid = int((root / 'sway.pid').read_text())
        clients = [dict(pid=pid + 1, address='0x99', title='wlroots - WL-1', monitor=1)]
        if count > int(os.environ.get('HYPR_DELAY_QUERIES', '0')):
            clients += [dict(pid=pid, address=f'0x{index}', title=f'wlroots - WL-{index}',
                             monitor=(index - 1 if count <= int(os.environ.get('MOVE_AFTER', '9999')) else 1))
                        for index in range(len(outputs), 0, -1)]
        print(json.dumps(clients))
    else:
        command = sys.argv[-1]
        commands = root / 'outer-commands.json'
        history = json.loads(commands.read_text()) if commands.exists() else []
        history.append(command)
        commands.write_text(json.dumps(history))
        raise RuntimeError('Unexpected outer window mutation')
elif name == 'grim':
    pathlib.Path(sys.argv[-1]).write_bytes(b'inner screenshot')
    (root / 'grim-arguments.json').write_text(json.dumps(sys.argv[1:]))
elif name == 'app':
    (root / 'app.pid').write_text(str(os.getpid()))
    (root / 'app-env.json').write_text(json.dumps(dict(os.environ)))
    if os.environ.get('SPAWN_DESCENDANT'):
        child = subprocess.Popen([sys.executable, '-c',
            'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
        (root / 'descendant.pid').write_text(str(child.pid))
    print('theme started', flush=True)
    time.sleep(float(os.environ.get('APP_DURATION', '1.8')))
    sys.exit(int(os.environ.get('APP_EXIT', '0')))
''')
        handler.chmod(0o755)
        for name in ['sway', 'swaymsg', 'hyprctl', 'grim', 'app']:
            (self.bin / name).symlink_to(handler)
        reference = json.loads((ROOT / 'config/sway/reference.json').read_text())
        self.profile = {'source': reference['source'], 'outputs': reference['outputs'],
                        'selection': 'reference', 'custom': False}
        self.environment = {**os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
                            'SESSION_TEST_ROOT': str(self.root),
                            'AKARI_DISPLAY_PROFILE_JSON': json.dumps(self.profile),
                            'WAYLAND_DISPLAY': 'outer-wayland',
                            'XDG_RUNTIME_DIR': str(self.root / 'outer'),
                            'SWAYSOCK': 'outer-sway-socket',
                            'AKARI_DISPLAY_SOURCE': 'greetd-login'}
        self.command = [sys.executable, str(ROOT / 'scripts/sway-session.py'),
                        '--log-dir', str(self.root / 'session'), '--backend', 'headless',
                        '--', str(self.bin / 'app')]

    def run_session(self, **environment):
        return subprocess.run(self.command, env={**self.environment, **environment},
                              capture_output=True, text=True, timeout=12)

    def get_report(self):
        return json.loads((self.root / 'session/display-report.json').read_text())

    def assert_processes_stopped(self):
        self.assertFalse((self.root / 'session/runtime').exists())
        for name in ['sway', 'app', 'descendant']:
            path = self.root / f'{name}.pid'
            if not path.exists():
                continue
            status = Path(f'/proc/{path.read_text()}/stat')
            if status.exists():
                self.assertEqual(status.read_text().split()[2], 'Z', name)

    def test_session_captures_inner_screenshots_and_cleans_its_processes(self):
        result = self.run_session()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.get_report()
        self.assertTrue(report['matched'])
        self.assertEqual(report['actual'][0]['rect'], self.profile['outputs'][0]['rect'])
        self.assertEqual(len(report['screenshots']), 1)
        self.assertEqual(Path(report['screenshots'][0]).read_bytes(), b'inner screenshot')
        app_environment = json.loads((self.root / 'app-env.json').read_text())
        self.assertNotEqual(app_environment['SWAYSOCK'], 'outer-sway-socket')
        self.assertNotIn('AKARI_DISPLAY_SOURCE', app_environment)
        self.assertEqual(app_environment['AKARI_WINDOW_MODE'], 'fullscreen')
        self.assertIn('theme started', (self.root / 'session/flutter.log').read_text())
        self.assert_processes_stopped()

    def test_nested_backend_uses_absolute_parent_socket_and_private_inner_runtime(self):
        self.command[self.command.index('headless')] = 'wayland'
        result = self.run_session()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        environment = json.loads((self.root / 'sway-env.json').read_text())
        self.assertEqual(environment['WAYLAND_DISPLAY'], str(self.root / 'outer/outer-wayland'))
        self.assertEqual(environment['WLR_WL_OUTPUTS'], '1')
        self.assertEqual(self.get_report()['actual'][0]['name'], 'WL-1')
        self.assert_processes_stopped()

    def test_fractional_scale_screenshots_request_the_output_pixel_scale(self):
        self.profile['outputs'][0]['scale'] = 1.6
        self.profile['outputs'][0]['rect'].update(width=1200, height=675)
        result = self.run_session(AKARI_DISPLAY_PROFILE_JSON=json.dumps(self.profile))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((self.root / 'grim-arguments.json').read_text())[:2],
                         ['-s', '1.6'])
        self.assert_processes_stopped()

    def run_hyprland_session(self, **environment):
        self.command[self.command.index('headless')] = 'wayland'
        self.environment.pop('SWAYSOCK')
        return self.run_session(HYPR_TEST='1', HYPRLAND_INSTANCE_SIGNATURE='outer-hyprland',
                                **environment)

    def test_hyprland_compensates_host_scale_without_mutating_outer_windows(self):
        result = self.run_hyprland_session(HYPR_DELAY_QUERIES='2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.get_report()
        self.assertTrue(report['matched'])
        self.assertEqual(report['actual'][0]['scale'], .625)
        self.assertEqual(report['effective_target'][0]['host_monitor'], 'eDP-1')
        self.assertEqual(report['target'][0]['scale'], 1)
        self.assertFalse((self.root / 'outer-commands.json').exists())
        self.assertNotIn(' mode ', (self.root / 'session/sway.conf').read_text())
        parent = json.loads((self.root / 'hypr-env.json').read_text())
        self.assertEqual(parent['XDG_RUNTIME_DIR'], str(self.root / 'outer'))
        self.assertEqual(parent['WAYLAND_DISPLAY'], 'outer-wayland')
        self.assert_processes_stopped()

    def test_fullscreen_and_retiling_keep_scale_without_failing_session(self):
        result = self.run_hyprland_session(FULLSCREEN_AFTER='3', RETILE_AFTER='5', APP_DURATION='3')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.get_report()
        self.assertTrue(report['matched'])
        self.assertEqual(report['actual'][0]['scale'], .625)
        self.assertEqual(report['actual'][0]['mode']['width'], 766)
        self.assertGreaterEqual(sum(check['stage'] == 'output-change' for check in report['checks']), 2)
        self.assert_processes_stopped()

    def test_fullscreen_matches_tty_viewport_and_uses_adopted_screenshot_scale(self):
        # A fullscreen 1600x1000 nested window on a 1.6-scaled 2560x1600
        # monitor must expose the same logical viewport as TTY scale 1.
        result = self.run_hyprland_session(FULLSCREEN_AFTER='0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.get_report()
        self.assertEqual(report['actual'][0]['rect']['width'], 2560)
        self.assertEqual(report['actual'][0]['rect']['height'], 1600)
        self.assertEqual(json.loads((self.root / 'grim-arguments.json').read_text())[:2],
                         ['-s', '0.625'])
        self.assert_processes_stopped()

    def test_mixed_host_scales_preserve_each_profile_scale(self):
        self.profile['outputs'][0]['scale'] = 1.6
        self.profile['outputs'][0]['rect'].update(width=1200, height=675)
        second = json.loads(json.dumps(self.profile['outputs'][0]))
        second.update(name='second', scale=1)
        second['rect'].update(x=1200, width=1920, height=1080)
        self.profile['outputs'].append(second)
        result = self.run_hyprland_session(AKARI_DISPLAY_PROFILE_JSON=json.dumps(self.profile))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.get_report()
        self.assertTrue(report['matched'])
        self.assertEqual([output['scale'] for output in report['actual']], [1, .5])
        self.assertEqual(len(report['screenshots']), 2)
        self.assert_processes_stopped()

    def test_moving_to_a_different_monitor_updates_scale(self):
        result = self.run_hyprland_session(MOVE_AFTER='4')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.get_report()['actual'][0]['scale'], .5)
        self.assertEqual(self.get_report()['effective_target'][0]['host_monitor'], 'DP-1')
        self.assert_processes_stopped()

    def test_invalid_host_scale_does_not_start_theme(self):
        result = self.run_hyprland_session(HOST_SCALE='0')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Invalid Hyprland monitor scale', self.get_report()['error'])
        self.assertFalse((self.root / 'app.pid').exists())
        self.assert_processes_stopped()

    def test_scale_command_failure_does_not_start_theme(self):
        result = self.run_hyprland_session(FAIL_SCALE='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Could not apply nested output scales', self.get_report()['error'])
        self.assertFalse((self.root / 'app.pid').exists())
        self.assert_processes_stopped()

    def test_startup_failure_does_not_start_the_theme_and_cleans_runtime(self):
        result = self.run_session(FAIL_SWAY='1')
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / 'app.pid').exists())
        self.assertFalse(self.get_report()['matched'])
        self.assert_processes_stopped()

    def test_initial_output_mismatch_retains_target_and_actual_without_launching_theme(self):
        result = self.run_session(DRIFT_AFTER='0')
        self.assertEqual(result.returncode, 1)
        report = self.get_report()
        self.assertFalse(report['matched'])
        self.assertEqual(report['target'][0]['mode']['width'], 1920)
        self.assertEqual(report['actual'][0]['mode']['width'], 1820)
        self.assertFalse((self.root / 'app.pid').exists())
        self.assert_processes_stopped()

    def test_resize_stops_running_theme_and_retains_failed_verification(self):
        result = self.run_session(DRIFT_AFTER='2', APP_DURATION='60')
        self.assertEqual(result.returncode, 1)
        report = self.get_report()
        self.assertFalse(report['matched'])
        self.assertEqual(report['checks'][-1]['stage'], 'output-change')
        self.assertIn('requested', report['error'])
        self.assert_processes_stopped()

    def test_theme_failure_preserves_status_and_kills_descendants(self):
        result = self.run_session(APP_EXIT='7', APP_DURATION='.2', SPAWN_DESCENDANT='1')
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertTrue(self.get_report()['matched'])
        self.assert_processes_stopped()

    def test_interrupt_cleans_theme_compositor_and_descendants(self):
        process = subprocess.Popen(self.command, env={**self.environment,
                                   'APP_DURATION': '60', 'SPAWN_DESCENDANT': '1'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not (self.root / 'descendant.pid').exists():
                if time.monotonic() > deadline or process.poll() is not None:
                    self.fail('Theme did not start.')
                time.sleep(.05)
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 143, stdout + stderr)
            self.assert_processes_stopped()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
