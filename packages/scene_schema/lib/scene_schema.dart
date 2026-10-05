/// Flutter-free scene model and authoring codec shared by tooling and codegen.
///
/// [decodeSceneDocument] validates JSON and normalizes supported versions into
/// the current model. [encodeSceneDocument] writes its authoring representation.
/// Production themes import generated Dart instead of decoding JSON at login.
library;

export 'src/scene_codec.dart';
export 'src/scene_document.dart';
