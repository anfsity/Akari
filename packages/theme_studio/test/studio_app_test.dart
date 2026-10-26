import 'dart:convert';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

class _PresetComponents implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) =>
      Center(child: Text('preset component ${node.id}'));
}

class _Components implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) =>
      Center(child: Text(node.componentId));
}

enum _PanelStyle { regular, large }

const _editableCatalog = ThemeComponentCatalog(
  components: {
    'panel': ThemeComponentDefinition(
      label: 'Panel appearance',
      properties: [
        ThemeTextProperty(name: 'text', label: 'Text', defaultValue: 'Welcome'),
        ThemeChoiceProperty(
          name: 'variant',
          label: 'Text style',
          defaultValue: _PanelStyle.regular,
          choices: {_PanelStyle.regular: 'Regular', _PanelStyle.large: 'Large'},
        ),
      ],
    ),
  },
);

const _assemblyLayout = ThemeLayoutDefinition(
  sceneId: 'test',
  label: 'Test composition',
  slots: [
    ThemeLayoutSlot(
      label: 'Login panel',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'panel',
        componentId: 'panel',
        rect: SceneRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4),
      ),
    ),
    ThemeLayoutSlot(
      label: 'Standby badge',
      defaultNode: SceneNode(
        id: 'badge',
        componentId: 'label',
        rect: SceneRect(x: 0.2, y: 0.05, width: 0.3, height: 0.1),
        motion: SceneMotionPreset.fade,
        visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
        properties: {'text': 'Welcome'},
      ),
    ),
    ThemeLayoutSlot(
      label: 'Sign-in action',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'action',
        componentId: 'primaryAction',
        rect: SceneRect(x: 0.7, y: 0.5, width: 0.1, height: 0.1),
        interactive: true,
        focusOrder: 40,
      ),
    ),
    ThemeLayoutSlot(
      label: 'Status message',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'status',
        componentId: 'status',
        rect: SceneRect(x: 0.2, y: 0.7, width: 0.4, height: 0.1),
      ),
    ),
  ],
);

