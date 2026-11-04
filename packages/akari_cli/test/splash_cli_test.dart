import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:akari_cli/src/execution/paths.dart';

import 'package:akari_cli/src/sdk_commands.dart';

final _repoRoot = findRepositoryRoot();

void main() {
  test(
    'standalone splash holds one renderer without preparing a theme',
    () async {
      final dart = getDartCommand(_repoRoot);
      final result = await Process.run(dart.first, [
        ...dart.skip(1),
        'packages/akari_cli/bin/akari.dart',
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
    expect(steps.last['interactive'], isFalse);
    },
  );
}
