import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/theme_studio.dart';
import 'package:theme_studio/src/studio_preview.dart';

const _document = SceneDocument(
  id: 'test',
  version: currentSceneVersion,
  canvas: SceneCanvas(referenceWidth: 1280, referenceHeight: 720),
  background: SceneBackground(kind: SceneBackgroundKind.solid),
  nodes: [
    SceneNode(
      id: 'panel',
      componentId: 'panel',
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4),
    ),
    SceneNode(
      id: 'label',
      componentId: 'label',
      rect: SceneRect(x: 0.5, y: 0.2, width: 0.2, height: 0.2),
      visibleWhen: SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
    ),
  ],
);

class _Components implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) =>
      Center(child: Text(node.componentId));
}

ThemeDefinition _buildTheme({Color? seed}) => ThemeDefinition(
  id: 'test',
  document: _document,
  components: (_) => _Components(),
  bundle: ThemeBundle(
    tokens: ThemeTokens(
      materialTheme: material.ThemeData(),
      panelRadius: 8,
      mediumMotion: Duration.zero,
      standardCurve: Curves.linear,
      minHitTarget: 44,
      surfaceColor: const Color(0xff222222),
      surfaceVariantColor: const Color(0xff333333),
    ),
  ),
);

void main() {
  late Directory directory;
  late File file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('studio-ui-');
    file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(encodeSceneDocument(_document));
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> openStudio(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ThemeStudioApp(themeBuilder: _buildTheme, scenePaths: [file.path]),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'drag uses canvas scale, stays in bounds and creates one undo step',
    (tester) async {
      await openStudio(tester);
      final target = find.byKey(const ValueKey('preview-panel'));
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(2000, 2000));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(moved.document.nodes.first.rect.x, closeTo(0.7, 0.00001));
      expect(moved.document.nodes.first.rect.y, closeTo(0.6, 0.00001));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .x,
        0.1,
      );
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.x,
        closeTo(0.7, 0.00001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid inspector drafts block dragging', (tester) async {
    await openStudio(tester);
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '2');
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(80, 40),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first
          .rect
          .x,
      0.1,
    );
    expect(find.textContaining('non-normalized rect'), findsOneWidget);
  });

  testWidgets('select, edit, undo, redo and save through shadcn controls', (
    tester,
  ) async {
    await openStudio(tester);
    expect(find.byType(ShadcnApp), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-label')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
      'label',
    );
    await tester.enterText(find.byKey(const ValueKey('field-X')), '0.6');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Apply to preview'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .last
          .rect
          .x,
      0.6,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .last
          .rect
          .x,
      0.5,
    );
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(decodeSceneDocument(file.readAsStringSync()).nodes.last.rect.x, 0.6);
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid edits preserve preview and block save, valid drafts save directly',
    (tester) async {
      await openStudio(tester);
      final source = file.readAsStringSync();
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(file.readAsStringSync(), source);
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .width,
        0.3,
      );
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '0.4');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.width,
        0.4,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate applies drafts and updates layers, selection and saved nodes',
    (tester) async {
      await openStudio(tester);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
      await tester.tap(find.text('Duplicate node'));
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.selectedId, 'panel-copy');
      expect(preview.document.nodes.map((node) => node.id), [
        'panel',
        'panel-copy',
        'label',
      ]);
      expect(preview.document.nodes[0].rect.x, 0.2);
      expect(preview.document.nodes[1].rect.x, 0.2);
      expect(find.byKey(const ValueKey('layer-panel-copy')), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layer-panel-copy')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel',
      );
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel-copy',
      );
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes[1].id,
        'panel-copy',
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid drafts block duplicate and delete without changing the document',
    (tester) async {
      await openStudio(tester);
      final source = file.readAsStringSync();
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2');
      for (final action in ['Duplicate node', 'Delete node']) {
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final preview = tester.widget<StudioPreview>(
          find.byType(StudioPreview),
        );
        expect(preview.selectedId, 'panel');
        expect(encodeSceneDocument(preview.document), source);
        expect(find.textContaining('non-normalized rect'), findsOneWidget);
      }
      expect(file.readAsStringSync(), source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delete supports hidden nodes, restores drafts on undo and protects the last node',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-X')), '0.6');
      await tester.tap(find.text('Delete node'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layer-label')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel',
      );
      expect(
        tester
            .widget<OutlineButton>(
              find.widgetWithText(OutlineButton, 'Delete node'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('A scene needs at least one node.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final restored = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(restored.selectedId, 'label');
      expect(restored.document.nodes.last.rect.x, 0.6);
      expect(find.byKey(const ValueKey('layer-label')), findsOneWidget);
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.single.id,
        'panel',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dormant preview respects visibility and hidden nodes remain selectable in layers',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview-label')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'label',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reload requires explicit discard and retains node selection', (
    tester,
  ) async {
    await openStudio(tester);
    await tester.tap(find.byKey(const ValueKey('layer-label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
    await tester.tap(find.text('Reload from disk'));
    await tester.pumpAndSettle();
    expect(find.text('Discard edits and reload?'), findsOneWidget);
    await tester.tap(find.text('Discard and reload'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
      'label',
    );
    expect(tester.takeException(), isNull);
  });
}