ThemeDefinition _buildTheme({
  Color? seed,
  ThemeComponentCatalog componentCatalog = const ThemeComponentCatalog(),
  ThemeLayoutDefinition? layout,
}) => ThemeDefinition(
  id: 'test',
  document: _document,
  components: (_) => _Components(),
  componentCatalog: componentCatalog,
  layout: layout,
  bundle: ThemeBundle(
    tokens: ThemeTokens(
      materialTheme: material.ThemeData(
        colorScheme: seed == null
            ? const material.ColorScheme.dark()
            : material.ColorScheme.fromSeed(
                seedColor: seed,
                brightness: material.Brightness.dark,
              ),
      ),
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

Future<void> _writeImage(File file) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xff123456), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
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
    List<StudioThemeProject> additionalProjects = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ThemeStudioApp(
        initialThemePackageName: 'test',
        projects: [
          StudioThemeProject(
            themeBuilder: themeBuilder,
            scenePaths: [file.path],
            directory: directory.path,
            packageName: 'test',
          ),
          ...additionalProjects,
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'theme switching guards drafts and switches compiled components and asset ownership',
    (tester) async {
      final presetDirectory = Directory('${directory.path}/preset')
        ..createSync();
      File('${presetDirectory.path}/pubspec.yaml')
          .writeAsStringSync('name: theme_preset\n');
      final presetFile = File('${presetDirectory.path}/preset.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(_document.copyWith(id: 'preset')),
        );
      Directory('${presetDirectory.path}/assets').createSync();
      File('${presetDirectory.path}/assets/preset.txt')
          .writeAsStringSync('preset asset');
      final preset = StudioThemeProject(
        packageName: 'theme_preset',
        directory: presetDirectory.path,
        scenePaths: [presetFile.path],
        themeBuilder: ({Color? seed}) => ThemeDefinition(
          id: 'preset',
          document: _document,
          bundle: _buildTheme().bundle,
          components: (_) => _PresetComponents(),
          componentCatalog: _editableCatalog,
          layout: ThemeLayoutDefinition(
            sceneId: 'preset',
            label: 'Preset composition',
            slots: [_assemblyLayout.slots.first],
          ),
        ),
      );
      await openStudio(tester, additionalProjects: [preset]);
      Future<void> choosePreset() async {
        await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('theme_preset').last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await choosePreset();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await choosePreset();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      await choosePreset();
      await tester.tap(find.text('Save and switch'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.width,
        0.4,
      );
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'preset',
      );
      expect(find.text('preset component panel'), findsOneWidget);
      expect(
        tester
            .widget<StudioCanvas>(find.byType(StudioCanvas))
            .editor!
            .layout!
            .label,
        'Preset composition',
      );
      expect(find.text('Panel appearance'), findsOneWidget);
      expect(find.byKey(const ValueKey('property-variant')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      expect(find.text('preset.txt'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(presetFile.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.x,
        0.1,
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '384');
      await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and switch'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(presetFile.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(find.text('preset.txt'), findsNothing);
      expect(
        tester.widget<StudioCanvas>(find.byType(StudioCanvas)).editor!.layout,
        isNull,
      );
      expect(find.text('Panel appearance'), findsNothing);
      expect(find.byKey(const ValueKey('property-variant')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading a registered preset scene switches its component factory; broken presets retain the active scene',
    (tester) async {
      final presetDirectory = Directory('${directory.path}/preset')
        ..createSync();
      File('${presetDirectory.path}/pubspec.yaml')
          .writeAsStringSync('name: theme_preset\n');
      final presetFile = File('${presetDirectory.path}/preset.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(_document.copyWith(id: 'preset')),
        );
      final preset = StudioThemeProject(
        packageName: 'theme_preset',
        directory: presetDirectory.path,
        scenePaths: [presetFile.path],
        themeBuilder: ({Color? seed}) => _buildTheme().copyWith(id: 'preset'),
      );
      await openStudio(tester, additionalProjects: [preset]);
      presetFile.writeAsStringSync('invalid');
      await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('theme_preset').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      expect(find.textContaining('Cannot open theme'), findsOneWidget);
      presetFile.writeAsStringSync(
        encodeSceneDocument(_document.copyWith(id: 'preset')),
      );
      picker.selected = _PickedFile(presetFile);
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'preset',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inspect follows selection, copies code and prevents canvas edits',
    (tester) async {
      await openStudio(tester);
      final original = file.readAsStringSync();
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
      expect(file.readAsStringSync(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid drafts block inspection and valid drafts reach copied code',
    (tester) async {
      await openStudio(tester);
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
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.width,
        0.4,
      );
    },
  );

  testWidgets('canvas toolbar stays compact and wraps within narrow panels', (
    tester,
  ) async {
    await openStudio(tester);
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
        'tool-scale',
        'canvas-hand',
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
      file.writeAsStringSync(
        encodeSceneDocument(
          _document.copyWith(
            nodes: [
              for (var index = 0; index < 30; index++)
                _document.nodes.first.copyWith(id: 'node-$index'),
            ],
          ),
        ),
      );
      await openStudio(tester);
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
      await openStudio(tester);
      final source = file.readAsStringSync();
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
          'Add',
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
      expect(file.readAsStringSync(), source);
      expect(find.text('Saved'), findsOneWidget);
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

  testWidgets(
    'compact inspector keeps long errors scrollable and actions accessible',
    (tester) async {
      final longId = List.filled(30, 'long-node-name').join('-');
      file.writeAsStringSync(
        encodeSceneDocument(
          _document.copyWith(
            nodes: [_document.nodes.first.copyWith(id: longId)],
          ),
        ),
      );
      await openStudio(tester);
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
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
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
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
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

  testWidgets(
    'assembly adds preset nodes, previews states and persists across reopening',
    (tester) async {
      ThemeDefinition buildAssembly({Color? seed}) =>
          _buildTheme(seed: seed, layout: _assemblyLayout);
      await openStudio(tester, themeBuilder: buildAssembly);
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      expect(find.text('Test composition'), findsOneWidget);
      final add = find.byKey(const ValueKey('slot-badge'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final canvas = tester.widget<StudioCanvas>(find.byType(StudioCanvas));
      expect(canvas.editor!.selectedId, 'badge');
      expect(canvas.editor!.selectedNode.properties, {'text': 'Welcome'});
      expect(canvas.editor!.selectedNode.rect.x, 0.2);
      expect(find.byKey(const ValueKey('preview-badge')), findsNothing);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview-badge')), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(canvas.editor!.selectedId, 'panel');
      expect(canvas.editor!.document.nodes, hasLength(2));
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await openStudio(tester, themeBuilder: buildAssembly);
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: add, matching: find.text('Remove')),
        findsOneWidget,
      );
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
      await tester.tap(find.text('Undo'));
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
      await openStudio(
        tester,
        themeBuilder: ({Color? seed}) =>
            _buildTheme(seed: seed, layout: _assemblyLayout),
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
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(editor.document.nodes, hasLength(2));
      expect(editor.canUndo, isFalse);
      expect(find.byKey(const ValueKey('add-required-slots')), findsOneWidget);
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlineButton>(find.byKey(const ValueKey('slot-panel')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid drafts and inspection prevent assembly mutations', (
    tester,
  ) async {
    await openStudio(
      tester,
      themeBuilder: ({Color? seed}) =>
          _buildTheme(seed: seed, layout: _assemblyLayout),
    );
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    final original = editor.document;
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
    await tester.tap(find.byKey(const ValueKey('sidebar-components')));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('slot-badge'));
    await tester.ensureVisible(add);
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
    expect(tester.widget<OutlineButton>(add).onPressed, isNull);
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
      await openStudio(
        tester,
        themeBuilder: ({Color? seed}) =>
            _buildTheme(seed: seed, layout: _assemblyLayout),
      );
      final other = File('${directory.path}/other.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(_document.copyWith(id: 'other')),
        );
      picker.selected = _PickedFile(other);
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
      expect(
        find.text('Component assembly is unavailable for this scene.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('slot-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('declared controls show defaults without creating scene edits', (
    tester,
  ) async {
    final source = file.readAsStringSync();
    await openStudio(
      tester,
      themeBuilder: ({Color? seed}) =>
          _buildTheme(seed: seed, componentCatalog: _editableCatalog),
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
      decodeSceneDocument(file.readAsStringSync()).nodes.first.properties,
      isEmpty,
    );
    expect(
      encodeSceneDocument(decodeSceneDocument(source)),
      encodeSceneDocument(decodeSceneDocument(file.readAsStringSync())),
    );
  });

  testWidgets(
    'declared text and choices save, undo and reopen with private data',
    (tester) async {
      file.writeAsStringSync(
        encodeSceneDocument(
          _document.copyWith(
            nodes: [
              _document.nodes.first.copyWith(properties: {'private': 'keep'}),
              _document.nodes.last,
            ],
          ),
        ),
      );
      ThemeDefinition buildEditable({Color? seed}) =>
          _buildTheme(seed: seed, componentCatalog: _editableCatalog);
      await openStudio(tester, themeBuilder: buildEditable);
      expect(find.byKey(const ValueKey('property-private')), findsNothing);
      final text = find.byKey(const ValueKey('property-text'));
      await tester.enterText(text, 'My desktop');
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
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Regular'), findsOneWidget);
      expect(tester.widget<TextField>(text).controller!.text, 'My desktop');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(text).controller!.text, 'Welcome');
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.properties,
        {'private': 'keep', 'text': 'My desktop', 'variant': 'large'},
      );

      await tester.pumpWidget(const SizedBox());
      await openStudio(tester, themeBuilder: buildEditable);
      expect(tester.widget<TextField>(text).controller!.text, 'My desktop');
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported JSON choices keep the preview and can be repaired', (
    tester,
  ) async {
    await openStudio(
      tester,
      themeBuilder: ({Color? seed}) =>
          _buildTheme(seed: seed, componentCatalog: _editableCatalog),
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
      await openStudio(
        tester,
        themeBuilder: ({Color? seed}) =>
            _buildTheme(seed: seed, componentCatalog: catalog),
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      catalog = _editableCatalog;
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
    await openStudio(tester);
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
    final node = decodeSceneDocument(file.readAsStringSync()).nodes.first;
    expect(node.rect.x, 0.2);
    expect(node.properties, {'variant': 'wide'});
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'component fields apply on blur and stay synchronized with JSON and undo',
    (tester) async {
      file.writeAsStringSync(
        encodeSceneDocument(
          _document.copyWith(
            nodes: [
              _document.nodes.first.copyWith(
                properties: {'variant': 'compact'},
              ),
              _document.nodes.last,
            ],
          ),
        ),
      );
      await openStudio(tester);
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
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(property).controller!.text, 'compact');
      await tester.tap(find.text('Redo'));
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
        decodeSceneDocument(file.readAsStringSync())
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
      await openStudio(tester);
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
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester
            .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Undo'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('settings presets and background drafts apply as one undo step', (
    tester,
  ) async {
    await openStudio(tester);
    final source = file.readAsStringSync();
    await tester.tap(find.text('Settings'));
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
    expect(file.readAsStringSync(), source);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(encodeSceneDocument(editor.document), source);
    expect(editor.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings reveal invalid categories and preserve drafts while correcting them',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('Settings'));
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
      await openStudio(tester);
      await tester.tap(find.text('Settings'));
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
      expect(encodeSceneDocument(preview.document), file.readAsStringSync());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance, grid and snapping apply and persist across remounts',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.text('Settings'));
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
    await tester.runAsync(() => _writeImage(source));
    await openStudio(tester);
    picker.selected = _PickedFile(source);
    await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import asset'));
    await tester.pumpAndSettle();
    final initialTheme = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .theme;
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
    expect(
      preview.theme.materialTheme.colorScheme.primary,
      isNot(initialTheme.materialTheme.colorScheme.primary),
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final undonePreview = tester.widget<StudioPreview>(
      find.byType(StudioPreview),
    );
    expect(undonePreview.document.background.kind, SceneBackgroundKind.solid);
    expect(
      undonePreview.theme.materialTheme.colorScheme.primary,
      initialTheme.materialTheme.colorScheme.primary,
    );
    expect(File('${directory.path}/assets/wallpaper.png').existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loaded theme owns imported assets, saved paths and background previews',
    (tester) async {
      final source = File('${directory.path}/assets/wallpaper.png');
      source.parent.createSync();
      await tester.runAsync(() => _writeImage(source));
      final originalManifest = File('${directory.path}/pubspec.yaml')
          .readAsStringSync();
      final other = Directory('${directory.path}/other-project')..createSync();
      final manifest = File('${other.path}/pubspec.yaml')
        ..writeAsStringSync('name: theme_other\n');
      final localImage = File('${other.path}/assets/local.png');
      localImage.parent.createSync();
      source.copySync(localImage.path);
      const localAsset = 'packages/theme_other/assets/local.png';
      final scene = File('${other.path}/lib/scenes/other.scene.json');
      scene.parent.createSync(recursive: true);
      scene.writeAsStringSync(
        encodeSceneDocument(
          _document.copyWith(
            id: 'other',
            background: const SceneBackground(
              kind: SceneBackgroundKind.image,
              asset: localAsset,
            ),
          ),
        ),
      );
      await openStudio(tester);
      final invalid = File('${scene.parent.path}/invalid.json')
        ..writeAsStringSync('invalid');
      picker.selected = _PickedFile(invalid);
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      expect(find.text('wallpaper.png'), findsWidgets);
      expect(find.text('local.png'), findsNothing);
      picker.selected = _PickedFile(scene);
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.text('local.png'), findsWidgets);
      expect(find.text('wallpaper.png'), findsNothing);
      var preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      var renderer =
          preview.theme.bundle.backgrounds[SceneBackgroundKind.image]
              as ImageBackgroundRenderer;
      expect(
        (renderer.resolveImage(localAsset) as FileImage).file.path,
        localImage.path,
      );

      picker.selected = _PickedFile(source);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import asset'));
      await tester.pumpAndSettle();
      expect(
        File('${other.path}/assets/wallpaper.png').readAsBytesSync(),
        source.readAsBytesSync(),
      );
      expect(manifest.readAsStringSync(), contains('assets/wallpaper.png'));
      expect(
        File('${directory.path}/pubspec.yaml').readAsStringSync(),
        originalManifest,
      );
      expect(
        File('${directory.path}/assets/wallpaper-2.png').existsSync(),
        isFalse,
      );
      await tester.ensureVisible(find.text('Use image').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use image').last);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      const importedAsset = 'packages/theme_other/assets/wallpaper.png';
      expect(
        decodeSceneDocument(scene.readAsStringSync()).background.asset,
        importedAsset,
      );
      preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      renderer =
          preview.theme.bundle.backgrounds[SceneBackgroundKind.image]
              as ImageBackgroundRenderer;
      expect(
        (renderer.resolveImage(importedAsset) as FileImage).file.path,
        '${other.path}/assets/wallpaper.png',
      );
      expect(
        decodeSceneDocument(file.readAsStringSync()).background.kind,
        SceneBackgroundKind.solid,
      );

      await tester.tap(find.text('test.scene.json'));
      await tester.pumpAndSettle();
      expect(find.text('local.png'), findsNothing);
      expect(find.text('wallpaper.png'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import asset'));
      await tester.pumpAndSettle();
      expect(
        File('${directory.path}/assets/wallpaper-2.png').existsSync(),
        isTrue,
      );
      expect(
        File('${other.path}/assets/wallpaper-2.png').existsSync(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved scene changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.id,
        'imported',
      );
      expect(find.text('imported.json'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '384');
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
      final form = find.byKey(const ValueKey('node-inspector-form'));
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
        closeTo(liveX / 1280, 1e-7),
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(inspector.getField('X').text, '128');
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

  testWidgets(
    'fit keeps the scene centered when the window and panels resize',
    (tester) async {
      await openStudio(tester);
      final scene = find.byType(SceneRuntime);
      final viewport = find.byKey(const ValueKey('studio-viewport'));
      void checkFit() {
        final sceneRect = tester.getRect(scene);
        final viewportRect = tester.getRect(viewport);
        expect(
          (sceneRect.center - viewportRect.center).distance,
          lessThan(1e-6),
        );
        expect(sceneRect.width, lessThanOrEqualTo(viewportRect.width + 1e-6));
        expect(sceneRect.height, lessThanOrEqualTo(viewportRect.height + 1e-6));
        expect(find.text('Saved'), findsOneWidget);
      }

      for (final size in [
        const Size(1100, 900),
        const Size(1800, 900),
        const Size(1400, 1200),
        const Size(1400, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        checkFit();
      }
      final divider = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      await tester.drag(divider.first, const Offset(100, 0));
      await tester.pumpAndSettle();
      checkFit();
      expect(file.readAsStringSync(), encodeSceneDocument(_document));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom and pan preserve geometry, pointer anchor and handle size',
    (tester) async {
      await openStudio(tester);
      final scene = find.byType(SceneRuntime);
      final originalRect = tester.getRect(scene);
      final handle = find.byKey(const ValueKey('resize-right'));
      final originalHandleSize = tester.getRect(handle).size;
      final viewport = find.byKey(const ValueKey('studio-viewport'));
      final pointer = tester.getCenter(viewport) + const Offset(70, 20);
      final canvas = tester.renderObject<RenderBox>(scene);
      final local = canvas.globalToLocal(pointer);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect((canvas.globalToLocal(pointer) - local).distance, lessThan(1e-6));
      expect(tester.getRect(scene).width, greaterThan(originalRect.width));
      expect(
        tester.getRect(handle).size.width,
        closeTo(originalHandleSize.width, 1e-6),
      );
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene), originalRect);
      await tester.tap(find.byKey(const ValueKey('canvas-hand')));
      await tester.pumpAndSettle();
      await tester.drag(viewport, const Offset(60, 30));
      await tester.pumpAndSettle();
      expect(
        (tester.getRect(scene).topLeft -
                originalRect.topLeft -
                const Offset(60, 30))
            .distance,
        lessThan(1e-6),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        encodeSceneDocument(_document),
      );
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene), originalRect);
      await tester.tap(find.byKey(const ValueKey('canvas-hand')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('zoom-actual-size')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene).width, closeTo(1280, 1e-6));
      await tester.drag(handle, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .width,
        closeTo(0.3 + 40 / 1280, 1e-8),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canvas shortcuts nudge, undo, duplicate, delete, save and leave text editing alone',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('preview-panel')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      var preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(
        preview.document.nodes.first.rect.x,
        closeTo(0.1 + 1 / 1280, 1e-8),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .y,
        closeTo(0.1 + 10 / 720, 1e-8),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).panEnabled,
        isTrue,
      );
      await tester.drag(
        find.byKey(const ValueKey('studio-viewport')),
        const Offset(20, 10),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).panEnabled,
        isFalse,
      );
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('studio-viewport'));
      await tester.drag(canvas, const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.selectedId, 'panel-copy');
      expect(decodeSceneDocument(file.readAsStringSync()).nodes, hasLength(3));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.nodes,
        hasLength(2),
      );
      final before = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document;
      await tester.tap(find.byKey(const ValueKey('field-X')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        same(before),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resize relayouts text, cancels and commits one undo step', (
    tester,
  ) async {
    await openStudio(tester);
    final inspector = tester
        .widget<NodeInspector>(find.byType(NodeInspector))
        .controller;
    final handle = find.byKey(const ValueKey('resize-right'));
    final canvas = tester.getRect(find.byType(SceneRuntime));
    final text = find.descendant(
      of: find.byKey(const ValueKey('preview-panel')),
      matching: find.byType(Text),
    );
    final style = tester.widget<Text>(text).style;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final live = tester
        .widget<SceneRuntime>(find.byType(SceneRuntime))
        .document
        .nodes
        .first;
    expect(live.rect.width, closeTo(0.3 + 60 / canvas.width, 1e-8));
    expect(live.rect.height, 0.4);
    expect(live.transform.isIdentity, isTrue);
    expect(
      double.parse(inspector.getField('Width').text) / 1280,
      closeTo(live.rect.width, 1e-7),
    );
    expect(inspector.hasDraft, isFalse);
    expect(tester.widget<Text>(text).style, style);
    expect(find.text('Saved'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(inspector.getField('Width').text, '384');
    await tester.drag(handle, const Offset(60, 0));
    await tester.pumpAndSettle();
    final changed = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document;
    expect(changed.nodes.first.rect.width, closeTo(live.rect.width, 1e-8));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester
          .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Undo'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(
      encodeSceneDocument(decodeSceneDocument(file.readAsStringSync())),
      encodeSceneDocument(changed),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'aspect lock and Shift preserve ratio, hidden selections have no handles',
    (tester) async {
      await openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('lock-aspect-ratio')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('resize-bottomRight')),
        const Offset(50, 10),
      );
      await tester.pumpAndSettle();
      var node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.width / node.rect.height, closeTo(0.75, 1e-8));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lock-aspect-ratio')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.drag(
        find.byKey(const ValueKey('resize-bottomRight')),
        const Offset(50, 10),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.width / node.rect.height, closeTo(0.75, 1e-8));
      await tester.tap(find.byKey(const ValueKey('preview-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('resize-right')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(inspector.getField('X').text, '128');
    expect(inspector.getField('Y').text, '72');
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
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
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

  for (final (tool, fields) in [
    (StudioCanvasTool.scale, ['Scale X', 'Scale Y']),
    (StudioCanvasTool.rotate, ['Rotate Z']),
    (StudioCanvasTool.rotate3d, ['Rotate X', 'Rotate Y']),
  ]) {
    testWidgets('${tool.label} drag previews, cancels, commits and saves', (
      tester,
    ) async {
      await openStudio(tester);
      await tester.tap(find.byKey(ValueKey('tool-${tool.name}')));
      await tester.pumpAndSettle();
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final original = encodeSceneDocument(_document);
      final target = find.byKey(const ValueKey('preview-panel'));
      final canvas = tester.getRect(find.byType(SceneRuntime));
      var inspectorNotifications = 0;
      inspector.addListener(() => inspectorNotifications++);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      final first = double.parse(inspector.getField(fields.first).text);
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      expect(double.parse(inspector.getField(fields.first).text), isNot(first));
      expect(inspectorNotifications, 0);
      expect(inspector.hasDraft, isFalse);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<SceneRuntime>(find.byType(SceneRuntime)).document,
        ),
        isNot(original),
      );
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        original,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<SceneRuntime>(find.byType(SceneRuntime)).document,
        ),
        original,
      );
      for (final field in fields) {
        expect(
          inspector.getField(field).text,
          tool == StudioCanvasTool.scale ? '1.0' : '0.0',
        );
      }
      expect(find.text('Saved'), findsOneWidget);
      expect(inspector.hasDraft, isFalse);

      await tester.drag(target, const Offset(60, 30));
      await tester.pumpAndSettle();
      final node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.x, 0.1);
      expect(node.rect.y, 0.1);
      expect(node.rect.width, 0.3);
      expect(node.rect.height, 0.4);
      expect(
        node.transform.scaleX,
        closeTo(
          tool == StudioCanvasTool.scale ? 1 + 180 / canvas.width : 1,
          0.00001,
        ),
      );
      expect(
        node.transform.scaleY,
        closeTo(
          tool == StudioCanvasTool.scale ? 1 + 90 / canvas.height : 1,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationZ,
        closeTo(
          tool == StudioCanvasTool.rotate ? 21600 / canvas.width : 0,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationX,
        closeTo(
          tool == StudioCanvasTool.rotate3d ? -5400 / canvas.height : 0,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationY,
        closeTo(
          tool == StudioCanvasTool.rotate3d ? 10800 / canvas.width : 0,
          0.00001,
        ),
      );
      final changed = encodeSceneDocument(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        original,
      );
      expect(
        tester
            .widget<OutlineButton>(find.widgetWithText(OutlineButton, 'Undo'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Redo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(decodeSceneDocument(file.readAsStringSync())),
        changed,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scaling preserves mirrored axes and authored transforms', (
    tester,
  ) async {
    const transform = SceneTransform(
      scaleX: -1.2,
      scaleY: 0.8,
      rotationX: 10,
      rotationY: 15,
      rotationZ: 20,
      translateX: 12,
      translateY: 6,
      pivotX: 0.4,
      pivotY: 0.6,
      perspective: 0.0007,
    );
    final document = _document.copyWith(
      nodes: [
        _document.nodes.first.copyWith(transform: transform),
        _document.nodes.last,
      ],
    );
    file.writeAsStringSync(encodeSceneDocument(document));
    await openStudio(tester);
    await tester.tap(find.byKey(const ValueKey('tool-scale')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(-2000, -2000),
    );
    await tester.pumpAndSettle();
    final node = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document
        .nodes
        .first;
    expect(node.transform.scaleX, -0.01);
    expect(node.transform.scaleY, 0.01);
    expect(
      encodeSceneDocument(
        document.copyWith(
          nodes: [
            node.copyWith(
              transform: node.transform.copyWith(
                scaleX: transform.scaleX,
                scaleY: transform.scaleY,
              ),
            ),
            document.nodes.last,
          ],
        ),
      ),
      encodeSceneDocument(document),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reset scale repairs stretched nodes and preserves other transforms',
    (tester) async {
      const transform = SceneTransform(
        scaleX: 1.4,
        scaleY: 0.7,
        rotationZ: 20,
        pivotX: 0.3,
      );
      final original = _document.copyWith(
        nodes: [
          _document.nodes.first.copyWith(transform: transform),
          _document.nodes.last,
        ],
      );
      file.writeAsStringSync(encodeSceneDocument(original));
      await openStudio(tester);
      final scroll = find
          .descendant(
            of: find.byType(NodeInspector),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Advanced layout'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.text('Advanced layout'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reset-node-scale')),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.byKey(const ValueKey('reset-node-scale')));
      await tester.pumpAndSettle();
      final node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.transform.scaleX, 1);
      expect(node.transform.scaleY, 1);
      expect(node.transform.rotationZ, 20);
      expect(node.transform.pivotX, 0.3);
      expect(node.rect.width, 0.3);
      expect(node.rect.height, 0.4);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        encodeSceneDocument(original),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    'save shortcut applies focused inspector drafts and validates them',
    (tester) async {
      await openStudio(tester);
      final source = file.readAsStringSync();
      Future<void> saveWithKeyboard() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await saveWithKeyboard();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(file.readAsStringSync(), source);

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await saveWithKeyboard();
      expect(
        decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.width,
        0.4,
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      file.writeAsStringSync(source);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await saveWithKeyboard();
      expect(find.textContaining('The scene changed on disk'), findsOneWidget);
      expect(file.readAsStringSync(), source);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid edits preserve preview and block save, valid drafts save directly',
    (tester) async {
      await openStudio(tester);
      final source = file.readAsStringSync();
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
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
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
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
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
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
