import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:scene/scene.dart';
import 'package:scene/src/runtime/state_effects.dart';

void main() {
  testWidgets(
    'SVG assets render independently of theme factories and retain their source across tint edits',
    (tester) async {
      var loads = 0;
      Future<String> loadSvg(String asset) async {
        loads++;
        return '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="#000000"/></svg>';
      }

      Future<void> render(int tint) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              document: _document(
                nodes: [
                  SceneNode(
                    id: 'icon',
                    componentId: 'sceneAsset',
                    asset: SceneAsset(
                      path: 'assets/icon.svg',
                      kind: SceneAssetKind.svg,
                      tint: tint,
                    ),
                    rect: const SceneRect(x: 0, y: 0, width: 1, height: 1),
                  ),
                ],
              ),
              theme: ThemeBundle(tokens: _tokens()),
              assetSvgLoader: loadSvg,
              nodeBuilder: (_, _) => throw StateError(
                'Asset nodes must not enter the component factory',
              ),
            ),
          ),
        ),
      );
      await render(0xffff0000);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        const ColorFilter.mode(Color(0xffff0000), BlendMode.srcIn),
      );
      final state = tester.state(find.byType(SceneAssetView));
      await render(0xff00ff00);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(SceneAssetView)), same(state));
      expect(loads, 1);
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        const ColorFilter.mode(Color(0xff00ff00), BlendMode.srcIn),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'state-entry effects trigger once, reset and respect reduced motion',
    (tester) async {
      final predicates = ValueNotifier<Set<ScenePredicate>>({});
      addTearDown(predicates.dispose);
      final document = _document(
        nodes: const [
          SceneNode(
            id: 'form',
            componentId: 'form',
            stateEffects: {ScenePredicate.isAuthError: SceneStateEffect.shake},
            motionTiming: SceneMotionTiming(durationMs: 800),
            rect: SceneRect(x: .1, y: .1, width: .8, height: .8),
          ),
        ],
      );
      Future<void> render(bool reduced) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              document: document,
              theme: ThemeBundle(tokens: _tokens(disableAnimations: reduced)),
              activePredicatesListenable: predicates,
              nodeBuilder: (_, _) => const Text('Form'),
            ),
          ),
        ),
      );
      double translation() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(SceneStateEffects),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .entry(0, 3);
      await render(false);
      predicates.value = {ScenePredicate.isAuthError};
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(translation().abs(), greaterThan(.1));
      await tester.pumpAndSettle();
      expect(translation(), closeTo(0, 1e-8));
      predicates.value = {
        ScenePredicate.isAuthError,
        ScenePredicate.isServiceReady,
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(translation(), closeTo(0, 1e-8));
      predicates.value = {};
      await tester.pump();
      predicates.value = {ScenePredicate.isAuthError};
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(translation().abs(), greaterThan(.1));
      await render(true);
      expect(translation(), closeTo(0, 1e-8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline samples the same delayed Bezier motion as live playback',
    (tester) async {
      final document = _document(
        nodes: const [
          SceneNode(
            id: 'motion',
            componentId: 'text',
            motion: SceneMotionPreset.fade,
            motionTiming: SceneMotionTiming(
              durationMs: 1000,
              delayMs: 500,
              curve: SceneCubicBezier(0, 0, 1, 1),
            ),
            rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
          ),
        ],
      );
      Future<void> render(Duration? elapsed) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              key: ValueKey(elapsed == null),
              document: document,
              theme: ThemeBundle(
                tokens: _tokens(),
                motions: const {SceneMotionPreset.fade: FadeMotionBuilder()},
              ),
              playback: elapsed == null
                  ? null
                  : ScenePlayback(
                      elapsed: elapsed,
                      from: const {},
                      enterAll: true,
                    ),
              nodeBuilder: (_, _) => const Text('Motion sample'),
            ),
          ),
        ),
      );
      await render(const Duration(milliseconds: 1000));
      final sampled = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      expect(sampled, closeTo(.5, 1e-5));
      await render(null);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).last)
            .opacity
            .value,
        closeTo(0, 1e-5),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).last)
            .opacity
            .value,
        closeTo(sampled, 1e-5),
      );
    },
  );

  testWidgets(
    'style tokens update typography without replacing component state',
    (tester) async {
      final controller = TextEditingController(text: 'retained');
      addTearDown(controller.dispose);
      final document = _document(
        nodes: const [
          SceneNode(
            id: 'label',
            componentId: 'text',
            styleToken: 'type',
            rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
          ),
        ],
      );
      Future<void> render(SceneStyle style) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              document: document.copyWith(styleTokens: {'type': style}),
              theme: ThemeBundle(tokens: _tokens()),
              nodeBuilder: (context, node) => Builder(
                builder: (context) => TextField(
                  key: const ValueKey('styled-input'),
                  controller: controller,
                  style: getSceneTextStyle(
                    context,
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await render(const SceneStyle(fontSize: 24, textColor: 0xff112233));
      final state = tester.state(find.byKey(const ValueKey('styled-input')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('styled-input')))
            .style!
            .fontSize,
        24,
      );
      await render(
        const SceneStyle(
          fontSize: 32,
          textColor: 0xff445566,
          radius: 20,
          backgroundBlur: 8,
        ),
      );
      expect(
        tester.state(find.byKey(const ValueKey('styled-input'))),
        same(state),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('styled-input')))
            .style!
            .color,
        const Color(0xff445566),
      );
      expect(controller.text, 'retained');
    },
  );

  testWidgets('frames own child layout, transforms and presence', (
    tester,
  ) async {
    final document = _document(
      nodes: const [
        SceneNode(
          id: 'frame',
          componentId: 'frame',
          rect: SceneRect(x: .1, y: .1, width: .8, height: .8),
          layout: SceneLayout(
            direction: SceneLayoutDirection.column,
            padding: 16,
            gap: 8,
          ),
          visibleWhen: ScenePredicateCondition(ScenePredicate.isAuthPrompting),
        ),
        SceneNode(
          id: 'input',
          componentId: 'input',
          parentId: 'frame',
          interactive: true,
          rect: SceneRect(x: 0, y: 0, width: 1, height: .1),
          sizing: SceneSizing(height: 50),
        ),
      ],
    );
    Future<void> render(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneRuntime(
            document: document,
            theme: ThemeBundle(tokens: _tokens()),
            activePredicates: {if (visible) ScenePredicate.isAuthPrompting},
            nodeBuilder: (_, node) => Text(node.id),
          ),
        ),
      ),
    );
    await render(true);
    expect(find.text('frame'), findsNothing);
    expect(find.text('input').hitTestable(), findsOneWidget);
    final input = tester.getRect(find.text('input'));
    expect(
      input.top,
      greaterThan(tester.getSize(find.byType(Scaffold)).height * .1),
    );
    expect(input.height, 50);
    await render(false);
    expect(find.text('input').hitTestable(), findsNothing);
  });

  testWidgets(
    'theme no-motion policy reaches custom components and preserves their state',
    (tester) async {
      final document = _document(
        nodes: const [
          SceneNode(
            id: 'custom',
            componentId: 'custom',
            rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
          ),
        ],
      );
      final controller = TextEditingController(text: 'retained');
      addTearDown(controller.dispose);
      bool? reduced;
      Future<void> render(bool disabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneRuntime(
              document: document,
              theme: ThemeBundle(tokens: _tokens(disableAnimations: disabled)),
              nodeBuilder: (context, node) {
                reduced = MediaQuery.disableAnimationsOf(context);
                return TextField(
                  key: const ValueKey('custom-input'),
                  controller: controller,
                );
              },
            ),
          ),
        ),
      );
      await render(false);
      final state = tester.state(find.byKey(const ValueKey('custom-input')));
      expect(reduced, isFalse);
      await render(true);
      expect(reduced, isTrue);
      expect(
        tester.state(find.byKey(const ValueKey('custom-input'))),
        same(state),
      );
      expect(controller.text, 'retained');
    },
  );

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

    buildCount = 0;
    final stableBuilder = _countPrewarmedNodeBuilds((_) => buildCount++);
    Widget buildStableHost(Set<ScenePredicate> active) {
      return MaterialApp(
        home: Scaffold(
          body: SceneRuntime(
            document: document,
            theme: theme,
            activePredicates: active,
            activePredicatesListenable: predicates,
            prewarmHiddenNodes: true,
            nodeBuilder: stableBuilder,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildStableHost(const {}));
    expect(buildCount, 1);
    await tester.pumpWidget(buildStableHost(const {ScenePredicate.isDormant}));
    expect(buildCount, 1);

    predicates.dispose();
  });

  testWidgets('preserves mounted node state when renderOrder changes', (
    tester,
  ) async {
    const first = SceneNode(
      id: 'first',
      componentId: 'decoration',
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      renderOrder: 10,
    );
    const second = SceneNode(
      id: 'second',
      componentId: 'decoration',
      rect: SceneRect(x: 0.4, y: 0.1, width: 0.2, height: 0.2),
      renderOrder: 20,
    );
    await tester.pumpWidget(_runtime(_document(nodes: const [first, second])));
    final firstElement = tester.element(find.byKey(const ValueKey('first')));
    final secondElement = tester.element(find.byKey(const ValueKey('second')));

    await tester.pumpWidget(
      _runtime(_document(nodes: [first.copyWith(renderOrder: 30), second])),
    );
    expect(
      tester.element(find.byKey(const ValueKey('first'))),
      same(firstElement),
    );
    expect(
      tester.element(find.byKey(const ValueKey('second'))),
      same(secondElement),
    );
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

SceneNodeBuilder _countPrewarmedNodeBuilds(void Function(SceneNode) onBuild) {
  return (context, node) {
    onBuild(node);
    return Text(node.id);
  };
}

ThemeTokens _tokens({bool disableAnimations = false}) {
  return ThemeTokens(
    materialTheme: ThemeData.dark(),
    panelRadius: 12,
    mediumMotion: const Duration(milliseconds: 200),
    standardCurve: Curves.easeOut,
    minHitTarget: 44,
    surfaceColor: Colors.black,
    surfaceVariantColor: Colors.black,
    disableAnimations: disableAnimations,
  );
}
