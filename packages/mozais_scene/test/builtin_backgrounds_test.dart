import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  testWidgets('clips a blurred background to the scene rectangle', (
    tester,
  ) async {
    const background = SceneBackground(
      kind: SceneBackgroundKind.image,
      asset: 'assets/wallpaper.png',
      blurSigma: 48,
    );
    const renderer = ImageBackgroundRenderer(resolveImage: _memoryImage);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 200,
          height: 100,
          child: Builder(
            builder: (context) => renderer.build(context, background),
          ),
        ),
      ),
    );

    final clip = tester.widget<ClipRect>(find.byType(ClipRect));
    expect(clip.clipBehavior, Clip.hardEdge);
    expect(
      find.descendant(
        of: find.byType(ClipRect),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
  });
}

ImageProvider _memoryImage(String asset) {
  return MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    ),
  );
}
