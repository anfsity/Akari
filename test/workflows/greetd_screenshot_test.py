"""Check output capture without accessing a user's running compositor."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / 'scripts/greetd-test/screenshot.py'
spec = importlib.util.spec_from_file_location('screenshot', SOURCE)
screenshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screenshot)


class ScreenshotTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='akari-screenshot-test-')
        self.addCleanup(self.temporary.cleanup)
        self.session = Path(self.temporary.name)
        self.outputs = [
            {'name': 'eDP-1', 'active': True, 'scale': 1, 'rect': {'width': 1920}},
            {'name': 'DP-1', 'active': True, 'scale': 1.5, 'rect': {'width': 2560}},
            {'name': 'HDMI-A-1', 'active': False},
        ]

    def capture(self):
        def write_image(command, **options):
            Path(command[-1]).write_bytes(b'PNG')
            Path(command[-1]).chmod(0o600)

        with patch.object(screenshot.subprocess, 'check_output',
                          return_value=json.dumps(self.outputs)), \
                patch.object(screenshot.subprocess, 'run', side_effect=write_image) as grim:
            directory = screenshot.capture_screenshots(self.session)
        return directory, grim

    def test_mixed_scales_and_readable_images_keep_output_mapping(self):
        directory, grim = self.capture()
        self.assertEqual([call.args[0][1:5] for call in grim.call_args_list],
                         [['-o', 'eDP-1', '-s', '1'], ['-o', 'DP-1', '-s', '1.5']])
        metadata = json.loads((directory / 'capture.json').read_text())
        self.assertEqual(metadata['outputs'], self.outputs)
        self.assertEqual(metadata['source'], 'greetd-login')
        self.assertEqual(metadata['images'], [
            {'output': 'eDP-1', 'file': 'output-1.png'},
            {'output': 'DP-1', 'file': 'output-2.png'},
        ])
        self.assertEqual(directory.stat().st_mode & 0o777, 0o755)
        for file in directory.iterdir():
            self.assertEqual(file.stat().st_mode & 0o777, 0o644)

    def test_repeated_captures_preserve_previous_images(self):
        first, _ = self.capture()
        second, _ = self.capture()
        self.assertNotEqual(first, second)
        self.assertTrue((first / 'output-1.png').exists())
        self.assertTrue((second / 'output-1.png').exists())

    def test_failed_capture_does_not_publish_success_metadata(self):
        with patch.object(screenshot.subprocess, 'check_output',
                          return_value=json.dumps(self.outputs)), \
                patch.object(screenshot.subprocess, 'run',
                             side_effect=subprocess.CalledProcessError(1, 'grim')):
            with self.assertRaises(subprocess.CalledProcessError):
                screenshot.capture_screenshots(self.session)
        self.assertEqual(list(self.session.rglob('capture.json')), [])

    def test_no_active_outputs_does_not_create_a_capture(self):
        with patch.object(screenshot.subprocess, 'check_output', return_value='[]'):
            with self.assertRaisesRegex(ValueError, 'No active'):
                screenshot.capture_screenshots(self.session)
        self.assertFalse((self.session / 'screenshots').exists())


if __name__ == '__main__':
    unittest.main()
