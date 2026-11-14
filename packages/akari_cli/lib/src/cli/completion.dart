import 'definition.dart';
import 'scripts.dart';

String getShellCompletion(String shell) =>
    shell == 'zsh' ? _getZshCompletion() : _getBashCompletion();

String _getZshCompletion() {
  final commands = [
    for (final command in cliCommands)
      if (command.isRootCommand)
        for (final spelling in command.spellings)
          '      ${encodeShellArgument('$spelling:${command.description}')}\n',
  ].join();
  final subcommandCases = [
    for (final command in cliCommands)
      if (command.isSubcommand)
        '    ${encodeShellArgument(command.name)}) command=${encodeShellArgument(command.name)}; command_words=2;;\n',
  ].join();
  return [
    r'''#compdef akari
_akari() {
  local separator=${words[(i)--]}
  (( separator < CURRENT )) && return 0
  if (( CURRENT == 2 )); then
    local -a commands=(
''',
    commands,
    r'''    )
    _describe 'command' commands
    return
  fi
  local command="$words[2]" command_words=1
''',
    cliCommands.map(_encodeZshSubcommandCompletion).join(),
    r'''  case "$words[2] $words[3]" in
''',
    subcommandCases,
    '''  esac
  if [[ \$command == 'script run' ]] && (( CURRENT >= 4 )) && [[ "\$words[CURRENT]" != -* ]]; then
    local has_script=0 idx
    for (( idx = 4; idx < CURRENT; idx++ )); do
      if [[ "\${words[idx]}" != -* ]]; then
        has_script=1
        break
      fi
    done
    if (( ! has_script )); then
      local -a scripts=(${repositoryScripts.where((script) => script.kind != ScriptKind.library).map((script) => encodeShellArgument(script.path)).join(' ')})
      _describe 'script' scripts
      return
    fi
  fi
''',
    r'''  local -a options
  case "$command" in
''',
    cliCommands.map(_encodeZshCommandOptions).join(),
    r'''    *) return 0;;
  esac
  # Parse options after removing the command words, including a selected target.
  words=("$words[1]" "${words[@]:$((command_words + 1))}")
  (( CURRENT -= command_words ))
  _arguments -s "${options[@]}"
}
compdef _akari akari
''',
  ].join();
}

String _encodeZshSubcommandCompletion(CliCommand parent) {
  final subcommands = getCliSubcommands(parent.name);
  if (subcommands.isEmpty) return '';
  final targets = [
    for (final command in subcommands)
      '        ${encodeShellArgument('${command.name.substring(parent.name.length + 1)}:${command.description}')}\n',
  ].join();
  return '''  if [[ "\$words[2]" == ${encodeShellArgument(parent.name)} ]]; then
    if (( CURRENT == 3 )) && [[ "\$words[CURRENT]" != -* ]]; then
      local -a targets=(
$targets      )
      _describe 'subcommand' targets
      return
    fi
  fi
''';
}

String _encodeZshCommandOptions(CliCommand command) =>
    '''    ${command.spellings.map(encodeShellArgument).join('|')})
      options=(
${getCliOptions(command).map(_encodeZshOption).join()}      );;
''';

String _encodeZshOption(CliOption option) {
  final group = '(${option.spellings.join(' ')})';
  final description = option.description
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
  var suffix = '[$description]';
  if (option.valueName != null) {
    final action = option.values.isNotEmpty
        ? '(${option.values.join(' ')})'
        : option.valueName == 'PATH'
        ? (option.directory ? '_files -/' : '_files')
        : '';
    suffix += ':${option.valueName}:$action';
  }
  return [
    for (final spelling in option.spellings)
      '        ${encodeShellArgument('$group$spelling${option.valueName != null && spelling.startsWith('--') ? '=' : ''}$suffix')}\n',
  ].join();
}

