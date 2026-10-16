import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/preview/scenarios.dart';
import '../tool/src/commands/theme.dart';
import '../tool/src/execution/model.dart';

void main() {
  test(
    'preview cannot pass with absent, incomplete or failed journey results',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'akari-preview-result-',
      );
      addTearDown(() => root.delete(recursive: true));
      final manifest = File('${root.path}/results.json');
      final successfulProcess = RunResult(
        steps: [],
        startedAt: DateTime.now(),
        finishedAt: DateTime.now(),
        durationMs: 0,
      );
      expect(
        (await collectPreviewResult(
          manifest,
          previewScenarioNames,
          successfulProcess,
        )).error,
        isNotNull,
      );
      for (final data in [
        <String, String>{},
        {'face-success': 'passed'},
        {'face-success': 'passed', 'password-fallback': 'failed'},
        {'face-success': 'passed', 'unexpected': 'passed'},
      ]) {
        await manifest.writeAsString(jsonEncode(data));
        expect(
          (await collectPreviewResult(
            manifest,
            previewScenarioNames,
            successfulProcess,
          )).error,
          isNotNull,
        );
      }
      await manifest.writeAsString(jsonEncode({'face-success': 'passed'}));
      expect(
        (await collectPreviewResult(manifest, [
          'face-success',
        ], successfulProcess)).error,
        isNull,
      );
    },
  );
}
