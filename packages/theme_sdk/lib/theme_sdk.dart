/// Public contract for compiled Akari themes.
///
/// Start with [ThemeDefinition] to assemble a scene, visual bundle, and component
/// factory. Components receive a [GreeterHost] with typed display slots and
/// semantic callbacks; authentication and transport remain owned by the greeter.
/// Scene model and runtime types are re-exported for theme authors.
library;

export 'package:scene/scene.dart';

export 'src/greeter_host.dart';
export 'src/greeter_models.dart';
export 'src/greeter_slots.dart';
export 'src/palette_extractor.dart';
export 'src/scene_region.dart';
export 'src/theme_components.dart';
export 'src/theme_definition.dart';
