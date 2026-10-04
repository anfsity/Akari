"""Login snapshot boundaries and reproducible virtual display configuration."""

import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/greetd-test'))
import display_profile as displays


def output(name='eDP-1', scale=1.5, x=0):
    return {'name': name, 'active': True, 'make': 'Test', 'model': 'Panel', 'serial': '123',
            'current_mode': {'width': 1920, 'height': 1080, 'refresh': 60000},
            'scale': scale, 'transform': 'normal',
            'rect': {'x': x, 'y': 0, 'width': round(1920 / scale), 'height': round(1080 / scale)}}


class DisplayProfileTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='mozais-display-profile-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.installation = self.root / 'installed'
        self.installation.mkdir()
        self.run = self.root / 'run'
        self.run.mkdir()
        (self.installation / 'current-run').symlink_to(self.run)
        (self.run / 'config.json').write_text(json.dumps({'source': 'greetd-login'}))
        self.state = self.root / 'state'
        self.reference = ROOT / 'config/sway/reference.json'

    def capture(self, raw=None, name='session-one', timestamp=None, source='greetd-login'):
        session = self.run / 'greeter' / name
        session.mkdir(parents=True, exist_ok=True)
        with patch.dict(os.environ, MOZAIS_LOG_DIR=str(session),
                        MOZAIS_DISPLAY_SOURCE=source, MOZAIS_TEST_RUN=str(self.run)), patch.object(
                            displays.subprocess, 'check_output', return_value=json.dumps(
                                [output()] if raw is None else raw).encode()):
            displays.capture_outputs()
        if timestamp:
            path = session / 'display-profile.json'
            profile = json.loads(path.read_text())
            profile['source']['captured_at'] = timestamp
            path.write_text(json.dumps(profile))
        return session

    def resolve(self, **options):
        return displays.resolve_profile(self.reference, self.state, self.installation, **options)

    def test_first_run_uses_reference_without_creating_state(self):
        profile = self.resolve()
        self.assertEqual(profile['source']['kind'], 'reference')
        self.assertEqual(profile['outputs'][0]['scale'], 1)
        self.assertEqual(profile['outputs'][0]['mode']['width'], 1920)
        self.assertFalse(self.state.exists())

    def test_capture_preserves_raw_and_imports_complete_login_record_atomically(self):
        session = self.capture()
        raw = (session / 'outputs.json').read_bytes()
        profile = self.resolve()
        self.assertEqual(profile['source']['snapshot_sha256'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(profile['source']['session'], str(session))
        self.assertEqual(profile['outputs'][0]['mode']['refresh'], 60000)
        self.assertEqual(profile['outputs'][0]['serial'], '123')
        self.assertEqual(profile['outputs'][0]['scale'], 1.5)
        self.assertEqual((session / 'outputs.json').read_bytes(), raw)
        saved = self.state / 'login.json'
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(saved.read_text())['source'], profile['source'])
        self.assertEqual(list(self.state.iterdir()), [saved])

    def test_invalid_current_run_keeps_saved_login_even_after_original_logs_are_removed(self):
        self.capture()
        original = self.resolve()
        (self.installation / 'current-run').unlink()
        (self.installation / 'current-run').symlink_to(self.root / 'failed-attempt')
        self.assertEqual(self.resolve()['outputs'], original['outputs'])

    def test_newest_valid_capture_wins_over_bad_or_incomplete_new_sessions(self):
        self.capture(name='session-old', timestamp='2026-01-01T00:00:00+00:00')
        newest = self.capture([output(scale=2)], name='session-new',
                              timestamp='2026-02-01T00:00:00+00:00')
        broken = self.run / 'greeter/session-broken'
        broken.mkdir()
        (broken / 'display-profile.json').write_text('{')
        profile = self.resolve()
        self.assertEqual(profile['source']['session'], str(newest))
        self.assertEqual(profile['outputs'][0]['scale'], 2)

    def test_reference_bypasses_login_discovery_and_import(self):
        self.capture()
        profile = self.resolve(selection='reference')
        self.assertEqual(profile['source']['kind'], 'reference')
        self.assertFalse(self.state.exists())

    def test_login_missing_reports_error(self):
        with self.assertRaisesRegex(ValueError, 'No valid login'):
            self.resolve(selection='login')

    def test_dry_run_discovers_login_without_persisting(self):
        self.capture()
        self.assertEqual(self.resolve(persist=False)['source']['kind'], 'login')
        self.assertFalse(self.state.exists())

    def test_unmarked_nested_headless_and_incomplete_captures_are_not_imported(self):
        self.capture(source='nested', raw=[output('WL-1')])
        self.assertEqual(self.resolve()['source']['kind'], 'reference')
        for name in ['WL-1', 'HEADLESS-1', 'X11-1']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.capture(raw=[output(name)])
        self.assertEqual(self.resolve()['source']['kind'], 'reference')

    def test_altered_snapshot_wrong_run_and_unmarked_run_are_not_imported(self):
        session = self.capture()
        manifest = session / 'display-profile.json'
        original = manifest.read_text()
        (session / 'outputs.json').write_text('[]')
        self.assertEqual(self.resolve()['source']['kind'], 'reference')
        self.capture()
        profile = json.loads(original)
        profile['source']['run'] = str(self.root / 'other-run')
        manifest.write_text(json.dumps(profile))
        self.assertEqual(self.resolve()['source']['kind'], 'reference')
        manifest.write_text(original)
        for run_configuration in [{}, [], None, 'broken']:
            (self.run / 'config.json').write_text(json.dumps(run_configuration))
            self.assertEqual(self.resolve()['source']['kind'], 'reference')

    def test_corrupt_saved_profile_falls_back_and_is_replaced_by_valid_capture(self):
        self.state.mkdir()
        (self.state / 'login.json').write_text('{')
        self.assertEqual(self.resolve()['source']['kind'], 'reference')
        self.capture()
        self.assertEqual(self.resolve()['source']['kind'], 'login')

    def test_newer_saved_profile_is_not_replaced_by_older_current_run(self):
        self.capture(timestamp='2026-02-01T00:00:00+00:00')
        self.resolve()
        self.capture(raw=[output(scale=2)], timestamp='2026-01-01T00:00:00+00:00')
        self.assertEqual(self.resolve()['outputs'][0]['scale'], 1.5)

    def test_partial_overrides_keep_same_base_and_do_not_modify_saved_login(self):
        self.capture()
        profile = self.resolve(scale='2')
        self.assertTrue(profile['custom'])
        self.assertEqual(profile['source']['kind'], 'login')
        self.assertEqual(profile['outputs'][0]['rect']['width'], 960)
        self.assertEqual(self.resolve()['outputs'][0]['scale'], 1.5)
        profile = self.resolve(resolution='2560x1440')
        self.assertEqual(profile['outputs'][0]['scale'], 1.5)
        self.assertEqual(profile['outputs'][0]['rect']['width'], 1707)

    def test_multi_display_mapping_keeps_order_transform_and_rectangles(self):
        right = output('DP-1', scale=2, x=1280)
        left = output()
        self.capture([right, left])
        profile = self.resolve()
        virtual = displays.get_virtual_outputs(profile, 'wayland')
        self.assertEqual([o['source_name'] for o in virtual], ['eDP-1', 'DP-1'])
        self.assertEqual([o['name'] for o in virtual], ['WL-1', 'WL-2'])
        self.assertIn('position 1280 0', displays.get_output_commands(virtual)[1])
        for options in [{'scale': '1'}, {'resolution': '1920x1080'}]:
            with self.assertRaisesRegex(ValueError, 'single-output'):
                self.resolve(**options)

    def test_rotation_is_accounted_for_when_overriding_scale(self):
        rotated = output()
        rotated['transform'] = '90'
        rotated['rect'].update(width=720, height=1280)
        self.capture([rotated])
        self.assertEqual(self.resolve(scale='2')['outputs'][0]['rect'],
                         {'x': 0, 'y': 0, 'width': 540, 'height': 960})

    def test_invalid_overrides_and_corrupt_outputs_are_rejected(self):
        for options in [{'scale': value} for value in ['0', '-1', 'nan', 'inf', 'abc']] + [
                {'resolution': value} for value in ['0x10', '1920', '1x-1', '1x2; exit']]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.resolve(**options)
        for raw in [[], {}, [output(), output()], [dict(output(), scale=0)],
                    [dict(output(), transform={})], [dict(output(), current_mode=None)]]:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                displays.get_outputs(raw)

    def test_geometry_comparison_ignores_refresh_and_float_precision_but_detects_resize(self):
        target = displays.get_outputs([output()])
        actual = copy.deepcopy(target)
        actual[0]['mode']['refresh'] = 0
        actual[0]['scale'] += 1e-8
        self.assertEqual(displays.get_output_differences(target, actual), [])
        actual[0]['mode']['width'] = 1280
        actual[0]['rect']['width'] = 853
        self.assertEqual(len(displays.get_output_differences(target, actual)), 2)


if __name__ == '__main__':
    unittest.main()
