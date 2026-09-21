/// The reusable Mozais greeter UI: feature, scene composition, and themes.
///
/// This library has no backend dependency. The app supplies a
/// `GreeterGateway` and a `SessionStore`; the editor supplies a demo gateway
/// and an in-memory document.
library;

export 'feature/greeter/greeter_commands.dart';
export 'feature/greeter/greeter_effect.dart';
export 'feature/greeter/greeter_feature.dart';
export 'feature/greeter/greeter_slots.dart';
export 'feature/greeter/greeter_state.dart';
export 'feature/greeter/ports/greeter_gateway.dart';
export 'feature/greeter/ports/session_store.dart';
export 'scene/greeter_scene/greeter_scene_adapter.dart';
export 'scene/scene_region.dart';
export 'theme/theme_registry.dart';
export 'themes/default/theme.dart';
export 'themes/fallback/theme.dart';
