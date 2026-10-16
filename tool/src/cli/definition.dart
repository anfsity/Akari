import '../theme/model.dart';
import '../../preview/scenarios.dart';

enum CommandGroup {
  development('Development and preview'),
  verification('Checks and performance'),
  installation('Installation and login'),
  tools('Tools');

  const CommandGroup(this.label);
  final String label;
}

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
    this.development,
    this.group = CommandGroup.development,
    this.examples = const [],
    this.scriptPath,
    this.positionalUsage,
  });

  final String name;
  final String description;
  final List<String> aliases;
  final List<String> options;
  final bool forwardsArguments;
  final DevelopmentCommand? development;
  final CommandGroup group;
  final List<String> examples;
  final String? scriptPath;
  final String? positionalUsage;

  bool get hasRunReport => development != null;

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
    'Flutter build mode (build: release; run: debug).',
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
  '--scenario': CliOption(
    '--scenario',
    'Preview journey (default: all).',
    valueName: 'NAME',
    values: ['all', ...previewScenarioNames],
  ),
  '--light': CliOption('--light', 'Use the light splash variant.'),
  '--scope': CliOption(
    '--scope',
    'Installation scope (default: login).',
    valueName: 'SCOPE',
    values: ['login', 'test', 'all'],
  ),
  '--keyring': CliOption(
    '--keyring',
    'Configure installed keyring PAM modules (default: auto); offer installation when missing.',
    valueName: 'PROVIDER',
    values: ['auto', 'gnome', 'kwallet', 'none'],
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
    'Shell for completion (install cli default: zsh).',
    valueName: 'SHELL',
    values: ['zsh', 'bash'],
  ),
  '--prefix': CliOption(
    '--prefix',
    'Shell launcher installation prefix (default: ~/.local).',
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
    'Standalone Sway scale (default: 1; nested Hyprland compensates host scale).',
    valueName: 'NUMBER',
  ),
  '--resolution': CliOption(
    '--resolution',
    'Override reference pixel size (enforced headless; Hyprland controls window size).',
    valueName: 'WIDTHxHEIGHT',
  ),
  '--display-profile': CliOption(
    '--display-profile',
    'Display defaults: latest valid login, or project reference (default: auto).',
    valueName: 'PROFILE',
    values: ['auto', 'login', 'reference'],
  ),
  '--sway-backend': CliOption(
    '--sway-backend',
    'Sway backend (default: wayland; headless for fixed screenshots).',
    valueName: 'BACKEND',
    values: ['wayland', 'headless'],
  ),
  '--log-dir': CliOption(
    '--log-dir',
    'Test log root (default: /var/tmp/akari-greetd-test-<uid>).',
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
      'screenshot',
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
  '--component': CliOption(
    '--component',
    'Production log component (default: service journal).',
    valueName: 'NAME',
    values: ['service', 'backend', 'flutter', 'sway'],
  ),
};

