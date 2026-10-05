import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/theme_perf.dart';
import '../tool/src/theme_project.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('akari-theme-perf-');
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'commands require an explicit supported version and operation',
    () async {
      final theme = ThemePackage(
        packageName: 'theme_ocean',
        builderName: 'buildOceanTheme',
        directory: temporary,
      );
      final manifest = File('${temporary.path}/pubspec.yaml');
      for (final configuration in [
        '',
        'perf: {version: 2, verify: [dart, run, perf.dart]}',
        'perf: {version: 1, trace: [dart, run, perf.dart]}',
        'perf: {version: 1, verify: "dart run perf.dart"}',
        'perf: {version: 1, verify: []}',
        'perf: {version: 1, verify: [dart, 42]}',
      ]) {
        await manifest.writeAsString('name: theme_ocean\n$configuration\n');
        expect(
          () => getThemePerfCommand(theme, 'verify'),
          throwsFormatException,
        );
      }
      await manifest.writeAsString(
        'name: theme_ocean\nperf: {version: 1, verify: [dart, run, "my perf.dart"]}\n',
      );
      expect(getThemePerfCommand(theme, 'verify'), [
        'dart',
        'run',
        'my perf.dart',
      ]);
    },
  );

  test(
    'artifact contents are opaque and paths resolve within the output',
    () async {
      final output = Directory('${temporary.path}/output');
      await Directory('${output.path}/nested').create(recursive: true);
      final artifact = File('${output.path}/nested/report.txt');
      await artifact.writeAsString('theme-specific format, not JSON');
      final manifest = File('${output.path}/result.json');
      await manifest.writeAsString(
        jsonEncode({
          'version': 1,
          'artifacts': [
            {'name': 'custom metric report', 'path': 'nested/report.txt'},
          ],
        }),
      );
      expect(await getThemePerfArtifacts(manifest), {
        'custom metric report': await artifact.resolveSymbolicLinks(),
      });
    },
  );

  test(
    'invalid manifests cannot register missing or escaped artifacts',
    () async {
      final output = Directory('${temporary.path}/output');
      await output.create();
      await File('${output.path}/report.txt').writeAsString('data');
      final outside = File('${temporary.path}/outside.txt');
      await outside.writeAsString('outside');
      await Link('${output.path}/outside-link').create(outside.path);
      final manifest = File('${output.path}/result.json');
      for (final result in [
        {'version': 2, 'artifacts': []},
        {'version': 1, 'artifacts': {}},
        {
          'version': 1,
          'artifacts': [42],
        },
        {
          'version': 1,
          'artifacts': [
            {'name': '', 'path': 'report.txt'},
          ],
        },
        {
          'version': 1,
          'artifacts': [
            {'name': 'report', 'path': 'report.txt'},
            {'name': 'report', 'path': 'report.txt'},
          ],
        },
        {
          'version': 1,
          'artifacts': [
            {'name': 'report', 'path': outside.path},
          ],
        },
        {
          'version': 1,
          'artifacts': [
            {'name': 'report', 'path': '../outside.txt'},
          ],
        },
        {
          'version': 1,
          'artifacts': [
            {'name': 'report', 'path': 'outside-link'},
          ],
        },
      ]) {
        await manifest.writeAsString(jsonEncode(result));
        await expectLater(
          getThemePerfArtifacts(manifest),
          throwsFormatException,
        );
      }
      await manifest.writeAsString(
        jsonEncode({
          'version': 1,
          'artifacts': [
            {'name': 'report', 'path': 'missing.txt'},
          ],
        }),
      );
      await expectLater(
        getThemePerfArtifacts(manifest),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
