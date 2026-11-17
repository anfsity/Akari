import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

typedef SceneFontLoader = Future<String> Function(String asset);

// Native font registrations last as long as the engine. Share this ownership
// between production text and Studio previews instead of registering per widget.
final _fontFamilies = ValueNotifier<Map<String, String>>(const {});
ValueListenable<Map<String, String>> get sceneFontFamilies => _fontFamilies;

final _fontLoads = <String, Future<String>>{};
var _nextFontId = 0;

Future<String> registerSceneFont({
  required String source,
  required String revision,
  String? asset,
  required Future<ByteData> Function() loadBytes,
}) async {
  final key = '$source:$revision';
  late final Future<String> pending;
  pending = _fontLoads.putIfAbsent(key, () async {
    final family = 'akari-font-${_nextFontId++}';
    try {
      await (FontLoader(family)..addFont(loadBytes())).load();
      return family;
    } on Object {
      if (identical(_fontLoads[key], pending)) {
        unawaited(_fontLoads.remove(key));
      }
      rethrow;
    }
  });
  final family = await pending;
  if (asset != null && _fontFamilies.value[asset] != family) {
    _fontFamilies.value = {..._fontFamilies.value, asset: family};
  }
  return family;
}

Future<String> loadBundledSceneFont(String asset) => registerSceneFont(
  source: asset,
  asset: asset,
  revision: 'bundle',
  loadBytes: () => rootBundle.load(asset),
);
