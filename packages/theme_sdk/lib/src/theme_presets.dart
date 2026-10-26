import 'package:scene/scene.dart';

import 'theme_customization.dart';

/// Theme-wide preset choices share their typed values with the runtime builder.
/// Unknown keys remain code-owned, just as undeclared node properties do.
class ThemePresetCatalog {
  const ThemePresetCatalog({this.properties = const []});

  final List<ThemeChoiceProperty<Enum>> properties;

  void validateDocument(SceneDocument document) {
    for (final property in properties) {
      property.getValue(document.themeProperties);
    }
  }
}
