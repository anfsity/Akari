/// Compiled scene layout, presence, background, and motion runtime.
///
/// [SceneRuntime] renders a [SceneDocument] using a [ThemeBundle] and a theme's
/// node builder. The runtime owns animation lifetime and node layout; components
/// own visual content. The Flutter-free scene schema is re-exported here.
library;

export 'package:scene_schema/scene_schema.dart';

export 'src/model/theme_bundle.dart';
export 'src/model/theme_tokens.dart';
export 'src/runtime/background_renderer.dart';
export 'src/runtime/builtin_backgrounds.dart';
export 'src/runtime/builtin_motions.dart';
export 'src/runtime/motion.dart';
export 'src/runtime/node_transform.dart';
export 'src/runtime/scene_runtime.dart';
