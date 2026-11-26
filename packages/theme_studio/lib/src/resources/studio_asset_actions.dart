import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_assets.dart';

String? getEffectiveBackgroundAsset(SceneBackground background) =>
    background.kind == SceneBackgroundKind.image ? background.asset : null;

Future<ui.Color?> resolveBackgroundSeedColor(
  StudioAssets assets,
  String asset,
) async {
  final file = assets.findFile(asset);
  if (file != null && file.existsSync()) {
    try {
      final bytes = await file.readAsBytes();
      return await decodeSeedColor(bytes);
    } on Object {
      return null;
    }
  }
  try {
    return await loadSeedColor(asset);
  } on Object {
    return null;
  }
}

Future<void> validateImageAssetFile(
  StudioAssets assets,
  String assetPath,
) async {
  final file = assets.findFile(assetPath);
  if (file == null) {
    throw FormatException('Asset "$assetPath" is not a local theme file.');
  }
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  codec.dispose();
}

Future<void> validatePlaceableAsset(
  StudioAssets assets,
  SceneAsset asset,
) async {
  if (asset.kind == SceneAssetKind.svg) {
    final source = await assets.loadTextAsset(asset.path);
    final picture = await vg.loadPicture(SvgStringLoader(source), null);
    picture.picture.dispose();
    return;
  }
  final bytes = await assets.loadBytes(asset.path);
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  codec.dispose();
}
