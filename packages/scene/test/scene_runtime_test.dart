import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

void main() {
  for (final preset in [SceneMotionPreset.none, SceneMotionPreset.fade]) {
    testWidgets('prewarmed state survives presence changes with $preset', (
      tester,
    ) async {
      final predicates = ValueNotifier<Set<ScenePredicate>>({});
      addTearDown(predicates.dispose);
      const componentKey = ValueKey('retained-input');
      final controller = TextEditingController(text: 'retained');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              document: _document(
                nodes: [
                  SceneNode(
                    id: 'input',
                    componentId: 'decoration',
                    rect: const SceneRect(
                      x: 0.1,
                      y: 0.1,
                      width: 0.4,
                      height: 0.2,
                    ),
                    motion: preset,
                    visibleWhen: const ScenePredicateCondition(
                      ScenePredicate.isDormant,
                    ),
                  ),
                ],
              ),
              theme: ThemeBundle(
                tokens: _tokens(),
                motions: const {SceneMotionPreset.fade: FadeMotionBuilder()},
              ),
              activePredicatesListenable: predicates,
              prewarmHiddenNodes: true,
              nodeBuilder: (context, node) =>
                  TextField(key: componentKey, controller: controller),
            ),
          ),
        ),
      );
      final originalState = tester.state(find.byKey(componentKey));
      for (final visible in [true, false, true]) {
        predicates.value = visible ? {ScenePredicate.isDormant} : {};
        await tester.pumpAndSettle();
        expect(tester.state(find.byKey(componentKey)), same(originalState));
        expect(
          find.byKey(componentKey).hitTestable(),
          visible ? findsOneWidget : findsNothing,
        );
      }
    });
  }

  for (final prewarm in [false, true]) {
    testWidgets('applies hover motion with prewarming $prewarm', (
      tester,
    ) async {
      final predicates = ValueNotifier<Set<ScenePredicate>>({
        ScenePredicate.isDormant,
      });
      addTearDown(predicates.dispose);
      final document = _document(
        nodes: const [
          SceneNode(
            id: 'hover',
            componentId: 'decoration',
            rect: SceneRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            motion: SceneMotionPreset.hoverLift,
            visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
          ),
        ],
      );
      final theme = ThemeBundle(
        tokens: _tokens(),
        motions: const {SceneMotionPreset.hoverLift: HoverLiftMotionBuilder()},
      );
      await tester.pumpWidget(
        _runtimeWithTheme(
          document,
          theme,
          activePredicates: predicates.value,
          activePredicatesListenable: predicates,
          prewarmHiddenNodes: prewarm,
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final target = find.byKey(const ValueKey('hover'));
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.02,
      );

      predicates.value = {};
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsNothing);
      if (prewarm) {
        expect(target, findsOneWidget);
        expect(
          find.ancestor(of: target, matching: find.byType(ExcludeFocus)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: target, matching: find.byType(ExcludeSemantics)),
          findsOneWidget,
        );
      } else {
        expect(target, findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('suppresses hover motion when animations are disabled', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'hover',
          componentId: 'decoration',
          rect: SceneRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
          motion: SceneMotionPreset.hoverLift,
        ),
      ],
    );
    await tester.pumpWidget(
      _runtimeWithTheme(
        document,
        ThemeBundle(
          tokens: _tokens(),
          motions: const {
            SceneMotionPreset.hoverLift: HoverLiftMotionBuilder(),
          },
        ),
        disableAnimations: true,
      ),
    );
    expect(find.text('hover'), findsOneWidget);
    expect(find.byType(AnimatedScale), findsNothing);
  });
  testWidgets('keeps node elements mounted across identity transforms', (
    tester,
  ) async {
    const node = SceneNode(
      id: 'editable',
      componentId: 'decoration',
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
    );
    await tester.pumpWidget(_runtime(_document(nodes: [node])));
    final element = tester.element(find.byKey(const ValueKey('editable')));
    for (final transform in const [
      SceneTransform(scaleX: 1.2, rotationY: 25, rotationZ: 40),
      SceneTransform(),
    ]) {
      await tester.pumpWidget(
        _runtime(_document(nodes: [node.copyWith(transform: transform)])),
      );
      expect(
        tester.element(find.byKey(const ValueKey('editable'))),
        same(element),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('isolates each scene node behind its own repaint boundary', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'static',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ),
        SceneNode(
          id: 'animated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.4, y: 0.1, width: 0.2, height: 0.2),
          motion: SceneMotionPreset.fade,
        ),
      ],
    );
    final theme = ThemeBundle(
      tokens: _tokens(),
      backgrounds: const {SceneBackgroundKind.solid: SolidBackgroundRenderer()},
      motions: const {SceneMotionPreset.fade: FadeMotionBuilder()},
    );
    const rootBoundaryKey = ValueKey('root-boundary');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: rootBoundaryKey,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SceneRuntime(
              document: document,
              theme: theme,
              nodeBuilder: (context, node) =>
                  Text(node.id, key: ValueKey(node.id)),
            ),
          ),
        ),
      ),
    );

    for (final id in ['static', 'animated']) {
      final nearestBoundary = find
          .ancestor(
            of: find.byKey(ValueKey(id)),
            matching: find.byType(RepaintBoundary),
          )
          .first;
      expect(
        tester.widget<RepaintBoundary>(nearestBoundary).key,
        isNot(rootBoundaryKey),
      );
    }
  });

  testWidgets('paints nodes in explicit render order', (tester) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'later',
          componentId: 'decoration',
          rect: SceneRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
          renderOrder: 20,
        ),
        SceneNode(
          id: 'earlier',
          componentId: 'decoration',
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
          componentId: 'primaryAction',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.001, height: 0.001),
          interactive: true,
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document));

    final size = tester.getSize(find.byKey(const ValueKey('tiny_action')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets(
    'falls back to a solid background when no renderer is registered',
    (tester) async {
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
            componentId: 'decoration',
            rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          ),
        ],
      );

      await tester.pumpWidget(_runtime(document));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overrides the document background blur when provided', (
    tester,
  ) async {
    final renderer = _RecordingBackgroundRenderer();
    final document = SceneDocument(
      id: 'test',
      version: 1,
      canvas: const SceneCanvas(useSafeArea: false),
      background: const SceneBackground(
        kind: SceneBackgroundKind.image,
        blurSigma: 12,
      ),
      nodes: const [
        SceneNode(
          id: 'content',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ),
      ],
    );
    final theme = ThemeBundle(
      tokens: _tokens(),
      backgrounds: {SceneBackgroundKind.image: renderer},
    );

    await tester.pumpWidget(
      _runtimeWithTheme(document, theme, backgroundBlurSigma: 0),
    );
    expect(renderer.background?.blurSigma, 0);

    await tester.pumpWidget(_runtimeWithTheme(document, theme));
    expect(renderer.background?.blurSigma, 12);
  });

  testWidgets('gates a node on its visibleWhen condition', (tester) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'gated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document));
    expect(find.text('gated'), findsNothing);

    await tester.pumpWidget(
      _runtime(document, activePredicates: const {ScenePredicate.isDormant}),
    );
    expect(find.text('gated'), findsOneWidget);
  });

  testWidgets('prewarms hidden node layout when enabled', (tester) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'gated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      ],
    );

    await tester.pumpWidget(_runtime(document, prewarmHiddenNodes: true));
    expect(find.text('gated'), findsOneWidget);

    await tester.pumpWidget(
      _runtime(
        document,
        activePredicates: const {ScenePredicate.isDormant},
        prewarmHiddenNodes: true,
      ),
    );
    expect(find.text('gated'), findsOneWidget);
  });

  testWidgets('updates prewarmed visibility from its predicate listenable', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'gated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      ],
    );
    final activePredicates = ValueNotifier<Set<ScenePredicate>>({});

    await tester.pumpWidget(
      _runtime(
        document,
        activePredicatesListenable: activePredicates,
        prewarmHiddenNodes: true,
      ),
    );
    final gated = find.text('gated');
    expect(gated.hitTestable(), findsNothing);

    activePredicates.value = const {ScenePredicate.isDormant};
    await tester.pump();
    expect(gated.hitTestable(), findsOneWidget);

    activePredicates.dispose();
  });

  testWidgets('reuses the prewarmed node subtree on visibility changes', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'gated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      ],
    );
    final predicates = ValueNotifier<Set<ScenePredicate>>({});
    var buildCount = 0;
    final theme = ThemeBundle(
      tokens: _tokens(),
      backgrounds: const {SceneBackgroundKind.solid: SolidBackgroundRenderer()},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneRuntime(
            document: document,
            theme: theme,
            activePredicates: predicates.value,
            activePredicatesListenable: predicates,
            prewarmHiddenNodes: true,
            nodeBuilder: (context, node) {
              buildCount++;
              return Text(node.id);
            },
          ),
        ),
      ),
    );
    expect(buildCount, 1);

    predicates.value = const {ScenePredicate.isDormant};
    await tester.pump();
    expect(buildCount, 1);

    predicates.dispose();
  });

  testWidgets('keeps a node mounted through its exit transition', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'gated',
          componentId: 'decoration',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          motion: SceneMotionPreset.fade,
          visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      ],
    );
    final theme = ThemeBundle(
      tokens: _tokens(),
      backgrounds: const {SceneBackgroundKind.solid: SolidBackgroundRenderer()},
      motions: const {SceneMotionPreset.fade: FadeMotionBuilder()},
    );

    await tester.pumpWidget(
      _runtimeWithTheme(
        document,
        theme,
        activePredicates: const {ScenePredicate.isDormant},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('gated'), findsOneWidget);

    await tester.pumpWidget(
      _runtimeWithTheme(document, theme, activePredicates: const {}),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('gated'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('gated'), findsNothing);
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

Widget _runtime(
  SceneDocument document, {
  Set<ScenePredicate> activePredicates = const <ScenePredicate>{},
  ValueListenable<Set<ScenePredicate>>? activePredicatesListenable,
  bool prewarmHiddenNodes = false,
}) {
  final theme = ThemeBundle(
    tokens: _tokens(),
    backgrounds: const {SceneBackgroundKind.solid: SolidBackgroundRenderer()},
  );
  return _runtimeWithTheme(
    document,
    theme,
    activePredicates: activePredicates,
    activePredicatesListenable: activePredicatesListenable,
    prewarmHiddenNodes: prewarmHiddenNodes,
  );
}

Widget _runtimeWithTheme(
  SceneDocument document,
  ThemeBundle theme, {
  Set<ScenePredicate> activePredicates = const <ScenePredicate>{},
  ValueListenable<Set<ScenePredicate>>? activePredicatesListenable,
  double? backgroundBlurSigma,
  bool prewarmHiddenNodes = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: SceneRuntime(
          document: document,
          theme: theme,
          activePredicates: activePredicates,
          activePredicatesListenable: activePredicatesListenable,
          prewarmHiddenNodes: prewarmHiddenNodes,
          backgroundBlurSigma: backgroundBlurSigma == null
              ? null
              : AlwaysStoppedAnimation<double>(backgroundBlurSigma),
          nodeBuilder: (context, node) =>
              SizedBox.expand(key: ValueKey(node.id), child: Text(node.id)),
        ),
      ),
    ),
  );
}

class _RecordingBackgroundRenderer extends BackgroundRenderer {
  SceneBackground? background;

  @override
  Widget build(BuildContext context, SceneBackground background) {
    this.background = background;
    return const SizedBox.shrink();
  }
}

ThemeTokens _tokens() {
  return ThemeTokens(
    materialTheme: ThemeData.dark(),
    panelRadius: 12,
    mediumMotion: const Duration(milliseconds: 200),
    standardCurve: Curves.easeOut,
    minHitTarget: 44,
    surfaceColor: Colors.black,
    surfaceVariantColor: Colors.black,
  );
}
