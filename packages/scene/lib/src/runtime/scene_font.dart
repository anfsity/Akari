import 'package:flutter/services.dart';

typedef SceneFontLoader = Future<String> Function(String asset);

// Native font registrations last as long as the engine. Share this ownership
// between production text and Studio previews instead of registering per widget.
final _fontLoads = <String, Future<String>>{};

Future<String> registerSceneFont({
  required String source,
  required String revision,
  required Future<ByteData> Function() loadBytes,
}) => _fontLoads.putIfAbsent('$source:$revision', () async {
  final family = 'akari-font-${_fontLoads.length}';
  await (FontLoader(family)..addFont(loadBytes())).load();
  return family;
});

Future<String> loadBundledSceneFont(String asset) => registerSceneFont(
  source: asset,
  revision: 'bundle',
  loadBytes: () => rootBundle.load(asset),
);
