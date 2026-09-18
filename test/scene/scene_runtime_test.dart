import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  testWidgets('paints nodes in explicit render order', (tester) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'later',
          kind: SceneNodeKind.decoration,
          rect: SceneRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
          renderOrder: 20,
        ),
        SceneNode(
          id: 'earlier',
          kind: SceneNodeKind.decoration,
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          renderOrder: 10,
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document));

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .toList();
    expect(labels, ['earlier', 'later']);
  });

  testWidgets('enforces the minimum hit target for interactive nodes', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'tiny_action',
          kind: SceneNodeKind.primaryAction,
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.001, height: 0.001),
          action: SceneAction.beginAuthentication,
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document));

    final size = tester.getSize(find.byKey(const ValueKey('tiny_action')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('falls back to a solid background when no renderer is registered', (
    tester,
  ) async {
    final document = SceneDocument(
      id: 'fallback',
      version: 1,
      canvas: const SceneCanvas(useSafeArea: false),
      background: const SceneBackground(
        kind: SceneBackgroundKind.image,
        asset: 'assets/missing.jpg',
      ),
      nodes: const [
        SceneNode(
          id: 'content',
          kind: SceneNodeKind.decoration,
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document));
    expect(tester.takeException(), isNull);
  });
}

SceneDocument _document({required List<SceneNode> nodes}) {
  return SceneDocument(
    id: 'test',
    version: 1,
    canvas: const SceneCanvas(useSafeArea: false),
    background: const SceneBackground(kind: SceneBackgroundKind.solid),
    nodes: nodes,
  );
}

Widget _runtime(SceneDocument document) {
  final theme = ThemeBundle(
    id: 'test',
    tokens: _tokens(),
    document: document,
    backgrounds: const {
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
    },
  );
  return MaterialApp(
    home: Scaffold(
      body: SceneRuntime(
        document: document,
        theme: theme,
        nodeBuilder: (context, node) => SizedBox.expand(
          key: ValueKey(node.id),
          child: Text(node.id),
        ),
      ),
    ),
  );
}

ThemeTokens _tokens() {
  return ThemeTokens(
    materialTheme: ThemeData.dark(),
    pagePadding: EdgeInsets.zero,
    panelPadding: EdgeInsets.zero,
    contentMaxWidth: 400,
    controlHeight: 44,
    panelRadius: 12,
    sectionGap: 12,
    controlGap: 8,
    shortMotion: const Duration(milliseconds: 100),
    mediumMotion: const Duration(milliseconds: 200),
    standardCurve: Curves.easeOut,
    minHitTarget: 44,
    maxInteractiveRotationDegrees: 15,
    minTextScale: 0.9,
    allowBlur: false,
    blurSigma: 0,
    glassColor: Colors.black,
    scrimColor: Colors.black,
  );
}