const cliCommands = [
  CliCommand(
    'build',
    'Build the selected frontend, production Rust backend and native splash.',
    examples: ['akari build --theme themes/default --jobs 4'],
    options: ['--theme', '--jobs', '--mode', '--platform'],
    development: DevelopmentCommand.build,
  ),
  CliCommand(
    'run',
    'Run the greeter on a private D-Bus session (default), or a selected target.',
    examples: [
      'akari run --theme themes/default',
      'akari run sway --display-profile reference',
    ],
    options: ['--theme', '--jobs', '--mode', '--backend'],
    development: DevelopmentCommand.run,
  ),
  CliCommand(
    'preview',
    'Show each automated login journey once in one window, then exit.',
    examples: [
      'akari preview --theme themes/default',
      'akari preview --scenario face-success',
      'akari preview --scenario password-fallback',
    ],
    options: ['--theme', '--jobs', '--scenario'],
    development: DevelopmentCommand.preview,
  ),
  CliCommand(
    'run sway',
    'Run the selected greeter in isolated Sway with verified display defaults.',
    options: [
      '--theme',
      '--jobs',
      '--mode',
      '--backend',
      '--display-profile',
      '--resolution',
      '--scale',
      '--sway-backend',
    ],
    development: DevelopmentCommand.sway,
  ),
  CliCommand(
    'run splash',
    'Preview the native loading animation until closed.',
    options: ['--jobs', '--mode', '--light'],
    development: DevelopmentCommand.splash,
    examples: ['akari run splash', 'akari run splash --light'],
  ),
  CliCommand(
    'run studio',
    'Edit theme scenes with a compiled preview and shadcn controls (debug, no backend).',
    options: ['--theme', '--jobs'],
    development: DevelopmentCommand.studio,
  ),
  CliCommand(
    'verify',
    'Verify shared code, backend, and theme projects.',
    group: CommandGroup.verification,
    options: ['--theme'],
    development: DevelopmentCommand.verify,
  ),
  CliCommand(
    'verify-perf',
    'Execute the selected theme performance gate.',
    group: CommandGroup.verification,
    aliases: ['perf'],
    options: ['--theme'],
    forwardsArguments: true,
    development: DevelopmentCommand.verifyPerf,
  ),
  CliCommand(
    'generate-scenes',
    'Generate theme scene code.',
    options: ['--theme'],
    development: DevelopmentCommand.generateScenes,
  ),
  CliCommand(
    'trace-perf',
    'Execute the selected theme performance trace.',
    group: CommandGroup.verification,
    aliases: ['trace'],
    options: ['--theme'],
    forwardsArguments: true,
    development: DevelopmentCommand.tracePerf,
  ),
  CliCommand(
    'install',
    'Build and install the production login environment without switching services.',
    examples: ['akari install --theme themes/default'],
    group: CommandGroup.installation,
    options: ['--theme', '--jobs', '--keyring', '--dry-run'],
  ),
  CliCommand(
    'install cli',
    'Install the akari launcher and shell completion.',
    group: CommandGroup.installation,
    options: ['--shell', '--prefix', '--rc'],
  ),
  CliCommand(
    'uninstall',
    'Remove login or test installations, including partial installs; retain preferences and logs.',
    examples: ['akari uninstall --scope all --dry-run'],
    group: CommandGroup.installation,
    options: ['--scope', '--dry-run'],
  ),

  CliCommand(
    'login',
    'Manage the production login service.',
    group: CommandGroup.installation,
  ),
  CliCommand(
    'login enable',
    'Select Akari for the next boot and save the previous login service.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'login disable',
    'Restore the previous login service for the next boot.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'login rollback',
    'Select the previous installed release for the next greeter launch.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'login configure-keyring',
    'Configure greetd keyring PAM without rebuilding the login environment.',
    group: CommandGroup.installation,
    options: ['--keyring', '--dry-run'],
  ),
  CliCommand(
    'login enable-gaze',
    'Enable Gaze for the stock Arch greetd PAM stack with password fallback.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'login disable-gaze',
    'Restore greetd password authentication and remove the managed Gaze helper.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'login status',
    'Show the installed release, boot login service and runtime state.',
    group: CommandGroup.installation,
    options: ['--format'],
  ),
  CliCommand(
    'login logs',
    'Read the production service journal or newest greeter logs.',
    group: CommandGroup.installation,
    options: ['--component', '--lines', '--follow'],
  ),
  CliCommand(
    'completion',
    'Print a shell completion script.',
    group: CommandGroup.tools,
    options: ['--shell'],
  ),
  CliCommand(
    'greetd-test',
    'Manage standalone greetd testing.',
    group: CommandGroup.installation,
  ),
  CliCommand(
    'greetd-test install',
    'Build, back up and install the test environment; save desktop display order.',
    group: CommandGroup.installation,
    options: ['--theme', '--dry-run'],
  ),
  CliCommand(
    'greetd-test start',
    'Check service configuration, arm recovery and start the test service.',
    group: CommandGroup.installation,
    options: ['--scale', '--log-dir', '--dry-run'],
  ),
  CliCommand(
    'greetd-test restore',
    'Restore SDDM using the independently installed recovery script.',
    group: CommandGroup.installation,
    options: ['--dry-run'],
  ),
  CliCommand(
    'greetd-test status',
    'Show installation, service, recovery timer and saved log paths.',
    group: CommandGroup.installation,
    options: ['--format'],
  ),
  CliCommand(
    'greetd-test logs',
    'Read startup, greeter or recovery logs without sudo.',
    group: CommandGroup.installation,
    options: ['--run', '--file', '--lines', '--follow'],
  ),
  CliCommand(
    'toolchain',
    'Check or configure the development toolchain.',
    group: CommandGroup.tools,
  ),
  CliCommand(
    'toolchain check',
    'Check development dependencies.',
    group: CommandGroup.tools,
    scriptPath: 'check-toolchain.sh',
    options: ['--dry-run'],
  ),
  CliCommand(
    'toolchain setup',
    'Install the configured SDK and fetch dependencies.',
    group: CommandGroup.tools,
    scriptPath: 'bootstrap-toolchain.sh',
    options: ['--dry-run'],
  ),
  CliCommand(
    'docs',
    'Build and check documentation.',
    group: CommandGroup.tools,
  ),
  CliCommand(
    'docs build-api',
    'Build Dart API documentation.',
    group: CommandGroup.tools,
    scriptPath: 'build-api-docs.sh',
    options: ['--dry-run'],
  ),
  CliCommand(
    'docs verify',
    'Check a built documentation site.',
    group: CommandGroup.tools,
    scriptPath: 'verify-docs.py',
    options: ['--dry-run'],
    forwardsArguments: true,
    examples: ['akari docs verify -- docs/site/dist'],
  ),
  CliCommand(
    'script',
    'Discover and invoke repository scripts.',
    group: CommandGroup.tools,
  ),
  CliCommand(
    'script list',
    'List all scripts and their calling conditions.',
    group: CommandGroup.tools,
    options: ['--format'],
  ),
  CliCommand(
    'script run',
    'Invoke a script with its original calling contract.',
    group: CommandGroup.tools,
    options: ['--dry-run'],
    forwardsArguments: true,
    positionalUsage: 'SCRIPT',
    examples: ['akari script run greetd-test/display-layout.py -- capture'],
  ),
];

