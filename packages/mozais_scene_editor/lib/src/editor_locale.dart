import 'editor_strings.dart';
import 'english_strings.dart';

/// One selectable editor language.
class EditorLocale {
  const EditorLocale({
    required this.code,
    required this.name,
    required this.strings,
  });

  final String code;
  final String name;
  final EditorStrings strings;
}

const defaultEditorLocaleCode = 'en';

/// Every language the editor ships. Adding one is a single entry here.
const editorLocales = <EditorLocale>[
  EditorLocale(code: 'en', name: 'English', strings: EnglishStrings()),
];

EditorStrings editorStringsFor(String code) {
  for (final locale in editorLocales) {
    if (locale.code == code) {
      return locale.strings;
    }
  }
  return editorLocales.first.strings;
}
