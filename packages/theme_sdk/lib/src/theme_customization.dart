import 'package:scene/scene.dart';

/// Theme-owned editing capabilities. Unlisted components and properties remain
/// code-owned; this catalog does not replace the scene or component factory.
class ThemeComponentCatalog {
  const ThemeComponentCatalog({this.components = const {}});

  final Map<String, ThemeComponentDefinition> components;

  /// Checks authored values before a document reaches preview or history.
  /// Unknown properties are preserved so partial opt-in never loses theme data.
  void validateDocument(SceneDocument document) {
    for (final node in document.nodes) {
      final definition = components[node.componentId];
      if (definition == null) continue;
      for (final property in definition.properties) {
        try {
          property.getValue(node.properties);
        } on FormatException catch (error) {
          throw FormatException('Node "${node.id}": ${error.message}');
        }
      }
    }
  }
}

class ThemeComponentDefinition {
  const ThemeComponentDefinition({
    required this.label,
    this.properties = const [],
  });

  final String label;
  final List<ThemeProperty<Object>> properties;
}

/// Values retain the scene's string encoding. Reading an omitted property uses
/// its default without materializing it in the scene or creating an edit.
sealed class ThemeProperty<T extends Object> {
  const ThemeProperty({
    required this.name,
    required this.label,
    required this.defaultValue,
  });

  final String name;
  final String label;
  final T defaultValue;

  T getValue(Map<String, String> properties);
}

final class ThemeTextProperty extends ThemeProperty<String> {
  const ThemeTextProperty({
    required super.name,
    required super.label,
    required super.defaultValue,
  });

  @override
  String getValue(Map<String, String> properties) =>
      properties[name] ?? defaultValue;
}

/// Enum names are persisted identifiers; labels are presentation only. Authors
/// must include [defaultValue] in [choices] and keep enum names stable.
final class ThemeChoiceProperty<T extends Enum> extends ThemeProperty<T> {
  const ThemeChoiceProperty({
    required super.name,
    required super.label,
    required super.defaultValue,
    required this.choices,
  });

  final Map<T, String> choices;

  @override
  T getValue(Map<String, String> properties) {
    final value = properties[name];
    if (value == null) return defaultValue;
    for (final choice in choices.keys) {
      if (choice.name == value) return choice;
    }
    throw FormatException(
      'Property "$name" must be one of: '
      '${choices.keys.map((choice) => choice.name).join(', ')}.',
    );
  }
}