CliCommand getCliCommand(String spelling) {
  for (final command in cliCommands) {
    if (command.spellings.contains(spelling)) return command;
  }
  throw FormatException('Unknown command: $spelling');
}

(CliCommand, List<String>) getCliInvocation(List<String> arguments) {
  CliCommand? selected;
  var consumed = 0;
  for (final command in cliCommands) {
    for (final spelling in command.spellings) {
      final words = spelling.split(' ');
      if (words.length > consumed &&
          arguments.length >= words.length &&
          List.generate(
            words.length,
            (index) => arguments[index] == words[index],
          ).every((matches) => matches)) {
        selected = command;
        consumed = words.length;
      }
    }
  }
  if (selected == null) {
    throw FormatException('Unknown command: ${arguments.first}');
  }
  return (selected, arguments.sublist(consumed));
}

List<CliCommand> getCliSubcommands(String parent) => [
  for (final command in cliCommands)
    if (command.name.startsWith('$parent ')) command,
];

List<CliOption> getCliOptions(CliCommand command) => [
  for (final name in command.options) cliOptions[name]!,
  if (command.hasRunReport) ...[
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

// The command table binds external spellings to these internal identities once.
// Development workflows consume the identity without parsing command strings.
enum DevelopmentCommand {
  build,
  splash,
  run(runTarget: ThemeRunTarget.greeter),
  sway(runTarget: ThemeRunTarget.sway),
  preview,
  studio(runTarget: ThemeRunTarget.studio),
  verify,
  verifyPerf,
  tracePerf,
  generateScenes;

  const DevelopmentCommand({this.runTarget});
  final ThemeRunTarget? runTarget;

  bool get isThemeSelectionRequired => switch (this) {
    verify || generateScenes || splash => false,
    _ => true,
  };
}
