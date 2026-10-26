import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  testWidgets(
    'file image binding retains Terrace atmosphere and focal alignment',
    (tester) async {
      final theme = buildDefaultTheme();
      final image = MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
          'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
        ),
      );
      final renderer = theme.bundle.backgrounds[SceneBackgroundKind.image]!
          .getWithImageResolver((_) => image);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.build(context, theme.document.background),
            ),
          ),
        ),
      );
      expect(tester.widget<Image>(find.byType(Image)).image, same(image));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient != null,
        ),
        findsNWidgets(2),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).alignment,
        const Alignment(0.72, 0),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
