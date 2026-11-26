import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/theme_studio.dart';

const studioTestDocument = SceneDocument(
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

class StudioTestComponents implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) =>
      Center(child: Text(node.componentId));
}

enum StudioTestPanelStyle { regular, large }

const studioEditableCatalog = ThemeComponentCatalog(
  components: {
    'panel': ThemeComponentDefinition(
      label: 'Panel appearance',
      properties: [
        ThemeTextProperty(name: 'text', label: 'Text', defaultValue: 'Welcome'),
        ThemeChoiceProperty(
          name: 'variant',
          label: 'Text style',
          defaultValue: StudioTestPanelStyle.regular,
          choices: {
            StudioTestPanelStyle.regular: 'Regular',
            StudioTestPanelStyle.large: 'Large',
          },
        ),
      ],
    ),
  },
);

const studioAssemblyLayout = ThemeLayoutDefinition(
  sceneId: 'test',
  label: 'Test composition',
  presets: {
    'left': ThemeLayoutPreset(label: 'Left column'),
    'right': ThemeLayoutPreset(
      label: 'Right column',
      rects: {
        'panel': SceneRect(x: 0.5, y: 0.1, width: 0.3, height: 0.4),
        'badge': SceneRect(x: 0.6, y: 0.05, width: 0.3, height: 0.1),
        'action': SceneRect(x: 0.78, y: 0.5, width: 0.1, height: 0.1),
        'status': SceneRect(x: 0.6, y: 0.7, width: 0.4, height: 0.1),
      },
    ),
  },
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

ThemeDefinition buildStudioTestTheme({
  Color? seed,
  SceneDocument? document,
  ThemeComponentCatalog componentCatalog = const ThemeComponentCatalog(),
  ThemePresetCatalog presetCatalog = const ThemePresetCatalog(),
  ThemeLayoutDefinition? layout,
  GreeterThemeComponentsFactory? components,
  Duration mediumMotion = Duration.zero,
  bool disableAnimations = false,
}) => ThemeDefinition(
  id: 'test',
  document: document ?? studioTestDocument,
  components: components ?? (_) => StudioTestComponents(),
  componentCatalog: componentCatalog,
  presetCatalog: presetCatalog,
  layout: layout,
  bundle: ThemeBundle(
    backgrounds: const {
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
      SceneBackgroundKind.image: ImageBackgroundRenderer(),
    },
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
      mediumMotion: mediumMotion,
      disableAnimations: disableAnimations,
      standardCurve: Curves.linear,
      minHitTarget: 44,
      surfaceColor: const Color(0xff222222),
      surfaceVariantColor: const Color(0xff333333),
    ),
  ),
);

final class StudioTestPickedFile extends PlatformFile {
  StudioTestPickedFile(File file) : uri = file.uri;
  @override
  final Uri uri;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StudioTestFilePicker extends FilePickerPlatform {
  PlatformFile? selected;
  String? selectedDirectory;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selectedDirectory;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selected;
}

class StudioAppTestHarness {
  late Directory directory;
  late File file;
  late StudioTestFilePicker picker;
  late FilePickerPlatform originalPicker;

  void setUp() {
    SharedPreferences.setMockInitialValues({});
    originalPicker = FilePickerPlatform.instance;
    picker = StudioTestFilePicker();
    FilePickerPlatform.instance = picker;
    directory = Directory.systemTemp.createTempSync('studio-ui-');
    File('${directory.path}/pubspec.yaml').writeAsStringSync('name: test\n');
    file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(encodeSceneDocument(studioTestDocument));
  }

  void tearDown() {
    FilePickerPlatform.instance = originalPicker;
    directory.deleteSync(recursive: true);
  }

  Future<void> openStudio(
    WidgetTester tester, {
    ThemeBuilder themeBuilder = buildStudioTestTheme,
    List<StudioThemeProject> additionalProjects = const [],
    String packageName = 'test',
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ThemeStudioApp(
        initialThemePackageName: packageName,
        projects: [
          StudioThemeProject(
            themeBuilder: themeBuilder,
            scenePaths: [file.path],
            directory: directory.path,
            packageName: packageName,
          ),
          ...additionalProjects,
        ],
      ),
    );
    await tester.pumpAndSettle();
  }
}
