class CliOption {
  const CliOption(
    this.name,
    this.description, {
    this.short,
    this.valueName,
    this.values = const [],
    this.directory = false,
  });

  final String name;
  final String description;
  final String? short;
  final String? valueName;
  final List<String> values;
  final bool directory;

  List<String> get spellings => [?short, name];
}

class CliCommand {
  const CliCommand(
    this.name,
    this.description, {
    this.aliases = const [],
    this.options = const [],
    this.forwardsArguments = false,
  });

  final String name;
  final String description;
  final List<String> aliases;
  final List<String> options;
  final bool forwardsArguments;

  List<String> get spellings => [name, ...aliases];
}

const cliOptions = {
  '--theme': CliOption(
    '--theme',
    'Select a theme project (default: themes/default).',
    short: '-t',
    valueName: 'PATH',
    directory: true,
  ),
  '--jobs': CliOption(
    '--jobs',
    'Limit Cargo and native compile/link parallel jobs.',
    short: '-j',
    valueName: 'COUNT',
  ),
  '--mode': CliOption(
    '--mode',
    'Flutter build mode (build: release; run/preview: debug).',
    short: '-m',
    valueName: 'MODE',
    values: ['debug', 'profile', 'release'],
  ),
  '--platform': CliOption(
    '--platform',
    'Flutter target for build (default: linux).',
    valueName: 'NAME',
  ),
  '--backend': CliOption(
    '--backend',
    'Backend transport for run (default: mock).',
    valueName: 'MODE',
    values: ['mock', 'real'],
  ),
  '--format': CliOption(
    '--format',
    'Console output format (default: text).',
    valueName: 'FORMAT',
    values: ['text', 'json'],
  ),
  '--report': CliOption(
    '--report',
    'Write the run report to PATH.',
    valueName: 'PATH',
  ),
  '--dry-run': CliOption(
    '--dry-run',
    'Print the execution plan without changing files.',
  ),
  '--help': CliOption('--help', 'Show help.', short: '-h'),
  '--shell': CliOption(
    '--shell',
    'Shell for completion (install default: zsh).',
    valueName: 'SHELL',
    values: ['zsh', 'bash'],
  ),
  '--prefix': CliOption(
    '--prefix',
    'Installation prefix (default: ~/.local).',
    valueName: 'PATH',
    directory: true,
  ),
  '--rc': CliOption(
    '--rc',
    'Shell startup file for command and completion registration.',
    valueName: 'PATH',
  ),
};

const cliCommands = [
  CliCommand(
    'build',
    'Build the selected frontend and production Rust backend.',
    options: ['--theme', '--jobs', '--mode', '--platform'],
  ),
  CliCommand(
    'run',
    'Run the greeter and backend on a private D-Bus session.',
    options: ['--theme', '--jobs', '--mode', '--backend'],
  ),
  CliCommand(
    'preview',
    'Run the selected theme with demo login state.',
    options: ['--theme', '--jobs', '--mode'],
  ),
  CliCommand(
    'verify',
    'Verify shared code, backend, and theme projects.',
    options: ['--theme'],
  ),
  CliCommand(
    'verify-perf',
    'Execute the selected theme performance gate.',
    aliases: ['perf'],
    options: ['--theme'],
    forwardsArguments: true,
  ),
  CliCommand(
    'generate-scenes',
    'Generate theme scene code.',
    options: ['--theme'],
  ),
  CliCommand(
    'trace-perf',
    'Execute the selected theme performance trace.',
    aliases: ['trace'],
    options: ['--theme'],
    forwardsArguments: true,
  ),
  CliCommand(
    'install',
    'Install the mozais launcher and shell completion.',
    options: ['--shell', '--prefix', '--rc'],
  ),
  CliCommand(
    'completion',
    'Print a shell completion script.',
    options: ['--shell'],
  ),
];

CliCommand getCliCommand(String spelling) {
  for (final command in cliCommands) {
    if (command.spellings.contains(spelling)) return command;
  }
  throw FormatException('Unknown command: $spelling');
}

List<CliOption> getCliOptions(CliCommand command) => [
  for (final name in command.options) cliOptions[name]!,
  if (command.name != 'install' && command.name != 'completion') ...[
    cliOptions['--format']!,
    cliOptions['--report']!,
    cliOptions['--dry-run']!,
  ],
  cliOptions['--help']!,
];

Map<String, String> getCliOptionValues(
  CliCommand command,
  List<String> arguments,
) {
  final options = {
    for (final option in getCliOptions(command))
      for (final spelling in option.spellings) spelling: option,
  };
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    final equals = argument.indexOf('=');
    final spelling = equals < 0 ? argument : argument.substring(0, equals);
    final option = options[spelling];
    if (option == null) {
      throw FormatException('Unknown option for ${command.name}: $spelling');
    }
    if (values.containsKey(option.name)) {
      throw FormatException('Duplicate ${option.name} option.');
    }
    String value;
    if (option.valueName == null) {
      if (equals >= 0) {
        throw FormatException('${option.name} does not accept a value.');
      }
      value = 'true';
    } else if (equals >= 0) {
      value = argument.substring(equals + 1);
    } else {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        throw FormatException('Missing value for ${option.name}.');
      }
      value = arguments[++index];
    }
    if (value.isEmpty) {
      throw FormatException('Missing value for ${option.name}.');
    }
    if (option.values.isNotEmpty && !option.values.contains(value)) {
      throw FormatException(
        'Invalid value for ${option.name}: $value (expected ${option.values.join(', ')}).',
      );
    }
    values[option.name] = value;
  }
  return values;
}
