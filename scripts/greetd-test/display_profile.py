"""Sway output snapshots, local login defaults and virtual output configuration.

Raw outputs remain session diagnostics. A separate, atomically published profile
marks a completed DRM login capture; nested/headless diagnostics never become
login defaults. Both login capture and desktop testing use this normalization.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


TRANSFORMS = {'normal', '90', '180', '270', 'flipped', 'flipped-90',
              'flipped-180', 'flipped-270'}


def get_outputs(raw):
    if not isinstance(raw, list):
        raise ValueError('Expected a Sway output array.')
    outputs = []
    for item in raw:
        if not isinstance(item, dict) or not isinstance(item.get('active'), bool):
            raise ValueError('Invalid Sway output.')
        if not item['active']:
            continue
        output = {key: item.get(key) for key in
                  ['name', 'make', 'model', 'serial', 'scale', 'transform', 'rect']}
        output['mode'] = item.get('current_mode')
        outputs.append(output)
    validate_outputs(outputs)
    return sorted(outputs, key=lambda output: (
        output['rect']['y'], output['rect']['x'], output['name']))


def validate_outputs(outputs):
    if not isinstance(outputs, list) or not outputs:
        raise ValueError('No active Sway outputs.')
    names = set()
    for output in outputs:
        if not isinstance(output, dict):
            raise ValueError('Invalid display output.')
        name = output.get('name')
        if not isinstance(name, str) or not re.fullmatch(r'[\w.:-]+', name) or name in names:
            raise ValueError('Invalid or duplicate display name.')
        names.add(name)
        mode, rect, scale = output.get('mode'), output.get('rect'), output.get('scale')
        if (not isinstance(mode, dict) or
                any(type(mode.get(key)) is not int or mode[key] <= 0
                    for key in ['width', 'height']) or
                type(mode.get('refresh')) is not int or mode['refresh'] < 0):
            raise ValueError(f'Invalid output mode: {name}')
        if (not isinstance(rect, dict) or
                any(type(rect.get(key)) is not int for key in ['x', 'y', 'width', 'height']) or
                rect['width'] <= 0 or rect['height'] <= 0):
            raise ValueError(f'Invalid logical rectangle: {name}')
        if type(scale) not in [int, float] or not math.isfinite(scale) or scale <= 0:
            raise ValueError(f'Invalid output scale: {name}')
        if not isinstance(output.get('transform'), str) or output['transform'] not in TRANSFORMS:
            raise ValueError(f'Invalid output transform: {name}')
        if any(output.get(key) is not None and not isinstance(output[key], str)
               for key in ['make', 'model', 'serial']):
            raise ValueError(f'Invalid output identity: {name}')


def validate_profile(profile):
    if (not isinstance(profile, dict) or profile.get('schema_version') != 1 or
            not isinstance(profile.get('source'), dict)):
        raise ValueError('Invalid display profile.')
    validate_outputs(profile.get('outputs'))
    source = profile['source']
    if source.get('kind') == 'reference':
        return
    if (source.get('kind') != 'login' or source.get('backend') != 'drm' or
            any(not isinstance(source.get(key), str) or not source[key]
                for key in ['run', 'session', 'captured_at', 'snapshot', 'snapshot_sha256']) or
            any(output['name'].startswith(('WL-', 'HEADLESS-', 'X11-'))
                for output in profile['outputs'])):
        raise ValueError('Not a standalone DRM login profile.')
    get_capture_time(profile)


def get_capture_time(profile):
    captured = datetime.fromisoformat(profile['source']['captured_at'])
    if captured.tzinfo is None:
        raise ValueError('Capture time must include its time zone.')
    return captured


def write_json_atomic(path, value, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f'.{path.name}-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            os.fchmod(stream.fileno(), mode)
            json.dump(value, stream, indent=2, allow_nan=False)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def capture_outputs():
    directory = Path(os.environ['MOZAIS_LOG_DIR'])
    raw = subprocess.check_output(['swaymsg', '-r', '-t', 'get_outputs'])
    snapshot = directory / 'outputs.json'
    # Publish raw diagnostics first; the profile is the completion marker.
    snapshot.write_bytes(raw)
    if os.environ.get('MOZAIS_DISPLAY_SOURCE') == 'greetd-login':
        profile = {
            'schema_version': 1,
            'source': {
                'kind': 'login', 'backend': 'drm',
                'run': str(Path(os.environ['MOZAIS_TEST_RUN']).resolve()),
                'session': str(directory.resolve()),
                'captured_at': datetime.now(timezone.utc).isoformat(),
                'snapshot': str(snapshot.resolve()),
                'snapshot_sha256': hashlib.sha256(raw).hexdigest(),
            },
            'outputs': get_outputs(json.loads(raw)),
        }
        validate_profile(profile)
        write_json_atomic(directory / 'display-profile.json', profile, mode=0o644)


def find_login_profile(installation, saved):
    candidates = []
    warnings = []
    if saved.exists():
        try:
            profile = json.loads(saved.read_text())
            validate_profile(profile)
            if profile['source']['kind'] != 'login':
                raise ValueError('Saved profile is not a login capture.')
            candidates.append(profile)
        except (OSError, ValueError) as error:
            warnings.append(f'Ignoring saved login profile {saved}: {error}')
    run = (installation / 'current-run').resolve()
    for path in (run / 'greeter').glob('session-*/display-profile.json'):
        try:
            profile = json.loads(path.read_text())
            validate_profile(profile)
            source = profile['source']
            snapshot = path.parent / 'outputs.json'
            run_configuration = json.loads((run / 'config.json').read_text())
            if (source['kind'] != 'login' or source['run'] != str(run) or
                    source['session'] != str(path.parent.resolve()) or
                    source['snapshot'] != str(snapshot.resolve()) or
                    not isinstance(run_configuration, dict) or
                    run_configuration.get('source') != 'greetd-login'):
                raise ValueError('Snapshot does not belong to this login run/session.')
            raw = snapshot.read_bytes()
            if (hashlib.sha256(raw).hexdigest() != source['snapshot_sha256'] or
                    get_outputs(json.loads(raw)) != profile['outputs']):
                raise ValueError('Incomplete or changed output snapshot.')
            candidates.append(profile)
        except (OSError, ValueError, KeyError) as error:
            warnings.append(f'Ignoring login snapshot {path}: {error}')
    return (max(candidates, key=get_capture_time) if candidates else None), warnings


def get_logical_size(output):
    mode = output['mode']
    width, height = mode['width'], mode['height']
    if output['transform'] in ['90', '270', 'flipped-90', 'flipped-270']:
        width, height = height, width
    return round(width / output['scale']), round(height / output['scale'])


def resolve_profile(reference, state, installation, selection='auto',
                    resolution=None, scale=None, persist=True):
    if resolution is not None and not re.fullmatch(r'[1-9][0-9]*x[1-9][0-9]*', resolution):
        raise ValueError('--resolution must be WIDTHxHEIGHT with positive pixel dimensions.')
    if scale is not None:
        try:
            scale = float(scale)
        except ValueError:
            raise ValueError('--scale must be a positive number.') from None
        if not math.isfinite(scale) or scale <= 0:
            raise ValueError('--scale must be a positive number.')
    saved = state / 'login.json'
    login = None
    if selection != 'reference':
        login, warnings = find_login_profile(installation, saved)
        for warning in warnings:
            print(warning, file=sys.stderr)
    if selection == 'login' and login is None:
        raise ValueError('No valid login display profile. Run a standalone greetd test first.')
    profile = copy.deepcopy(login) if login else json.loads(reference.read_text())
    validate_profile(profile)
    if (resolution is not None or scale is not None) and len(profile['outputs']) != 1:
        raise ValueError('Global --resolution/--scale overrides require a single-output profile; '
                         'select --display-profile reference for a single virtual output.')
    if login and persist:
        write_json_atomic(saved, login)
    if not login:
        profile['source']['path'] = str(reference.resolve())
    result = {'selection': selection, 'source': profile['source'],
              'custom': resolution is not None or scale is not None,
              'outputs': profile['outputs']}
    if result['custom']:
        output = result['outputs'][0]
        if resolution is not None:
            output['mode']['width'], output['mode']['height'] = map(int, resolution.split('x'))
        if scale is not None:
            output['scale'] = scale
        output['rect']['width'], output['rect']['height'] = get_logical_size(output)
        validate_outputs(result['outputs'])
    return result


def get_virtual_outputs(profile, backend):
    prefix = 'WL' if backend == 'wayland' else 'HEADLESS'
    return [dict(output, name=f'{prefix}-{index}', source_name=output['name'])
            for index, output in enumerate(profile['outputs'], 1)]


def get_output_commands(outputs):
    return [f'output {json.dumps(output["name"])} mode '
            f'{output["mode"]["width"]}x{output["mode"]["height"]} '
            f'scale {output["scale"]} transform {output["transform"]} '
            f'position {output["rect"]["x"]} {output["rect"]["y"]}'
            for output in outputs]


def get_output_differences(target, actual):
    differences = []
    actual_by_name = {output['name']: output for output in actual}
    if set(actual_by_name) != {output['name'] for output in target}:
        differences.append('Active output names/count differ.')
    for output in target:
        adopted = actual_by_name.get(output['name'])
        if adopted is None:
            continue
        # Virtual backends choose their own refresh rate. Preserve the physical
        # refresh as provenance, but compare the reproducible geometry and scale.
        for field in ['scale', 'transform', 'rect']:
            if field == 'scale' and math.isclose(output[field], adopted[field], abs_tol=1e-6):
                continue
            if output[field] != adopted[field]:
                differences.append(f'{output["name"]}: {field} requested {output[field]}, actual {adopted[field]}')
        for dimension in ['width', 'height']:
            if output['mode'][dimension] != adopted['mode'][dimension]:
                differences.append(f'{output["name"]}: mode {dimension} requested '
                                   f'{output["mode"][dimension]}, actual {adopted["mode"][dimension]}')
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--installation', type=Path, default=Path('/opt/mozais-test'))
    parser.add_argument('--display-profile', choices=['auto', 'login', 'reference'], default='auto')
    parser.add_argument('--resolution')
    parser.add_argument('--scale')
    parser.add_argument('--dry-run', action='store_true')
    arguments = parser.parse_args()
    try:
        print(json.dumps(resolve_profile(
            arguments.reference, arguments.state, arguments.installation,
            arguments.display_profile, arguments.resolution, arguments.scale,
            persist=not arguments.dry_run)))
        return 0
    except (OSError, ValueError) as error:
        print(f'Display profile: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
