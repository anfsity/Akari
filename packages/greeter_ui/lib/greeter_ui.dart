/// The reusable Akari greeter UI: feature and scene composition.
///
/// This library has no backend dependency. The executable or a development
/// host supplies a `GreeterGateway` and a `SessionStore`.
library;

export 'src/feature/greeter_commands.dart';
export 'src/feature/greeter_effect.dart';
export 'src/feature/greeter_feature.dart';
export 'src/feature/greeter_slots.dart';
export 'src/feature/greeter_state.dart';
export 'src/feature/ports/greeter_gateway.dart';
export 'src/feature/ports/session_store.dart';
export 'src/scene/greeter_scene_adapter.dart';

export 'package:theme_sdk/theme_sdk.dart' show ThemeDefinition;
