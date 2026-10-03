import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/theme_studio.dart';
import 'package:theme_studio/src/studio_preview.dart';
import 'package:theme_studio/src/node_inspector.dart';
import 'package:theme_studio/src/studio_canvas.dart';
import 'package:theme_studio/src/studio_theme.dart';

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

final class _PickedFile extends PlatformFile {
  _PickedFile(File file) : uri = file.uri;
  @override
  final Uri uri;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FilePicker extends FilePickerPlatform {
  PlatformFile? selected;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selected;
}

void main() {
  late Directory directory;
  late File file;
  late _FilePicker picker;
  late FilePickerPlatform originalPicker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPicker = FilePickerPlatform.instance;
    picker = _FilePicker();
    FilePickerPlatform.instance = picker;
    directory = Directory.systemTemp.createTempSync('studio-ui-');
    File('${directory.path}/pubspec.yaml').writeAsStringSync('name: test\n');
    file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(encodeSceneDocument(_document));
  });
  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
    directory.deleteSync(recursive: true);
  });

  Future<void> openStudio(
    WidgetTester tester, {
    ThemeBuilder themeBuilder = _buildTheme,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ThemeStudioApp(
        themeBuilder: themeBuilder,
        scenePaths: [file.path],
        themeDirectory: directory.path,
        themePackageName: 'test',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview header preserves original alignment and surface styling',
    (tester) async {
      await openStudio(tester);
      for (final width in [1100.0, 1400.0, 1800.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        for (final state in ['Login', 'Dormant']) {
          final canvas = find.byType(StudioCanvas);
          final canvasRect = tester.getRect(canvas);
          final title = find.text('Preview');
          final button = find.widgetWithText(OutlineButton, 'State: $state');
          expect(title, findsOneWidget);
          final titleRect = tester.getRect(title);
          final buttonRect = tester.getRect(button);
          expect(titleRect.left, canvasRect.left + 16);
          expect(buttonRect.right, canvasRect.right - 16);
          expect(buttonRect.top, canvasRect.top + 16);
          expect(titleRect.center.dy, buttonRect.center.dy);
          final surface = tester.widget<ColoredBox>(
            find
                .descendant(of: canvas, matching: find.byType(ColoredBox))
                .first,
          );
          expect(
            surface.color,
            Theme.of(tester.element(canvas)).colorScheme.muted
                .withValues(alpha: 0.3),
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace and sidebar boundaries resize without replacing editor state',
    (tester) async {
      await openStudio(tester);
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final source = file.readAsStringSync();
      final columns = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeRow,
      );
      Finder pane(String name) => find.byWidgetPredicate(
        (widget) => widget is ResizablePane && widget.key == ValueKey(name),
      );
      final left = pane('sidebar-pane');
      final right = pane('inspector-pane');
      final scenes = pane('scenes-pane');
      final assets = pane('assets-pane');
      expect(columns, findsNWidgets(2));
      expect(rows, findsNWidgets(4));
      final leftWidth = tester.getSize(left).width;
      await tester.drag(columns.first, const Offset(70, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(left).width, greaterThan(leftWidth));
      final rightWidth = tester.getSize(right).width;
      await tester.drag(columns.last, const Offset(-70, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(right).width, greaterThan(rightWidth));
      final sceneHeight = tester.getSize(scenes).height;
      await tester.drag(rows.first, const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(tester.getSize(scenes).height, greaterThan(sceneHeight));
      final assetHeight = tester.getSize(assets).height;
      await tester.drag(rows.at(1), const Offset(0, -50));
      await tester.pumpAndSettle();
      expect(tester.getSize(assets).height, greaterThan(assetHeight));
      final header = pane('inspector-header-pane');
      final headerHeight = tester.getSize(header).height;
      await tester.drag(rows.at(2), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, greaterThan(headerHeight));
      final actions = pane('inspector-actions-pane');
      final actionsHeight = tester.getSize(actions).height;
      await tester.drag(rows.last, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(tester.getSize(actions).height, greaterThan(actionsHeight));
      final resized = tester.getSize(left);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(tester.getSize(left), resized);
      expect(
        tester.widget<NodeInspector>(find.byType(NodeInspector)).controller,
        same(inspector),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(file.readAsStringSync(), source);
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

  testWidgets('preview dependencies survive edits and refresh on hot reload', (
    tester,
  ) async {
    var componentCreations = 0;
    await openStudio(
      tester,
      themeBuilder: ({Color? seed}) {
        final theme = _buildTheme(seed: seed);
        return ThemeDefinition(
          id: theme.id,
          document: theme.document,
          bundle: theme.bundle,
          components: (_) {
            componentCreations++;
            return _Components();
          },
        );
      },
    );
    final theme = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .theme;
    await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
    await tester.tap(find.text('Apply to preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State: Login'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(20, 10),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(preview.theme, same(theme));
    expect(componentCreations, 1);

    final reload = tester.binding.reassembleApplication();
    await tester.pumpAndSettle();
    await reload;
    final refreshed = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(refreshed.theme, isNot(same(theme)));
    expect(refreshed.document, same(preview.document));
    expect(componentCreations, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspector drafts only rebuild controls that observe drafts', (
    tester,
  ) async {
    await openStudio(tester);
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)),
      same(preview),
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
  });

  testWidgets('lazy inspector sections preserve fields while scrolling', (
    tester,
  ) async {
    await openStudio(tester);
    final inspectorScroll = find
        .descendant(
          of: find.byType(NodeInspector),
          matching: find.byType(Scrollable),
        )
        .first;
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
    await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    final node = decodeSceneDocument(file.readAsStringSync()).nodes.first;
    expect(node.rect.x, 0.2);
    expect(node.properties, {'variant': 'wide'});
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed initial load disables editor actions and reload recovers',
    (tester) async {
      file.writeAsStringSync('invalid scene');
      await openStudio(tester);
      expect(find.byType(StudioPreview), findsNothing);
      expect(find.byType(NodeInspector), findsNothing);
      for (final label in ['Settings', 'Undo', 'Redo']) {
        expect(
          tester
              .widget<OutlineButton>(find.widgetWithText(OutlineButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Save scene'),
            )
            .onPressed,
        isNull,
      );
      file.writeAsStringSync(encodeSceneDocument(_document));
      await tester.tap(find.text('Reload from disk'));
      await tester.pumpAndSettle();
      expect(find.byType(StudioPreview), findsOneWidget);
      expect(find.byType(NodeInspector), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings validate, cancel, apply and undo scene changes', (
    tester,
  ) async {
    await openStudio(tester);
    await tester.tap(find.text('Settings'));
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
      decodeSceneDocument(file.readAsStringSync()).canvas.referenceWidth,
      1600,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .canvas
          .referenceWidth,
      1280,
    );
    await tester.tap(find.text('Settings'));
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

  testWidgets(
    'appearance, grid and snapping apply and persist across remounts',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final settingsScroll = find
          .descendant(
            of: find.byKey(const ValueKey('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Appearance: Follow system'),
        150,
        scrollable: settingsScroll,
      );
      await tester.tap(find.text('Appearance: Follow system'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Color theme: Zinc'),
        100,
        scrollable: settingsScroll,
      );
      await tester.tap(find.text('Color theme: Zinc'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Violet').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('setting-Grid size (pixels)')),
        100,
        scrollable: settingsScroll,
      );
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
      await openStudio(tester);
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
      await openStudio(tester);
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

  testWidgets('imported image previews immediately and background edits undo', (
    tester,
  ) async {
    final source = File('${directory.path}/wallpaper.png');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xff123456), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      source.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    await openStudio(tester);
    picker.selected = _PickedFile(source);
    await tester.tap(find.text('Import asset'));
    await tester.pumpAndSettle();
    expect(File('${directory.path}/assets/wallpaper.png').existsSync(), isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.text('Use image'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(
      preview.document.background.asset,
      'packages/test/assets/wallpaper.png',
    );
    expect(preview.document.background.kind, SceneBackgroundKind.image);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .background
          .kind,
      SceneBackgroundKind.solid,
    );
    expect(File('${directory.path}/assets/wallpaper.png').existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'load JSON handles cancellation, invalid files and unsaved edits',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      final imported = File('${directory.path}/imported.json')
        ..writeAsStringSync('invalid');
      picker.selected = _PickedFile(imported);
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.id,
        'test',
      );
      imported.writeAsStringSync(
        encodeSceneDocument(_document.copyWith(id: 'imported')),
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '0.2');
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save or reload'), findsOneWidget);
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.id,
        'imported',
      );
      expect(find.text('imported.json'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '0.3');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(imported.readAsStringSync()).nodes.first.rect.x,
        0.3,
      );
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'live drag updates position inputs without rebuilding inspector or committing revisions',
    (tester) async {
      await openStudio(tester);
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      final form = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_InspectorForm',
      );
      final formWidget = tester.widget(form);
      final widthController = inspector.getField('Width');
      var inspectorNotifications = 0;
      var widthNotifications = 0;
      inspector.addListener(() => inspectorNotifications++);
      widthController.addListener(() => widthNotifications++);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('preview-panel'))),
      );
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      final firstX = double.parse(inspector.getField('X').text);
      expect(firstX, greaterThan(0.1));
      await gesture.moveBy(const Offset(30, 15));
      await tester.pump();
      expect(double.parse(inspector.getField('X').text), greaterThan(firstX));
      expect(double.parse(inspector.getField('Y').text), greaterThan(0.1));
      expect(inspector.hasDraft, isFalse);
      expect(inspectorNotifications, 0);
      expect(widthNotifications, 0);
      expect(tester.widget(form), same(formWidget));
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)),
        same(preview),
      );
      expect(preview.document.nodes.first.rect.x, 0.1);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester
            .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Undo'))
            .onPressed,
        isNull,
      );
      final liveX = double.parse(inspector.getField('X').text);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .x,
        liveX,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(inspector.getField('X').text, '0.1');
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a transformed node follows canvas coordinates', (
    tester,
  ) async {
    file.writeAsStringSync(
      encodeSceneDocument(
        _document.copyWith(
          nodes: [
            _document.nodes.first.copyWith(
              transform: const SceneTransform(
                rotationZ: 0.6,
                scaleX: 1.2,
                scaleY: 0.8,
              ),
            ),
            _document.nodes.last,
          ],
        ),
      ),
    );
    await openStudio(tester);
    final canvasRect = tester.getRect(find.byType(SceneRuntime));
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(60, 30),
    );
    await tester.pumpAndSettle();
    final node = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document
        .nodes
        .first;
    expect(node.rect.x, closeTo(0.1 + 60 / canvasRect.width, 0.00001));
    expect(node.rect.y, closeTo(0.1 + 30 / canvasRect.height, 0.00001));
    expect(node.transform.rotationZ, 0.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled drags preserve the scene and history', (tester) async {
    await openStudio(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('preview-panel'))),
    );
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    final inspector = tester
        .widget<NodeInspector>(find.byType(NodeInspector))
        .controller;
    expect(double.parse(inspector.getField('X').text), greaterThan(0.1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(
      encodeSceneDocument(preview.document),
      encodeSceneDocument(_document),
    );
    expect(inspector.getField('X').text, '0.1');
    expect(inspector.getField('Y').text, '0.1');
    expect(inspector.hasDraft, isFalse);
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester
          .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Undo'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

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
