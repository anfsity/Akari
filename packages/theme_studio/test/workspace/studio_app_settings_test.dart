import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/model/studio_theme.dart';
import 'package:theme_studio/src/model/studio_input.dart';
import 'package:theme_studio/src/model/studio_preferences.dart';

import 'studio_app_test_harness.dart';

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'shortcut recorder rejects collisions and applies persistent canvas and workspace bindings',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-input')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shortcut-search')),
        'Move / resize',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('bind-move')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bind-move')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('is assigned to Save scene'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(find.textContaining('is assigned to'), findsNothing);
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioCanvas>(find.byType(StudioCanvas))
            .preferences
            .input
            .getBinding(StudioCommand.move)!
            .key,
        LogicalKeyboardKey.keyQ,
      );
      await tester.tap(find.byKey(const ValueKey('preview-panel')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).tool,
        StudioCanvasTool.move,
      );
      expect(
        (await StudioPreferences.load()).input
            .getBinding(StudioCommand.move)!
            .key,
        LogicalKeyboardKey.keyQ,
      );
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings validate, cancel, apply and undo scene changes', (
    tester,
  ) async {
    await harness.openStudio(tester);
    await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setting-Canvas width')),
      '0',
    );
    await tester.tap(find.text('Apply settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('between 1 and 16384'), findsOneWidget);
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .canvas
          .referenceWidth,
      1280,
    );
    await tester.enterText(
      find.byKey(const ValueKey('setting-Canvas width')),
      '1600',
    );
    await tester.tap(find.text('Apply settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .canvas
          .referenceWidth,
      1600,
    );
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(
      decodeSceneDocument(harness.file.readAsStringSync())
          .canvas
          .referenceWidth,
      1600,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .canvas
          .referenceWidth,
      1280,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setting-Canvas width')),
      '800',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .canvas
          .referenceWidth,
      1280,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings presets and background drafts apply as one undo step', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final source = harness.file.readAsStringSync();
    await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-resolution-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full HD · 1920 × 1080').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap-canvas-dimensions')));
    await tester.tap(find.byKey(const ValueKey('settings-nav-background')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setting-Background color')),
      '#123456',
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-canvas')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('setting-Canvas width')))
          .controller!
          .text,
      '1080',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('setting-Canvas height')),
          )
          .controller!
          .text,
      '1920',
    );
    await tester.tap(find.text('Apply settings'));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    expect(editor.document.canvas.referenceWidth, 1080);
    expect(editor.document.canvas.referenceHeight, 1920);
    expect(editor.document.background.color, 0xff123456);
    expect(harness.file.readAsStringSync(), source);
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
    await tester.pumpAndSettle();
    expect(encodeSceneDocument(editor.document), source);
    expect(editor.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings reveal invalid categories and preserve drafts while correcting them',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('setting-Canvas width')),
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between 1 and 16384'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('setting-Canvas width')),
        '1600',
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-background')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('setting-Background color')),
        'invalid',
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('setting-Background color')),
        findsOneWidget,
      );
      expect(find.textContaining('Color must use'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('setting-Background color')),
        '#abcdef',
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-grid')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('setting-Grid size (pixels)')),
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('settings-nav-canvas')));
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Grid size must be'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('grid-preset-32')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-preset-32')));
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.document.canvas.referenceWidth, 1600);
      expect(preview.document.background.color, 0xffabcdef);
      expect(preview.preferences.gridSize, 32);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings reset editor defaults without changing the scene and fit small windows',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-violet')));
      await tester.ensureVisible(find.text('Reset appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset appearance'));
      await tester.tap(find.byKey(const ValueKey('settings-nav-grid')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show grid'));
      await tester.tap(find.text('Snap to grid'));
      await tester.tap(find.byKey(const ValueKey('grid-preset-48')));
      await tester.ensureVisible(find.text('Reset grid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset grid'));
      tester.view.physicalSize = const Size(600, 540);
      await tester.pumpAndSettle();
      final dialog = tester.getRect(
        find.byKey(const ValueKey('studio-settings')),
      );
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(600));
      expect(dialog.bottom, lessThanOrEqualTo(540));
      expect(find.text('Apply settings').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.preferences.palette, StudioPalette.zinc);
      expect(preview.preferences.themeMode, ThemeMode.system);
      expect(preview.preferences.showGrid, isFalse);
      expect(preview.preferences.snapToGrid, isFalse);
      expect(preview.preferences.gridSize, 24);
      expect(
        encodeSceneDocument(preview.document),
        harness.file.readAsStringSync(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance, grid and snapping apply and persist across remounts',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance: Follow system'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-violet')));
      await tester.tap(find.byKey(const ValueKey('settings-nav-grid')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show grid'));
      await tester.tap(find.text('Snap to grid'));
      await tester.enterText(
        find.byKey(const ValueKey('setting-Grid size (pixels)')),
        '32',
      );
      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.preferences.themeMode, ThemeMode.light);
      expect(preview.preferences.palette, StudioPalette.violet);
      expect(preview.preferences.showGrid, isTrue);
      expect(preview.preferences.snapToGrid, isTrue);
      expect(find.text('Saved'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('preview-panel')),
        const Offset(50, 30),
      );
      await tester.pumpAndSettle();
      final rect = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first
          .rect;
      expect((rect.x * 1280) % 32, closeTo(0, 0.00001));
      expect((rect.y * 720) % 32, closeTo(0, 0.00001));
      await tester.pumpWidget(const SizedBox());
      await harness.openStudio(tester);
      final restored = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(restored.preferences.themeMode, ThemeMode.light);
      expect(restored.preferences.palette, StudioPalette.violet);
      expect(restored.preferences.showGrid, isTrue);
      expect(restored.preferences.gridSize, 32);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system appearance reacts without changing scene or preview theme',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await harness.openStudio(tester);
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      final canvas = find.byType(StudioCanvas);
      expect(Theme.of(tester.element(canvas)).brightness, Brightness.light);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      final darkScheme = Theme.of(tester.element(canvas)).colorScheme;
      expect(darkScheme.brightness, Brightness.dark);
      expect(darkScheme.background, isNot(ColorSchemes.darkZinc.background));
      expect(darkScheme.card, isNot(darkScheme.background));
      final updated = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(updated.document, same(preview.document));
      expect(updated.theme, same(preview.theme));
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
