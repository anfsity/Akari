/// The reusable Mozais greeter UI: feature and scene composition.
///
/// This library has no backend dependency. The executable or a development
/// host supplies a `GreeterGateway` and a `SessionStore`.
library;

export 'feature/greeter_commands.dart';
export 'feature/greeter_effect.dart';
export 'feature/greeter_feature.dart';
export 'feature/greeter_slots.dart';
export 'feature/greeter_state.dart';
export 'feature/ports/greeter_gateway.dart';
export 'feature/ports/session_store.dart';
export 'scene/greeter_scene_adapter.dart';

export 'package:mozais_theme_sdk/mozais_theme_sdk.dart' show ThemeDefinition;
