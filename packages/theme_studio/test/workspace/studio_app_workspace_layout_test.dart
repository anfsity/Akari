import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/inspector/node_inspector.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/ui/studio_form.dart';
import 'package:theme_studio/src/model/studio_workspace_layout.dart';

import 'studio_app_test_harness.dart';

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'workspace docking groups preserve fields and restore the motion layout',
    (tester) async {
      await harness.openStudio(tester);
      final field = find.byKey(const ValueKey('field-X'));
      final state = tester.state(field);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('float-Sidebar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dock-right-Sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-tab-Sidebar')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dock-tab-Inspector')));
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      tester
          .widget<StudioEnumSelect<StudioWorkspaceMode>>(
            find.byKey(const ValueKey('workspace-preset')),
          )
          .onChanged(StudioWorkspaceMode.motion);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timeline-scrubber')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        (await StudioWorkspaceLayout.load()).sidebarDock,
        StudioDock.right,
      );
      expect(
        (await StudioWorkspaceLayout.load()).mode,
        StudioWorkspaceMode.motion,
      );
      expect(editor.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.openStudio(tester);
      expect(find.byKey(const ValueKey('dock-tab-Sidebar')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-scrubber')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'panel edges face outward and floating drags accumulate between frames',
    (tester) async {
      await harness.openStudio(tester);
      expect(
        tester.getCenter(find.byKey(const ValueKey('toggle-sidebar'))).dx,
        lessThan(40),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('toggle-inspector'))).dx,
        greaterThan(1360),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('studio-toolbar'))).dx,
        lessThan(100),
      );
      await tester.tap(find.byKey(const ValueKey('float-Sidebar')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('floating-Sidebar'));
      final before = tester.getRect(panel);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('float-drag-Sidebar'))),
      );
      await drag.moveBy(const Offset(40, 20));
      await drag.moveBy(const Offset(40, 20));
      await tester.pump();
      expect(tester.getTopLeft(panel) - before.topLeft, const Offset(80, 40));
      await drag.up();
      await tester.tap(find.byKey(const ValueKey('dock-Sidebar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('toggle-sidebar'))).dx,
        lessThan(40),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layer-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating panels and presentation retain drafts and component state',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final field = find.byKey(const ValueKey('field-X'));
      await tester.enterText(field, 'draft');
      final state = tester.state(field);
      await tester.tap(find.byKey(const ValueKey('float-Inspector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('floating-Inspector')), findsOneWidget);
      expect(tester.state(field), same(state));
      expect(editor.inspector.getField('X').text, 'draft');
      await tester.drag(
        find.byKey(const ValueKey('float-drag-Inspector')),
        const Offset(60, 20),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dock-Inspector')));
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      await tester.tap(find.byKey(const ValueKey('toggle-inspector')));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      await tester.tap(find.byKey(const ValueKey('toggle-inspector')));
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      await tester.tap(find.byKey(const ValueKey('presentation-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-toolbar')), findsNothing);
      expect(find.byKey(const ValueKey('exit-presentation')), findsOneWidget);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).interactive,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      expect(editor.inspector.getField('X').text, 'draft');
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main toolbar stays on one row and compact actions retain draft undo',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(seed: seed, document: document).copyWith(
              id: 'a-theme-with-a-long-name-that-must-not-displace-editor-actions',
            ),
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final original = editor.encodedDocument;
      for (final width in [1000.0, 1280.0, 1400.0, 1920.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('studio-toolbar')),
        );
        expect(toolbar.height, lessThanOrEqualTo(56));
        for (final action in [
          'studio-scene-menu',
          'toolbar-settings',
          'toolbar-undo',
          'toolbar-redo',
          'toolbar-save',
        ]) {
          final bounds = tester.getRect(find.byKey(ValueKey(action)));
          expect(bounds.center.dy, closeTo(toolbar.center.dy, 0.1));
          expect(bounds.left, greaterThanOrEqualTo(toolbar.left));
          expect(
            bounds.right,
            lessThanOrEqualTo(toolbar.right),
            reason: '$action at $width: $bounds, toolbar: $toolbar',
          );
        }
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(editor.inspector.hasDraft, isFalse);
      expect(editor.encodedDocument, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sizing controls stay readable and advanced limits remain editable',
    (tester) async {
      await harness.openStudio(tester);
      tester.view.physicalSize = const Size(1400, 1400);
      await tester.pumpAndSettle();
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final original = editor.encodedDocument;
      final widthMode = tester.getRect(
        find.byKey(const ValueKey('layout-width-mode')),
      );
      final heightMode = tester.getRect(
        find.byKey(const ValueKey('layout-height-mode')),
      );
      expect(widthMode.width, greaterThan(250));
      expect(heightMode.left, widthMode.left);
      expect(heightMode.right, widthMode.right);
      expect(heightMode.top, greaterThan(widthMode.bottom));
      expect(
        find.byKey(const ValueKey('layout-Max width')).hitTestable(),
        findsNothing,
      );
      final limits = find.byKey(const ValueKey('layout-size-constraints'));
      await tester.ensureVisible(limits);
      await tester.tap(limits);
      await tester.pumpAndSettle();
      final maxWidth = find.byKey(const ValueKey('layout-Max width'));
      await tester.ensureVisible(maxWidth);
      await tester.enterText(maxWidth, '420');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.sizing.maxWidth, 420);
      editor.undo();
      await tester.pumpAndSettle();
      expect(editor.encodedDocument, original);
      final add = find.byKey(const ValueKey('layout-add-breakpoint'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.breakpoints, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('layout-remove-breakpoint')));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.breakpoints, isEmpty);
      expect(editor.encodedDocument, original);
      editor.selectNode('label');
      editor.updateNode(
        editor.selectedNode.copyWith(sizing: const SceneSizing(maxWidth: 360)),
      );
      final constrained = editor.encodedDocument;
      editor.selectNode('panel');
      await tester.pumpAndSettle();
      expect(maxWidth.hitTestable(), findsNothing);
      editor.selectNode('label');
      await tester.pumpAndSettle();
      expect(maxWidth.hitTestable(), findsOneWidget);
      expect(editor.encodedDocument, constrained);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canvas toolbar stays compact and wraps within narrow panels', (
    tester,
  ) async {
    await harness.openStudio(tester);
    for (final width in [1100.0, 1400.0, 1800.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final canvasRect = tester.getRect(find.byType(StudioCanvas));
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('canvas-toolbar')),
      );
      expect(toolbar.width, canvasRect.width);
      expect(toolbar.height, lessThan(150));
      for (final name in [
        'tool-move',
        'canvas-hand',
        'canvas-tool-menu',
        'zoom-fit',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(name)));
        expect(rect.left, greaterThanOrEqualTo(canvasRect.left));
        expect(rect.right, lessThanOrEqualTo(canvasRect.right));
      }
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State: Dormant'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'layer list reveals canvas selection without scrolling on edits',
    (tester) async {
      harness.file.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            nodes: [
              for (var index = 0; index < 30; index++)
                studioTestDocument.nodes.first.copyWith(id: 'node-$index'),
            ],
          ),
        ),
      );
      await harness.openStudio(tester);
      expect(
        find.byKey(const ValueKey('layer-node-0')).hitTestable(),
        findsOneWidget,
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      editor.selectNode('node-29');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('layer-node-29')).hitTestable(),
        findsOneWidget,
      );
      final list = find.byKey(const ValueKey('layer-list'));
      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(list).controller!;
      final offset = scroll.offset;
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.pump();
      await tester.tap(find.text('Apply to preview'));
      await tester.pumpAndSettle();
      expect(scroll.offset, offset);
      expect(editor.selectedNode.rect.x, 0.2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'panel tabs have centered labels and usable targets at sidebar limits',
    (tester) async {
      await harness.openStudio(tester);
      final source = harness.file.readAsStringSync();
      final columns = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      for (final delta in [-2000.0, 2000.0]) {
        await tester.drag(columns.first, Offset(delta, 0));
        await tester.pumpAndSettle();
        for (final label in [
          'Layers',
          'Compose',
          'Assets',
          'Design',
          'Inspect code',
        ]) {
          final tab = find.ancestor(
            of: find.text(label),
            matching: find.byType(TabItem),
          );
          final bounds = tester.getRect(tab);
          final text = tester.getRect(find.text(label));
          expect(bounds.height, greaterThanOrEqualTo(32));
          expect(bounds.height, lessThanOrEqualTo(40));
          expect(text.center.dx, closeTo(bounds.center.dx, 0.1));
          expect(text.left, greaterThan(bounds.left));
          expect(text.right, lessThan(bounds.right));
        }
        await tester.tap(find.byKey(const ValueKey('sidebar-components')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('layer-list')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
        await tester.pumpAndSettle();
        expect(find.text('Import asset'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('sidebar-layers')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('layer-list')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('layer-panel'))).height,
          lessThanOrEqualTo(36),
        );
        expect(tester.takeException(), isNull);
      }
      expect(harness.file.readAsStringSync(), source);
      expect(find.text('Saved'), findsOneWidget);
    },
  );

  testWidgets(
    'workspace and sidebar boundaries resize without replacing editor state',
    (tester) async {
      await harness.openStudio(tester);
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final source = harness.file.readAsStringSync();
      final columns = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      Finder findPane(String name) => find.byWidgetPredicate(
        (widget) => widget is ResizablePane && widget.key == ValueKey(name),
      );
      final left = findPane('sidebar-pane');
      final right = findPane('inspector-pane');
      expect(columns, findsNWidgets(2));
      final leftWidth = tester.getSize(left).width;
      await tester.drag(columns.first, const Offset(70, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(left).width, greaterThan(leftWidth));
      final rightWidth = tester.getSize(right).width;
      await tester.drag(columns.last, const Offset(-70, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(right).width, greaterThan(rightWidth));
      final resized = tester.getSize(left);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(tester.getSize(left), resized);
      expect(
        tester.widget<NodeInspector>(find.byType(NodeInspector)).controller,
        same(inspector),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(harness.file.readAsStringSync(), source);
      await tester.drag(columns.first, const Offset(2000, 0));
      await tester.pumpAndSettle();
      await tester.drag(columns.last, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(left).width, lessThanOrEqualTo(360));
      expect(tester.getSize(right).width, lessThanOrEqualTo(420));
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(StudioCanvas)).width,
        greaterThanOrEqualTo(300),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact inspector keeps long errors scrollable and actions accessible',
    (tester) async {
      final longId = List.filled(30, 'long-node-name').join('-');
      harness.file.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            nodes: [studioTestDocument.nodes.first.copyWith(id: longId)],
          ),
        ),
      );
      await harness.openStudio(tester);
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      inspector.showError(List.filled(50, 'Invalid property value.').join(' '));
      await tester.pumpAndSettle();
      final actions = find.byKey(const ValueKey('inspector-actions'));
      expect(tester.getSize(actions).height, lessThan(160));
      expect(find.text('Apply to preview').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Apply to preview'));
      await tester.pumpAndSettle();
      expect(inspector.node.id, longId);
      expect(tester.takeException(), isNull);
    },
  );
}
