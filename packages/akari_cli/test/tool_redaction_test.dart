import 'package:test/test.dart';

import 'package:akari_cli/src/execution/redaction.dart';

void main() {
  test(
    'credential syntax preserves quotes and surrounding diagnostic text',
    () {
      final redactor = SecretRedactor.fromEnvironments(const []);
      for (final sample in <String, String>{
        'password=value, ok': 'password=[REDACTED], ok',
        '"refresh_token": "two words"; ok': '"refresh_token": "[REDACTED]"; ok',
        "'api-key'='two words'": "'api-key'='[REDACTED]'",
        '--pam-response "two words" --verbose':
            '--pam-response [REDACTED] --verbose',
        'Bearer token; ok': 'Bearer [REDACTED]; ok',
      }.entries) {
        expect(redactor.redact(sample.key), sample.value);
      }
      expect(
        redactor.redactCommand(['app', '--access-token', 'two words', '-v']),
        ['app', '--access-token', '[REDACTED]', '-v'],
      );
    },
  );

  test('environment secrets use word boundaries and longest value first', () {
    final redactor = SecretRedactor.fromEnvironments([
      {
        'TOKEN': 'overlap',
        'PAM_PROVIDER_ANSWER': 'overlap-long',
        'TOKENIZER': 'visible',
      },
    ]);
    expect(
      redactor.redact('overlap-long overlap visible'),
      '[REDACTED] [REDACTED] visible',
    );
    expect(
      redactor.redactEnvironment({'TOKENIZER': 'visible', 'API_KEY': 'key'}),
      {'TOKENIZER': 'visible', 'API_KEY': '[REDACTED]'},
    );
  });

  test('redacts client/pam answer syntax while skipping tiny env values', () {
    final redactor = SecretRedactor.fromEnvironments([
      {'SECRET': 'x'},
    ]);
    expect(
      redactor.redact('client_secret=longsecret pam_answer=xyz ok x'),
      'client_secret=[REDACTED] pam_answer=[REDACTED] ok x',
    );
    expect(redactor.redactEnvironment({'SECRET': 'x'}), {'SECRET': '[REDACTED]'});
  });
}
