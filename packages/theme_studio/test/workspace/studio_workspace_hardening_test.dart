import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_studio/src/resources/confined_path.dart';
import 'package:theme_studio/src/workspace/studio_workspace.dart';
import 'package:theme_studio/src/workspace/studio_workspace_layout.dart';

void main() {
  testWidgets(
    'hidden floating panels remain reopenable via collapsed rail and dispose safely',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        StudioWorkspaceLayout.storageKey: jsonEncode({
          'mode': StudioWorkspaceMode.design.name,
          'sidebarDock': StudioDock.left.name,
          'inspectorDock': StudioDock.floating.name,
          'sidebarVisible': true,
          'inspectorVisible': false,
          'leftWidth': StudioWorkspaceLayout.defaultLeftWidth,
          'rightWidth': StudioWorkspaceLayout.defaultRightWidth,
          'sidebarBounds': const [16.0, 16.0, 300.0, 520.0],
          'inspectorBounds': const [460.0, 16.0, 300.0, 520.0],
        }),
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ShadcnApp(
          home: StudioWorkspace(
            toolbar: const SizedBox(height: 40),
            sidebar: const Text('Sidebar Body'),
            canvas: const ColoredBox(color: Color(0xff111111)),
            inspector: const Text('Inspector Body'),
            statusBar: const SizedBox(height: 24),
            onSave: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hidden floating inspector still renders a 32px right rail reopen button.
      Finder findPane(String name) => find.byWidgetPredicate(
        (widget) => widget is ResizablePane && widget.key == ValueKey(name),
      );
      final reopen = find.byKey(const ValueKey('toggle-inspector'));
      expect(reopen, findsOneWidget);
      expect(
        tester.getSize(findPane('inspector-pane')).width,
        greaterThanOrEqualTo(32),
      );

      await tester.tap(reopen);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('floating-Inspector')), findsOneWidget);

      // Presentation mode collapses both rails to 0 width, then Exit button restores.
      await tester.tap(find.byKey(const ValueKey('presentation-mode')));
      await tester.pumpAndSettle();
      expect(tester.getSize(findPane('sidebar-pane')).width, 0);
      expect(tester.getSize(findPane('inspector-pane')).width, 0);
      await tester.tap(find.byKey(const ValueKey('exit-presentation')));
      await tester.pumpAndSettle();

      // Dock inspector back right so a debounced save timer is active on dispose.
      await tester.tap(find.byKey(const ValueKey('dock-Inspector')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('writeFileAtomically writes content without leaving temp dirs', () {
    final directory = Directory.systemTemp.createTempSync('studio-atomic-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final target = File('${directory.path}/nested/scene.json');
    writeFileAtomically(target, '{"ok":true}\n', tempName: 'scene.json');
    expect(target.readAsStringSync(), '{"ok":true}\n');
    expect(
      target.parent.listSync().map((e) => e.uri.pathSegments.last),
      ['scene.json'],
    );
  });
}
