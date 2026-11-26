import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/inspector/node_inspector.dart';

import 'studio_app_test_harness.dart';

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'inspect follows selection, copies code and prevents canvas edits',
    (tester) async {
      await harness.openStudio(tester);
      final original = harness.file.readAsStringSync();
      await tester.tap(find.text('Inspect code'));
      await tester.pumpAndSettle();
      String getSource() => tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('inspect-code-source')),
          )
          .data!;
      expect(jsonDecode(getSource())['id'], 'panel');
      expect(find.byKey(const ValueKey('resize-right')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('preview-panel')),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        original,
      );
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      expect(jsonDecode(getSource())['id'], 'label');
      await tester.tap(find.text('Dart'));
      await tester.pumpAndSettle();
      expect(getSource(), contains("id: 'label'"));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy code'));
      await tester.pumpAndSettle();
      expect(copied, getSource());
      await tester.tap(find.text('Scene'));
      await tester.pumpAndSettle();
      expect(getSource(), contains('SceneDocument get testSceneDocument'));
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      expect(getSource(), original);
      await tester.tap(find.text('Design'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-X')), findsOneWidget);
      expect(find.byKey(const ValueKey('resize-right')), findsOneWidget);
      expect(harness.file.readAsStringSync(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid drafts block inspection and valid drafts reach copied code',
    (tester) async {
      await harness.openStudio(tester);
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await tester.tap(find.text('Inspect code'));
      await tester.pumpAndSettle();
      expect(find.text('Copy code'), findsNothing);
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await tester.tap(find.text('Inspect code'));
      await tester.pumpAndSettle();
      final source = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('inspect-code-source')),
          )
          .data!;
      expect(jsonDecode(source)['rect']['width'], 0.4);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .rect
            .width,
        0.4,
      );
    },
  );

  testWidgets('inspector drafts only rebuild controls that observe drafts', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Apply to preview'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
    await tester.pump();
    expect(find.text('Pending draft'), findsOneWidget);
    expect(find.text('Apply to preview').hitTestable(), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)),
      same(preview),
    );
    await tester.tap(find.text('Apply to preview'));
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Apply to preview'), findsNothing);
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first
          .rect
          .x,
      0.2,
    );
  });

  testWidgets('declared controls show defaults without creating scene edits', (
    tester,
  ) async {
    final source = harness.file.readAsStringSync();
    await harness.openStudio(
      tester,
      themeBuilder: ({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            componentCatalog: studioEditableCatalog,
          ),
    );
    expect(find.text('Panel appearance'), findsOneWidget);
    final text = find.byKey(const ValueKey('property-text'));
    expect(tester.widget<TextField>(text).controller!.text, 'Welcome');
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Text style'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(preview.document.nodes.first.properties, isEmpty);
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(
      decodeSceneDocument(harness.file.readAsStringSync())
          .nodes
          .first
          .properties,
      isEmpty,
    );
    expect(
      encodeSceneDocument(decodeSceneDocument(source)),
      encodeSceneDocument(decodeSceneDocument(harness.file.readAsStringSync())),
    );
  });

  testWidgets(
    'declared text and choices save, undo and reopen with private data',
    (tester) async {
      harness.file.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            nodes: [
              studioTestDocument.nodes.first.copyWith(
                properties: {'private': 'keep'},
              ),
              studioTestDocument.nodes.last,
            ],
          ),
        ),
      );
      ThemeDefinition buildEditable({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            componentCatalog: studioEditableCatalog,
          );
      await harness.openStudio(tester, themeBuilder: buildEditable);
      expect(find.byKey(const ValueKey('property-private')), findsNothing);
      final text = find.byKey(const ValueKey('property-text'));
      await tester.enterText(text, 'My desktop');
      await tester.pump();
      await tester.tap(find.text('Apply to preview'));
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('property-variant'));
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Large').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .properties,
        {'private': 'keep', 'text': 'My desktop', 'variant': 'large'},
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Regular'), findsOneWidget);
      expect(tester.widget<TextField>(text).controller!.text, 'My desktop');
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(text).controller!.text, 'Welcome');
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .properties,
        {'private': 'keep', 'text': 'My desktop', 'variant': 'large'},
      );

      await tester.pumpWidget(const SizedBox());
      await harness.openStudio(tester, themeBuilder: buildEditable);
      expect(tester.widget<TextField>(text).controller!.text, 'My desktop');
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported JSON choices keep the preview and can be repaired', (
    tester,
  ) async {
    await harness.openStudio(
      tester,
      themeBuilder: ({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            componentCatalog: studioEditableCatalog,
          ),
    );
    final inspector = tester
        .widget<NodeInspector>(find.byType(NodeInspector))
        .controller;
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    inspector.getField('Properties').text = '{"variant":"unsupported"}';
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to preview'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Property "variant" must be one of'),
      findsOneWidget,
    );
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
      same(preview.document),
    );
    expect(find.text('Choose a valid option'), findsOneWidget);
    final choice = find.byKey(const ValueKey('property-variant'));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();
    expect(inspector.error, isNull);
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first
          .properties,
      {'variant': 'large'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hot reload refreshes declared controls without resetting drafts',
    (tester) async {
      var catalog = const ThemeComponentCatalog();
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              seed: seed,
              document: document,
              componentCatalog: catalog,
            ),
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      catalog = studioEditableCatalog;
      final reload = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reload;
      expect(find.text('Panel appearance'), findsOneWidget);
      expect(find.text('Regular'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('field-X')))
            .controller!
            .text,
        '256',
      );
      await tester.tap(find.text('Apply to preview'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .x,
        0.2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspector sections preserve fields while scrolling', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final inspectorScroll = find
        .descendant(
          of: find.byType(NodeInspector),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Advanced properties'),
      200,
      scrollable: inspectorScroll,
    );
    await tester.tap(find.text('Advanced properties'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('field-Properties')),
      200,
      scrollable: inspectorScroll,
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-Properties')),
      '{"variant":"wide"}',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('field-X')),
      -200,
      scrollable: inspectorScroll,
    );
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    final node = decodeSceneDocument(harness.file.readAsStringSync())
        .nodes
        .first;
    expect(node.rect.x, 0.2);
    expect(node.properties, {'variant': 'wide'});
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'component fields apply on blur and stay synchronized with JSON and undo',
    (tester) async {
      harness.file.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            nodes: [
              studioTestDocument.nodes.first.copyWith(
                properties: {'variant': 'compact'},
              ),
              studioTestDocument.nodes.last,
            ],
          ),
        ),
      );
      await harness.openStudio(tester);
      expect(find.byKey(const ValueKey('field-Scale X')), findsNothing);
      final property = find.byKey(const ValueKey('property-variant'));
      await tester.enterText(property, 'wide');
      await tester.pump();
      expect(tester.widget<TextField>(property).controller!.text, 'wide');
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .properties['variant'],
        'compact',
      );
      await tester.tap(find.byKey(const ValueKey('field-X')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .properties['variant'],
        'wide',
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(property).controller!.text, 'compact');
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(property).controller!.text, 'wide');
      final scroll = find
          .descendant(
            of: find.byType(NodeInspector),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Advanced properties'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.text('Advanced properties'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('field-Properties')),
        200,
        scrollable: scroll,
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-Properties')),
        '{"variant":"narrow"}',
      );
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .properties['variant'],
        'narrow',
      );
      await tester.scrollUntilVisible(property, -200, scrollable: scroll);
      expect(tester.widget<TextField>(property).controller!.text, 'narrow');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'numeric fields apply on blur and unit selection creates no scene edit',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.text('Pixels'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Percent').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('field-Width')))
            .controller!
            .text,
        '30',
      );
      expect(find.text('Saved'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '40');
      await tester.tap(find.byKey(const ValueKey('field-Height')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .width,
        0.4,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester
            .widget<OutlineButton>(find.byKey(const ValueKey('toolbar-undo')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('select, edit, undo, redo and save through shadcn controls', (
    tester,
  ) async {
    await harness.openStudio(tester);
    expect(find.byType(ShadcnApp), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-label')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
      'label',
    );
    await tester.enterText(find.byKey(const ValueKey('field-X')), '768');
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
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
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
    await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(
      decodeSceneDocument(harness.file.readAsStringSync()).nodes.last.rect.x,
      0.6,
    );
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'save shortcut applies focused inspector drafts and validates them',
    (tester) async {
      await harness.openStudio(tester);
      final source = harness.file.readAsStringSync();
      Future<void> saveWithKeyboard() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await saveWithKeyboard();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(harness.file.readAsStringSync(), source);

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await saveWithKeyboard();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .rect
            .width,
        0.4,
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      harness.file.writeAsStringSync(source);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await saveWithKeyboard();
      expect(find.textContaining('The scene changed on disk'), findsOneWidget);
      expect(harness.file.readAsStringSync(), source);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid edits preserve preview and block save, valid drafts save directly',
    (tester) async {
      await harness.openStudio(tester);
      final source = harness.file.readAsStringSync();
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(harness.file.readAsStringSync(), source);
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
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .rect
            .width,
        0.4,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate applies drafts and updates layers, selection and saved nodes',
    (tester) async {
      await harness.openStudio(tester);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.tap(find.text('Duplicate'));
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
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layer-panel-copy')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel',
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel-copy',
      );
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes[1].id,
        'panel-copy',
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid drafts block duplicate and delete without changing the document',
    (tester) async {
      await harness.openStudio(tester);
      final source = harness.file.readAsStringSync();
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      for (final action in ['Duplicate', 'Delete']) {
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final preview = tester.widget<StudioPreview>(
          find.byType(StudioPreview),
        );
        expect(preview.selectedId, 'panel');
        expect(encodeSceneDocument(preview.document), source);
        expect(find.textContaining('non-normalized rect'), findsOneWidget);
      }
      expect(harness.file.readAsStringSync(), source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delete supports hidden nodes, restores drafts on undo and protects the last node',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-X')), '768');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layer-label')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'panel',
      );
      expect(
        tester
            .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Delete'))
            .onPressed,
        isNull,
      );
      expect(find.text('A scene needs at least one node.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      final restored = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(restored.selectedId, 'label');
      expect(restored.document.nodes.last.rect.x, 0.6);
      expect(find.byKey(const ValueKey('layer-label')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes.single.id,
        'panel',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
