"""Capture the actual standalone greeter outputs from its compositor session."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def capture_screenshots(session):
    outputs = json.loads(subprocess.check_output(
        ['swaymsg', '-r', '-t', 'get_outputs'], text=True, timeout=5))
    active = [output for output in outputs if output['active']]
    if not active:
        raise ValueError('No active greeter outputs to capture.')
    screenshots = session / 'screenshots'
    screenshots.mkdir(exist_ok=True)
    captured_at = datetime.now(timezone.utc).isoformat()
    directory = Path(tempfile.mkdtemp(
        prefix=datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=screenshots))
    # Match the harness logs' read access even with grim's own private umask.
    directory.chmod(0o755)
    images = []
    for index, output in enumerate(active, 1):
        image = directory / f'output-{index}.png'
        # grim defaults to the highest scale across ALL monitors. Use each
        # output's scale so mixed-DPI captures keep their native pixel sizes.
        subprocess.run(['grim', '-o', output['name'], '-s', str(output['scale']),
                        str(image)], check=True, timeout=15)
        image.chmod(0o644)
        images.append({'output': output['name'], 'file': image.name})
    metadata = directory / 'capture.json'
    metadata.write_text(json.dumps({
        'source': 'greetd-login', 'captured_at': captured_at,
        'outputs': outputs, 'images': images,
    }, indent=2) + '\n')
    metadata.chmod(0o644)
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--delay', type=int, choices=[0, 3], default=0)
    arguments = parser.parse_args()
    try:
        session = Path(os.environ['AKARI_LOG_DIR'])
        time.sleep(arguments.delay)
        directory = capture_screenshots(session)
        print(f'Greeter screenshots: {directory}', flush=True)
        return 0
    except (KeyError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Greeter screenshot failed: {error}', file=sys.stderr, flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
