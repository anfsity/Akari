import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/sdk_commands.dart';

void main() {
  test(
    'standalone splash holds one renderer without preparing a theme',
    () async {
      final dart = getDartCommand(Directory.current);
      final result = await Process.run(dart.first, [
        ...dart.skip(1),
        'tool/akari.dart',
        'run',
        'splash',
        '--light',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map;
      final steps = (plan['steps'] as List).cast<Map>();
      expect(steps.map((step) => step['id']), [
        'splash.build',
        'splash.preview',
      ]);
      expect((steps.last['command'] as List).skip(1), [
        'window',
        '--hold',
        '--light',
      ]);
      expect(steps.last['interactive'], isTrue);
    },
  );
}
