import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';

import 'studio_app_test_harness.dart';

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> revealAssemblyControl(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('component-assembly')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'component library drops a slot at the canvas pointer in one edit',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              seed: seed,
              document: document,
              layout: studioAssemblyLayout,
            ),
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await revealAssemblyControl(
        tester,
        find.byKey(const ValueKey('select-slot-badge')),
      );
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(SceneRuntime));
      final target =
          canvas.topLeft + Offset(canvas.width * .6, canvas.height * .6);
      final drag = find.ancestor(
        of: find.byKey(const ValueKey('select-slot-badge')),
        matching: find.byType(Draggable<SceneNode>),
      );
      expect(drag, findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('select-slot-badge'))),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(find.text('Standby badge'), findsNWidgets(2));
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editor.selectedId, 'badge');
      expect(editor.selectedNode.rect.x, closeTo(.6, .001));
      expect(editor.selectedNode.rect.y, closeTo(.6, .001));
      editor.undo();
      expect(editor.document.nodes.any((node) => node.id == 'badge'), isFalse);
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'layout selector composes, repairs, saves and restores insertion defaults',
    (tester) async {
      ThemeDefinition buildLayouts({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            layout: studioAssemblyLayout,
          );
      await harness.openStudio(tester, themeBuilder: buildLayouts);
      final selector = find.byKey(const ValueKey('layout-preset'));
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Right column').last);
      await tester.pumpAndSettle();
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      expect(editor.document.themeProperties['layout'], 'right');
      expect(editor.document.nodes.first.rect.x, 0.5);
      expect(editor.missingRequiredSlots, isEmpty);
      expect(editor.document.nodes.any((node) => node.id == 'badge'), isFalse);
      final badge = find.byKey(const ValueKey('slot-badge'));
      await tester.ensureVisible(badge);
      await tester.pumpAndSettle();
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.rect.x, 0.6);
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(editor.document.nodes, hasLength(2));
      expect(editor.document.themeProperties, isEmpty);
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await harness.openStudio(tester, themeBuilder: buildLayouts);
      expect(find.text('Right column'), findsOneWidget);
      await tester.tap(find.text('Inspect code'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Select<String>>(
              find.descendant(
                of: selector,
                matching: find.byType(Select<String>),
              ),
            )
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assembly adds preset nodes, previews states and persists across reopening',
    (tester) async {
      ThemeDefinition buildAssembly({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            layout: studioAssemblyLayout,
          );
      await harness.openStudio(tester, themeBuilder: buildAssembly);
      expect(find.text('Test composition'), findsOneWidget);
      expect(find.byKey(const ValueKey('component-assembly')), findsOneWidget);
      expect(find.text('Optional components'), findsOneWidget);
      final add = find.byKey(const ValueKey('slot-badge'));
      await revealAssemblyControl(tester, add);
      expect(tester.widget<Checkbox>(add).state, CheckboxState.unchecked);
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final canvas = tester.widget<StudioCanvas>(find.byType(StudioCanvas));
      expect(canvas.editor!.selectedId, 'badge');
      expect(tester.widget<Checkbox>(add).state, CheckboxState.checked);
      expect(canvas.editor!.selectedNode.properties, {'text': 'Welcome'});
      expect(canvas.editor!.selectedNode.rect.x, 0.2);
      expect(find.byKey(const ValueKey('preview-badge')), findsNothing);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview-badge')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(canvas.editor!.selectedId, 'panel');
      expect(canvas.editor!.document.nodes, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await harness.openStudio(tester, themeBuilder: buildAssembly);
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      await revealAssemblyControl(tester, add);
      expect(tester.widget<Checkbox>(add).state, CheckboxState.checked);
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioCanvas>(find.byType(StudioCanvas))
            .editor!
            .document
            .nodes
            .any((node) => node.id == 'badge'),
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioCanvas>(find.byType(StudioCanvas))
            .editor!
            .document
            .nodes
            .singleWhere((node) => node.id == 'badge')
            .properties,
        {'text': 'Welcome'},
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'required repair is one undo step and canvas shortcuts respect slots',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              seed: seed,
              document: document,
              layout: studioAssemblyLayout,
            ),
      );
      expect(
        find.textContaining('Missing required components:'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('add-required-slots')));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      expect(editor.missingRequiredSlots, isEmpty);
      expect(editor.document.nodes, hasLength(4));
      expect(editor.selectedId, 'action');
      expect(editor.selectedNode.interactive, isTrue);
      expect(find.byKey(const ValueKey('layout-completeness')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-layers')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('layer-action')),
          matching: find.text('Sign-in action'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Delete'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlineButton>(
              find.widgetWithText(OutlineButton, 'Duplicate'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('preview-action')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(editor.document.nodes, hasLength(4));
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(editor.document.nodes, hasLength(2));
      expect(editor.canUndo, isFalse);
      expect(find.byKey(const ValueKey('add-required-slots')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-panel')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('component-assembly')),
          matching: find.text('Remove'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid drafts and inspection prevent assembly mutations', (
    tester,
  ) async {
    await harness.openStudio(
      tester,
      themeBuilder: ({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            layout: studioAssemblyLayout,
          ),
    );
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    final original = editor.document;
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
    await tester.tap(find.byKey(const ValueKey('sidebar-components')));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('slot-badge'));
    await revealAssemblyControl(tester, add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-required-slots')));
    await tester.pumpAndSettle();
    expect(editor.document, same(original));
    expect(editor.canUndo, isFalse);
    expect(find.textContaining('non-normalized rect'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '384');
    await tester.tap(find.text('Inspect code'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(add).enabled, isFalse);
    expect(
      tester
          .widget<OutlineButton>(
            find.byKey(const ValueKey('add-required-slots')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(editor.selectedId, 'badge');
    expect(editor.inspector.error, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading a different scene keeps its nodes outside layout constraints',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              seed: seed,
              document: document,
              layout: studioAssemblyLayout,
            ),
      );
      final other = File('${harness.directory.path}/other.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(studioTestDocument.copyWith(id: 'other')),
        );
      harness.picker.selected = StudioTestPickedFile(other);
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      expect(editor.layout, isNull);
      expect(editor.canDuplicateNode, isTrue);
      expect(find.byKey(const ValueKey('layout-completeness')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      expect(find.text('Component library'), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
