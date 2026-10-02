import 'cli_definition.dart';

String getShellCompletion(String shell) =>
    shell == 'zsh' ? _getZshCompletion() : _getBashCompletion();

String _getZshCompletion() {
  final script = StringBuffer(r'''#compdef mozais
_mozais() {
  local separator=${words[(i)--]}
  (( separator < CURRENT )) && return 0
  if (( CURRENT == 2 )); then
    local -a commands=(
''');
  for (final command in cliCommands) {
    for (final spelling in command.spellings) {
      script.writeln(
        '      ${encodeShellArgument('$spelling:${command.description}')}',
      );
    }
  }
  script.writeln(r'''    )
    _describe 'command' commands
    return
  fi
  local -a options
  case "$words[2]" in''');
  for (final command in cliCommands) {
    script.writeln('    ${command.spellings.join('|')})');
    script.writeln('      options=(');
    for (final option in getCliOptions(command)) {
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
      for (final spelling in option.spellings) {
        final equals = option.valueName != null && spelling.startsWith('--')
            ? '='
            : '';
        script.writeln(
          '        ${encodeShellArgument('$group$spelling$equals$suffix')}',
        );
      }
    }
    script.writeln('      );;');
  }
  script.writeln(r'''    *) return 0;;
  esac
  # Remove the subcommand before _arguments parses the command's options.
  words=("$words[1]" "${words[@]:2}")
  (( CURRENT-- ))
  _arguments -s "${options[@]}"
}
compdef _mozais mozais''');
  return script.toString();
}

String _getBashCompletion() {
  final script = StringBuffer(r'''_mozais() {
  COMPREPLY=()
  local i cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
  for (( i=1; i<COMP_CWORD; i++ )); do
    [[ "${COMP_WORDS[i]}" == -- ]] && return 0
  done
  if (( COMP_CWORD == 1 )); then
''');
  final commands = [for (final command in cliCommands) ...command.spellings];
  script.writeln(
    '    mapfile -t COMPREPLY < <(compgen -W ${encodeShellArgument(commands.join(' '))} -- "\$cur")',
  );
  script.writeln(r'''    return 0
  fi
  local option="$prev" value="$cur" prefix='' candidate options
  if [[ "$cur" == -*=* ]]; then
    option="${cur%%=*}"
    value="${cur#*=}"
    prefix="$option="
  elif [[ "$prev" == '=' ]] && (( COMP_CWORD >= 2 )); then
    option="${COMP_WORDS[COMP_CWORD-2]}"
  elif [[ "$cur" == '=' ]]; then
    value=''
  fi
  case "${COMP_WORDS[1]}" in''');
  for (final command in cliCommands) {
    script.writeln('    ${command.spellings.join('|')})');
    final options = getCliOptions(command);
    script.writeln(
      '      options=${encodeShellArgument([for (final option in options) ...option.spellings].join(' '))}',
    );
    script.writeln('      case "\$option" in');
    for (final option in options.where((option) => option.valueName != null)) {
      script.writeln('        ${option.spellings.join('|')})');
      if (option.values.isNotEmpty || option.valueName == 'PATH') {
        final generator = option.values.isNotEmpty
            ? '-W ${encodeShellArgument(option.values.join(' '))}'
            : option.directory
            ? '-d'
            : '-f';
        script.writeln(
          '          while IFS= read -r candidate; do COMPREPLY+=("\$prefix\$candidate"); done < <(compgen $generator -- "\$value")',
        );
      }
      script.writeln('          return 0;;');
    }
    script.writeln('      esac;;');
  }
  script.writeln(r'''    *) return 0;;
  esac
  if [[ "$cur" == -* || -z "$cur" ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$options" -- "$cur")
  fi
  return 0
}
complete -o filenames -F _mozais mozais''');
  return script.toString();
}

String encodeShellArgument(String value) =>
    "'${value.replaceAll("'", "'\\''")}'";
