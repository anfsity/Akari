import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:akari_cli/src/execution/paths.dart';

import 'package:akari_cli/src/sdk_commands.dart';

import 'cli_test_snapshots.dart';

final _repoRoot = findRepositoryRoot();

void main() {
  test(
    'standalone splash holds one renderer without preparing a theme',
    () async {
      final dart = getDartCommand(_repoRoot);
      final snapshot = await ensureAkariCliSnapshot(_repoRoot);
      final result = await Process.run(dart.first, [
        ...dart.skip(1),
        snapshot,
        'run',
        'splash',
        '--light',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final steps = (plan['steps'] as List).cast<Map<String, dynamic>>();
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