String _getBashCompletion() {
  final commands = [
    for (final command in cliCommands)
      if (command.isRootCommand) ...command.spellings,
  ].join(' ');
  final subcommandCases = [
    for (final command in cliCommands)
      if (command.isSubcommand)
        '    ${encodeShellArgument(command.name)}) command=${encodeShellArgument(command.name)};;\n',
  ].join();
  return [
    r'''_akari() {
  COMPREPLY=()
  local i cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
  for (( i=1; i<COMP_CWORD; i++ )); do
    [[ "${COMP_WORDS[i]}" == -- ]] && return 0
  done
  if (( COMP_CWORD == 1 )); then
''',
    '''    mapfile -t COMPREPLY < <(compgen -W ${encodeShellArgument(commands)} -- "\$cur")
    return 0
  fi
''',
    r'''  local command="${COMP_WORDS[1]}"
''',
    cliCommands.map(_encodeBashSubcommandCompletion).join(),
    r'''  case "${COMP_WORDS[1]} ${COMP_WORDS[2]}" in
''',
    subcommandCases,
    '''  esac
  if [[ \$command == 'script run' ]] && (( COMP_CWORD >= 3 )) && [[ "\$cur" != -* ]]; then
    local has_script=0 idx
    for (( idx = 3; idx < COMP_CWORD; idx++ )); do
      if [[ "\${COMP_WORDS[idx]}" != -* ]]; then
        has_script=1
        break
      fi
    done
    if (( ! has_script )); then
      mapfile -t COMPREPLY < <(compgen -W ${encodeShellArgument(repositoryScripts.where((script) => script.kind != ScriptKind.library).map((script) => script.path).join(' '))} -- "\$cur")
      return 0
    fi
  fi
''',
    r'''  local option="$prev" value="$cur" prefix='' candidate options
  if [[ "$cur" == -*=* ]]; then
    option="${cur%%=*}"
    value="${cur#*=}"
    prefix="$option="
  elif [[ "$prev" == '=' ]] && (( COMP_CWORD >= 2 )); then
    option="${COMP_WORDS[COMP_CWORD-2]}"
  elif [[ "$cur" == '=' ]]; then
    value=''
  fi
  case "$command" in
''',
    cliCommands.map(_encodeBashCommandOptions).join(),
    r'''    *) return 0;;
  esac
  if [[ "$cur" == -* || -z "$cur" ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$options" -- "$cur")
  fi
  return 0
}
complete -F _akari akari
''',
  ].join();
}

String _encodeBashSubcommandCompletion(CliCommand parent) {
  final subcommands = getCliSubcommands(parent.name);
  if (subcommands.isEmpty) return '';
  final targets = subcommands
      .map((command) => command.name.substring(parent.name.length + 1))
      .join(' ');
  return '''  if (( COMP_CWORD == 2 )) && [[ "\$command" == ${encodeShellArgument(parent.name)} && "\$cur" != -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W ${encodeShellArgument(targets)} -- "\$cur")
    return 0
  fi
''';
}

String _encodeBashCommandOptions(CliCommand command) {
  final options = getCliOptions(command);
  return '''    ${command.spellings.map(encodeShellArgument).join('|')})
      options=${encodeShellArgument([for (final option in options) ...option.spellings].join(' '))}
      case "\$option" in
${options.where((option) => option.valueName != null).map(_encodeBashOptionValueCompletion).join()}      esac;;
''';
}

String _encodeBashOptionValueCompletion(CliOption option) {
  var completion = '';
  final isPath = option.valueName == 'PATH';
  if (option.values.isNotEmpty || isPath) {
    final generator = option.values.isNotEmpty
        ? '-W ${encodeShellArgument(option.values.join(' '))}'
        : option.directory
        ? '-d'
        : '-f';
    final filenamesHook = isPath
        ? '          compopt -o filenames 2>/dev/null || true\n'
        : '';
    completion =
        '''          while IFS= read -r candidate; do COMPREPLY+=("\$prefix\$candidate"); done < <(compgen $generator -- "\$value")
$filenamesHook''';
  }
  return '''        ${option.spellings.join('|')})
$completion          return 0;;
''';
}

String encodeShellArgument(String value) =>
    "'${value.replaceAll("'", "'\\''")}'";
