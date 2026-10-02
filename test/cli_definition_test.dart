import 'package:flutter_test/flutter_test.dart';

import '../tool/src/cli_definition.dart';

void main() {
  test('short and long options normalize to the same values', () {
    final build = getCliCommand('build');
    expect(
      getCliOptionValues(build, [
        '-t',
        'theme with spaces',
        '-m',
        'debug',
        '-j',
        '4',
      ]),
      getCliOptionValues(build, [
        '--theme=theme with spaces',
        '--mode=debug',
        '--jobs=4',
      ]),
    );
    expect(getCliCommand('perf').name, 'verify-perf');
    expect(getCliCommand('trace').name, 'trace-perf');
    expect(getCliCommand('perf').forwardsArguments, isTrue);
  });

  test('mixed spellings still reject duplicates and missing values', () {
    for (final arguments in [
      ['-t', 'themes/default', '--theme', 'themes/fallback'],
      ['--mode=debug', '-m', 'release'],
      ['-j'],
      ['-t', '-m', 'debug'],
      ['--jobs='],
      ['--dry-run=true'],
      ['-m', 'invalid'],
    ]) {
      expect(
        () => getCliOptionValues(getCliCommand('build'), arguments),
        throwsFormatException,
        reason: '$arguments',
      );
    }
    expect(
      () => getCliOptionValues(getCliCommand('verify'), ['-m', 'debug']),
      throwsFormatException,
    );
    expect(() => getCliCommand('b'), throwsFormatException);
  });
}
