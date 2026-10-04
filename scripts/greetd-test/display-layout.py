"""Carry a desktop's row/column display order into the standalone greeter.

Positions are recomputed from Sway's live logical sizes, rather than copied
from a desktop that can use different modes and scales. Unknown outputs are
appended until a new desktop layout is captured.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading

sys.dont_write_bytecode = True
from display_profile import capture_outputs


def get_layout(displays):
    if not displays:
        raise ValueError('No active desktop outputs to capture.')
    if len({display['name'] for display in displays}) != len(displays):
        raise ValueError('Duplicate desktop outputs.')
    if len({display['y'] for display in displays}) == 1:
        axis = 'x'
    elif len({display['x'] for display in displays}) == 1:
        axis = 'y'
    else:
        raise ValueError('Layout capture supports a single aligned row or column.')
    return {'axis': axis, 'outputs': [
        display['name'] for display in sorted(displays, key=lambda display: display[axis])
    ]}


def get_desktop_displays():
    runtime = Path(f'/run/user/{os.getuid()}')
    environment = {**os.environ, 'XDG_RUNTIME_DIR': str(runtime)}
    if not environment.get('SWAYSOCK'):
        sockets = list(runtime.glob(f'sway-ipc.{os.getuid()}.*.sock'))
        if len(sockets) == 1:
            environment['SWAYSOCK'] = str(sockets[0])
    if environment.get('SWAYSOCK'):
        outputs = json.loads(subprocess.check_output(
            ['swaymsg', '-r', '-t', 'get_outputs'], env=environment, text=True))
        return [dict(name=output['name'], **output['rect'])
                for output in outputs if output['active']]
    if shutil.which('hyprctl'):
        instances = json.loads(subprocess.check_output(
            ['hyprctl', '-j', 'instances'], env=environment, text=True))
        signature = environment.get('HYPRLAND_INSTANCE_SIGNATURE')
        instance = next((item for item in instances if item['instance'] == signature), None)
        # Installation can follow a logout/login, leaving the launching shell
        # with an old signature. A single live instance is unambiguous.
        if instance is None and len(instances) == 1:
            instance = instances[0]
        if instance is not None:
            outputs = json.loads(subprocess.check_output(
                ['hyprctl', '-j', '-i', instance['instance'], 'monitors'],
                env=environment, text=True))
            return [output for output in outputs if not output['disabled']]
    raise ValueError('No active Sway or Hyprland desktop to capture.')


def get_positions(layout, outputs):
    active = {output['name']: output['rect'] for output in outputs if output['active']}
    names = [name for name in layout['outputs'] if name in active]
    names.extend(sorted(active.keys() - set(layout['outputs'])))
    position = 0
    positions = {}
    for name in names:
        positions[name] = (position, 0) if layout['axis'] == 'x' else (0, position)
        position += active[name]['width' if layout['axis'] == 'x' else 'height']
    return positions


def update_positions(layout):
    outputs = json.loads(subprocess.check_output(
        ['swaymsg', '-r', '-t', 'get_outputs'], text=True))
    positions = get_positions(layout, outputs)
    commands = []
    for output in outputs:
        name = output['name']
        if name in positions:
            x, y = positions[name]
            if (output['rect']['x'], output['rect']['y']) != (x, y):
                commands.append(f'output {json.dumps(name)} position {x} {y}')
    if commands:
        results = json.loads(subprocess.check_output(
            ['swaymsg', '-r', '; '.join(commands)], text=True))
        if not all(result['success'] for result in results):
            raise RuntimeError(f'Could not apply display positions: {results}')


def run_greeter(layout, command):
    # Subscribe before querying so a hotplug between setup and app startup is
    # retained. The subscription lives exactly as long as this greeter launch.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
        events.connect(os.environ['SWAYSOCK'])
        subscription = b'["output"]'
        events.sendall(b'i3-ipc' + struct.pack('<II', len(subscription), 2) + subscription)
        stream = events.makefile('rb')

        def receive_event():
            header = stream.read(14)
            if not header:
                return None
            size, _ = struct.unpack('<II', header[6:])
            return json.loads(stream.read(size))

        response = receive_event()
        if not response['success']:
            raise RuntimeError(f'Could not subscribe to output changes: {response}')
        if layout is not None:
            update_positions(layout)
        if os.environ.get('MOZAIS_LOG_DIR'):
            capture_outputs()

        def update_on_output_changes():
            try:
                while receive_event() is not None:
                    if layout is not None:
                        update_positions(layout)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                print(f'Display layout update failed: {error}', file=sys.stderr)

        with subprocess.Popen(command) as app:
            handlers = {}
            for signum in [signal.SIGTERM, signal.SIGINT]:
                handlers[signum] = signal.signal(
                    signum, lambda received, frame: app.send_signal(received))
            watcher = threading.Thread(target=update_on_output_changes)
            watcher.start()
            try:
                return app.wait()
            finally:
                events.shutdown(socket.SHUT_RDWR)
                watcher.join(timeout=5)
                stream.close()
                for signum, handler in handlers.items():
                    signal.signal(signum, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('capture')
    run = commands.add_parser('run')
    run.add_argument('layout', type=Path)
    run.add_argument('app', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    try:
        if arguments.command == 'capture':
            layout = get_layout(get_desktop_displays())
            print(json.dumps(layout))
            return 0
        if not arguments.app:
            raise ValueError('A greeter command is required.')
        layout = json.loads(arguments.layout.read_text()) if arguments.layout.exists() else None
        if layout is not None and (not isinstance(layout, dict) or layout.get('axis') not in ['x', 'y'] or
                not isinstance(layout.get('outputs'), list) or not layout['outputs'] or
                any(not isinstance(name, str) or not re.fullmatch(r'[\w.:-]+', name)
                    for name in layout['outputs']) or
                len(set(layout['outputs'])) != len(layout['outputs'])):
            raise ValueError('Invalid saved display layout.')
        return run_greeter(layout, arguments.app)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Display layout: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
