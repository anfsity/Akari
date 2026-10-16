import 'definition.dart';
import '../execution/model.dart';
import '../theme/model.dart';

/// Separates CLI input from the theme's arguments before interpreting options.
/// Help applies only to CLI input, even when the theme receives its own --help.
class CliArguments {
  CliArguments(this.raw) {
    final arguments = raw;
    final separator = arguments.indexOf('--');
    if (separator < 0) {
      options = arguments;
      theme = const [];
      forwardsArguments = false;
    } else {
      options = arguments.sublist(0, separator);
      theme = arguments.sublist(separator + 1);
      forwardsArguments = true;
    }
  }

  final List<String> raw;
  late final List<String> options;
  late final List<String> theme;
  late final bool forwardsArguments;

  bool get hasHelp =>
      options.any((argument) => argument == '-h' || argument == '--help');
}

/// Typed options for commands that plan and report a development run. Defaults
/// belong here; dispatch and execution consume already validated values.
class DevCommandOptions {
  DevCommandOptions._(
    Map<String, String> values,
    this.themeArguments,
    this.jobs,
    this.command,
  ) : format = values['--format'] == 'json'
          ? RunOutputFormat.json
          : RunOutputFormat.text,
      buildTarget = values['--platform'] ?? 'linux',
      buildMode = BuildMode.values.byName(
        values['--mode'] ??
            (command == DevelopmentCommand.build ? 'release' : 'debug'),
      ),
      reportPath = values['--report'],
      dryRun = values.containsKey('--dry-run'),
      themePath = values['--theme'],
      backendMode = BackendMode.values.byName(values['--backend'] ?? 'mock'),
      displayProfile = values['--display-profile'] ?? 'auto',
      resolution = values['--resolution'],
      scale = values['--scale'],
      splashDuration = values['--splash-duration'],
      splashLight = values.containsKey('--light'),
      swayBackend = SwayBackend.values.byName(
        values['--sway-backend'] ?? 'wayland',
      );

  factory DevCommandOptions.parse(CliCommand command, CliArguments arguments) {
    if (arguments.forwardsArguments && !command.forwardsArguments) {
      throw FormatException(
        '${command.name} does not accept theme arguments after --.',
      );
    }
    final values = getCliOptionValues(command, arguments.options);
    int? jobs;
    if (values['--jobs'] case final value?) {
      jobs = int.tryParse(value);
      if (jobs == null || jobs < 1) {
        throw const FormatException('--jobs must be a positive integer.');
      }
    }
    final options = DevCommandOptions._(
      values,
      arguments.theme,
      jobs,
      command.development!,
    );
    if (options.splashDuration case final value?) {
      final duration = double.tryParse(value);
      if (duration == null || !duration.isFinite || duration < 0) {
        throw const FormatException(
          '--splash-duration must be a finite, non-negative number of seconds.',
        );
      }
    }
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(options.buildTarget)) {
      throw FormatException(
        'Invalid Flutter build target: ${options.buildTarget}',
      );
    }
    return options;
  }

  final RunOutputFormat format;
  final List<String> themeArguments;
  final String buildTarget;
  final DevelopmentCommand command;
  final BuildMode buildMode;
  final String? reportPath;
  final bool dryRun;
  final String? themePath;
  final int? jobs;
  final BackendMode backendMode;
  final String displayProfile;
  final String? resolution;
  final String? scale;
  final SwayBackend swayBackend;
  final String? splashDuration;
  final bool splashLight;
}
