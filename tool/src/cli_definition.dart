/// Shared command grammar for parsing, help, and shell completion. Keep aliases,
/// accepted options, and enumerated values here so those consumers cannot drift.
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
    this.reportsRun = true,
  });

  final String name;
  final String description;
  final List<String> aliases;
  final List<String> options;
  final bool forwardsArguments;
  final bool reportsRun;

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
    'Backend transport for the greeter (default: mock).',
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
  '--scale': CliOption(
    '--scale',
    'Standalone Sway output scale (default: 1).',
    valueName: 'NUMBER',
  ),
  '--log-dir': CliOption(
    '--log-dir',
    'Test log root (default: /var/tmp/mozais-greetd-test-<uid>).',
    valueName: 'PATH',
    directory: true,
  ),
  '--run': CliOption(
    '--run',
    'Test logs to read (default: latest attempt; current: last armed test).',
    valueName: 'RUN',
    values: ['latest', 'current'],
  ),
  '--file': CliOption(
    '--file',
    'Log to read (default: start; session logs use the newest greeter session).',
    valueName: 'LOG',
    values: [
      'start',
      'backend',
      'flutter',
      'sway',
      'lifecycle',
      'restore',
      'journal',
    ],
  ),
  '--lines': CliOption(
    '--lines',
    'Number of log lines to display (default: 100).',
    short: '-n',
    valueName: 'COUNT',
  ),
  '--follow': CliOption('--follow', 'Follow the selected log.', short: '-f'),
};

const cliCommands = [
  CliCommand(
    'build',
    'Build the selected frontend and production Rust backend.',
    options: ['--theme', '--jobs', '--mode', '--platform'],
  ),
  CliCommand(
    'run',
    'Run the greeter on a private D-Bus session (default), or a selected target.',
    options: ['--theme', '--jobs', '--mode', '--backend'],
  ),
  CliCommand(
    'preview',
    'Run the selected theme with demo login state.',
    options: ['--theme', '--jobs', '--mode'],
  ),
  CliCommand(
    'run studio',
    'Edit theme scenes with a compiled preview and shadcn controls (debug, no backend).',
    options: ['--theme', '--jobs'],
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
    reportsRun: false,
  ),
  CliCommand(
    'completion',
    'Print a shell completion script.',
    options: ['--shell'],
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test',
    'Manage standalone greetd testing.',
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test install',
    'Build, back up and install the test environment; save desktop display order.',
    options: ['--dry-run'],
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test start',
    'Check the TTY and desktop, arm recovery and start the test service.',
    options: ['--scale', '--log-dir', '--dry-run'],
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test restore',
    'Restore SDDM using the independently installed recovery script.',
    options: ['--dry-run'],
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test status',
    'Show installation, service, recovery timer and saved log paths.',
    options: ['--format'],
    reportsRun: false,
  ),
  CliCommand(
    'greetd-test logs',
    'Read startup, greeter or recovery logs without sudo.',
    options: ['--run', '--file', '--lines', '--follow'],
    reportsRun: false,
  ),
];

CliCommand getCliCommand(String spelling) {
  for (final command in cliCommands) {
    if (command.spellings.contains(spelling)) return command;
  }
  throw FormatException('Unknown command: $spelling');
}

List<CliCommand> getCliSubcommands(String parent) => [
  for (final command in cliCommands)
    if (command.name.startsWith('$parent ')) command,
];

List<CliOption> getCliOptions(CliCommand command) => [
  for (final name in command.options) cliOptions[name]!,
  if (command.reportsRun) ...[
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
    // Store by canonical name, making mixed short/long spellings duplicates
    // rather than two independently accepted values for the same option.
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
