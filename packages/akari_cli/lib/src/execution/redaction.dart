/// Masks known sensitive environment values and common credential syntax in
/// plans, reports, and captured output. This is a logging safeguard, not a
/// reason for child commands to print arbitrary credentials or PAM payloads.
class SecretRedactor {
  SecretRedactor._(this._secretValues);

  static const _environmentNames = [
    'password',
    'passwd',
    'passphrase',
    'token',
    'secret',
    r'api[_-]?key',
    'credential',
    'authorization',
  ];
  static const _credentialNames = [
    'password',
    'passwd',
    'passphrase',
    'token',
    r'access[_-]?token',
    r'refresh[_-]?token',
    r'api[_-]?key',
    'credential',
    'authorization',
    r'pam[_-]?(?:secret|password|response)',
  ];
  static final _credentialName = '(?:${_credentialNames.join('|')})';
  static const _quotedOrBareValue = r"""(?:"[^"]*"|'[^']*'|[^\s,;]+)""";

  // Environment names match complete words; PAM response/answer variables also
  // occur with provider-specific prefixes. Printed assignments and CLI options
  // share the same credential names and quoted/unquoted value syntax.
  static final _sensitiveEnvironmentName = RegExp(
    '(?:^|[_-])(?:${_environmentNames.join('|')})(?:\$|[_-])'
    r'|pam.*(?:response|answer)',
    caseSensitive: false,
  );
  static final _sensitiveAssignment = RegExp(
    r"""(["']?"""
    '$_credentialName'
    r"""["']?\s*[:=]\s*)"""
    '$_quotedOrBareValue',
    caseSensitive: false,
  );
  static final _sensitiveOptionValue = RegExp(
    '(--$_credentialName'
    r'\s+)'
    '$_quotedOrBareValue',
    caseSensitive: false,
  );
  static final _sensitiveOption = RegExp(
    '^--$_credentialName\$',
    caseSensitive: false,
  );
  static final _bearerToken = RegExp(
    r'\bBearer\s+[^\s,;]+',
    caseSensitive: false,
  );

  final List<String> _secretValues;

  factory SecretRedactor.fromEnvironments(
    Iterable<Map<String, String>> environments,
  ) {
    final secretValues = <String>{};
    for (final environment in environments) {
      for (final entry in environment.entries) {
        if (_sensitiveEnvironmentName.hasMatch(entry.key) &&
            entry.value.isNotEmpty) {
          secretValues.add(entry.value);
        }
      }
    }
    // Replace longer values first so a shorter overlapping secret does not
    // destroy the match and leave the remaining suffix of a longer one exposed.
    final sortedSecrets = secretValues.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    return SecretRedactor._(sortedSecrets);
  }

  List<String> redactCommand(List<String> command) {
    final safeCommand = <String>[];
    for (var index = 0; index < command.length; index++) {
      final argument = command[index];
      safeCommand.add(redact(argument));
      if (_sensitiveOption.hasMatch(argument) && index + 1 < command.length) {
        safeCommand.add('[REDACTED]');
        index++;
      }
    }
    return safeCommand;
  }

  Map<String, String> redactEnvironment(Map<String, String> environment) => {
    for (final entry in environment.entries)
      entry.key: _sensitiveEnvironmentName.hasMatch(entry.key)
          ? '[REDACTED]'
          : redact(entry.value),
  };

  String redact(String value) {
    var sanitized = value;
    for (final secret in _secretValues) {
      sanitized = sanitized.replaceAll(secret, '[REDACTED]');
    }
    sanitized = sanitized.replaceAllMapped(_sensitiveAssignment, (match) {
      final assignedValue = match.group(0)!.substring(match.group(1)!.length);
      final quote = assignedValue.startsWith('"')
          ? '"'
          : assignedValue.startsWith("'")
          ? "'"
          : '';
      return '${match.group(1)}$quote[REDACTED]$quote';
    });
    sanitized = sanitized.replaceAllMapped(
      _sensitiveOptionValue,
      (match) => '${match.group(1)}[REDACTED]',
    );
    return sanitized.replaceAll(_bearerToken, 'Bearer [REDACTED]');
  }
}
