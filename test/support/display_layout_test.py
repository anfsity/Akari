"""Display order capture and scale-independent login layout checks."""

import importlib.util
from pathlib import Path
import sys
import unittest


sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    'display_layout', Path(__file__).resolve().parents[2] /
    'scripts/greetd-test/display-layout.py')
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


def output(name, width, height, active=True):
    return {'name': name, 'active': active,
            'rect': {'x': 0, 'y': 0, 'width': width, 'height': height}}


class DisplayLayoutTest(unittest.TestCase):
    def test_capture_uses_positions_instead_of_connector_order(self):
        self.assertEqual(layout.get_layout([
            {'name': 'external', 'x': 1600, 'y': 0},
            {'name': 'internal', 'x': 0, 'y': 0},
        ]), {'axis': 'x', 'outputs': ['internal', 'external']})

    def test_capture_vertical_order_with_negative_origin(self):
        self.assertEqual(layout.get_layout([
            {'name': 'bottom', 'x': -200, 'y': 0},
            {'name': 'top', 'x': -200, 'y': -1000},
        ]), {'axis': 'y', 'outputs': ['top', 'bottom']})

    def test_capture_rejects_unknown_or_unsupported_arrangements(self):
        for displays in [[], [
            {'name': 'same', 'x': 0, 'y': 0},
            {'name': 'same', 'x': 1000, 'y': 0},
        ], [
            {'name': 'one', 'x': 0, 'y': 0},
            {'name': 'two', 'x': 1000, 'y': 200},
        ]]:
            with self.subTest(displays=displays), self.assertRaises(ValueError):
                layout.get_layout(displays)

    def test_login_uses_live_logical_widths_at_different_scales(self):
        saved = {'axis': 'x', 'outputs': ['internal', 'external']}
        self.assertEqual(layout.get_positions(saved, [
            output('external', 2560, 1440), output('internal', 2560, 1600),
        ]), {'internal': (0, 0), 'external': (2560, 0)})
        self.assertEqual(layout.get_positions(saved, [
            output('external', 960, 540), output('internal', 1280, 720),
        ]), {'internal': (0, 0), 'external': (1280, 0)})

    def test_vertical_positions_use_live_heights(self):
        self.assertEqual(layout.get_positions(
            {'axis': 'y', 'outputs': ['top', 'bottom']},
            [output('bottom', 1280, 720), output('top', 960, 540)]),
            {'top': (0, 0), 'bottom': (0, 540)})

    def test_hotplug_compacts_remaining_outputs_and_appends_unknown_outputs(self):
        saved = {'axis': 'x', 'outputs': ['internal', 'external']}
        self.assertEqual(layout.get_positions(saved, [
            output('external', 960, 540), output('new', 1280, 720),
            output('internal', 2560, 1600, active=False),
        ]), {'external': (0, 0), 'new': (960, 0)})
        self.assertEqual(layout.get_positions(saved, []), {})


if __name__ == '__main__':
    unittest.main()
