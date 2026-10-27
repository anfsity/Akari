import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_studio/src/smart_guides.dart';

void main() {
  test('snaps the nearest edge or center independently on each axis', () {
    final result = calculateSmartGuides(
      moving: const Rect.fromLTWH(103, 202, 50, 40),
      targets: const [Rect.fromLTWH(100, 200, 50, 40)],
      canvasSize: const Size(1000, 600),
      tolerance: 6,
    );
    expect(result.correction, const Offset(-3, -2));
    expect(result.vertical, contains(100));
    expect(result.horizontal, contains(200));
  });
  test('canvas centers snap; distant targets do not pull the selection', () {
    final result = calculateSmartGuides(
      moving: const Rect.fromLTWH(474, 150, 50, 40),
      targets: const [],
      canvasSize: const Size(1000, 600),
      tolerance: 3,
    );
    expect(result.correction, const Offset(1, 0));
    expect(result.vertical, [500]);
    expect(result.horizontal, isEmpty);
  });
}
